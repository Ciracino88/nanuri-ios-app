// 청구 폼 링크에 실어 보내는 서명 토큰.
//
// 폼 URL은 카카오톡 인앱 브라우저로 열리는 공개 주소라 그 자체로는 보호되지 않는다.
// 발신자(카카오 채널 고유 ID)와 만료 시각을 HMAC으로 묶어, 챗봇이 발급한 링크로만
// 폼을 열고 제출할 수 있게 한다.

const TOKEN_TTL_SECONDS = 30 * 60;

function base64UrlEncode(bytes) {
    let binary = '';
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function base64UrlDecode(text) {
    const padded = text.replace(/-/g, '+').replace(/_/g, '/');
    const binary = atob(padded.padEnd(Math.ceil(padded.length / 4) * 4, '='));
    return Uint8Array.from(binary, (char) => char.charCodeAt(0));
}

async function hmacKey(secret) {
    return crypto.subtle.importKey(
        'raw',
        new TextEncoder().encode(secret),
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign', 'verify'],
    );
}

/** 발신자 ID를 담은 서명 토큰을 만든다. */
export async function issueToken(kakaoUserId, secret) {
    const payload = {
        uid: kakaoUserId,
        exp: Math.floor(Date.now() / 1000) + TOKEN_TTL_SECONDS,
    };
    const body = base64UrlEncode(new TextEncoder().encode(JSON.stringify(payload)));
    const signature = await crypto.subtle.sign('HMAC', await hmacKey(secret), new TextEncoder().encode(body));
    return `${body}.${base64UrlEncode(new Uint8Array(signature))}`;
}

/**
 * 토큰을 검증하고 발신자 ID를 돌려준다.
 * 서명이 틀리거나 만료됐으면 null.
 */
export async function verifyToken(token, secret) {
    if (typeof token !== 'string' || !token.includes('.')) return null;

    const [body, signature] = token.split('.');
    if (!body || !signature) return null;

    let valid;
    try {
        valid = await crypto.subtle.verify(
            'HMAC',
            await hmacKey(secret),
            base64UrlDecode(signature),
            new TextEncoder().encode(body),
        );
    } catch {
        return null;
    }
    if (!valid) return null;

    let payload;
    try {
        payload = JSON.parse(new TextDecoder().decode(base64UrlDecode(body)));
    } catch {
        return null;
    }

    if (typeof payload.exp !== 'number' || payload.exp < Math.floor(Date.now() / 1000)) {
        return null;
    }
    return typeof payload.uid === 'string' ? payload.uid : null;
}
