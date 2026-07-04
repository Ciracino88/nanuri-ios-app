import SwiftUI
import Supabase
import GoogleSignIn
import LocalAuthentication
import Combine

enum AuthState {
    case loading
    case loggedIn
    case requiresFaceID
    case requiresGoogleLogin
}

@MainActor
class AuthViewModel: ObservableObject {
    @Published var authState: AuthState = .loading
    @Published var isLoading = false

    private let lastActiveKey = "lastActiveDate"
    private let sessionTimeout: TimeInterval = 3600

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

    func checkSession() async {
        isLoading = true
        let session = try? await supabase.auth.session

        if session != nil {
            let lastActive = UserDefaults.standard.object(forKey: lastActiveKey) as? Date
            let elapsed = lastActive.map { Date().timeIntervalSince($0) } ?? sessionTimeout + 1

            if elapsed < sessionTimeout {
                authState = .loggedIn
            } else {
                authState = .requiresFaceID
            }
        } else {
            authState = .requiresGoogleLogin
        }

        isLoading = false
    }

    func handleForeground() async {
        guard authState == .loggedIn else { return }
        let lastActive = UserDefaults.standard.object(forKey: lastActiveKey) as? Date
        guard let lastActive else { return }

        if Date().timeIntervalSince(lastActive) >= sessionTimeout {
            authState = .requiresFaceID
        }
    }

    func updateLastActiveDate() {
        UserDefaults.standard.set(Date(), forKey: lastActiveKey)
    }

    func switchToGoogleLogin() {
        authState = .requiresGoogleLogin
    }

    func signInWithFaceID() async {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            authState = .requiresGoogleLogin
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "관리자 인증"
            )
            if success {
                let session = try? await supabase.auth.session
                if session != nil {
                    updateLastActiveDate()
                    authState = .loggedIn
                } else {
                    authState = .requiresGoogleLogin
                }
            }
        } catch {
            print("Face ID 실패: \(error)")
        }
    }

    func signInWithGoogle() async {
        isLoading = true
        do {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else { return }

            let result = try await GIDSignIn.sharedInstance.signIn(
                withPresenting: rootViewController,
                hint: nil,
                additionalScopes: ["https://www.googleapis.com/auth/gmail.readonly"]
            )

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
            updateLastActiveDate()
        } catch {
            print("로그인 실패: \(error)")
        }
        isLoading = false
    }

    func signOut() async {
        UserDefaults.standard.removeObject(forKey: lastActiveKey)
        GIDSignIn.sharedInstance.signOut()
        try? await supabase.auth.signOut()
        authState = .requiresGoogleLogin
    }
}
