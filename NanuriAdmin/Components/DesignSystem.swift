import SwiftUI

/// 앱 전체가 공유하는 디자인 토큰.
///
/// **이 앱의 디자인 기준은 저장소 루트의 `TOSS.md` 다.** 원본을 한 글자도 고치지 않고
/// 받아 뒀고, 원시 팔레트는 `DesignTokens.swift` 의 `Ramp` 에 따로 있다.
///
/// 두 층으로 나뉜다 — 원시 팔레트(`Ramp`)와 뜻이 붙은 시맨틱 층(여기).
/// **화면은 시맨틱 층만 쓴다.** 원문 규칙이 그렇다: product 색은 시맨틱 alias 로만
/// 호출하고, base 팔레트는 새 role 을 만들 때만 직접 본다.
///
/// 화면 코드에 숫자를 직접 적지 않는 규칙은 그대로다. 새 값이 필요하면 먼저
/// 여기에 이름을 붙인다.
enum DS {

    // MARK: - 여백

    /// 4px 를 기본 단위로 하는 12단 사다리.
    enum Spacing {
        static let s1: CGFloat = 4
        static let s2: CGFloat = 8
        static let s3: CGFloat = 12
        static let s4: CGFloat = 16
        static let s5: CGFloat = 20
        static let s6: CGFloat = 24
        static let s7: CGFloat = 28
        static let s8: CGFloat = 32
        static let s10: CGFloat = 40
        static let s12: CGFloat = 48
        static let s16: CGFloat = 64
        static let s20: CGFloat = 80

        // 뜻이 붙은 자리 — 화면은 되도록 이 이름들을 쓴다.
        // 원문의 룰 오브 섬 세 가지가 그대로 들어와 있다.

        /// 라벨과 입력처럼 **밀접하게 붙는 것들** 사이.
        static let tight = s1
        static let small = s2
        static let medium = s3

        /// 화면 좌우 여백. 원문이 값을 발행한 자리다 — "24px 화면 outer padding".
        /// 카드 안쪽 여백도 같은 값이라야 카드가 화면에 정렬돼 보인다.
        static let screen = s6

        /// 섹션 사이.
        static let section = s8

        /// 시트 안쪽 위아래 여백.
        static let sheetEdge = s8

        /// 세로로 이어지는 카드 사이 간격 (위아래 각각).
        /// 원문의 "16px list-row 간 간격" 을 위아래로 나눠 가진 값이다.
        static let cardGap = s2
    }

    // MARK: - 모서리

    /// 4~32px 8단 + `full`. 원문이 "프로덕션에서 가장 둥근 모바일 시스템 중 하나"로
    /// 분류되는 사다리다. **iOS 류 squircle 은 쓰지 않는다.**
    enum Radius {
        static let xs: CGFloat = 4    // 작은 배지
        static let s: CGFloat = 8     // 인라인 태그
        static let m: CGFloat = 12    // 입력 필드 · M 버튼(40)
        static let l: CGFloat = 14    // L 버튼(48) · 토스트
        static let xl: CGFloat = 16   // XL 버튼(56) · 카드
        static let xl2: CGFloat = 20  // 시트 · 다이얼로그
        static let xl3: CGFloat = 24  // 큰 카드 · 섹션
        static let xl4: CGFloat = 32  // hero 블록
        /// pill·capsule 자리. SwiftUI 에서는 `Capsule()` 로 그린다 (원문 999px).

        /// 카드 한 장.
        ///
        /// 버튼 라운드(16)가 아니라 **`xl3`(24)** 다 — 원문 사다리에서 24 가
        /// "big cards / sections" 자리고, 목록을 이고 있는 큰 카드가 여기 해당한다.
        /// 16 으로 두면 카드가 야무져 보여서 이 시스템 특유의 뭉툭함이 안 난다.
        static let card = xl3
        /// 시트 안에서 값 줄을 묶는 상자.
        static let group = xl2
        /// 여러 버튼을 감싸는 컨트롤 (세그먼트 트랙).
        static let control = m
        /// 정사각형 아이콘 버튼. 원문 S 버튼(32)과 같은 10 이다.
        static let button: CGFloat = 10
    }

    // MARK: - 색: 글자와 아이콘

