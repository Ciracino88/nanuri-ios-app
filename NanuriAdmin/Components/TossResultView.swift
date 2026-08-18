import SwiftUI

struct TossResultView: View {
    let bill: Bill
    /// 계좌부에서 찾은 수취인. 송금 화면을 연 시점엔 항상 있다.
    let payee: Payee?
    let onApprove: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: DS.Icon.feature))
                    .foregroundColor(.blue)
            }
            .padding(.bottom, 16)
            .padding(.top, 32)

            Text("송금하셨나요?")
                .font(.title3)
                .fontWeight(.medium)
                .padding(.bottom, 6)

            Text("토스에서 송금 후 결과를 선택해주세요")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .padding(.bottom, 24)

            VStack(spacing: 0) {
                infoRow(label: "청구 항목", value: bill.title)
                Divider().padding(.vertical, 10)
                infoRow(label: "수령인", value: bill.submitterName)
                Divider().padding(.vertical, 10)
                if let payee {
                    infoRow(label: "계좌", value: payee.accountLine)
                    Divider().padding(.vertical, 10)
                }
                HStack {
                    Text("금액")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(bill.amount.formatted())원")
                        .font(.title3)
                        .fontWeight(.medium)
                }
            }
            .groupBox()
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
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}
