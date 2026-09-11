// 나누리 청구 접수 워커.
//
//   GET  /             공개 청구 폼 (= /bill)
//   POST /bill/receipt          영수증만 먼저 올린다 → { url, token }
//   POST /bill/receipt/discard  올렸지만 접수까지 가지 않은 영수증을 지운다
//   POST /bill/submit   검증 → bills INSERT → 관리자에게 푸시
//
//   POST /receipt/upload   앱이 영수증을 올린다 (청구서 삭제 복구용 · 재정 영수증)
//   POST /receipt/delete   앱이 영수증을 지운다
//   (둘 다 관리자 인증 필요 — Supabase 토큰 + admins 화이트리스트)
//
// 폼은 공개 URL이다. 주소를 아는 사람은 누구나 청구를 넣을 수 있고,
// 발신자를 식별할 방법이 없다. 그래서 이름만 받고, 계좌는 관리자가 앱의
// 계좌부(payees)에 등록해 둔 값을 이름으로 대조해서 쓴다.
//
// 영수증 이미지는 R2에 직접 넣는다 (`receipts.js`). 예전에는 `nanuri-bill` 이라는
// 별도 워커에 서비스 바인딩으로 넘겼는데, 그 워커는 소스가 어디에도 없어서 고칠 수도
// 되돌릴 수도 없었다. 버킷을 여기 붙이고 코드를 가져왔다.
//
// `/receipt/*` 는 앱이 부르고 `/bill/*` 은 공개 폼이 부른다.

import { sendBillNotification } from './apns.js';
import { renderForm } from './form.js';
import { putReceipt, deleteReceiptByUrl } from './receipts.js';

const MAX_RECEIPT_BYTES = 10 * 1024 * 1024;

// 오타로 0을 몇 개 더 붙이는 사고를 막는다. amount 컬럼이 integer라 상한은 어차피 필요하다.
const MAX_AMOUNT = 10_000_000;

// 선행 업로드 토큰의 유효 시간. 폼 하나 채우는 시간보다 넉넉하면 된다.
const RECEIPT_TOKEN_TTL_MS = 60 * 60 * 1000;

const html = (body, status = 200) =>
    new Response(body, { status, headers: { 'content-type': 'text/html; charset=utf-8' } });

const json = (body, status = 200) =>
    new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json' } });

// ---------------------------------------------------------------------------
// Supabase (service_role — RLS를 우회하므로 이 워커 밖으로 새어나가면 안 된다)
// ---------------------------------------------------------------------------