    /// 전경색. 원문의 `tds-fg-*` 축이다.
    ///
    /// 어두운 화면 값은 **이 앱이 정했다** — 원문은 밝은 모드만 발행한다.
    enum Ink {
        /// 본문. **순수 검정이 아니다** — 차갑게 기운 `grey900` 이다.
        static let primary = Color.adaptive(light: Ramp.grey900, dark: Ramp.grey50)
        static let secondary = Color.adaptive(light: Ramp.grey700, dark: Ramp.grey400)
        static let tertiary = Color.adaptive(light: Ramp.grey600, dark: Ramp.grey500)
        static let placeholder = Color.adaptive(light: Ramp.grey400, dark: Ramp.grey600)
        static let disabled = Color.adaptive(light: Ramp.grey400, dark: Ramp.grey600)
        /// **`Ink.primary` 로 채운 자리** 위의 글자 (선택된 칩, 날짜 셀렉터의 선택 칸).
        ///
        /// 이름 그대로 `primary` 의 반대라서 **모드를 따라 같이 뒤집힌다.** 어두운
        /// 화면에서 `primary` 가 흰색에 가까워지므로 여기는 검정 쪽으로 가야 한다.
        /// 예전에는 양쪽 다 흰색이어서 **다크 모드의 선택된 칩이 흰 바탕에 흰
        /// 글자로 사라졌다.**
        static let inverse = Color.adaptive(light: Ramp.white, dark: Ramp.grey900)
        /// **유채색으로 채운 자리** 위의 글자 (파랑 주요 버튼, 빨강 파괴적 버튼).
        ///
        /// 이쪽은 두 모드 모두 흰색이다 — 파랑·빨강 채움은 무채색 사다리와 달리
        /// 어두운 화면에서 밝기가 뒤집히지 않는다. `inverse` 와 갈라 둔 이유가
        /// 이것이고, 둘을 하나로 합치면 한쪽이 반드시 안 읽힌다.
        static let onAccent = Color.adaptive(light: Ramp.white, dark: Ramp.white)
        static let brand = Color.adaptive(light: Ramp.blue500, dark: 0x5A9CF8)
        static let danger = Color.adaptive(light: Ramp.red500, dark: 0xF56273)
    }

    // MARK: - 색: 바탕

    /// 배경색. 원문의 `tds-bg-*` 축이다.
    enum Surface {
        /// 카드가 얹히는 화면 바닥.
        static let page = Color.adaptive(light: Ramp.grey50, dark: 0x0E1116)
        /// 카드 · 시트 안쪽.
        static let card = Color.adaptive(light: Ramp.white, dark: 0x181C22)
        /// 보조 표면 — 입력 필드 쉬는 상태, 보조 버튼, 세그먼트 트랙.
        static let secondary = Color.adaptive(light: Ramp.grey100, dark: 0x232830)
        static let tertiary = Color.adaptive(light: Ramp.grey200, dark: 0x2E343D)
        /// 브랜드의 옅은 바탕.
        static let brandWeak = Color.adaptive(light: Ramp.blue50, dark: 0x16283F)

        /// 알림함처럼 **화면 하나를 통째로 물들이는** 섹션 배경.
        ///
        /// ⚠️ **원문에 없는 토큰이다.** 레퍼런스 화면에서 눈으로 뜬 값이라 브랜드
        /// 스펙이 아니다. `blue50`(#EAF5FF)보다 채도를 낮춰 회색 쪽으로 당겼다 —
        /// 그대로 쓰면 파랑이 너무 서서 그 위의 파란 요소들이 안 보인다.
        ///
        /// 이 위에 얹는 아이콘 타일은 `brandWeak` 가 아니라 `card`(흰색)를 쓴다.
        /// 둘 다 옅은 파랑이면 타일이 배경에 묻힌다.
        static let notice = Color.adaptive(light: 0xF0F4FB, dark: 0x131720)
    }

    // MARK: - 색: 선

    /// 원문의 `tds-line-*` 축. **기본은 1px 헤어라인이고, 2px 장식 보더는 쓰지 않는다.**
    enum Line {
        /// 기본 구분선.
        static let `default` = Color.adaptive(light: Ramp.grey200, dark: 0x2E343D)
        /// 회색 배경 위 카드 보더. 원문이 이 자리에 알파 토큰을 따로 둔다 (검정 8%).
        static let subtle = Color.black.opacity(0.08)
        static let strong = Color.adaptive(light: Ramp.grey400, dark: 0x4B5765)
        /// 포커스된 입력. **1.5px 로 한 단 굵어진다.**
        static let focused = Color.adaptive(light: Ramp.blue500, dark: 0x5A9CF8)
        /// 포커스 테두리 굵기.
        static let focusedWidth: CGFloat = 1.5
        /// 기본 헤어라인 굵기.
        static let hairline: CGFloat = 1
    }

