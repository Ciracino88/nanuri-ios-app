import SwiftUI

/// 앱 전체가 공유하는 디자인 토큰.
///
/// 규칙과 그 이유는 저장소 루트의 `DESIGN.md` 에 있다.
/// 화면 코드에 숫자를 직접 적기 시작하면 값이 조용히 갈라진다. 새 값이 필요하면
/// 먼저 여기에 이름을 붙이고 쓴다.
enum DS {

    // MARK: - 여백

    enum Spacing {
        static let tight: CGFloat = 4
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        /// 화면 좌우 여백이자 카드 안쪽 여백. 이 둘이 같아야 카드가 화면에 정렬돼 보인다.
        static let screen: CGFloat = 16
        static let section: CGFloat = 20
        /// 세로로 이어지는 카드 사이 간격 (위아래 각각).
        static let cardGap: CGFloat = 6
    }

    // MARK: - 모서리

    enum Radius {
        static let card: CGFloat = 16
        /// 시트 안에서 값 줄을 묶는 상자, 그리고 가로를 채우는 큰 버튼.
        static let group: CGFloat = 14
        /// PillPicker 처럼 여러 버튼을 감싸는 컨트롤.
        static let control: CGFloat = 13
        /// 정사각형 아이콘 버튼.
        static let button: CGFloat = 10
    }

    // MARK: - 색

    /// 뜻이 정해진 색. 화면이 달라도 같은 뜻이면 같은 색을 쓴다.
    enum Palette {
        /// 입금 · 주요 동작(송금) · 첨부.
        static let deposit = Color.blue
        /// 출금 · 되돌릴 수 없는 동작(삭제·거절).
        static let withdrawal = Color.red
        /// 대기 · 주의(계좌 미등록).
        static let pending = Color.orange
        /// 완료(송금됨).
        static let done = Color.green
    }

    // MARK: - 아이콘 크기

    /// 아이콘만 고정 pt 를 쓴다. 텍스트는 항상 시맨틱 폰트다 (DESIGN.md 참고).
    enum Icon {
        /// 카드 안 작은 액션 버튼.
        static let inline: CGFloat = 15
        /// 헤더 · 툴바 액션.
        static let action: CGFloat = 18
        /// 목록 행이나 카드의 대표 아이콘.
        static let feature: CGFloat = 22
        /// 빈 화면 일러스트.
        static let placeholder: CGFloat = 46
    }

    enum Size {
        /// 카드 안 정사각 아이콘 버튼 한 변.
        static let iconButton: CGFloat = 36
        /// 시트 바닥에서 가로를 채우는 액션 버튼 높이.
        static let actionButton: CGFloat = 50
        /// 목록 행의 이니셜 원.
        static let rowAvatar: CGFloat = 44
        /// 시트 머리의 이니셜 원.
        static let sheetAvatar: CGFloat = 52
        /// 헤더 아이콘 버튼 한 변이자 헤더 바 높이. 손가락이 닿는 최소치(44)다.
        static let headerButton: CGFloat = 44
        /// 프로필 화면의 큰 아바타.
        static let avatar: CGFloat = 88
    }

    // MARK: - 움직임

    enum Motion {
        /// 목록 항목이 들고 날 때.
        static let list = Animation.spring(response: 0.4, dampingFraction: 0.8)
        /// 컨트롤 선택이 바뀔 때.
        static let control = Animation.spring(response: 0.3, dampingFraction: 0.7)
    }
}

// MARK: - 카드

extension View {
    /// 카드 한 장. 목록의 행, 요약 상자, 안내 상자가 전부 이 모양이다.
    ///
    /// 그림자는 일부러 아주 옅다(6%). 카드가 화면을 가득 채우는 구조라
    /// 이보다 진해지면 목록 전체가 무거워 보인다.
    func cardStyle(padding: CGFloat = DS.Spacing.screen) -> some View {
        self
            .padding(padding)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
    }

    /// 카드를 `List` 행으로 쓸 때 함께 붙인다.
    ///
    /// `List` 기본 장식(구분선·선택 배경·기본 인셋)을 걷어내고 카드 간격만 남긴다.
    /// 카드는 자기 그림자를 가지므로 구분선이 겹치면 지저분해진다.
    func cardRow() -> some View {
        self
            .padding(.horizontal, DS.Spacing.screen)
            .padding(.vertical, DS.Spacing.cardGap)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }

