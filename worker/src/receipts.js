// 영수증 이미지 저장. R2 를 **직접** 다룬다.
//
// 예전에는 이 일을 `nanuri-bill` 이라는 별도 워커가 했고, 이 워커는 서비스
// 바인딩으로 그쪽에 넘겼다. 그 워커는 **소스가 어디에도 없었다** — 대시보드에서
// 만들어 배포한 것이라 고칠 수도 되돌릴 수도 없었다. 그래서 R2 버킷을 여기에
// 직접 붙이고 코드를 가져왔다.
//
// 가져오면서 얻은 것 셋.
//   * 배포되는 전부가 저장소에 있다.
//   * 워커 간 HTTP 왕복이 없어져서 폼 제출이 한 단계 짧아진다.
//   * 업로드 메타데이터(캐시 지시 등)를 이제 여기서 고칠 수 있다.
//
// **키 형식을 바꾸지 말 것** — `<folder>/<uuid>.<ext>` 다. 이미 저장된 영수증
// URL 이 이 형식이고, 삭제는 공개 URL 앞부분을 떼어내 키를 얻는다. 형식이
// 달라지면 옛 영수증을 지울 수 없게 된다.

/** 확장자를 못 알아보면 이걸 쓴다. 폼도 앱도 JPEG 로 줄여서 올린다. */
const FALLBACK_EXT = 'jpg';

/**
 * 파일 이름에서 확장자만 뽑는다.
 *
 * 점이 없는 이름(`receipt`)이면 `split('.').pop()` 이 이름 전체를 돌려준다.
 * 그대로 키에 붙이면 `receipts/<uuid>.receipt` 같은 게 나오므로 걸러낸다.
 */
function extensionOf(filename) {
    if (typeof filename !== 'string') return FALLBACK_EXT;
    const dot = filename.lastIndexOf('.');
    if (dot <= 0 || dot === filename.length - 1) return FALLBACK_EXT;
    const ext = filename.slice(dot + 1).toLowerCase();
    // 확장자 자리에 들어온 이상한 것(경로·공백)은 안 쓴다.
    return /^[a-z0-9]{1,8}$/.test(ext) ? ext : FALLBACK_EXT;
}

/**
 * 영수증 한 장을 R2 에 올리고 **공개 URL** 을 돌려준다.
 *
 * 영수증 버킷은 `pub-*.r2.dev` 공개 도메인이 붙어 있다. 앱이 이미지를 그릴 때
 * Kingfisher 가 인증 없이 GET 하고, 공개 폼도 올린 직후 미리보기를 보여주기
 * 때문이다. URL 은 추측할 수 없는 UUID 라 주소를 모르면 닿지 못한다.
 * (**장부 엑셀은 이 버킷에 두면 안 된다** — 그건 공개 도메인이 없는 별도 버킷이다)
 */
export async function putReceipt(env, file, folder = 'receipts') {
    const key = `${folder}/${crypto.randomUUID()}.${extensionOf(file.name)}`;

    await env.RECEIPT_BUCKET.put(key, file.stream(), {
        httpMetadata: {
            contentType: file.type || 'image/jpeg',
            // 영수증은 URL 이 곧 그 파일이라 내용이 절대 안 바뀐다. 1년 + immutable.
            // 앱은 Kingfisher 가 자기 디스크 캐시로 관리해서 이 헤더를 안 타지만,
            // 브라우저로 URL 을 직접 열거나 나중에 CDN 을 끼우면 그때 의미가 생긴다.
            cacheControl: 'public, max-age=31536000, immutable',
        },
    });

    return `${env.R2_PUBLIC_URL}/${key}`;
}

/**
 * 공개 URL 로 R2 오브젝트를 지운다.
 *
 * 우리 버킷 URL 이 아니면 아무것도 안 한다. 안 그러면 `replace` 가 아무 문자열이나
 * 그대로 통과시켜서 엉뚱한 키를 지우려 든다.
 */
export async function deleteReceiptByUrl(env, receiptUrl) {
    const prefix = `${env.R2_PUBLIC_URL}/`;
    if (typeof receiptUrl !== 'string' || !receiptUrl.startsWith(prefix)) return false;

    const key = receiptUrl.slice(prefix.length);
    if (!key) return false;

    await env.RECEIPT_BUCKET.delete(key);
    return true;
}
