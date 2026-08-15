import Foundation
import Combine
import UserNotifications

/// 받은 푸시 하나.
///
/// `id` 는 `UNNotificationRequest.identifier` 다. 알림 센터에서 다시 주워 올 때
/// 같은 알림이 두 번 들어오는 걸 이걸로 막는다.
struct AppNotification: Identifiable, Codable, Equatable {
    let id: String
    let title: String
    let body: String
    let receivedAt: Date
    var isRead: Bool
}

/// 헤더 종 버튼이 보여 주는 알림함.
///
/// 서버에 알림 테이블이 없다. 그래서 이 목록은 **이 기기가 실제로 받은 푸시**가
/// 전부다 — 앱이 켜져 있을 때 온 것(`PushAppDelegate`)과, 꺼져 있는 동안 와서
/// 알림 센터에 남아 있는 것(`syncFromNotificationCenter`)을 합친다.
/// 사용자가 알림 센터에서 이미 지운 건 되살릴 수 없고, 기기를 바꾸면 비어 있다.
/// 기록이 남아야 한다면 그건 DB 테이블이 필요한 별개의 일이다.
@MainActor
final class NotificationStore: ObservableObject {
    static let shared = NotificationStore()

    @Published private(set) var items: [AppNotification] = []

    var unreadCount: Int { items.filter { !$0.isRead }.count }

    private let storageKey = "nanuri.receivedNotifications"
    /// 오래된 것부터 버린다. 청구 알림은 청구서 탭에 원본이 남으므로 길게 둘 이유가 없다.
    private let limit = 100

    private init() {
        load()
        syncBadge()
    }

    /// 앱이 켜져 있는 동안 도착한 알림.
    func record(_ notification: UNNotification) {
        let content = notification.request.content
        insert(
            AppNotification(
                id: notification.request.identifier,
                title: content.title.isEmpty ? "알림" : content.title,
                body: content.body,
                receivedAt: notification.date,
                isRead: false
            )
        )
    }

    /// 앱이 꺼져 있는 동안 온 알림을 알림 센터에서 주워 온다.
    /// 앱을 켤 때와 다시 활성화될 때 부른다 (`ContentView`).
    func syncFromNotificationCenter() async {
        let delivered = await UNUserNotificationCenter.current().deliveredNotifications()
        for notification in delivered {
            record(notification)
        }
    }

    func markAllRead() {
        guard unreadCount > 0 else { return }
        for index in items.indices where !items[index].isRead {
            items[index].isRead = true
        }
        save()
        syncBadge()
    }

    func removeAll() {
        guard !items.isEmpty else { return }
        items = []
        save()
        syncBadge()
    }

    /// 앱 아이콘 뱃지를 안 읽은 개수에 맞춘다.
    ///
    /// 워커는 푸시마다 `badge: 1` 을 보낸다. iOS 는 그 값을 **앱이 직접 바꾸기
    /// 전까지** 그대로 들고 있다 — 알림 센터를 비워도 안 지워진다. 그래서 뱃지를
    /// 내리는 건 이 앱의 몫이다. 알림함을 열어 다 읽으면(`markAllRead`) 0이 된다.
    private func syncBadge() {
        let count = unreadCount
        Task { try? await UNUserNotificationCenter.current().setBadgeCount(count) }
    }

    // MARK: - 내부

    /// 최신이 위로. 같은 알림이 다시 들어오면 읽음 상태를 유지한 채 무시한다.
    private func insert(_ notification: AppNotification) {
        guard !items.contains(where: { $0.id == notification.id }) else { return }
        items.append(notification)
        items.sort { $0.receivedAt > $1.receivedAt }
        if items.count > limit {
            items.removeLast(items.count - limit)
        }
        save()
        syncBadge()
    }

    private func load() {
        guard
            let data = UserDefaults.standard.data(forKey: storageKey),
            let decoded = try? JSONDecoder().decode([AppNotification].self, from: data)
        else { return }
        items = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
