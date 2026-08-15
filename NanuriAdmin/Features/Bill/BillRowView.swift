import SwiftUI

struct BillRowView: View {
    let bill: Bill
    /// 이름으로 찾은 계좌. 계좌부에 없으면 nil이고, 이때는 송금 대신 등록을 유도한다.
    let payee: Payee?
    @ObservedObject var viewModel: BillViewModel
    @Binding var pendingBill: Bill?
    /// 계좌 미등록 청구서에서 계좌부로 넘어갈 때 쓴다.
    let onRegisterPayee: (String) -> Void
    @State private var showReceiptSheet = false

    var statusColor: Color {
        switch bill.status {
        case "approved": return DS.Palette.done
        case "rejected": return DS.Palette.withdrawal
        default: return DS.Palette.pending
        }
    }

    var statusLabel: String {
        switch bill.status {
        case "approved": return "송금완료"
        case "rejected": return "거절"
        default: return "대기중"
        }
    }

    @ViewBuilder
    private func billButton(_ icon: String, bg: Color, fg: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: DS.Icon.inline, weight: .medium))
                .frame(width: DS.Size.iconButton, height: DS.Size.iconButton)
                .background(bg)
                .foregroundColor(fg)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button))
        }
        .buttonStyle(.plain)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 상단: 제목 + 날짜 + 상태 뱃지
            HStack {
                Text(bill.title)
                    .rowTitle()
                Spacer()
                HStack(spacing: 6) {
                    Text(bill.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(statusLabel)
                        .fontWeight(.medium)
                        .tagChip(color: statusColor)
                }
            }
            .padding(.bottom, 8)

            // 이름 + 계좌부에서 찾은 계좌
            Text(bill.submitterName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)

            if let payee {
                Text(payee.accountLine)
                    .rowSubtext()
                    .padding(.top, 1)
            } else {
                Button {
                    onRegisterPayee(bill.submitterName)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("계좌 미등록 · 등록하기")
                    }
                    .font(.caption)
                    .foregroundColor(DS.Palette.pending)
                }
                .buttonStyle(.plain)
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
                        // 계좌를 모르면 송금할 수 없다. 계좌부 등록이 먼저다.
                        if let payee {
                            billButton("paperplane.fill", bg: DS.Palette.deposit, fg: .white) {
                                pendingBill = bill
                                viewModel.openToss(bill: bill, payee: payee)
                            }
                        }
                        billButton("xmark", bg: DS.Palette.withdrawal.opacity(0.1), fg: DS.Palette.withdrawal) {
                            Task { await viewModel.updateStatus(billId: bill.id, status: "rejected") }
                        }
                    } else {
                        billButton("trash", bg: DS.Palette.withdrawal.opacity(0.1), fg: DS.Palette.withdrawal) {
                            Task { await viewModel.deleteBill(billId: bill.id, receiptUrl: bill.receiptUrl) }
                        }
                    }
                }
            }
        }
        .cardStyle()
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
