import SwiftUI
import GoogleSignIn
import Combine

@main
struct NanuriAdminApp: App {
    @StateObject private var authViewModel = AuthViewModel()

    var body: some Scene {
        WindowGroup {
            Group {
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
