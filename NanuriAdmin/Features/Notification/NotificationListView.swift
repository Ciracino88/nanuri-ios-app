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
            // 헤더는 흰색으로 두고 **목록 영역만** 물들인다.
            .screenBackground(DS.Surface.notice)
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

    /// **카드가 아니라 섹션이다.**
    ///
    /// 항목마다 흰 상자를 주지 않고 줄이 배경 위에 그냥 앉는다. 가르는 건 상자도
    /// 구분선도 아닌 **여백**이다. 거래 목록처럼 촘촘히 훑는 화면이 아니라
    /// 문장을 읽는 화면이라, 상자가 줄마다 끼면 읽는 흐름이 끊긴다.
    private var list: some View {
        List(store.items) { notification in
            row(notification)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
        }
        .listStyle(.plain)
        .scrollBounceBehavior(.always)
        .screenBackground(DS.Surface.notice)
        .animation(DS.Motion.list, value: store.items)
    }

    /// 알림 한 줄 — 아이콘 타일 + 제목/본문 + 우측 시각.
    ///
    /// **본문을 자르지 않는다.** 알림은 기록이 아니라 문장이라 몇 줄이 되든 다 보인다.
    private func row(_ notification: AppNotification) -> some View {
        HStack(alignment: .top, spacing: DS.Spacing.medium) {
            iconTile(isRead: notification.isRead)

            VStack(alignment: .leading, spacing: DS.Spacing.s1 / 2) {
                Text(notification.title)
                    .rowTitle()
                if !notification.body.isEmpty {
                    Text(notification.body)
                        .typeStyle(DS.Typo.body2)
                        .foregroundColor(DS.Ink.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: DS.Spacing.small)

            Text(notification.receivedAt.koreanTimeString)
                .typeStyle(DS.Typo.body3)
                .foregroundColor(DS.Ink.placeholder)
                .lineLimit(1)
        }
        .padding(.horizontal, DS.Spacing.s4)
        .padding(.vertical, DS.Spacing.medium)
    }

    /// 타일 바탕은 **읽음 여부와 무관하게 흰색**이고, 읽지 않은 것만 글리프가
    /// 브랜드색이다.
    ///
    /// 배경이 옅은 파랑이라 타일까지 옅은 파랑(`brandWeak`)으로 주면 묻힌다.
    /// 흰 타일이 파란 바탕 위로 떠오르고, 색은 글리프가 진다.
    private func iconTile(isRead: Bool) -> some View {
        Image(systemName: "bell.fill")
            .font(DS.Icon.font(DS.Icon.m))
            .foregroundColor(isRead ? DS.Ink.placeholder : DS.Ink.brand)
            .frame(width: DS.Size.rowAvatar, height: DS.Size.rowAvatar)
            .background(DS.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l))
    }
}
