import SwiftUI
import UserNotifications
import Supabase

/// APNs 디바이스 토큰 등록.
///
/// 워커가 청구 접수 후 `device_tokens` 에 있는 토큰으로 푸시를 보낸다.
/// 이 파일이 그 테이블을 채우는 쪽이다.
///
/// - Note: 실제로 알림이 오려면 Xcode 의 Signing & Capabilities 에
///   **Push Notifications** capability 가 있어야 한다. 없으면
///   `registerForRemoteNotifications()` 가 `didFailToRegister...` 로 떨어진다.
///   (앱은 그대로 동작하고 알림만 오지 않는다)
@MainActor
final class PushManager {
    static let shared = PushManager()

    private init() {}

    /// 알림 권한을 묻고, 허용되면 APNs 등록을 시작한다.
    /// 등록 결과는 `PushAppDelegate` 의 콜백으로 돌아온다.
    ///
    /// 로그인 뒤에 불러야 한다. 토큰을 저장할 때 `auth.uid()` 가 필요하고,
    /// `device_tokens` 의 RLS 가 본인 행만 허용하기 때문이다.
    func requestAuthorizationAndRegister() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            guard granted else {
                print("알림 권한 거부됨")
                return
            }
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            print("알림 권한 요청 실패: \(error)")
        }
    }

    /// APNs 가 내려준 토큰을 `device_tokens` 에 넣는다.
    /// 토큰은 재설치·복원 등으로 바뀔 수 있으므로 켤 때마다 upsert 한다.
    func store(deviceToken: Data) async {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()

        guard let user = try? await supabase.auth.user() else {
            print("로그인 상태가 아니라 디바이스 토큰을 저장하지 못했다")
            return
        }

        do {
            try await supabase
                .from("device_tokens")
                .upsert(
                    DeviceTokenRow(token: token, userId: user.id, environment: Self.apnsEnvironment),
                    onConflict: "token"
                )
                .execute()
        } catch {
            print("디바이스 토큰 저장 실패: \(error)")
        }
    }

    /// 워커가 어느 APNs 호스트로 보낼지 정하는 값.
    ///
    /// 토큰이 발급되는 환경은 프로비저닝 프로파일의 `aps-environment` 를 따른다.
    /// Debug 빌드는 development 프로파일로 서명되므로 sandbox 가 맞다.
    /// TestFlight·배포 빌드는 production 이다.
    private static var apnsEnvironment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}

private struct DeviceTokenRow: Encodable {
    let token: String
    let userId: UUID
    let environment: String

    enum CodingKeys: String, CodingKey {
        case token, environment
        case userId = "user_id"
    }
}

/// APNs 콜백은 UIKit 델리게이트로만 온다. SwiftUI 앱에선 어댑터로 끼워 넣는다.
final class PushAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await PushManager.shared.store(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Push Notifications capability 가 없으면 여기로 떨어진다.
        print("APNs 등록 실패: \(error)")
    }

    /// 앱을 보고 있는 중에도 알림을 띄운다. 관리자 1인 전용이라 놓치면 곤란하다.
    /// 배너는 금방 사라지므로 헤더 알림함에도 같이 넣어 둔다.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        await NotificationStore.shared.record(notification)
        return [.banner, .sound, .badge]
    }

    /// 알림을 눌러서 앱이 열린 경우. 이때는 iOS 가 알림 센터에서 그 알림을 지우므로
    /// `syncFromNotificationCenter()` 로는 못 줍는다. 여기서 직접 넣는다.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        await NotificationStore.shared.record(response.notification)
    }
}
