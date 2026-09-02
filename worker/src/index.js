// 나누리 청구 접수 워커.
//
//   GET  /             공개 청구 폼 (= /bill)
//   POST /bill/receipt          영수증만 먼저 올린다 → { url, token }
//   POST /bill/receipt/discard  올렸지만 접수까지 가지 않은 영수증을 지운다
//   POST /bill/submit   검증 → bills INSERT → 관리자에게 푸시
//
//   POST /receipt/upload   앱이 영수증을 올린다 (청구서 삭제 복구용 · 재정 영수증)
//   POST /receipt/delete   앱이 영수증을 지운다
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
 * 공개 URL이라 아무나 제출할 수 있다. 최소한 한 IP가 R2에 이미지를 무한히
 * 밀어넣지는 못하게 막는다. 정상 사용자는 걸릴 일이 없는 수준(분당 5건)이다.
 * 바인딩이 없으면(로컬 개발 등) 그냥 통과시킨다.
 */
async function withinRateLimit(env, request) {
    if (!env.SUBMIT_RATE_LIMIT) {
        // 조용히 통과시키면 제한이 안 걸리는 걸 알아채지 못한다.
        console.warn('SUBMIT_RATE_LIMIT 바인딩 없음 — 제한을 건너뛴다');
        return true;
    }
    const key = request.headers.get('cf-connecting-ip') ?? 'unknown';
    try {
        // 주의: 2026-08-15 현재 이 계정에서는 항상 success:true 가 돌아온다.
        // 자세한 내용은 wrangler.toml 의 [[ratelimits]] 주석 참고.
        const { success } = await env.SUBMIT_RATE_LIMIT.limit({ key });
        return success;
    } catch (error) {
        console.error('rate limit 확인 실패', error);
        return true;
    }
}

// ---------------------------------------------------------------------------
// 라우트
// ---------------------------------------------------------------------------

async function handleSubmit(request, env, ctx) {
    if (!(await withinRateLimit(env, request))) {
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
    if (!(await withinRateLimit(env, request))) {
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
// **인증이 없다.** 예전 `nanuri-bill` 워커가 그랬고 그대로 옮겨 온 것이라, 지금은
// 영수증 URL 을 아는 사람이 그 영수증을 지울 수 있다. 공개 폼이 쓰는 `/bill/*` 는
// HMAC 서명(`verifyReceiptUrl`)으로 막혀 있지만 이쪽은 앱 전용이라 그게 없다.
// **관리자 인증을 붙일 때 여기도 같이 막을 것.**
//
// CORS 헤더는 안 준다. 부르는 건 앱의 URLSession 뿐이라 브라우저 프리플라이트가
// 없다. 공개 폼은 이 라우트를 안 쓰고 `/bill/receipt` 로 간다.
// ---------------------------------------------------------------------------

async function handleAppReceiptUpload(request, env) {
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
};
