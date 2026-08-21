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
        /// 시트 안쪽 위아래 여백. 위로는 닫기 줄(✕)과 금액 사이를,
        /// 아래로는 **마지막 버튼과 바닥에 고정된 버튼 사이**를 벌린다.
        /// `section`(20)으로는 위는 금액이 ✕ 에 붙어 보이고, 아래는 두 버튼이 붙어
        /// 보여서 누를 때 잘못 짚기 쉽다.
        static let sheetEdge: CGFloat = 32
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
        /// 헤더 아이콘 버튼 한 변이자 헤더 바 높이. 손가락이 닿는 최소치(44)다.
        static let headerButton: CGFloat = 44
        /// 프로필 화면의 큰 아바타.
        static let avatar: CGFloat = 88
        /// 폼 안 영수증 썸네일 한 변.
        static let thumbnail: CGFloat = 90
        /// 화면 가득 보는 사진(영수증)의 최대 변. 어느 아이폰 폭보다 넉넉하다.
        /// 실제 디코드 크기는 여기에 화면 배율(2x·3x)을 곱한 값이다.
        static let fullPhoto: CGFloat = 512
    }

    // MARK: - 시트

    enum Sheet {
        /// 청구서 상세 시트가 열리는 높이 (화면 높이 대비).
        ///
        /// 내용을 재서 딱 맞추던 시절이 있었는데 **열 때마다 높이가 달랐다** —
        /// 첫 측정이 애니메이션 중 어느 순간에 걸리느냐를 탔다 (`TROUBLESHOOTING.md`).
        /// 같은 청구서가 어떨 때는 길고 어떨 때는 짧은 것보다, 늘 같은 자리에서
        /// 열리는 게 낫다.
        ///
        /// iPhone 15(852)에서 비율에 852를 곱하고 65(위 손잡이 자리 + 아래 안전영역)를
        /// 빼면 내용이 쓸 수 있는 높이다. 0.75 면 574pt 다.
        ///
        /// 시트에 닫기 줄(44)이 생기고 값 줄이 상자에서 나와 간격이 넓어지면서
        /// 필요한 높이가 515pt(닫기 44 + 스크롤 내용 388 + 바닥 바 83)로 늘었다.
        /// **0.7 은 531pt 라 16pt 밖에 안 남는다** — 항목 이름이 길어 두 줄이 되면
        /// (+22) 바로 잘린다. 0.75 는 59pt 남는다.
        /// 남는 자리는 스크롤 안쪽 아래에 생기므로 잘리는 것보다 안전한 쪽으로 둔다.
        static let billDetail: CGFloat = 0.75
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
    /// 자리에 아예 안 들어간다.
    ///
    /// **카드 제목과 크기는 같고 굵기만 다르다** (20 semibold ↔ 20 regular).
    /// 헤더는 화면에 하나뿐이고 양옆이 비어 있어서 굵기를 안 줘도 화면 이름으로
    /// 읽힌다. 22 bold 이던 시절에는 상단만 무거워서 아래 내용이 눌렸다.
    /// **앱에서 굵기를 일부러 뺀 자리는 여기와 `amountUnit()` 둘뿐이다.**
    func headerTitle() -> some View {
        self.font(.title3).fontWeight(.regular)
    }

    /// 목록 행·카드의 제목.
    func rowTitle() -> some View {
        self.font(.subheadline).fontWeight(.semibold).foregroundColor(.primary)
    }

    /// 제목 아래 딸린 설명 (계좌 줄, 날짜, 메모).
    func rowSubtext() -> some View {
        self.font(.caption).foregroundColor(.secondary)
    }

    /// 카드 안 소제목 · 카드의 강조 금액.
    func cardTitle() -> some View {
        self.font(.title3).fontWeight(.semibold)
    }

    /// 시트에서 한 계층 키운 제목·값 (17).
    ///
    /// 시트는 한 건만 들여다보는 자리라 목록 카드와 밀도가 다르다. 목록에서
    /// 15pt 로 촘촘히 쌓던 걸 그대로 가져오면 화면이 넓은데 글자만 작아 보인다.
    /// **굵기는 주지 않는다.** 상자 안에서는 라벨(15 회색)과 값(17 검정)이 크기와
    /// 색으로 이미 갈린다. 거기에 굵기까지 얹으면 값 네 줄이 한꺼번에 진해져서
    /// 상자가 시트에서 제일 무거운 덩어리가 된다 — 그 자리는 금액 것이다.
    /// `.headline` 은 시스템이 semibold 를 물고 오므로 **눌러 줘야 한다.**
    func sheetTitle() -> some View {
        self.font(.headline).fontWeight(.regular)
    }

    /// 시트에서 한 계층 키운 설명 (15).
    func sheetSubtext() -> some View {
        self.font(.subheadline).foregroundColor(.secondary)
    }

    /// 상세 시트 머리의 금액 (34). **앱에서 가장 큰 글자다.**
    ///
    /// 맨 윗단을 이거 하나만 쓴다. 청구서 한 건을 열었을 때 제일 먼저 읽어야 하는
    /// 건 금액이고, 그 자리는 화면에 하나뿐이라서 크기를 독점시킨다. 시트 머리에서
    /// 이름·계좌·상태가 상자로 내려가 **금액만 남으면서** 한 계층 올렸다 (28 → 34).
    /// 화면 이름이 22 에서 20 으로 내려온 것과 같은 이유다 — 큰 자리는 하나면 된다.
    /// 목록 카드의 금액은 `cardTitle()`(20) 그대로다 — 거기선 여러 건이 나란히
    /// 놓이므로 하나만 커지면 안 된다.
    func heroAmount() -> some View {
        self.font(.largeTitle).fontWeight(.semibold)
    }

    /// 금액 뒤의 "원". **숫자보다 두 계층 작고 굵기도 색도 뒤로 뺀다** (20 regular, 회색).
    ///
    /// 읽어야 하는 건 숫자다. "원"은 어느 청구서에서나 같은 글자라 크기까지 같이
    /// 주면 큰 자리를 반쯤 나눠 갖는다. `heroAmount()` 와 짝이고, 베이스라인을
    /// 맞춰 쓴다 (`HStack(alignment: .firstTextBaseline)`).
    func amountUnit() -> some View {
        self.font(.title3).fontWeight(.regular).foregroundColor(.secondary)
    }
}

// MARK: - 당겨서 새로고침

extension View {
    /// 목록이 아닌 화면(빈 상태 등)도 당겨서 새로고침되게 감싼다.
    ///
    /// `.refreshable` 은 스크롤되는 것에만 붙는다. 헤더에서 새로고침 버튼을
    /// 걷어냈으므로(DESIGN.md 1번) 목록이 비었을 때 새로고침할 방법이 없으면
    /// 안 된다. 내용이 화면보다 짧아도 당길 수 있어야 해서 튕김을 항상 켠다.
    func pullToRefresh(_ action: @escaping @Sendable () async -> Void) -> some View {
        ScrollView {
            self.containerRelativeFrame(.vertical)
        }
        .scrollBounceBehavior(.always)
        .refreshable { await action() }
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
                .fontWeight(.semibold)
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
