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
struct BillRowView: View {
    let bill: Bill

    var body: some View {
        HStack(spacing: DS.Spacing.medium) {
            InitialAvatarView(name: bill.submitterName)

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

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .cardStyle()
        // 카드 전체가 하나의 버튼이다. 줄마다 따로 읽히면 세 번 넘겨야 한 건을 안다.
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("두 번 누르면 처리 화면이 열려요")
    }
}