    // MARK: - 색: 상태 겹침

    /// 눌림·비활성은 색을 갈아끼우지 않고 **덮어서** 표현한다.
    enum State {
        /// 눌린 상태. 원문이 그림자가 아니라 overlay 로 못 박은 자리다 (검정 26%).
        static let pressOverlay = Color.black.opacity(0.26)
        /// 화면을 덮는 막 (시트 뒤).
        static let scrim = Color.black.opacity(0.56)
        /// 비활성. **부분 회색 처리하지 않고 노드 전체에 건다.**
        static let disabledOpacity: Double = 0.30
    }

    // MARK: - 색: 뜻이 정해진 색

    /// 화면이 달라도 같은 뜻이면 같은 색을 쓴다.
    ///
    /// ## 입금이 파랑, 출금이 검정인 이유
    ///
    /// 원문 `list-row` 규칙이 그렇다 — **양수는 `text-brand`(파랑), 음수는
    /// `text-primary`(검정)**. 빨강이 아니다.
    ///
    /// 장부에서 지출은 사고가 아니라 일상이다. 출금을 빨강으로 칠하면 목록 절반이
    /// 경고처럼 보이고, 정작 진짜 경고(거절·삭제)가 묻힌다. **빨강은 되돌릴 수 없는
    /// 것에만 남긴다.**
    enum Palette {
        /// 입금 · 첨부.
        static let deposit = Ink.brand

        /// 출금. **빨강이 아니라 본문색이다.**
        static let withdrawal = Ink.primary

        /// 되돌릴 수 없는 동작 (삭제 · 거절), 그리고 잔액이 음수인 상태.
        static let danger = Ink.danger

        /// 대기 · 주의 (계좌 미등록).
        static let pending = Color.adaptive(light: Ramp.orange500, dark: Ramp.orange500)

        /// 완료 (송금됨).
        static let done = Color.adaptive(light: Ramp.green500, dark: 0x1FA35C)

        /// 주요 동작. **화면당 하나만 쓴다** — 원문이 단일 강조색 정책을 못 박는다.
        static let accent = Ink.brand

        /// 묶음(여러 청구가 한 출금으로 나간 것). **거래내역서 확인 계열 전용이다.**
        ///
        /// ⚠️ 원문에 없는 색이고 재정 탭 본체는 안 쓴다 — 불러오기 화면에서만
        /// "이 출금은 여러 항목이 묶인 것" 을 한눈에 갈라 보이려고 더한 보라다
        /// (DESIGN.md §13 의 문서화된 예외). 강조색(파랑)과 부딪히지 않게 색상만 뗀다.
        static let group = Color.adaptive(light: Ramp.purple500, dark: 0x9B8CFF)

        /// 카테고리 비중 막대의 사다리. 큰 것부터 이 순서로 쓴다.
        ///
        /// ⚠️ **원문에 없는 값이다.** `blue500` 에서 명도만 올려 이 앱이 뜬 세 단이다.
        ///
        /// 레퍼런스는 이 자리에 파랑·주황·초록을 나란히 쓰는데, 여기서는 그럴 수
        /// 없다 — 이 앱은 색마다 뜻이 붙어 있어서(파랑 입금 · 주황 주의 · 초록 완료)
        /// 카테고리에 그 색들을 빌려 주면 뜻이 흐려진다. **한 색의 명도만 낮춰
        /// 간다.** 막대에서 읽어야 하는 건 "어느 것이 제일 큰가" 지 색 이름이 아니다.
        ///
        /// 셋뿐인 건 목록도 셋까지만 이름을 적기 때문이다. 넷째부터는 `categoryRest`
        /// 로 합쳐진다 — 사다리를 더 늘리면 아래 두 단이 서로 구별되지 않는다.
        static let categorySeries: [Color] = [
            Ink.brand,
            .adaptive(light: 0x6BA6F8, dark: 0x3F76BF),
            .adaptive(light: 0xA5CAFB, dark: 0x2E5586)
        ]

