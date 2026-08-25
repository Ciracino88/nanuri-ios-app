import OSLog

/// 앱 로그. **`print` 대신 이걸 쓴다.**
///
/// `print` 를 안 쓰는 이유는 둘이다.
///
/// 1. **거를 수가 없다.** stdout 으로만 나가서 Console.app 이나 `log stream` 에서
///    레벨·카테고리로 걸러 볼 수 없고, 릴리스 빌드에도 그대로 남는다.
/// 2. **이 앱은 로그에 사람 이름과 계좌번호가 흐른다.** `Logger` 는 문자열 보간을
///    기본으로 가려서(`<private>`) 남긴다. 드러내려면 `\(값, privacy: .public)` 을
///    명시해야 한다. `print` 는 전부 그대로 찍히고, 그게 기기 로그에 남는다.
///
/// 그래서 **개인정보가 섞일 수 있는 값은 보간에 그대로 넣는다.** 가려지는 게 기본값이다.
/// 반대로 늘 보여야 하는 건 `privacy: .public` 을 붙인다.
enum Log {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "NanuriAdmin"

    /// 청구서 조회·상태 변경·삭제, 토스 송금.
    static let bill = Logger(subsystem: subsystem, category: "bill")
    /// 로그인·세션.
    static let auth = Logger(subsystem: subsystem, category: "auth")
    /// 장부·거래·거래내역서 PDF.
    static let finance = Logger(subsystem: subsystem, category: "finance")
    /// 계좌부.
    static let payee = Logger(subsystem: subsystem, category: "payee")
    /// APNs 등록·디바이스 토큰.
    static let push = Logger(subsystem: subsystem, category: "push")
}
