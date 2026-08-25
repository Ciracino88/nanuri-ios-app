import SwiftUI
import Supabase
import GoogleSignIn
import Combine
import OSLog

enum AuthState {
    case loading
    case loggedIn
    case requiresGoogleLogin
}

/// 로그인 과정에서 우리가 직접 판단해 세우는 실패.
///
/// 즉석 `NSError(domain:code:userInfo:)` 대신 타입으로 둔 이유는 둘이다.
/// **문구가 한곳에 모이고**, 나중에 `case` 별로 다르게 대응할 수 있다
/// (지금은 둘 다 같은 문구를 보여주지만, 앞의 것은 화면 구성 문제라 재시도가
/// 의미 없고 뒤의 것은 구글 쪽 문제라 재시도가 의미 있다).
enum AuthError: LocalizedError {
    /// 구글 로그인 시트를 올릴 화면을 못 찾았다.
    case noPresentingViewController
    /// 구글은 로그인시켰는데 Supabase 에 넘길 ID 토큰이 없다.
    case missingIDToken

    var errorDescription: String? {
        switch self {
        case .noPresentingViewController: "로그인 화면을 띄울 수 없습니다."
        case .missingIDToken: "구글에서 로그인 정보를 받지 못했습니다."
        }
    }
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

    /// 인증 상태 스트림을 듣는 태스크.
    private var authStateTask: Task<Void, Never>?

    deinit {
        authStateTask?.cancel()
    }

    /// `authStateChanges` 는 **앱이 사는 동안 끝나지 않는 스트림**이다.
    ///
    /// 그래서 태스크를 들고 있는다. 안 들고 있으면 끊을 방법이 없고, `self` 를
    /// 강하게 잡으면 뷰모델이 영원히 안 죽는다. 실제로 이 객체는 앱 생명주기
    /// 객체라 죽을 일이 거의 없지만, **"언제 끝나는지 말할 수 없는 태스크"를
    /// 남겨 두지 않는다**는 게 규칙이다.
    init() {
        authStateTask = Task { [weak self] in
            for await (event, session) in await supabase.auth.authStateChanges {
                guard let self else { return }
                switch event {
                case .initialSession, .signedIn, .tokenRefreshed:
                    self.authState = session != nil ? .loggedIn : .requiresGoogleLogin
                case .signedOut, .userDeleted:
                    self.authState = .requiresGoogleLogin
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
            let idToken = try await googleIDToken()
            try await supabase.auth.signInWithIdToken(credentials: idToken)
        } catch {
            handleSignInFailure(error)
        }
        isLoading = false
    }

    /// 구글 로그인 시트를 띄우고 Supabase 에 넘길 자격증명을 만든다.
    private func googleIDToken() async throws -> OpenIDConnectCredentials {
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            throw AuthError.noPresentingViewController
        }

        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootViewController)

        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.missingIDToken
        }

        return .init(
            provider: .google,
            idToken: idToken,
            accessToken: result.user.accessToken.tokenString
        )
    }

    /// 사용자가 구글 시트를 **직접 닫은 것은 실패가 아니다.** 이 경우만 조용히 넘긴다.
    private func handleSignInFailure(_ error: Error) {
        let nsError = error as NSError
        let userCancelled = nsError.domain == kGIDSignInErrorDomain
            && nsError.code == GIDSignInError.canceled.rawValue
        guard !userCancelled else { return }

        errorMessage = "로그인에 실패했어요. 잠시 후 다시 시도해 주세요."
        Log.auth.error("로그인 실패: \(error.localizedDescription)")
    }

    func signOut() async {
        GIDSignIn.sharedInstance.signOut()
        do {
            try await supabase.auth.signOut()
        } catch {
            // 서버에 못 알렸어도 로컬 세션은 지우고 로그인 화면으로 보낸다.
            // 사용자가 누른 건 "로그아웃"이고, 네트워크 사정으로 그대로 남아 있으면
            // 더 이상하다.
            Log.auth.error("서버 로그아웃 실패: \(error.localizedDescription)")
        }
        authState = .requiresGoogleLogin
    }
}