        /// 사다리 밖 나머지 ("그 외 N개"). 이름이 없으니 색도 뜻을 갖지 않는다.
        static let categoryRest = Line.default
    }

    // MARK: - 색 쌍 (배지)

    /// 글자색과 그 색의 옅은 바탕을 짝지은 것.
    struct ColorTone {
        let content: Color
        let surface: Color
    }

    /// 배지의 색 쌍.
    ///
    /// ⚠️ **옅은 바탕(washed) 단계는 원문에 없다.** 원문이 시맨틱 base step 만
    /// 발행하고 배지 전용 washed step 은 노출하지 않는다고 직접 밝힌다 — 원문조차
    /// red 배지 바탕을 "정식 토큰 없음, 추정" 으로 적어 뒀다.
    /// 아래 바탕색은 **이 앱의 추정치**이지 브랜드 스펙이 아니다.
    enum Tone {
        static let brand = ColorTone(content: Ink.brand, surface: Surface.brandWeak)
        static let danger = ColorTone(
            content: Ink.danger,
            surface: .adaptive(light: 0xFDEAEC, dark: 0x3A1A1F)
        )
        static let pending = ColorTone(
            content: .adaptive(light: 0xB35F00, dark: Ramp.orange500),
            surface: .adaptive(light: 0xFFF1E0, dark: 0x3A2A16)
        )
        static let done = ColorTone(
            content: Palette.done,
            surface: .adaptive(light: 0xE3F5EA, dark: 0x14301F)
        )
        /// 묶음 배지·아이콘 타일. **거래내역서 확인 계열 전용** (DESIGN.md §13 예외).
        static let group = ColorTone(
            content: Palette.group,
            surface: .adaptive(light: 0xF0EEFF, dark: 0x221E3A)
        )
        /// 뜻이 없는 회색 배지.
        static let neutral = ColorTone(content: Ink.secondary, surface: Surface.secondary)
    }

    // MARK: - 그림자

    /// **평면이 기본이다.** 그림자는 떠 있는 표면(메뉴·툴팁·다이얼로그·토스트)에만 쓴다.
    ///
    /// 목록 카드에는 그림자를 주지 않는다 — 대신 헤어라인 보더가 경계를 만든다.
    /// 눌린 상태도 그림자가 아니라 `State.pressOverlay` 다. **inner shadow 는 없다.**
    ///
    /// 원문은 CSS blur 로 발행한다. SwiftUI 의 `shadow(radius:)` 는 대략 그 절반이라
    /// 값을 나눠 담았다. 두 겹으로 쌓이는 토큰은 진한 쪽만 남겼다.
    struct Shadow {
        let color: Color
        let radius: CGFloat
        let x: CGFloat
        let y: CGFloat

        private init(alpha: Double, blur: CGFloat, y: CGFloat) {
            self.color = Color(hex: Ramp.navy900).opacity(alpha)
            self.radius = blur / 2
            self.x = 0
            self.y = y
        }

        /// 메뉴. 세그먼트에서 선택된 칸이 떠오르는 데도 쓴다.
        static let menu = Shadow(alpha: 0.04, blur: 2, y: 1)
        /// 툴팁.
        static let tooltip = Shadow(alpha: 0.06, blur: 12, y: 4)
        /// 다이얼로그.
        static let dialog = Shadow(alpha: 0.10, blur: 32, y: 12)
        /// 토스트.
        static let toast = Shadow(alpha: 0.16, blur: 24, y: 8)
        /// 바닥에 고정된 바. 원문에 컨벤션으로만 적힌 값이고 정식 토큰은 아니다.
        static let bottomBar = Shadow(alpha: 0.06, blur: 12, y: -2)
    }

    // MARK: - 글자

    /// 크기 · 굵기 · 행간 · 자간을 한 덩어리로 들고 다니는 글자 스타일.
    ///
    /// 원문 서체는 자체 제작 서체라 외부 배포가 안 되고, 원문 스스로 **Pretendard**
    /// 를 가장 가까운 대체로 지목한다. 앱에 번들돼 있지 않아 지금은 시스템 서체로
    /// 그린다 — Pretendard 를 넣게 되면 `font` 계산 한 줄만 고치면 된다.
    ///
    /// **자간이 음수다.** 큰 글자일수록 조여 무게를 잡는 것이 이 시스템의 특징이라
    /// 자간을 토큰에 같이 넣었다. 행간은 SwiftUI 의 `lineSpacing` 이 기본 행간에
    /// *더하는* 값이라 원문 배수를 그대로 못 넣는다 — 기본 행간을 크기의 1.2 배로
    /// 보고 차이만 넘긴다. 근사다.
    struct TypeStyle {
        let size: CGFloat
        let weight: Font.Weight
        /// 원문의 line-height 배수.
        let lineHeight: CGFloat
        /// 원문의 tracking(em)을 pt 로 환산한 값.
        let tracking: CGFloat

