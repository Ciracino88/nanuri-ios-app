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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            // 상단: 제목 + 상태
            HStack {
                Text(bill.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
                Text(statusLabel)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(statusColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(statusColor.opacity(0.1))
                    .cornerRadius(8)
            }

            Divider()

            // 중단: 이름 + 계좌
            if let profile = bill.userProfile {
                VStack(alignment: .leading, spacing: 4) {
                    Text(profile.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(profile.bankName) \(profile.accountNumber)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(bill.submitterName ?? "이름 없음")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("\(bill.bankName ?? "") \(bill.accountNumber ?? "")")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            // 하단: 금액 + 날짜
            HStack {
                Text("\(bill.amount.formatted())원")
                    .font(.title3)
                    .fontWeight(.bold)
                Spacer()
                Text(bill.createdAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Divider()

            // 영수증 확인 버튼
            Button {
                showReceiptSheet = true
            } label: {
                Label("영수증 확인", systemImage: "doc.text.magnifyingglass")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.gray.opacity(0.08))
                    .foregroundColor(.primary)
                    .cornerRadius(10)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            .buttonStyle(.plain)

            // 대기중: 송금/거절 버튼
            if bill.status == "pending" {
                HStack(spacing: 8) {
                    Button {
                        pendingBill = bill
                        viewModel.openToss(bill: bill)
                    } label: {
                        Label("토스로 송금", systemImage: "paperplane.fill")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }

                    Button {
                        Task { await viewModel.updateStatus(billId: bill.id, status: "rejected") }
                    } label: {
                        Label("거절", systemImage: "xmark")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Color.red.opacity(0.1))
                            .foregroundColor(.red)
                            .cornerRadius(10)
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .buttonStyle(.plain)
            }

            // 처리완료: 삭제 버튼
            if bill.status != "pending" {
                Button(role: .destructive) {
                    Task { await viewModel.deleteBill(billId: bill.id, receiptUrl: bill.receiptUrl) }
                } label: {
                    Label("삭제", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.1))
                        .foregroundColor(.red)
                        .cornerRadius(10)
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(16)
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
