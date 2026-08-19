import SwiftUI

/// 토스로 넘긴 한 번의 송금.
///
/// 같은 사람의 청구서 여러 건을 묶으면 `bills` 가 여럿이다. 토스 딥링크는
/// **수취인 한 명 · 금액 하나**만 받으므로, 묶음은 언제나 한 사람 안에서만
/// 만들어진다. 사람이 다르면 애초에 한 번으로 못 보낸다.
struct TossTransfer: Identifiable {
    let id = UUID()
    /// 이 송금으로 처리될 청구서들. 첫 번째가 사용자가 열었던 그 건이다.
    let bills: [Bill]
    let payee: Payee

    /// 토스에 넘기는 금액이자 화면에서 제일 크게 보여주는 수.
    var total: Int { bills.reduce(0) { $0 + $1.amount } }
    var billIds: [UUID] { bills.map(\.id) }
    /// 계좌부 이름이 아니라 **청구서에 적힌 이름**을 보여준다. 둘이 다를 수 있고
    /// (띄어쓰기 등) 관리자가 확인해야 하는 건 청구서 쪽 이름이다.
    var recipientName: String { bills.first?.submitterName ?? payee.name }
    var isGrouped: Bool { bills.count > 1 }
}

/// 토스에 다녀온 뒤 "정말 보냈는지"를 묻는 시트.
///
/// 앱은 송금 성공 여부를 알 수 없다. 토스가 결과를 돌려주지 않기 때문에
/// 사람이 직접 확인해 주는 자리다. **여기서 확인을 받아야 청구서가 완료로 간다.**
struct TossResultView: View {
    let transfer: TossTransfer
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(DS.Palette.deposit.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: DS.Icon.feature))
                    .foregroundColor(DS.Palette.deposit)
            }
            .padding(.bottom, 16)
            .padding(.top, 32)

            Text("송금하셨나요?")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.bottom, 6)

            Text(transfer.isGrouped
                 ? "\(transfer.bills.count)건을 합쳐서 보냈어요. 결과를 선택해주세요"
                 : "토스에서 송금 후 결과를 선택해주세요")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 24)

            // 묶음이 길어지면 상자가 자라서 아래 버튼을 밀어낸다. 상자만 스크롤시켜
            // **버튼은 언제나 같은 자리**에 두 개 다 보이게 한다.
            ScrollView {
                VStack(spacing: 0) {
                    infoRow(label: "수령인", value: transfer.recipientName)
                    Divider().padding(.vertical, 10)
                    infoRow(label: "계좌", value: transfer.payee.accountLine)
                    Divider().padding(.vertical, 10)

                    ForEach(transfer.bills) { bill in
                        infoRow(
                            label: transfer.isGrouped ? bill.title : "청구 항목",
                            value: transfer.isGrouped ? "\(bill.amount.formatted())원" : bill.title
                        )
                        Divider().padding(.vertical, 10)
                    }

                    HStack {
                        Text(transfer.isGrouped ? "합계 \(transfer.bills.count)건" : "금액")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(transfer.total.formatted())원")
                            .font(.title3)
                            .fontWeight(.medium)
                    }
                }
                .groupBox()
            }
            .padding(.bottom, 24)

            HStack(spacing: DS.Spacing.small) {
                ActionButton(title: "취소", action: onCancel)
                ActionButton(title: "송금 완료", kind: .primary, action: onApprove)
            }
            .padding(.bottom, DS.Spacing.small)
        }
        .padding(.horizontal, 24)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer(minLength: DS.Spacing.medium)
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.trailing)
        }
    }
}
