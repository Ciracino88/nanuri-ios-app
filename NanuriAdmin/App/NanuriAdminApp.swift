import SwiftUI
import GoogleSignIn
import Combine
import os

@main
struct NanuriAdminApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    // APNs 콜백은 UIKit 델리게이트로만 온다.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate

    init() {
        // 이미지 캐시 상한. 기본값은 디스크 무제한이라 우리가 정해 준다.
        RemoteImageCache.configure()
        Self.removeLegacyStatementArchive()
    }

    /// 옛 "저장된 거래내역서" 보관함을 지운다.
    ///
    /// 2026-09-03 까지는 공유로 들어온 PDF 를 `Documents/Statements` 에 복사해 두고
    /// 목록에서 골라 불러왔다. 그 목록을 없애면서(원본은 파일 앱에 있고, 앱이 사본을
    /// 쌓을 이유가 없다) **코드만 지우면 파일은 기기에 그대로 남는다.** 꺼낼 길도
    /// 없이 용량만 차지하고 백업에도 올라가므로 한 번 지운다.
    ///
    /// 폴더가 없으면 아무 일도 안 한다. **이 관리자가 쓰는 기기에서 한 번 돌고 나면
    /// 지워도 되는 코드다** — 앱을 쓰는 사람이 하나뿐이라 그 시점을 알 수 있다.
    private static func removeLegacyStatementArchive() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let legacy = docs.appendingPathComponent("Statements", isDirectory: true)
        guard fm.fileExists(atPath: legacy.path) else { return }
        do {
            try fm.removeItem(at: legacy)
            Log.finance.info("옛 거래내역서 보관함을 지웠다")
        } catch {
            Log.finance.error("옛 보관함 삭제 실패: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            // 모디파이어는 화면 전환과 무관한 고정 컨테이너에 붙인다.
            // Group에 붙이면 SwiftUI가 자식마다 따로 적용해서,
            // 로그인 상태가 바뀔 때마다 checkSession()이 다시 돈다.
            ZStack {
                switch authViewModel.authState {
                case .loading:
                    ProgressView()
                case .loggedIn:
                    ContentView()
                        .environmentObject(authViewModel)
                case .requiresGoogleLogin:
                    LoginView(authViewModel: authViewModel)
                }
            }
            .task {
                await authViewModel.checkSession()
            }
            // **URL 은 여기서만 받는다.** 화면 쪽에도 달면 SwiftUI 가 하나에만
            // 주기 때문에 항상 붙어 있는 이쪽이 삼켜 버린다. 그리고 공유로 앱이
            // 켜지는 순간엔 아직 `.loading` 이라 탭이 계층에 없다 — 거기 달면
            // 그 URL 은 사라진다. 파일은 `IncomingFile` 에 담아 두고 탭이 꺼내 간다.
            .onOpenURL { url in
                guard !IncomingFile.shared.accept(url) else { return }
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
