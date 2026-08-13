import SwiftUI
import Supabase
import GoogleSignIn
import Combine

enum AuthState {
    case loading
    case loggedIn
    case requiresGoogleLogin
}

/// 관리자 1인 전용 앱이라 세션 만료를 두지 않는다.
/// Supabase SDK가 세션을 키체인에 보관하며 자동 갱신하므로,
/// 로그아웃하거나 세션이 서버에서 무효화되기 전까지 계속 로그인 상태를 유지한다.
@MainActor
class AuthViewModel: ObservableObject {
    @Published var authState: AuthState = .loading
    @Published var isLoading = false

    var isLoggedIn: Bool { authState == .loggedIn }

    init() {
        Task {
            for await (event, session) in await supabase.auth.authStateChanges {
                switch event {
                case .signedIn, .tokenRefreshed:
                    if authState != .loggedIn {
                        authState = session != nil ? .loggedIn : .requiresGoogleLogin
                    }
                case .signedOut:
                    authState = .requiresGoogleLogin
                default:
                    break
                }
            }
        }
    }

    /// 저장된 세션이 있으면 그대로 로그인 상태로 들어간다.
    /// 만료된 액세스 토큰은 SDK가 리프레시 토큰으로 알아서 갱신한다.
    func checkSession() async {
        isLoading = true
        let session = try? await supabase.auth.session
        authState = session != nil ? .loggedIn : .requiresGoogleLogin
        isLoading = false
    }

    func signInWithGoogle() async {
        isLoading = true
        do {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else { return }

            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                throw NSError(domain: "Auth", code: -1, userInfo: [NSLocalizedDescriptionKey: "ID Token 없음"])
            }

            try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken,
                    accessToken: result.user.accessToken.tokenString
                )
            )
        } catch {
            print("로그인 실패: \(error)")
        }
        isLoading = false
    }

    func signOut() async {
        GIDSignIn.sharedInstance.signOut()
        try? await supabase.auth.signOut()
        authState = .requiresGoogleLogin
    }
}