        var font: Font { .system(size: size, weight: weight) }
        var lineSpacing: CGFloat { max(0, size * lineHeight - size * 1.2) }
    }

    enum Typo {
        // Display · Heading — Bold 700, 자간을 바짝 조인다.
        static let display1 = TypeStyle(size: 56, weight: .bold, lineHeight: 1.30, tracking: -0.28)
        static let display2 = TypeStyle(size: 40, weight: .bold, lineHeight: 1.20, tracking: -0.80)
        static let h1 = TypeStyle(size: 28, weight: .bold, lineHeight: 1.30, tracking: -0.56)
        static let h2 = TypeStyle(size: 24, weight: .bold, lineHeight: 1.30, tracking: -0.48)
        static let h3 = TypeStyle(size: 22, weight: .bold, lineHeight: 1.30, tracking: -0.33)
        static let h4 = TypeStyle(size: 20, weight: .bold, lineHeight: 1.35, tracking: -0.30)

        // Title — Semibold 600
        static let title1 = TypeStyle(size: 18, weight: .semibold, lineHeight: 1.45, tracking: -0.18)
        static let title2 = TypeStyle(size: 17, weight: .semibold, lineHeight: 1.45, tracking: -0.17)

        // Body — Regular 400. **본문 기본은 body2(15/1.5)다** (한글 가독성 표준).
        static let body1 = TypeStyle(size: 17, weight: .regular, lineHeight: 1.50, tracking: -0.085)
        static let body2 = TypeStyle(size: 15, weight: .regular, lineHeight: 1.50, tracking: -0.075)
        static let body3 = TypeStyle(size: 13, weight: .regular, lineHeight: 1.50, tracking: 0)

        // Label — 버튼·컨트롤 전용. "버튼은 장식이 아니라 문장처럼 읽힌다."
        static let labelL = TypeStyle(size: 17, weight: .bold, lineHeight: 1.25, tracking: -0.085)
        static let labelM = TypeStyle(size: 15, weight: .semibold, lineHeight: 1.25, tracking: -0.075)
        static let labelS = TypeStyle(size: 13, weight: .semibold, lineHeight: 1.25, tracking: 0)

        /// 목록 행의 금액. 원문 list-row 가 **Bold 700 15px** 로 못 박은 값이라
        /// Label 사다리와 따로 둔다 (`labelM` 은 Semibold 600 이다).
        static let amount = TypeStyle(size: 15, weight: .bold, lineHeight: 1.25, tracking: -0.075)

        /// 카드 머리에 홀로 서는 큰 수. 라벨이 이 수를 설명하는 구조로 쓴다.
        static let heroNumber = TypeStyle(size: 28, weight: .bold, lineHeight: 1.30, tracking: -0.56)

        // Caption — Medium 500
        static let caption = TypeStyle(size: 12, weight: .medium, lineHeight: 1.40, tracking: 0)
        static let captionS = TypeStyle(size: 11, weight: .medium, lineHeight: 1.40, tracking: 0)
    }

    // MARK: - 아이콘 크기

    /// 원문 아이콘 사이즈는 16/20/24/32 이고 **24 가 일꾼**이다.
    /// 조형은 아웃라인이 기본이고, 채운 변형은 활성 탭 아이콘에만 쓴다.
    enum Icon {
        static let s: CGFloat = 16
        static let m: CGFloat = 20
        static let l: CGFloat = 24
        static let xl: CGFloat = 32

        /// 카드 안 작은 액션 버튼.
        static let inline = s
        /// 헤더 · 툴바 액션.
        static let action = l
        /// 목록 행이나 카드의 대표 아이콘.
        static let feature = l
        /// 빈 화면 일러스트.
        static let placeholder: CGFloat = 48

