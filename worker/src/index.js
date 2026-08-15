// 나누리 청구 접수 워커.
//
//   GET  /            공개 청구 폼 (= /bill)
//   POST /bill/submit 검증 → 영수증 업로드 → bills INSERT → 관리자에게 푸시
//
// 폼은 공개 URL이다. 주소를 아는 사람은 누구나 청구를 넣을 수 있고,
// 발신자를 식별할 방법이 없다. 그래서 이름만 받고, 계좌는 관리자가 앱의
// 계좌부(payees)에 등록해 둔 값을 이름으로 대조해서 쓴다.
//
// 영수증 이미지는 청구서·재정에서 이미 쓰고 있는 기존 R2 워커(/upload)에 위임한다.
// 저장되는 URL 형식이 앱이 아는 형식과 같아야 하므로 여기서 직접 R2를 다루지 않는다.

import { sendBillNotification } from './apns.js';
import { renderForm } from './form.js';

const MAX_RECEIPT_BYTES = 10 * 1024 * 1024;

// 오타로 0을 몇 개 더 붙이는 사고를 막는다. amount 컬럼이 integer라 상한은 어차피 필요하다.
const MAX_AMOUNT = 10_000_000;

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
    const body = new FormData();
    body.append('folder', 'receipts');
    body.append('file', file, file.name || 'receipt.jpg');

    // 서비스 바인딩으로 부른다. 공개 URL로 fetch 하면 같은 workers.dev 서브도메인이라
    // 요청이 이 워커로 되돌아와서 404가 난다. (호스트명은 바인딩에선 의미 없고 경로만 쓴다)
    const response = await env.RECEIPT_WORKER.fetch(
        'https://receipt-worker/upload',
        { method: 'POST', body },
    );
    if (!response.ok) throw new Error(`영수증 업로드 실패: ${response.status}`);

    // 기존 워커는 JSON({url|imageUrl|receiptUrl}) 또는 URL 문자열을 돌려준다. (앱과 동일한 처리)
    const text = await response.text();
    try {
        const parsed = JSON.parse(text);
        for (const key of ['url', 'imageUrl', 'receiptUrl']) {
            if (typeof parsed[key] === 'string') return parsed[key];
        }
    } catch {
        // JSON이 아니면 본문이 곧 URL
    }
    const trimmed = text.trim();
    if (trimmed.startsWith('http')) return trimmed;
    throw new Error('영수증 업로드 응답에서 URL을 찾지 못했습니다.');
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

    const receipt = form.get('receipt');
    if (!receipt || typeof receipt !== 'object' || receipt.size === 0) {
        return json({ message: '영수증 사진을 첨부해 주세요.' }, 400);
    }
    if (receipt.size > MAX_RECEIPT_BYTES) {
        return json({ message: '영수증 사진이 너무 커요. 10MB 이하로 올려주세요.' }, 400);
    }
    if (receipt.type && !receipt.type.startsWith('image/')) {
        return json({ message: '영수증은 사진 파일만 올릴 수 있어요.' }, 400);
    }

    let receiptUrl;
    try {
        receiptUrl = await uploadReceipt(env, receipt);
    } catch (error) {
        console.error(error);
        return json({ message: '영수증 업로드에 실패했어요. 잠시 후 다시 시도해 주세요.' }, 502);
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

    return json({ ok: true });
}

export default {
    async fetch(request, env, ctx) {
        const { pathname } = new URL(request.url);
        const { method } = request;

        if (method === 'GET' && (pathname === '/' || pathname === '/bill')) {
            return html(renderForm());
        }
        if (method === 'POST' && pathname === '/bill/submit') {
            return handleSubmit(request, env, ctx);
        }

        return new Response('Not Found', { status: 404 });
    },
};
