// 카카오톡 챗봇 청구 접수 워커.
//
//   채팅방 [청구하기]
//     → POST /kakao/skill   챗봇 스킬. 서명된 폼 링크를 카드로 응답한다.
//     → GET  /bill/form     인앱 브라우저에서 열리는 청구 폼
//     → POST /bill/submit   검증 → 영수증 업로드 → bills INSERT → 관리자에게 푸시
//
// 영수증 이미지는 청구서·재정에서 이미 쓰고 있는 기존 R2 워커(/upload)에 위임한다.
// 저장되는 URL 형식이 앱이 아는 형식과 같아야 하므로 여기서 직접 R2를 다루지 않는다.

import { issueToken, verifyToken } from './token.js';
import { sendBillNotification } from './apns.js';
import { renderForm, renderExpired } from './form.js';

const MAX_RECEIPT_BYTES = 10 * 1024 * 1024;

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

/** 같은 발신자의 직전 청구서에서 이름·은행·계좌를 가져와 폼을 미리 채운다. */
async function fetchPrefill(env, kakaoUserId) {
    const query = new URLSearchParams({
        select: 'submitter_name,bank_name,account_number',
        kakao_user_id: `eq.${kakaoUserId}`,
        order: 'created_at.desc',
        limit: '1',
    });
    try {
        const response = await fetch(`${env.SUPABASE_URL}/rest/v1/bills?${query}`, {
            headers: supabaseHeaders(env),
        });
        if (!response.ok) return {};
        const [row] = await response.json();
        return row ?? {};
    } catch (error) {
        console.error('자동완성 조회 실패', error);
        return {};
    }
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

    const response = await fetch(`${env.RECEIPT_WORKER_URL}/upload`, { method: 'POST', body });
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
// 라우트
// ---------------------------------------------------------------------------

/** 챗봇 스킬. 폼 링크를 담은 카드를 돌려준다. */
async function handleSkill(request, env) {
    let payload;
    try {
        payload = await request.json();
    } catch {
        return json({ message: '잘못된 요청입니다.' }, 400);
    }

    // 오픈빌더는 요청에 서명을 붙이지 않으므로, 블록에 넣어둔 공유 시크릿으로 확인한다.
    if (env.KAKAO_SKILL_SECRET) {
        const provided = request.headers.get('x-nanuri-secret')
            ?? payload?.action?.params?.secret;
        if (provided !== env.KAKAO_SKILL_SECRET) {
            return json({ message: '허용되지 않은 요청입니다.' }, 403);
        }
    }

    const kakaoUserId = payload?.userRequest?.user?.id;
    if (!kakaoUserId) return json({ message: '발신자를 확인할 수 없습니다.' }, 400);

    const token = await issueToken(kakaoUserId, env.TOKEN_SECRET);
    const url = `${env.PUBLIC_BASE_URL}/bill/form?t=${encodeURIComponent(token)}`;

    return json({
        version: '2.0',
        template: {
            outputs: [{
                basicCard: {
                    title: '청구서 작성',
                    description: '아래 버튼을 눌러 작성해 주세요.\n작성하시면 담당자에게 바로 전달됩니다.',
                    buttons: [{ action: 'webLink', label: '청구서 작성하기', webLinkUrl: url }],
                },
            }],
        },
    });
}

async function handleForm(request, env) {
    const token = new URL(request.url).searchParams.get('t');
    const kakaoUserId = await verifyToken(token, env.TOKEN_SECRET);
    if (!kakaoUserId) return html(renderExpired(), 403);

    return html(renderForm(token, await fetchPrefill(env, kakaoUserId)));
}

async function handleSubmit(request, env, ctx) {
    let form;
    try {
        form = await request.formData();
    } catch {
        return json({ message: '폼을 읽지 못했습니다.' }, 400);
    }

    const kakaoUserId = await verifyToken(form.get('token'), env.TOKEN_SECRET);
    if (!kakaoUserId) {
        return json({ message: '링크가 만료됐어요. 채팅방에서 [청구하기]를 다시 눌러주세요.' }, 403);
    }

    const text = (name) => (form.get(name) ?? '').toString().trim();
    const submitterName = text('submitter_name');
    const bankName = text('bank_name');
    const accountNumber = text('account_number');
    const title = text('title');
    const note = text('note');
    const amount = Number.parseInt(text('amount').replace(/[,\s]/g, ''), 10);

    if (!submitterName || !bankName || !accountNumber || !title) {
        return json({ message: '빠진 항목이 있어요. 다시 확인해 주세요.' }, 400);
    }
    if (!Number.isInteger(amount) || amount <= 0) {
        return json({ message: '금액을 숫자로 입력해 주세요.' }, 400);
    }
    if (!/^[0-9-]{6,30}$/.test(accountNumber)) {
        return json({ message: '계좌번호를 다시 확인해 주세요.' }, 400);
    }

    let receiptUrl = null;
    const receipt = form.get('receipt');
    if (receipt && typeof receipt === 'object' && receipt.size > 0) {
        if (receipt.size > MAX_RECEIPT_BYTES) {
            return json({ message: '영수증 사진이 너무 커요. 10MB 이하로 올려주세요.' }, 400);
        }
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
            title,
            amount,
            submitter_name: submitterName,
            bank_name: bankName,
            account_number: accountNumber,
            receipt_url: receiptUrl,
            note: note || null,
            kakao_user_id: kakaoUserId,
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

        if (method === 'POST' && pathname === '/kakao/skill') return handleSkill(request, env);
        if (method === 'GET' && pathname === '/bill/form') return handleForm(request, env);
        if (method === 'POST' && pathname === '/bill/submit') return handleSubmit(request, env, ctx);

        return new Response('Not Found', { status: 404 });
    },
};