function supabaseHeaders(env, extra = {}) {
    return {
        apikey: env.SUPABASE_SERVICE_ROLE_KEY,
        authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}`,
        'content-type': 'application/json',
        ...extra,
    };
}

async function insertBill(env, bill) {
    const response = await fetch(`${env.SUPABASE_URL}/rest/v1/bills`, {
        method: 'POST',
        headers: supabaseHeaders(env, { prefer: 'return=representation' }),
        body: JSON.stringify(bill),
    });
    if (!response.ok) {
        throw new Error(`bills INSERT 실패: ${response.status} ${await response.text()}`);
    }
    const [row] = await response.json();
    return row;
}

async function fetchDeviceTokens(env) {
    try {
        const response = await fetch(
            `${env.SUPABASE_URL}/rest/v1/device_tokens?select=token,environment`,
            { headers: supabaseHeaders(env) },
        );
        return response.ok ? await response.json() : [];
    } catch (error) {
        console.error('디바이스 토큰 조회 실패', error);
        return [];
    }
}

// ---------------------------------------------------------------------------
// 영수증 업로드 (기존 R2 워커에 위임)
// ---------------------------------------------------------------------------

async function uploadReceipt(env, file) {
    return putReceipt(env, file, 'receipts');
}

/** 올려둔 영수증을 R2에서 지운다. */
async function deleteReceipt(env, receiptUrl) {
    await deleteReceiptByUrl(env, receiptUrl);
}

/** 이 URL이 이미 접수된 청구서에 붙어 있는지. 확정된 영수증은 지우면 안 된다. */
async function receiptIsInUse(env, receiptUrl) {
    const query = `${env.SUPABASE_URL}/rest/v1/bills?select=id&limit=1&receipt_url=eq.${encodeURIComponent(receiptUrl)}`;
    const response = await fetch(query, { headers: supabaseHeaders(env) });
    // 확인에 실패하면 지우지 않는 쪽으로 기운다. 안 지워진 파일보다 지워진 영수증이 나쁘다.
    if (!response.ok) return true;
    const rows = await response.json();
    return Array.isArray(rows) && rows.length > 0;
}

/** 첨부된 영수증의 문제를 한국어 메시지로 돌려준다. 문제가 없으면 null. */
function receiptProblem(receipt) {
    if (!receipt || typeof receipt !== 'object' || receipt.size === 0) {
        return '영수증 사진을 첨부해 주세요.';
    }
    if (receipt.size > MAX_RECEIPT_BYTES) {
        return '영수증 사진이 너무 커요. 10MB 이하로 올려주세요.';
    }
    if (receipt.type && !receipt.type.startsWith('image/')) {
        return '영수증은 사진 파일만 올릴 수 있어요.';
    }
    return null;
}

// ---------------------------------------------------------------------------
// 선행 업로드 토큰
// ---------------------------------------------------------------------------
//
// 폼은 사진을 고르는 즉시 /bill/receipt 로 먼저 올려두고, 제출할 때는 받은 URL만
// 넘긴다. 그래야 제출 버튼을 누른 뒤 기다리는 시간이 거의 없다.
// 다만 그 URL은 브라우저를 거쳐서 오므로 그대로 믿으면 안 된다 — 아무 주소나
// 적어 넣으면 관리자 앱이 남의 서버 이미지를 불러오게 된다. 그래서 워커가 URL에
// 서명해서 같이 주고, 제출 때 그 서명을 검증한다. (앱은 이 토큰을 모른다. bills 에
// 저장되는 건 URL 뿐이고, 토큰은 폼 → 워커 한 왕복 동안만 쓰인다)

const encoder = new TextEncoder();

const base64url = (buffer) =>
    btoa(String.fromCharCode(...new Uint8Array(buffer)))
        .replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');

const fromBase64url = (value) =>
    Uint8Array.from(atob(value.replace(/-/g, '+').replace(/_/g, '/')), (c) => c.charCodeAt(0));

// 서명 키는 이미 이 워커에만 있는 시크릿에서 뽑아 쓴다. 새 시크릿을 늘리지 않으려는 것뿐이고,
// 서명 자체가 service_role 키를 노출시키지는 않는다 (HMAC 은 역산되지 않는다).
const receiptKey = (env) =>
    crypto.subtle.importKey(
        'raw', encoder.encode(env.SUPABASE_SERVICE_ROLE_KEY),
        { name: 'HMAC', hash: 'SHA-256' }, false, ['sign', 'verify'],
    );

async function signReceiptUrl(env, url) {
    const issuedAt = Date.now();
    const signature = await crypto.subtle.sign(
        'HMAC', await receiptKey(env), encoder.encode(`${issuedAt}:${url}`),
    );
    return `${issuedAt}.${base64url(signature)}`;
}

async function verifyReceiptUrl(env, url, token) {
    const [issuedAt, signature] = (token ?? '').split('.');
    const at = Number(issuedAt);
    if (!Number.isFinite(at) || !signature) return false;
    if (Date.now() - at > RECEIPT_TOKEN_TTL_MS || at > Date.now() + 60_000) return false;
    try {
        return await crypto.subtle.verify(
            'HMAC', await receiptKey(env), fromBase64url(signature), encoder.encode(`${at}:${url}`),
        );
    } catch {
        return false;
    }
}

// ---------------------------------------------------------------------------
// 남용 방지
// ---------------------------------------------------------------------------

/**
 * 엔드포인트별 IP당 상한. `[창(초), 최대 건수]` 목록이고, **한 창이라도 넘으면
 * 막는다.** R2에 이미지를 쓰는 `/bill/receipt` 는 넉넉히(분당 20·시간당 120), 그
 * 다음 단계인 `/bill/submit` 은 더 낮게(분당 10) 잡았다.
 *
 * 값을 넉넉히 둔 이유: 정상 사용자를 절대 막지 않으려는 것이다. 교회 와이파이·
 * 통신사 CGNAT 때문에 **여러 사람이 한 IP로 보일 수 있어서**, 상한이 낮으면 이벤트
 * 직후 몰릴 때 애먼 사람이 막힌다. 피해 누적은 상한이 아니라 다른 층(R2 정리)이
 * 잡으므로 여기서는 "초당 수천 건" 만 끊으면 된다.
 */
const RATE_LIMITS = {
    receipt: [[60, 20], [3600, 120]],
    submit: [[60, 10]],
};

/**
 * 카운트의 기준이 되는 클라이언트 키. IPv4 는 주소 전체, **IPv6 는 앞 /64 프리픽스**다
 * — 한 기기가 자기 /64 안에서 주소를 바꿔 가며 개별-IP 상한을 우회하는 걸 막는다.
 */
function clientKey(request) {
    const ip = request.headers.get('cf-connecting-ip') ?? 'unknown';
    return ip.includes(':') ? ip.split(':').slice(0, 4).join(':') : ip;
}

/**
 * IP당 요청 횟수 제한. `action` 이 어떤 상한을 쓸지 고른다(`receipt`·`submit`).
 *
 * Workers KV 로 창별 카운터를 센다. 예전에는 네이티브 `[[ratelimits]]` 바인딩을
 * 썼는데 이 계정에서는 카운팅이 안 됐다(항상 통과). **막을 때는 KV 에 쓰지 않는다**
 * — 상한에 도달한 IP 의 추가 요청은 읽기만 하고 거절해서, KV 쓰기가 공격량이 아니라
 * "상한 수" 에만 비례하게 한다.
 *
 * 바인딩이 없거나(로컬 개발) KV 가 삐끗하면 **통과시킨다(fail-open)** — 값싼 공개
 * 폼에서 저장소 한 번 흔들렸다고 정상 사용자를 막을 이유가 없다.
 */
async function withinRateLimit(env, request, action) {
    const limits = RATE_LIMITS[action];
    if (!env.RATE_KV || !limits) {
        console.warn(`RATE_KV 없음 또는 미정의 action(${action}) — 제한을 건너뛴다`);
        return true;
    }
    const who = clientKey(request);
    const now = Date.now();
    try {
        const windows = limits.map(([windowSec, max]) => ({
            key: `rl:${action}:${who}:${windowSec}:${Math.floor(now / (windowSec * 1000))}`,
            windowSec,
            max,
        }));
        const counts = await Promise.all(
            windows.map((w) => env.RATE_KV.get(w.key).then((v) => Number(v) || 0)),
        );
        // 한 창이라도 상한에 닿으면 막는다. 이때는 쓰지 않는다.
        if (windows.some((w, i) => counts[i] >= w.max)) return false;
        // 다 통과 → 각 창 카운터를 올린다. 창이 지나면 저절로 사라지게 TTL 을 건다.
        await Promise.all(
            windows.map((w, i) =>
                env.RATE_KV.put(w.key, String(counts[i] + 1), { expirationTtl: w.windowSec + 5 }),
            ),
        );
        return true;
    } catch (error) {
        console.error('rate limit 확인 실패 — 통과시킨다', error);
        return true;
    }
}

// ---------------------------------------------------------------------------
// 라우트
// ---------------------------------------------------------------------------

async function handleSubmit(request, env, ctx) {
    if (!(await withinRateLimit(env, request, 'submit'))) {
        return json({ message: '요청이 많아요. 잠시 후 다시 시도해 주세요.' }, 429);
    }

    let form;
    try {
        form = await request.formData();
    } catch {
        return json({ message: '폼을 읽지 못했습니다.' }, 400);
    }

    const text = (name) => (form.get(name) ?? '').toString().trim();

    // 이름의 공백을 보통 공백으로 통일해서 저장한다.
    // DB 인덱스(\s)와 앱(isWhitespace)이 보는 공백 범위가 미묘하게 달라서,
    // 비분리 공백(U+00A0) 같은 게 섞여 들어오면 계좌부 대조가 어긋난다.
    // 앱의 String.whitespaceNormalized 와 같은 일을 한다.
    const submitterName = text('submitter_name').split(/\s+/u).filter(Boolean).join(' ');
    const title = text('title');
    const amount = Number.parseInt(text('amount').replace(/[,\s원]/g, ''), 10);

    if (!submitterName || !title) {
        return json({ message: '빠진 항목이 있어요. 다시 확인해 주세요.' }, 400);
    }
    if (submitterName.length > 30 || title.length > 60) {
        return json({ message: '입력이 너무 길어요. 짧게 줄여주세요.' }, 400);
    }
    if (!Number.isInteger(amount) || amount <= 0) {
        return json({ message: '금액을 숫자로 입력해 주세요.' }, 400);
    }
    if (amount > MAX_AMOUNT) {
        return json({ message: '금액이 너무 커요. 담당자에게 직접 알려주세요.' }, 400);
    }

    // 영수증은 두 가지 경로로 온다.
    //   (1) 폼이 미리 /bill/receipt 로 올려두고 URL+서명만 넘긴 경우 — 보통 이쪽이다
    //   (2) 파일이 그대로 붙어 온 경우 — 선행 업로드가 실패했거나 JS가 안 도는 브라우저
    let receiptUrl = text('receipt_url');
    if (receiptUrl) {
        if (!(await verifyReceiptUrl(env, receiptUrl, text('receipt_token')))) {
            return json({ message: '영수증 정보가 올바르지 않아요. 사진을 다시 첨부해 주세요.' }, 400);
        }
    } else {
        const receipt = form.get('receipt');
        const problem = receiptProblem(receipt);
        if (problem) return json({ message: problem }, 400);

        try {
            receiptUrl = await uploadReceipt(env, receipt);
        } catch (error) {
            console.error(error);
            return json({ message: '영수증 업로드에 실패했어요. 잠시 후 다시 시도해 주세요.' }, 502);
        }
    }

    let bill;
    try {
        bill = await insertBill(env, {
            submitter_name: submitterName,
            title,
            amount,
            receipt_url: receiptUrl,
        });
    } catch (error) {
        console.error(error);
        return json({ message: '접수에 실패했어요. 잠시 후 다시 시도해 주세요.' }, 502);
    }

    // 푸시는 접수 성공과 무관하게 백그라운드로 보낸다.
    ctx.waitUntil(
        fetchDeviceTokens(env).then((tokens) => sendBillNotification(env, tokens, bill)),
    );

    return json({ ok: true, bill: { submitter_name: bill.submitter_name, title: bill.title, amount: bill.amount } });
}

/**
 * 영수증만 먼저 받아 R2 에 올리고 URL + 서명을 돌려준다.
 *
 * 사진 업로드는 제출 과정에서 제일 오래 걸리는 구간이라, 사용자가 나머지 칸을
 * 채우는 동안 미리 끝내 둔다. 여기서 올렸는데 제출까지 오지 않으면 R2 에 안 쓰는
 * 파일이 남는다 — 폼이 축소해서 올리므로 수백 KB짜리고, 접수 실패보다 낫다고 봤다.
 */
async function handleReceiptUpload(request, env) {
    if (!(await withinRateLimit(env, request, 'receipt'))) {
        return json({ message: '요청이 많아요. 잠시 후 다시 시도해 주세요.' }, 429);
    }

    let form;
    try {
        form = await request.formData();
    } catch {
        return json({ message: '사진을 읽지 못했습니다.' }, 400);
    }

    const receipt = form.get('receipt');
    const problem = receiptProblem(receipt);
    if (problem) return json({ message: problem }, 400);

    let url;
    try {
        url = await uploadReceipt(env, receipt);
    } catch (error) {
        console.error(error);
        return json({ message: '영수증 업로드에 실패했어요. 잠시 후 다시 시도해 주세요.' }, 502);
    }

    return json({ url, token: await signReceiptUrl(env, url) });
}

/**
 * 접수까지 가지 않은 선행 업로드를 지운다.
 *
 * 폼은 두 시점에 이걸 부른다 — 사진을 다른 걸로 바꿨을 때, 그리고 접수 전에 창을 닫을 때.
 * 브라우저가 못 보내고 꺼지는 경우까지는 못 막으므로 고아 파일이 0이 되지는 않는다.
 * 완전히 없애려면 R2 수명 주기 규칙이 필요하고, 그건 별개의 일이다.
 *
 * 공개 경로라 URL만 알면 남의 영수증을 지우는 일이 없어야 한다. 그래서 두 겹으로 막는다 —
 * 업로드할 때 받은 서명이 있어야 하고, 이미 접수에 쓰인 영수증이면 거절한다.
 */
async function handleReceiptDiscard(request, env) {
    let payload;
    try {
        payload = await request.json();
    } catch {
        return new Response(null, { status: 204 });
    }

    const url = typeof payload?.url === 'string' ? payload.url : '';
    if (!url || !(await verifyReceiptUrl(env, url, payload?.token))) {
        return new Response(null, { status: 204 });
    }

    try {
        if (!(await receiptIsInUse(env, url))) await deleteReceipt(env, url);
    } catch (error) {
        // 못 지워도 사용자가 할 수 있는 일은 없다. 조용히 넘긴다.
        console.error('영수증 폐기 실패', error);
    }
    return new Response(null, { status: 204 });
}

// ---------------------------------------------------------------------------
// 앱이 부르는 영수증 라우트
//
// **관리자만 부를 수 있다.** 앱이 Supabase 세션의 access token 을
// `Authorization: Bearer` 로 넘기고, 워커가 그걸 Supabase 에 물어 확인한 뒤
// `admins` 화이트리스트에 있는 이메일인지 본다.
//
// 화이트리스트를 기준으로 삼는 이유는 RLS 와 같다 — Google provider 는 아무 구글
// 계정이나 로그인시키므로 "로그인했다" 만으로는 아무것도 못 막는다. DB 의 RLS 가
// `is_admin()` 을 쓰는 것과 **같은 판단을 같은 표로** 한다.
//
// CORS 헤더는 안 준다. 부르는 건 앱의 URLSession 뿐이라 브라우저 프리플라이트가
// 없다. 공개 폼은 이 라우트를 안 쓰고 `/bill/receipt` 로 간다.
// ---------------------------------------------------------------------------

/**
 * `Authorization: Bearer <supabase access token>` 을 확인한다.
 *
 * 통과하면 `null`, 막으면 그대로 돌려줄 `Response` 를 준다.
 * 부르는 쪽이 `const denied = await requireAdmin(...); if (denied) return denied;`
 * 로 쓴다.
 *
 * 토큰을 여기서 직접 열어보지 않는다. JWT 서명 검증을 손으로 하려면 Supabase 의
 * 서명 키를 워커가 들고 있어야 하는데, 그건 비밀이 하나 더 느는 일이다.
 * Supabase 에 물어보면 만료·폐기까지 한 번에 판정된다.
 */
async function requireAdmin(request, env) {
    const header = request.headers.get('authorization') || '';
    const token = header.toLowerCase().startsWith('bearer ') ? header.slice(7).trim() : '';
    if (!token) return json({ error: '인증이 필요합니다.' }, 401);

    // 1) 토큰이 진짜인가 → 누구인가
    const userResponse = await fetch(`${env.SUPABASE_URL}/auth/v1/user`, {
        headers: {
            apikey: env.SUPABASE_SERVICE_ROLE_KEY,
            authorization: `Bearer ${token}`,
        },
    });
    if (!userResponse.ok) return json({ error: '인증이 필요합니다.' }, 401);

    const email = (await userResponse.json())?.email?.toLowerCase();
    if (!email) return json({ error: '인증이 필요합니다.' }, 401);

    // 2) 그 사람이 관리자인가 (RLS 의 is_admin() 과 같은 표를 본다)
    const adminResponse = await fetch(
        `${env.SUPABASE_URL}/rest/v1/admins?select=email&email=eq.${encodeURIComponent(email)}`,
        { headers: supabaseHeaders(env) },
    );
    if (!adminResponse.ok) {
        console.error('admins 조회 실패', adminResponse.status);
        return json({ error: '인증을 확인할 수 없습니다.' }, 503);
    }
    if ((await adminResponse.json()).length === 0) {
        return json({ error: '권한이 없습니다.' }, 403);
    }

    return null;
}

async function handleAppReceiptUpload(request, env) {
    const denied = await requireAdmin(request, env);
    if (denied) return denied;

    try {
        const form = await request.formData();
        const file = form.get('file');
        if (!file || typeof file === 'string') return json({ error: '파일 없음' }, 400);

        const folder = form.get('folder');
        const url = await putReceipt(env, file, typeof folder === 'string' && folder ? folder : 'receipts');
        return json({ url });
    } catch (error) {
        console.error('앱 영수증 업로드 실패', error);
        return json({ error: '업로드에 실패했습니다.' }, 500);
    }
}

async function handleAppReceiptDelete(request, env) {
    const denied = await requireAdmin(request, env);
    if (denied) return denied;

    try {
        const { receiptUrl } = await request.json();
        // 우리 버킷 URL 이 아니면 지운 것이 없다. 그래도 앱은 할 일이 없으므로
        // 실패로 만들지 않는다 — 앱은 이 응답을 보지 않는다.
        await deleteReceiptByUrl(env, receiptUrl);
        return json({ success: true });
    } catch (error) {
        console.error('앱 영수증 삭제 실패', error);
        return json({ error: '삭제에 실패했습니다.' }, 500);
    }
}

// ---------------------------------------------------------------------------
// R2 고아 영수증 정리 (예약 실행)
// ---------------------------------------------------------------------------
//
// 폼이 사진을 미리 `/bill/receipt` 로 올렸는데 접수까지 오지 않으면 R2 에 안 쓰는
// 파일이 남는다. 폼이 사진 교체·창 닫기 때 `discard` 로 대부분 지우지만, 브라우저가
// 그냥 죽으면 못 지운다. 그 고아를 주기적으로 쓸어낸다.
//
// ⚠️ **일괄 "오래된 것 삭제" 로 하면 진짜 영수증까지 지운다.** 미리 올린 것과 접수까지
//    간 진짜 영수증이 같은 키 공간에 살기 때문이다. 그래서 **참조된 것은 절대 안
//    지운다** — DB 에서 실제로 쓰이는 URL 을 다 모아 그 목록에 없는 것만 지운다.
//    참조는 두 군데다: `bills.receipt_url`(공개 폼) 과 `finance_items.receipt_urls`
//    (앱/재정). 둘 중 하나라도 못 읽으면 **아무것도 안 지운다**(fail-closed) — 목록이
//    반쪽이면 멀쩡한 영수증을 고아로 오인하기 때문이다.

const RECEIPT_PREFIX = 'receipts/';
/** 막 올리고 아직 저장(제출/항목 저장) 전인 파일을 지우지 않도록 두는 유예 시간. */
const ORPHAN_GRACE_MS = 6 * 60 * 60 * 1000;

/**
 * PostgREST 한 표를 **전부** 읽는다. 기본 상한(1000행)에서 잘리면 참조 목록이
 * 반쪽이 되어 멀쩡한 영수증을 지우게 되므로, `Range` 로 페이지를 넘겨 끝까지 모은다.
 * 한 페이지라도 실패하면 throw — 호출부가 정리를 중단한다.
 */
async function fetchAllRows(env, pathAndQuery) {
    const pageSize = 1000;
    const rows = [];
    for (let from = 0; ; from += pageSize) {
        const res = await fetch(`${env.SUPABASE_URL}/rest/v1/${pathAndQuery}`, {
            headers: supabaseHeaders(env, {
                'range-unit': 'items',
                range: `${from}-${from + pageSize - 1}`,
            }),
        });
        if (!res.ok) throw new Error(`${pathAndQuery} 조회 실패: ${res.status}`);
        const batch = await res.json();
        rows.push(...batch);
        if (batch.length < pageSize) break;
    }
    return rows;
}

/**
 * DB 가 실제로 참조하는 영수증 **키**(공개 URL 앞부분을 뗀 것)를 전부 모은다.
 * 하나라도 못 읽으면 `null` — 호출부가 이걸 보고 정리를 통째로 건너뛴다.
 */
async function referencedReceiptKeys(env) {
    const prefix = `${env.R2_PUBLIC_URL}/`;
    const toKey = (u) =>
        typeof u === 'string' && u.startsWith(prefix) ? u.slice(prefix.length) : null;
    const keys = new Set();
    try {
        for (const row of await fetchAllRows(env, 'bills?select=receipt_url')) {
            const k = toKey(row.receipt_url);
            if (k) keys.add(k);
        }
        for (const row of await fetchAllRows(env, 'finance_items?select=receipt_urls')) {
            for (const u of row.receipt_urls ?? []) {
                const k = toKey(u);
                if (k) keys.add(k);
            }
        }
    } catch (error) {
        console.error('참조 영수증 목록을 못 만들었다 — 정리를 건너뛴다', error);
        return null;
    }
    return keys;
}

/**
 * 참조되지 않고 유예 시간보다 오래된 영수증만 지운다. 참조 목록을 못 만들면
 * 아무것도 안 지운다.
 */
async function cleanupOrphanReceipts(env) {
    const referenced = await referencedReceiptKeys(env);
    if (!referenced) return;

    const cutoff = Date.now() - ORPHAN_GRACE_MS;
    let cursor;
    let scanned = 0;
    let deleted = 0;
    do {
        const list = await env.RECEIPT_BUCKET.list({ prefix: RECEIPT_PREFIX, cursor });
        for (const obj of list.objects) {
            scanned += 1;
            if (referenced.has(obj.key)) continue; // 장부·청구가 쓰는 것 — 절대 안 지운다
            if (obj.uploaded.getTime() > cutoff) continue; // 막 올린 것 — 아직 저장 전일 수 있다
            await env.RECEIPT_BUCKET.delete(obj.key);
            deleted += 1;
        }
        cursor = list.truncated ? list.cursor : undefined;
    } while (cursor);

    console.log(`R2 고아 영수증 정리: ${scanned}개 중 ${deleted}개 삭제`);
}

export default {
    async fetch(request, env, ctx) {
        const { pathname } = new URL(request.url);
        const { method } = request;

        if (method === 'GET' && (pathname === '/' || pathname === '/bill')) {
            return html(renderForm());
        }
        if (method === 'POST' && pathname === '/bill/receipt') {
            return handleReceiptUpload(request, env);
        }
        if (method === 'POST' && pathname === '/bill/receipt/discard') {
            return handleReceiptDiscard(request, env);
        }
        if (method === 'POST' && pathname === '/bill/submit') {
            return handleSubmit(request, env, ctx);
        }
        if (method === 'POST' && pathname === '/receipt/upload') {
            return handleAppReceiptUpload(request, env);
        }
        if (method === 'POST' && pathname === '/receipt/delete') {
            return handleAppReceiptDelete(request, env);
        }

        return new Response('Not Found', { status: 404 });
    },

    // 예약 실행(cron). R2 에 남은 고아 영수증을 쓸어낸다. wrangler.toml 의
    // [triggers] 가 언제 도는지 정한다.
    async scheduled(event, env, ctx) {
        ctx.waitUntil(cleanupOrphanReceipts(env));
    },
};
