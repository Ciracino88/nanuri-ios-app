import Foundation

/// 공유로 막 들어온 거래내역서. `sheet(item:)` 에 넘기려고 감싼다.
///
/// 앱은 이 파일을 **보관하지 않는다.** 확인 화면이 닫히면 이 값도 사라지고,
/// 다시 필요하면 파일 앱에서 다시 공유한다.
struct IncomingStatement: Identifiable {
    let url: URL

    var id: String { url.absoluteString }
}
