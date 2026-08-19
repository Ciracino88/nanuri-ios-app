import SwiftUI
import GoogleSignIn
import Combine

@main
struct NanuriAdminApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    // APNs 콜백은 UIKit 델리게이트로만 온다.
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate

    init() {
        // 이미지 캐시 상한. 기본값은 디스크 무제한이라 우리가 정해 준다.
        RemoteImageCache.configure()
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
            .onOpenURL { url in
                GIDSignIn.sharedInstance.handle(url)
            }
        }
    }
}
