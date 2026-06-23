import SwiftUI
import GoogleSignIn

@main
struct NanuriAdminApp: App {
    @StateObject private var authViewModel = AuthViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                switch authViewModel.authState {
                case .loading:
                    ProgressView()
                case .loggedIn:
                    ContentView()
                        .environmentObject(authViewModel)
                case .requiresFaceID, .requiresGoogleLogin:
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
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
            case .background, .inactive:
                authViewModel.updateLastActiveDate()
            case .active:
                Task { await authViewModel.handleForeground() }
            default:
                break
            }
        }
    }
}
