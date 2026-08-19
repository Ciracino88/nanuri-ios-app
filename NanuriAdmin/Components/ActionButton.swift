import SwiftUI

/// 시트 바닥에서 가로를 채우는 큰 버튼.
///
/// 카드 안 36×36 아이콘 버튼(`BillRowView`)과 역할이 다르다. 그쪽은 목록을 훑다가
/// 누르는 것이고, 이건 **시트에서 결정을 내리는 자리**라 글자로 적는다.
/// 색은 뜻을 따른다 (DESIGN.md 5번) — 파랑은 주요 동작, 빨강은 되돌릴 수 없는 것.
struct ActionButton: View {
    enum Kind {
        /// 이 시트에서 하려던 일 (송금하기 · 등록하기).
        case primary
        /// 물러나기 (취소 · 닫기).
        case secondary
        /// 결정은 아니지만 눈에 띄어야 하는 것 (영수증 보기).
        ///
        /// 회색(`secondary`)은 흰 시트 위에서 버튼이 있는지도 잘 안 보인다.
        /// 파랑을 옅게 깐다 — 팔레트에서 파랑은 첨부의 색이다 (DESIGN.md 5번).
        case tinted
        /// 되돌릴 수 없는 것 (거절 · 삭제). 누르면 확인을 한 번 더 받는다.
        case destructive
    }

    let title: String
    var kind: Kind = .secondary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .frame(height: DS.Size.actionButton)
                .background(background)
                .foregroundColor(foreground)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.group))
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        switch kind {
        case .primary: return DS.Palette.deposit
        case .secondary: return Color(.systemGray5)
        case .tinted: return DS.Palette.deposit.opacity(0.1)
        case .destructive: return DS.Palette.withdrawal.opacity(0.1)
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary: return .white
        case .secondary: return .primary
        case .tinted: return DS.Palette.deposit
        case .destructive: return DS.Palette.withdrawal
        }
    }
}
