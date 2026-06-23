import SwiftUI

struct TossResultView: View {
    let bill: Bill
    let onApprove: () -> Void
    let onCancel: () -> Void

    var name: String {
        bill.userProfile?.name ?? bill.submitterName ?? "이름 없음"
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.12))
                    .frame(width: 56, height: 56)
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 24))
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
                infoRow(label: "수령인", value: name)
                Divider().padding(.vertical, 10)
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
            .padding(16)
            .background(Color(.systemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .padding(.bottom, 24)

            HStack(spacing: 10) {
                Button(action: onCancel) {
                    Text("취소")
                        .font(.body)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color(.systemGray6))
                        .foregroundColor(.secondary)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)

                Button(action: onApprove) {
                    Text("송금 완료")
                        .font(.body)
                        .fontWeight(.medium)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 8)
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
