import SwiftUI

/// 눌린 상태를 **덮어서** 표현하는 버튼 스타일.
///
/// 원문이 못 박은 자리다 — pressed 는 그림자도, 색 교체도 아니고 검정 26% overlay 다.
/// 비활성은 부분 회색 처리 없이 노드 전체에 불투명도를 건다.
struct PressOverlayButtonStyle: ButtonStyle {
    var shape: AnyShape = AnyShape(RoundedRectangle(cornerRadius: DS.Radius.l))
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if configuration.isPressed {
                    shape.fill(DS.State.pressOverlay)
                }
            }
            .clipShape(shape)
            .opacity(isEnabled ? 1 : DS.State.disabledOpacity)
            .animation(DS.Motion.ease(DS.Motion.fast), value: configuration.isPressed)
    }
}

/// 시트 바닥에서 가로를 채우는 큰 버튼. 원문 Button 의 L(48pt) 자리다.
///
/// 카드 안 아이콘 버튼(`BillRowView`)과 역할이 다르다. 그쪽은 목록을 훑다가
/// 누르는 것이고, 이건 **시트에서 결정을 내리는 자리**라 글자로 적는다.
///
/// 위계는 원문 Button 변종 네 가지를 그대로 쓴다 (`TOSS.md` Components).
/// **높이와 모서리가 짝으로 움직인다** — L 은 48pt 에 radius 14 다.
struct ActionButton: View {
    enum Kind {
        /// **Primary** — 화면당 단 하나의 가장 중요한 액션 (송금하기 · 등록하기).
        case primary
        /// **Secondary** — 같은 화면의 보조 액션 (취소 · 닫기).
        case secondary
        /// **Ghost** — 보더 없는 약한 위계, 텍스트 링크에 가깝다 (영수증 보기).
        ///
        /// 결정이 아니라 잠깐 들여다보는 것이라 위계를 낮춘다. 원문 변종이 네 개뿐이고
        /// 그중 이 자리에 맞는 건 ghost 다 — 채운 버튼을 하나 더 두면 화면에
        /// 강조가 둘이 된다.
        case tinted
        /// **Danger** — 되돌릴 수 없는 것 (거절 · 삭제). 누르면 확인을 한 번 더 받는다.
        case destructive
    }

    let title: String
    /// 글자 왼쪽에 붙는 SF Symbol. **버튼이 여럿 있는 자리에서는 주지 않는다** —
    /// 아이콘은 "이건 결정이 아니라 잠깐 보는 것"을 말해 주는 표시라서,
    /// 결정 버튼(송금·거절)까지 달면 뜻이 없어진다.
    var icon: String? = nil
    var kind: Kind = .secondary
    let action: () -> Void

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: DS.Radius.l)
    }

    var body: some View {
        Button(action: action) {
            label
                .frame(maxWidth: .infinity)
                .frame(height: DS.Size.actionButton)
                .background(background)
                .foregroundColor(foreground)
        }
        .buttonStyle(PressOverlayButtonStyle(shape: AnyShape(shape)))
    }

    /// 아이콘은 글자와 한 덩어리로 가운데 놓인다. 왼쪽 끝에 붙이지 않는다 —
    /// 가로를 채우는 버튼이라 아이콘만 멀리 떨어지면 다른 버튼처럼 보인다.
    ///
    /// 글자는 Label 스케일이다. "버튼은 장식이 아니라 문장처럼 읽힌다."
    private var label: some View {
        HStack(spacing: DS.Spacing.small) {
            if let icon {
                Image(systemName: icon)
                    .font(DS.Icon.font(DS.Icon.m))
            }
            Text(title)
                .typeStyle(DS.Typo.labelL)
        }
    }

    private var background: Color {
        switch kind {
        case .primary: return DS.Palette.accent
        case .secondary: return DS.Surface.secondary
        case .tinted: return .clear
        case .destructive: return DS.Palette.danger
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .destructive: return DS.Ink.inverse
        case .secondary: return DS.Ink.primary
        case .tinted: return DS.Ink.brand
        }
    }
}

/// 화면 최하단에 고정되는 강제 액션. 원문 Bottom-CTA 자리다.
///
/// `ActionButton(.primary)` 와 **같은 화면에 같이 두지 않는다** — 원문이 금지한다.
/// 둘 다 "이 화면의 가장 중요한 행동"을 주장해서 강조점이 흩어진다.
///
/// 위쪽에 흰색→투명 보호 그라디언트를 깔아 스크롤되는 내용과 부딪히지 않게 한다.
/// 이 앱에서 그라디언트가 허용되는 자리는 여기뿐이다.
struct BottomCTA: View {
    let title: String
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [DS.Surface.page.opacity(0), DS.Surface.page],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: DS.Spacing.section)
            .allowsHitTesting(false)

            Button(action: action) {
                Text(title)
                    .typeStyle(DS.Typo.labelL)
                    .frame(maxWidth: .infinity)
                    .frame(height: DS.Size.buttonXL)
                    .background(DS.Palette.accent)
                    .foregroundColor(DS.Ink.inverse)
            }
            .buttonStyle(PressOverlayButtonStyle(
                shape: AnyShape(RoundedRectangle(cornerRadius: DS.Radius.xl))
            ))
            .disabled(!isEnabled)
            .padding(.horizontal, DS.Spacing.s4)
            .padding(.bottom, DS.Spacing.small)
            .background(DS.Surface.page)
        }
    }
}
