import SwiftUI
import Combine

/// 모든 탭이 쓰는 헤더. 앱의 상단은 항상 이 모양이다.
///
/// 슬롯은 넷이다 — **왼쪽 화면별 동작 · 가운데 화면 이름 · 오른쪽 화면별 동작 · 알림**.
/// 알림만 헤더가 직접 갖고 어느 탭에서나 같은 자리에 있다.
///
/// **새로고침 버튼은 없다.** 목록을 아래로 당기면 새로고침된다(`.refreshable`).
/// 예전에는 왼쪽 자리가 새로고침 고정이었는데, 청구서 탭이 실시간으로 들어오게
/// 되면서 버튼을 누를 일이 거의 없어졌다. 당겨서 새로고침은 목록 어디서나 되는
/// 손동작이라 자리를 차지하지 않는다. 대신 비워진 왼쪽을 화면이 쓴다
/// (청구서 탭의 묶어 보내기 선택 모드).
///
/// 한쪽에 아이콘은 **하나까지**다. 둘 이상이면 `Menu` 하나로 묶는다 (재정 탭의
/// `ellipsis.circle`). 아이콘이 늘어나면 가운데 이름이 밀린다.
///
/// 가운데를 누를 일이 있는 화면(재정 탭의 장부 전환)은 `titleAction` 을 준다.
/// 그러면 이름 옆에 `chevron.down` 이 붙어 눌리는 자리라는 게 보인다.
struct AdminHeaderView<Leading: View, Trailing: View>: View {
    let title: String
    /// 가운데 이름을 눌렀을 때. 주면 `chevron.down` 이 함께 그려진다.
    var titleAction: (() -> Void)?
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    @ObservedObject private var notifications = NotificationStore.shared
    @State private var showNotifications = false

    init(
        title: String,
        titleAction: (() -> Void)? = nil,
        @ViewBuilder leading: @escaping () -> Leading,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.title = title
        self.titleAction = titleAction
        self.leading = leading
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            titleView
            HStack(spacing: 0) {
                leading()
                Spacer(minLength: 0)
                trailing()
                notificationButton
            }
        }
        .frame(height: DS.Size.headerButton)
        .padding(.horizontal, DS.Spacing.small)
        // 배경도 구분선도 주지 않는다. 헤더는 화면 배경 위에 그냥 얹힌다.
        // 목록이 헤더 아래로 지나가지 않으므로(같은 VStack 안이다) 경계를 그릴 이유가 없다.
        .sheet(isPresented: $showNotifications) {
            NotificationListView()
        }
    }

    /// 양옆 버튼 자리를 비워 두고 가운데에 놓는다. 길면 줄이지 않고 자른다 —
    /// 두 줄이 되면 헤더 높이가 탭마다 달라진다.
    private var titleView: some View {
        Group {
            if let titleAction {
                Button(action: titleAction) {
                    HStack(spacing: DS.Spacing.tight) {
                        Text(title).headerTitle()
                        Image(systemName: "chevron.down")
                            .font(.system(size: DS.Icon.inline, weight: .medium))
                    }
                    .foregroundColor(.primary)
                }
                .buttonStyle(.plain)
            } else {
                Text(title).headerTitle()
            }
        }
        .lineLimit(1)
        .padding(.horizontal, DS.Size.headerButton * 2)
    }

    /// 안 읽은 알림은 점 하나로만 알린다. 색은 주황(대기) — 빨강은 돈이 나가거나
    /// 무언가 사라질 때만 쓴다 (DESIGN.md 5).
    private var notificationButton: some View {
        HeaderIconButton(systemName: "bell", label: notificationLabel) {
            showNotifications = true
        }
        .overlay(alignment: .topTrailing) {
            if notifications.unreadCount > 0 {
                Circle()
                    .fill(DS.Palette.pending)
                    .frame(width: 8, height: 8)
                    .offset(x: -9, y: 9)
            }
        }
    }

    private var notificationLabel: String {
        let unread = notifications.unreadCount
        return unread > 0 ? "알림 \(unread)개 안 읽음" : "알림"
    }
}

// 빈 슬롯은 자리를 차지하지 않는다. 가운데 이름은 `ZStack` 으로 화면 가운데에
// 놓이므로 양옆이 비어도 제목이 흔들리지 않는다.

extension AdminHeaderView where Leading == EmptyView {
    init(
        title: String,
        titleAction: (() -> Void)? = nil,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(title: title, titleAction: titleAction, leading: { EmptyView() }, trailing: trailing)
    }
}

extension AdminHeaderView where Trailing == EmptyView {
    init(
        title: String,
        titleAction: (() -> Void)? = nil,
        @ViewBuilder leading: @escaping () -> Leading
    ) {
        self.init(title: title, titleAction: titleAction, leading: leading, trailing: { EmptyView() })
    }
}

extension AdminHeaderView where Leading == EmptyView, Trailing == EmptyView {
    init(title: String, titleAction: (() -> Void)? = nil) {
        self.init(title: title, titleAction: titleAction, leading: { EmptyView() }, trailing: { EmptyView() })
    }
}

// MARK: - 헤더 버튼

/// 헤더에 놓는 아이콘 버튼. 화면별 동작도 이걸 써야 크기와 여백이 맞는다.
struct HeaderIconButton: View {
    let systemName: String
    /// VoiceOver 가 읽을 말. 아이콘뿐인 버튼이라 없으면 심볼 이름을 읽는다.
    let label: String
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HeaderIcon(systemName: systemName, tint: tint)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

/// `Menu` 처럼 버튼이 아닌 컨트롤의 라벨. 헤더 버튼과 크기가 같아야 줄이 안 어긋난다.
struct HeaderIcon: View {
    let systemName: String
    var tint: Color = .primary

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: DS.Icon.action, weight: .medium))
            .foregroundColor(tint)
            .frame(width: DS.Size.headerButton, height: DS.Size.headerButton)
            .contentShape(Rectangle())
    }
}
