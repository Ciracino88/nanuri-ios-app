import Foundation
import Combine

/// 밖에서 들어온 파일을 **탭이 준비될 때까지 들고 있는 자리.**
///
/// 공유 시트로 앱이 켜지면 URL 은 실행 직후에 도착하는데, 그때 `authState` 는
/// 아직 `.loading` 이라 `ContentView` 가 계층에 없다. 받을 화면이 없는 시점이라
/// 화면 쪽에 `onOpenURL` 을 달면 **그 URL 은 조용히 사라진다.**
///
/// 그래서 URL 은 **늘 붙어 있는 루트에서 한 번만 받고**, 여기 담아 둔다.
/// 로그인이 끝나 탭이 뜨면 그때 꺼내 간다.
///
/// `onOpenURL` 을 두 군데 두면 안 되는 이유이기도 하다 — SwiftUI 는 여럿이면
/// 하나에만 주므로, 항상 붙어 있는 루트가 받아서 삼켜 버린다.
@MainActor
final class IncomingFile: ObservableObject {
    static let shared = IncomingFile()

    /// 아직 처리 안 된 거래내역서 PDF. 꺼내 간 쪽이 `nil` 로 비운다.
    @Published var pendingPDF: URL?

    private init() {}

    /// 루트가 받은 URL 을 갈라 보낸다. PDF 면 담아 두고, 아니면 안 맡는다.
    /// - Returns: 이 파일을 맡았으면 `true`. `false` 면 부른 쪽이 다른 처리로 넘긴다.
    func accept(_ url: URL) -> Bool {
        guard url.pathExtension.lowercased() == "pdf" else { return false }
        pendingPDF = url
        return true
    }

    func consume() -> URL? {
        defer { pendingPDF = nil }
        return pendingPDF
    }
}
