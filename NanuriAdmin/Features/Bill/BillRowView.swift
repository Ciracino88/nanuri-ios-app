import SwiftUI

/// 청구서 한 건의 목록 카드.
///
/// **카드는 정보만 보여준다.** 송금·거절·삭제·영수증은 전부 카드를 눌러서 여는
/// 상세 시트(`BillDetailView`)에 있다. 예전에는 36×36 버튼 네 개가 금액 옆에
/// 붙어 있었는데, 송금과 거절이 6pt 간격으로 나란히 있어서 잘못 누르기 쉬웠고
/// 글씨를 키우면 그 줄이 먼저 무너졌다. 계좌부 탭(`PayeeListView`)도 같은
/// 구조다 — 카드를 누르면 시트가 열린다.
/// 담는 것은 다섯 가지뿐이다 — 이니셜 원 · 이름 · 항목 · 금액 · 상태 칩.
/// 날짜와 계좌는 상세 시트로 내렸다. 목록에서 훑을 때 필요한 건 "누가 얼마를
/// 무엇으로 청구했고 처리했는가" 이고, 나머지는 한 건을 들여다볼 때 본다.
///
/// 예외가 하나 있다 — **묶어 보내기 선택 모드**(`selection`). 이때는 카드가
/// 시트를 여는 대신 눌러서 고르는 것이 되고, 이니셜 원 자리에 체크가 들어온다.
/// 왼쪽 칸을 원 하나 너비로 유지하려고 아바타를 밀어내고 그 자리를 쓴다.
struct BillRowView: View {
    let bill: Bill
    /// 선택 모드일 때만 준다. `nil` 이면 평소의 정보 카드다.
    var selection: Selection?

    /// 선택 모드에서 이 카드가 놓인 상태.
    enum Selection {
        case on
        case off
        /// 못 고르는 것 — 대기중이 아니거나, 계좌가 없거나, 이미 **다른 사람**을
        /// 고르고 있어서 같이 보낼 수 없는 것.
        case blocked
    }

    var body: some View {
        HStack(spacing: DS.Spacing.medium) {
            if let selection {
                selectionMark(selection)
            } else {
                InitialAvatarView(name: bill.submitterName)
            }

            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                HStack(alignment: .firstTextBaseline) {
                    Text(bill.submitterName)
                        .rowTitle()
                    Spacer(minLength: DS.Spacing.small)
                    Text("\(bill.amount.formatted())원")
                        .cardTitle()
                }

                HStack {
                    Text(bill.title)
                        .rowSubtext()
                        .lineLimit(1)
                    Spacer(minLength: DS.Spacing.small)
                    Text(bill.statusLabel)
                        .tagChip(color: bill.statusColor)
                }
            }

            // 선택 모드에서는 카드를 눌러도 시트가 안 열린다. 화살표를 그대로 두면
            // 거짓말이 된다.
            if selection == nil {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .opacity(selection == .blocked ? 0.4 : 1)
        .contentShape(Rectangle())
        .cardStyle()
        // 카드 전체가 하나의 버튼이다. 줄마다 따로 읽히면 세 번 넘겨야 한 건을 안다.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(accessibilityTraits)
        .accessibilityHint(accessibilityHint)
    }

    private func selectionMark(_ selection: Selection) -> some View {
        Image(systemName: selection == .on ? "checkmark.circle.fill" : "circle")
            .font(.system(size: DS.Icon.feature))
            .foregroundColor(selection == .on ? DS.Palette.deposit : .secondary)
            .frame(width: DS.Size.rowAvatar, height: DS.Size.rowAvatar)
    }

    private var accessibilityTraits: AccessibilityTraits {
        switch selection {
        case .on: return [.isButton, .isSelected]
        case .blocked: return []
        case .off, .none: return .isButton
        }
    }

    private var accessibilityHint: String {
        switch selection {
        case .on: return "두 번 누르면 묶음에서 빼요"
        case .off: return "두 번 누르면 묶음에 넣어요"
        case .blocked: return "지금 고른 사람과 달라서 같이 보낼 수 없어요"
        case .none: return "두 번 누르면 처리 화면이 열려요"
        }
    }
}