    /// 시트 안에서 라벨-값 줄을 묶는 상자.
    ///
    /// 카드와 배경색이 **반대**다. 시트 바닥이 `systemBackground` 라서 카드와 같은
    /// 색으로 칠하면 상자가 안 보인다. 그래서 여기서만 화면 바닥색을 안쪽에 쓴다.
    ///
    /// 그래도 흰 바탕 위의 `systemGroupedBackground` 는 명도 차가 4% 남짓이라
    /// 상자가 있는지 없는지 잘 안 보인다. **테두리 한 올이 실제로 경계를 만든다.**
    /// 카드는 그림자로 뜨지만 시트 안에서는 그림자를 쓰지 않는다 — 시트가 이미
    /// 떠 있는 면이라 그 위에 또 띄우면 층이 두 번 생긴다.
    func groupBox(padding: CGFloat = DS.Spacing.screen) -> some View {
        self
            .padding(padding)
            .background(Color(.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.group))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.group)
                    .strokeBorder(Color(.separator), lineWidth: 0.5)
            )
    }

    /// 카드를 얹는 화면 바닥색. 카드(`systemBackground`)와 대비를 만든다.
    ///
    /// 안전영역까지 덮는다. 헤더가 자기 배경 없이 이 색 위에 얹히기 때문에,
    /// 상태바 자리가 안 덮이면 헤더 위쪽에만 다른 색 띠가 남는다.
    func screenBackground() -> some View {
        self.background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

// MARK: - 글자

extension View {
    /// 화면 이름. 헤더 가운데(`AdminHeaderView`)와 로그인 화면 제목이 이걸 쓴다.
    ///
    /// 제목이 가운데로 오면서 양옆 버튼과 높이를 나눠 쓴다. `.largeTitle` 은 그
    /// 자리에 안 들어가고, 카드 제목(`.title3`)과 같으면 화면 이름으로 안 읽힌다.
    func headerTitle() -> some View {
        self.font(.title2).fontWeight(.bold)
    }

    /// 목록 행·카드의 제목.
    func rowTitle() -> some View {
        self.font(.subheadline).fontWeight(.medium).foregroundColor(.primary)
    }

    /// 제목 아래 딸린 설명 (계좌 줄, 날짜, 메모).
    func rowSubtext() -> some View {
        self.font(.caption).foregroundColor(.secondary)
    }

    /// 카드 안 소제목.
    func cardTitle() -> some View {
        self.font(.title3).fontWeight(.bold)
    }

    /// 시트에서 한 계층 키운 제목·값 (17).
    ///
    /// 시트는 한 건만 들여다보는 자리라 목록 카드와 밀도가 다르다. 목록에서
    /// 15pt 로 촘촘히 쌓던 걸 그대로 가져오면 화면이 넓은데 글자만 작아 보인다.
    /// `.headline` 은 시스템이 semibold 를 물고 있어서 medium 을 같이 준다.
    func sheetTitle() -> some View {
        self.font(.headline).fontWeight(.medium)
    }

    /// 시트에서 한 계층 키운 설명 (15).
    func sheetSubtext() -> some View {
        self.font(.subheadline).foregroundColor(.secondary)
    }

    /// 상세 시트 머리의 금액. **앱에서 가장 큰 글자다.**
    ///
    /// 여섯 번째 단계를 이거 하나만 쓴다. 청구서 한 건을 열었을 때 제일 먼저
    /// 읽어야 하는 건 금액이고, 그 자리는 화면에 하나뿐이라서 크기를 독점시킨다.
    /// 목록 카드의 금액은 `cardTitle()`(20) 그대로다 — 거기선 여러 건이 나란히
    /// 놓이므로 하나만 커지면 안 된다.
    func heroAmount() -> some View {
        self.font(.title).fontWeight(.bold)
    }
}

// MARK: - 빈 상태

/// 목록이 비었을 때 쓰는 안내.
///
/// 아이콘 없이 한 줄만 넘겨도 되고, 무엇을 하면 채워지는지까지 적어도 된다.
/// 그 자리에서 채울 수 있는 화면이면 후행 클로저로 버튼을 붙인다.
struct EmptyStateView<Action: View>: View {
    let title: String
    var icon: String? = nil
    var message: String? = nil
    @ViewBuilder let action: () -> Action

    var body: some View {
        VStack(spacing: DS.Spacing.medium) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: DS.Icon.placeholder))
                    .foregroundColor(.secondary)
            }
            Text(title)
                .font(.title3)
                .fontWeight(.medium)
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            action()
                .padding(.top, DS.Spacing.small)
        }
        .padding(DS.Spacing.section)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension EmptyStateView where Action == EmptyView {
    init(title: String, icon: String? = nil, message: String? = nil) {
        self.init(title: title, icon: icon, message: message) { EmptyView() }
    }
}