        /// 아이콘 폰트. **굵기를 기본(regular)으로 고정한다.**
        ///
        /// 원문 stroke 가 24px 그리드에서 1.5~1.67px 다. SF Symbols 의
        /// `.medium`/`.semibold` 는 그보다 훨씬 두꺼워서, 같은 크기여도 선이
        /// 굵어 화면이 무거워 보인다. 굵기를 화면이 고르지 못하게 여기서 닫는다.
        static func font(_ size: CGFloat) -> Font { .system(size: size, weight: .regular) }
    }

    enum Size {
        // 버튼 4단. **높이와 모서리가 짝으로 움직인다.**
        /// XL — 화면 최하단 강제 액션.
        static let buttonXL: CGFloat = 56
        /// L — 시트 안 결정 버튼.
        static let buttonL: CGFloat = 48
        static let buttonM: CGFloat = 40
        static let buttonS: CGFloat = 32

        /// 시트 바닥에서 가로를 채우는 액션 버튼 높이.
        static let actionButton = buttonL
        /// 입력 필드 높이.
        static let field = buttonL
        /// 칩 높이. 원문 값이 34 다.
        static let chip: CGFloat = 34
        /// 배지 높이.
        static let badge: CGFloat = 22

        /// 카드 안 정사각 아이콘 버튼 한 변.
        static let iconButton = buttonM
        /// 목록 행의 이니셜 원. 원문 list-row 아바타가 44 다.
        static let rowAvatar: CGFloat = 44
        /// 헤더 아이콘 버튼 한 변이자 헤더 바 높이.
        /// 원문 top-app-bar 가 56 이지만, 이 앱 헤더는 탭 넷을 이고 있어 44 를 유지한다.
        /// 손가락이 닿는 최소치(44)이기도 하다.
        static let headerButton: CGFloat = 44
        /// 프로필 화면의 큰 아바타.
        static let avatar: CGFloat = 88
        /// 폼 안 영수증 썸네일 한 변.
        static let thumbnail: CGFloat = 90
        /// 화면 가득 보는 사진(영수증)의 최대 변. 어느 아이폰 폭보다 넉넉하다.
        static let fullPhoto: CGFloat = 512

        /// 분석 화면의 큰 그래프 높이.
        ///
        /// 요약 밴드의 작은 그래프(`SpendingSparkline` 의 `inline`)는 두 선이
        /// 벌어졌다는 것만 말한다. 이 크기라야 **언제 벌어졌는지**가 읽힌다.
        static let chart: CGFloat = 200

        /// 카테고리 비중 막대 두께. 눈금도 축도 없는 띠 하나라 얇게 둔다.
        static let barTrack: CGFloat = 12
    }

    // MARK: - 시트

    enum Sheet {
        /// 청구서 상세 시트가 열리는 높이 (화면 높이 대비).
        ///
        /// 내용을 재서 딱 맞추던 시절이 있었는데 **열 때마다 높이가 달랐다** —
        /// 첫 측정이 애니메이션 중 어느 순간에 걸리느냐를 탔다 (`TROUBLESHOOTING.md`).
        /// 같은 청구서가 어떨 때는 길고 어떨 때는 짧은 것보다, 늘 같은 자리에서
        /// 열리는 게 낫다. **되돌리지 말 것.**
        static let billDetail: CGFloat = 0.75
    }

    // MARK: - 움직임

    /// **바운스 오버슈트가 없다.** 원문이 스프링이 아니라 시간·곡선 토큰으로만
    /// 모션을 운용하고, 오버슈트·parallax·320ms 초과 fade 를 금지한다.
    /// 그래서 예전에 쓰던 `Animation.spring` 을 전부 걷어냈다.
    enum Motion {
        /// 기본 곡선 (ease-out-expo).
        static func ease(_ duration: Double) -> Animation {
            .timingCurve(0.22, 0.61, 0.36, 1, duration: duration)
        }
        /// 더 빠르게 떨어지는 곡선. 시트가 들어올 때.
        static func easeOut(_ duration: Double) -> Animation {
            .timingCurve(0.16, 1, 0.3, 1, duration: duration)
        }

        static let fast: Double = 0.12   // 버튼 눌림
        static let base: Double = 0.20   // 토글 · 선택 변경
        static let slow: Double = 0.32   // 시트 · 다이얼로그

