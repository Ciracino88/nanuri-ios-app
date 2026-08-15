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
///
/// 로그인 화면으로 되돌리는 경우는 딱 두 가지뿐이다.
///   * 키체인에 저장된 세션이 아예 없을 때
///   * 서버가 세션을 무효화해 SDK가 `signedOut`을 쏠 때 (로그아웃·계정 삭제 등)
///
/// 네트워크 실패로 토큰을 갱신하지 못한 것은 로그아웃이 아니다.
/// 리프레시 토큰은 키체인(kSecAttrAccessibleAfterFirstUnlock)에 그대로 남아 있고,
/// SDK가 앱이 활성화될 때마다 자동 갱신을 다시 시도한다.
@MainActor
class AuthViewModel: ObservableObject {
    @Published var authState: AuthState = .loading
    @Published var isLoading = false
    @Published var errorMessage: String?

    var isLoggedIn: Bool { authState == .loggedIn }

    init() {
        Task {
            for await (event, session) in await supabase.auth.authStateChanges {
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed:
                    authState = session != nil ? .loggedIn : .requiresGoogleLogin
                case .signedOut, .userDeleted:
                    authState = .requiresGoogleLogin
                default:
                    break
                }
            }
        }
    }

    /// 저장된 세션이 있으면 네트워크를 기다리지 않고 바로 들어간다.
    ///
    /// `auth.session`은 액세스 토큰이 만료됐을 때 갱신을 시도하고, 그 요청이
    /// 실패하면 그냥 throw 한다. 예전처럼 `try?`로 nil을 받아 로그인 화면을 띄우면
    /// 비행기모드·지하철처럼 잠깐 네트워크가 없을 때 멀쩡한 세션이 있는데도
    /// 로그아웃돼 버린다. 그래서 네트워크를 타지 않는 `currentSession`으로만 판단한다.
    /// 만료된 토큰 갱신은 SDK의 자동 갱신에 맡긴다.
    func checkSession() async {
        authState = supabase.auth.currentSession != nil ? .loggedIn : .requiresGoogleLogin
    }

    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil
        do {
            guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                  let rootViewController = windowScene.windows.first?.rootViewController else {
                throw NSError(domain: "Auth", code: -2,
                              userInfo: [NSLocalizedDescriptionKey: "로그인 화면을 띄울 수 없습니다."])
            }

            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

            guard let idToken = result.user.idToken?.tokenString else {
                throw NSError(domain: "Auth", code: -1,
                              userInfo: [NSLocalizedDescriptionKey: "ID Token 없음"])
            }

            try await supabase.auth.signInWithIdToken(
                credentials: .init(
                    provider: .google,
                    idToken: idToken,
                    accessToken: result.user.accessToken.tokenString
                )
            )
        } catch {
            // 사용자가 구글 시트를 직접 닫은 경우는 실패가 아니므로 조용히 넘긴다.
            let nsError = error as NSError
            let userCancelled = nsError.domain == kGIDSignInErrorDomain
                && nsError.code == GIDSignInError.canceled.rawValue
            if !userCancelled {
                errorMessage = "로그인에 실패했어요. 잠시 후 다시 시도해 주세요."
                print("로그인 실패: \(error)")
            }
        }
        isLoading = false
    }

    func signOut() async {
        GIDSignIn.sharedInstance.signOut()
        try? await supabase.auth.signOut()
        authState = .requiresGoogleLogin
    }
}
