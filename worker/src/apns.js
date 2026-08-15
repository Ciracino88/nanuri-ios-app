// APNs 푸시 발송. 토큰 기반(.p8) 인증을 쓴다.
//
// 인증서 방식과 달리 p8 키 하나로 ES256 JWT를 서명해 Authorization 헤더에 넣는다.
// JWT는 최대 1시간 유효하고 재사용이 권장되므로 워커 인스턴스 수명 동안 캐시한다.

const JWT_REUSE_SECONDS = 50 * 60;

let cachedJwt = null;
let cachedAt = 0;

function base64UrlEncode(input) {
    const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : new Uint8Array(input);
    let binary = '';
    for (const byte of bytes) binary += String.fromCharCode(byte);
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/** PKCS#8 PEM(.p8 파일 내용)을 WebCrypto 키로 읽는다. */
async function importP8(pem) {
    const body = pem
        .replace(/-----BEGIN PRIVATE KEY-----/, '')
        .replace(/-----END PRIVATE KEY-----/, '')
        .replace(/\s+/g, '');
    const der = Uint8Array.from(atob(body), (char) => char.charCodeAt(0));

    return crypto.subtle.importKey(
        'pkcs8',
        der,
        { name: 'ECDSA', namedCurve: 'P-256' },
        false,
        ['sign'],
    );
}

async function providerToken(env) {
    const now = Math.floor(Date.now() / 1000);
    if (cachedJwt && now - cachedAt < JWT_REUSE_SECONDS) return cachedJwt;

    const header = base64UrlEncode(JSON.stringify({ alg: 'ES256', kid: env.APNS_KEY_ID }));
    const payload = base64UrlEncode(JSON.stringify({ iss: env.APNS_TEAM_ID, iat: now }));
    const signingInput = `${header}.${payload}`;

    // WebCrypto의 ECDSA 서명은 r||s 원시 형식이라 JWT가 요구하는 형식과 같다.
    const signature = await crypto.subtle.sign(
        { name: 'ECDSA', hash: 'SHA-256' },
        await importP8(env.APNS_P8),
        new TextEncoder().encode(signingInput),
    );

    cachedJwt = `${signingInput}.${base64UrlEncode(signature)}`;
    cachedAt = now;
    return cachedJwt;
}

/**
 * 등록된 모든 기기에 청구서 알림을 보낸다.
 * 실패해도 청구서 접수 자체는 성공이므로 예외를 밖으로 던지지 않는다.
 */
export async function sendBillNotification(env, deviceTokens, bill) {
    if (deviceTokens.length === 0) return;

    // 설정이 덜 됐으면 엉뚱한 JWT를 만들어 401을 받느니 여기서 분명하게 끊는다.
    const missing = ['APNS_KEY_ID', 'APNS_TEAM_ID', 'APNS_P8'].filter((key) => !env[key]);
    if (missing.length > 0) {
        console.warn(`APNs 설정 없음: ${missing.join(', ')} — 푸시를 건너뛴다`);
        return;
    }

    let jwt;
    try {
        jwt = await providerToken(env);
    } catch (error) {
        console.error('APNs JWT 생성 실패', error);
        return;
    }

    const body = JSON.stringify({
        aps: {
            alert: {
                title: '새 청구서',
                body: `${bill.submitter_name} · ${bill.amount.toLocaleString('ko-KR')}원 · ${bill.title}`,
            },
            sound: 'default',
            badge: 1,
        },
        billId: bill.id,
    });

    await Promise.all(
        deviceTokens.map(async ({ token, environment }) => {
            const host = environment === 'sandbox'
                ? 'https://api.sandbox.push.apple.com'
                : 'https://api.push.apple.com';
            try {
                const response = await fetch(`${host}/3/device/${token}`, {
                    method: 'POST',
                    headers: {
                        authorization: `bearer ${jwt}`,
                        'apns-topic': env.APNS_TOPIC,
                        'apns-push-type': 'alert',
                        'apns-priority': '10',
                        'content-type': 'application/json',
                    },
                    body,
                });
                if (!response.ok) {
                    console.error('APNs 발송 실패', response.status, await response.text());
                }
            } catch (error) {
                console.error('APNs 요청 오류', error);
            }
        }),
    );
}