        /// 목록 항목이 들고 날 때.
        static let list = ease(base)
        /// 컨트롤 선택이 바뀔 때.
        static let control = ease(base)
        /// 시트가 들고 날 때.
        static let sheet = easeOut(slow)
    }
}

// MARK: - 글자 붙이기

extension View {
    /// 크기·굵기·행간·자간을 한 번에 건다.
    func typeStyle(_ style: DS.TypeStyle) -> some View {
        self
            .font(style.font)
            .tracking(style.tracking)
            .lineSpacing(style.lineSpacing)
    }
}

extension View {
    /// 금액·잔액처럼 **자릿수가 흔들리면 안 되는 수**에 건다.
    ///
    /// 원문이 실시간 금융 데이터에 tabular figure 를 쓰라고 명시한다. 목록에서
    /// 금액이 세로로 쌓일 때 숫자 폭이 제각각이면 자릿수가 어긋나 보인다.
    ///
    /// `typeStyle()` 뒤에 붙인다 — 폰트를 나중에 걸면 이 설정이 덮인다.
    func tabularAmount() -> some View { self.monospacedDigit() }
}

// MARK: - 그림자 붙이기

extension View {
    func elevation(_ shadow: DS.Shadow) -> some View {
        self.shadow(color: shadow.color, radius: shadow.radius, x: shadow.x, y: shadow.y)
    }
}

// MARK: - 카드

extension View {
    /// 카드 한 장. 목록의 행, 요약 상자, 안내 상자가 전부 이 모양이다.
    ///
    /// **그림자도 테두리도 없다.** 평면이 기본이고 그림자는 떠 있는 표면에만 쓴다.
    /// 경계는 흰 카드와 회색 배경의 명도 차만으로 만든다 — 한때 여기에
    /// `line-subtle` 헤어라인을 둘렀는데, 카드마다 선이 생기니 화면이 목록이 아니라
    /// **폼처럼** 읽혔다. 토큰에 그 용도가 적혀 있어도 실제로는 안 쓰는 자리다.
    ///
    /// 여러 줄을 담는 카드는 `padding: 0` 으로 받아 안에서 `cardRowDivider` 로 가른다.
    func cardStyle(padding: CGFloat = DS.Spacing.screen) -> some View {
        self
            .padding(padding)
            .background(DS.Surface.card)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card))
    }

    /// 카드 **안에서** 줄을 가르는 헤어라인.
    ///
    /// 카드가 여러 줄을 담는 그릇이라는 게 이 시스템의 기본형이다 — 한 항목당
    /// 카드 한 장을 쌓으면 화면이 같은 크기 상자의 반복이 된다.
    func cardRowDivider(inset: CGFloat = DS.Spacing.screen) -> some View {
        self.overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.Line.default)
                .frame(height: DS.Line.hairline)
                .padding(.leading, inset)
        }
    }

    /// 카드를 `List` 행으로 쓸 때 함께 붙인다.
    ///
    /// `List` 기본 장식(구분선·선택 배경·기본 인셋)을 걷어내고 카드 간격만 남긴다.
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
    /// 시트 바닥이 카드색이라 같은 색으로 칠하면 상자가 안 보인다. 그래서 보조
    /// 표면색을 쓴다. 시트 안에서는 그림자를 쓰지 않는다 — 시트가 이미 떠 있는
    /// 면이라 그 위에 또 띄우면 층이 두 번 생긴다.
    func groupBox(padding: CGFloat = DS.Spacing.screen) -> some View {
        self
            .padding(padding)
            .background(DS.Surface.secondary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.group))
    }

    /// 카드를 얹는 화면 바닥색.
    ///
    /// 안전영역까지 덮는다. 헤더가 자기 배경 없이 이 색 위에 얹히기 때문에,
    /// 상태바 자리가 안 덮이면 헤더 위쪽에만 다른 색 띠가 남는다.
    /// 기본은 회색 페이지지만, 알림함처럼 화면을 다른 색으로 물들이는 자리는
    /// 색을 넘겨 쓴다.
    func screenBackground(_ surface: Color = DS.Surface.page) -> some View {
        self.background(surface.ignoresSafeArea())
    }
}

// MARK: - 글자 역할

extension View {
    /// 화면 이름. 헤더 가운데(`AdminHeaderView`)와 로그인 화면 제목이 이걸 쓴다.
    func headerTitle() -> some View {
        self.typeStyle(DS.Typo.h4).foregroundColor(DS.Ink.primary)
    }

