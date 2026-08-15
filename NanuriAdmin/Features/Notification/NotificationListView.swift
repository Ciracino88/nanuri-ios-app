import SwiftUI
import Combine

/// 헤더의 종 버튼이 여는 알림함.
///
/// 열면 전부 읽음으로 바꾼다. 관리자 1인이 쓰는 앱이라 알림 하나하나를
/// 읽음 처리하게 만들 이유가 없다 — 점이 사라지는 게 목적이다.
struct NotificationListView: View {
    @ObservedObject private var store = NotificationStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var showClearAlert = false

    var body: some View {
        NavigationView {
            Group {
                if store.items.isEmpty {
                    EmptyStateView(
                        title: "받은 알림이 없어요",
                        icon: "bell",
                        message: "청구서가 접수되면 여기에 쌓여요.\n알림 센터에서 지운 알림은 여기에도 없어요."
                    )
                } else {
                    list
                }
            }
            .screenBackground()
            .navigationTitle("알림")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("닫기") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("모두 지우기") { showClearAlert = true }
                        .foregroundColor(DS.Palette.withdrawal)
                        .disabled(store.items.isEmpty)
                }
            }
            .alert("알림을 모두 지울까요?", isPresented: $showClearAlert) {
                Button("모두 지우기", role: .destructive) { store.removeAll() }
                Button("취소", role: .cancel) {}
            } message: {
                Text("청구서는 그대로 남아요. 이 목록만 비워져요.")
            }
        }
        .task {
            await store.syncFromNotificationCenter()
            store.markAllRead()
        }
    }

    private var list: some View {
        List(store.items) { notification in
            row(notification)
                .cardRow()
        }
        .listStyle(.plain)
        .screenBackground()
        .animation(DS.Motion.list, value: store.items)
    }

    private func row(_ notification: AppNotification) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.medium) {
            Image(systemName: "bell.badge")
                .font(.system(size: DS.Icon.feature))
                .foregroundColor(notification.isRead ? .secondary : DS.Palette.pending)
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text(notification.title)
                    .rowTitle()
                if !notification.body.isEmpty {
                    Text(notification.body)
                        .font(.subheadline)
                        .foregroundColor(.primary)
                }
                Text(notification.receivedAt.koreanDateTimeString)
                    .rowSubtext()
            }
            Spacer(minLength: 0)
        }
        .cardStyle()
    }
}
