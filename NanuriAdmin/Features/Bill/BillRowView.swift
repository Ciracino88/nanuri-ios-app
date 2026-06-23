import SwiftUI

struct BillRowView: View {
    let bill: Bill
    @ObservedObject var viewModel: BillViewModel
    @Binding var pendingBill: Bill?
    @State private var showReceiptSheet = false

    var statusColor: Color {
        switch bill.status {
        case "approved": return .green
        case "rejected": return .red
        default: return .orange
        }
    }

    var statusLabel: String {
        switch bill.status {
        case "approved": return "송금완료"
        case "rejected": return "거절"
        default: return "대기중"
        }
    }

    var name: String {
        bill.userProfile?.name ?? bill.submitterName ?? "이름 없음"
    }

    var bankInfo: String {
        let bank = bill.userProfile?.bankName ?? bill.bankName ?? ""
        let account = bill.userProfile?.accountNumber ?? bill.accountNumber ?? ""
        return "\(bank) \(account)".trimmingCharacters(in: .whitespaces)
    }

    @ViewBuilder
    private func billButton(_ icon: String, bg: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .frame(width: 36, height: 36)
                .background(bg)
                .foregroundColor(fg)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 상단: 제목 + 날짜 + 상태 뱃지
            HStack {
                Text(bill.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                Spacer()
                HStack(spacing: 6) {
                    Text(bill.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(statusLabel)
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundColor(statusColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(statusColor.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
            .padding(.bottom, 8)

            // 이름 + 계좌
            Text(name)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
            if !bankInfo.isEmpty {
                Text(bankInfo)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 1)
            }

            Divider().padding(.vertical, 12)

            // 하단: 금액 + 버튼 그룹
            HStack {
                Text("\(bill.amount.formatted())원")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                HStack(spacing: 6) {
                    billButton("receipt", bg: Color(.systemGray6), fg: .primary) {
                        showReceiptSheet = true
                    }

                    if bill.status == "pending" {
                        billButton("paperplane.fill", bg: .blue, fg: .white) {
                            pendingBill = bill
                            viewModel.openToss(bill: bill)
                        }
                        billButton("xmark", bg: Color.red.opacity(0.1), fg: .red) {
                            Task { await viewModel.updateStatus(billId: bill.id, status: "rejected") }
                        }
                    } else {
                        billButton("trash", bg: Color.red.opacity(0.1), fg: .red) {
                            Task { await viewModel.deleteBill(billId: bill.id, receiptUrl: bill.receiptUrl) }
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 2)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .sheet(isPresented: $showReceiptSheet) {
            ReceiptSheetView(receiptUrl: bill.receiptUrl)
        }
    }
}

struct ReceiptSheetView: View {
    let receiptUrl: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            Group {
                if let url = URL(string: receiptUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView()
                        case .success(let image):
                            image
                                .resizable()
                                .scaledToFit()
                                .padding()
                        case .failure:
                            VStack(spacing: 12) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.largeTitle)
                                    .foregroundColor(.gray)
                                Text("이미지를 불러올 수 없어요")
                                    .foregroundColor(.gray)
                            }
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
            }
            .navigationTitle("영수증")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }
}