    /// 목록 행의 제목. **15pt Semibold 다.**
    ///
    /// 18(`title1`)이었던 적이 있는데, 그건 원문이 **카드 타이틀**에 준 값이지
    /// 촘촘히 반복되는 목록 행의 값이 아니다. 행에서 제목이 금액(15 Bold)보다
    /// 커지면 무게 중심이 왼쪽으로 쏠린다 — 목록에서 먼저 읽혀야 하는 건 금액이다.
    /// 제목과 금액은 **같은 15pt 이고 굵기만 갈린다** (Semibold ↔ Bold).
    ///
    /// 섹션을 이끄는 큰 제목이 필요하면 `cardTitle()` 을 쓴다.
    func rowTitle() -> some View {
        self.typeStyle(DS.Typo.labelM).foregroundColor(DS.Ink.primary)
    }

    /// 제목 아래 딸린 설명 (계좌 줄, 날짜, 메모).
    func rowSubtext() -> some View {
        self.typeStyle(DS.Typo.body3).foregroundColor(DS.Ink.secondary)
    }

    /// 카드 안 소제목 · 카드의 강조 금액.
    func cardTitle() -> some View {
        self.typeStyle(DS.Typo.h4).foregroundColor(DS.Ink.primary)
    }

    /// 시트에서 한 계층 키운 제목·값.
    ///
    /// **굵기를 올리지 않는다.** 상자 안에서는 라벨(회색)과 값(검정)이 크기와
    /// 색으로 이미 갈린다. 거기에 굵기까지 얹으면 값 줄이 한꺼번에 진해져서
    /// 상자가 시트에서 제일 무거운 덩어리가 된다. 그 자리는 금액 것이다.
    func sheetTitle() -> some View {
        self.typeStyle(DS.Typo.body1).foregroundColor(DS.Ink.primary)
    }

    /// 시트에서 한 계층 키운 설명.
    func sheetSubtext() -> some View {
        self.typeStyle(DS.Typo.body2).foregroundColor(DS.Ink.secondary)
    }

    /// 상세 시트 머리의 금액. **앱에서 가장 큰 글자다.**
    ///
    /// 청구서 한 건을 열었을 때 제일 먼저 읽어야 하는 건 금액이고, 그 자리는
    /// 화면에 하나뿐이라서 크기를 독점시킨다.
    func heroAmount() -> some View {
        self.typeStyle(DS.Typo.h1).foregroundColor(DS.Ink.primary)
    }

    /// 금액 뒤의 "원". **숫자보다 뒤로 뺀다.**
    ///
    /// 읽어야 하는 건 숫자다. "원"은 어느 청구서에서나 같은 글자라 크기까지 같이
    /// 주면 큰 자리를 반쯤 나눠 갖는다. `heroAmount()` 와 짝이고, 베이스라인을
    /// 맞춰 쓴다 (`HStack(alignment: .firstTextBaseline)`).
    func amountUnit() -> some View {
        self.typeStyle(DS.Typo.title2).foregroundColor(DS.Ink.secondary)
    }
}

// MARK: - 당겨서 새로고침

extension View {
    /// 목록이 아닌 화면(빈 상태 등)도 당겨서 새로고침되게 감싼다.
    ///
    /// `.refreshable` 은 스크롤되는 것에만 붙는다. 헤더에 새로고침 버튼이 없으므로
    /// 목록이 비었을 때 새로고침할 방법이 없으면 안 된다. 내용이 화면보다 짧아도
    /// 당길 수 있어야 해서 튕김을 항상 켠다.
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
                    .foregroundColor(DS.Ink.placeholder)
            }
            // **빈 상태는 목소리를 낮춘다.**
            //
            // 18 semibold 에 본문 검정이던 적이 있는데, 아무것도 없는 화면에서
            // 그 한 줄만 크고 진하니 "없다" 가 아니라 "무슨 일이 났다" 로 읽혔다.
            // 없는 건 사건이 아니라 상태다 — 크기도 색도 한 단씩 뒤로 뺀다.
            Text(title)
                .typeStyle(DS.Typo.labelM)
                .foregroundColor(DS.Ink.secondary)
            if let message {
                Text(message)
                    .typeStyle(DS.Typo.body3)
                    .foregroundColor(DS.Ink.tertiary)
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
