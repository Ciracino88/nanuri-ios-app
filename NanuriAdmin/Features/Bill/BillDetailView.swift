import SwiftUI

/// 청구서 한 건을 처리하는 시트. 카드를 누르면 열린다.
///
/// 청구서로 할 수 있는 일은 **전부 여기 있다** — 영수증 보기 · 송금 · 거절 · 삭제.
/// 목록 카드는 정보만 보여준다 (`BillRowView`). 되돌릴 수 없는 두 개(거절·삭제)는
/// 여기서 확인을 한 번 더 받는다 (DESIGN.md 6번).
///
/// 송금은 이 시트가 직접 못 한다. 토스 앱을 열고 돌아와서 "송금했나요?"를 물어야
/// 하는데(`TossResultView`) 시트 위에 시트를 겹치면 두 개를 같이 닫아야 해서,
/// **이 시트는 닫히기만 하고 다음 시트는 `BillListView` 가 연다.**
struct BillDetailView: View {
    let bill: Bill
    /// 이름으로 찾은 계좌. 없으면 송금 대신 계좌 등록을 유도한다.
    let payee: Payee?
    @ObservedObject var viewModel: BillViewModel
    /// 토스로 넘어간다. 시트를 닫는 것까지 이 클로저가 한다.
    let onTransfer: () -> Void
    /// 계좌부 등록 시트로 넘어간다. 계좌를 못 찾았을 때만 쓴다.
    let onRegisterPayee: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showReceipt = false
    @State private var showRejectAlert = false
    @State private var showDeleteAlert = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DS.Spacing.section) {
                    header
                    amount
                    details
                    ActionButton(title: "영수증 보기", kind: .tinted) { showReceipt = true }
                }
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.top, DS.Spacing.screen)
                .padding(.bottom, DS.Spacing.section)
            }

            // 바닥 버튼은 스크롤을 안 따라간다. 시트를 반만 올린 상태에서는 위 내용이
            // 이 선에서 잘리므로, 선과 여백으로 "여기까지가 읽는 자리"를 갈라 준다.
            // 이게 없으면 잘린 내용이 버튼에 붙어 한 덩어리로 보인다.
            Divider()

            actions
                .padding(.horizontal, DS.Spacing.screen)
                .padding(.top, DS.Spacing.screen)
                .padding(.bottom, DS.Spacing.screen)
        }
        .sheet(isPresented: $showReceipt) {
            ReceiptSheetView(receiptUrl: bill.receiptUrl)
        }
        .alert("이 청구서를 거절할까요?", isPresented: $showRejectAlert) {
            Button("거절", role: .destructive) {
                Task {
                    await viewModel.updateStatus(billId: bill.id, status: "rejected")
                    dismiss()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("처리 완료로 넘어가고, 앱에서는 다시 대기중으로 되돌릴 수 없어요.")
        }
        .alert("이 청구서를 지울까요?", isPresented: $showDeleteAlert) {
            Button("삭제", role: .destructive) {
                Task {
                    await viewModel.deleteBill(billId: bill.id, receiptUrl: bill.receiptUrl)
                    dismiss()
                }
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("영수증 이미지까지 같이 지워지고 되돌릴 수 없어요.")
        }
    }

    // MARK: - 머리

    private var header: some View {
        HStack(spacing: DS.Spacing.medium) {
            InitialAvatarView(name: bill.submitterName, placement: .sheet)
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text(bill.submitterName)
                    .sheetTitle()
                Text(payee?.accountLine ?? "계좌 미등록")
                    .font(.subheadline)
                    .foregroundColor(payee == nil ? DS.Palette.pending : .secondary)
            }
            Spacer(minLength: DS.Spacing.small)
            Text(bill.statusLabel)
                .tagChip(color: bill.statusColor)
        }
    }

    /// 시트에서 제일 먼저 읽어야 하는 자리. 크기를 여기에 몰아준다.
    private var amount: some View {
        VStack(spacing: DS.Spacing.tight) {
            Text("\(bill.amount.formatted())원")
                .heroAmount()
            Text(bill.title)
                .sheetSubtext()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var details: some View {
        VStack(spacing: 0) {
            // 기기 언어가 영어여도 한국어로 나와야 한다. `formatted()` 는 로케일을 탄다.
            detailRow("청구일", bill.createdAt.koreanDateTimeString)
            Divider().padding(.vertical, DS.Spacing.small)
            detailRow("상태", bill.statusLabel, color: bill.statusColor)
            if let payee {
                Divider().padding(.vertical, DS.Spacing.small)
                detailRow("계좌", payee.accountLine)
            }
        }
        .groupBox()
    }

    private func detailRow(_ label: String, _ value: String, color: Color? = nil) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .sheetSubtext()
            Spacer(minLength: DS.Spacing.medium)
            Text(value)
                .sheetTitle()
                .foregroundColor(color ?? .primary)
                .multilineTextAlignment(.trailing)
        }
    }

    // MARK: - 바닥 버튼

    /// 대기중이면 처리하는 자리고, 처리된 뒤에는 지우는 자리다.
    /// 계좌를 못 찾았으면 송금 대신 계좌 등록이 들어온다 — 등록이 먼저다.
    @ViewBuilder
    private var actions: some View {
        HStack(spacing: DS.Spacing.small) {
            if bill.isPending {
                ActionButton(title: "거절", kind: .destructive) { showRejectAlert = true }
                if payee != nil {
                    ActionButton(title: "송금하기", kind: .primary, action: onTransfer)
                } else {
                    ActionButton(title: "계좌 등록하기", kind: .primary, action: onRegisterPayee)
                }
            } else {
                ActionButton(title: "닫기") { dismiss() }
                ActionButton(title: "삭제", kind: .destructive) { showDeleteAlert = true }
            }
        }
    }
}

// MARK: - 영수증

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
                            VStack(spacing: DS.Spacing.medium) {
                                Image(systemName: "exclamationmark.triangle")
                                    .font(.system(size: DS.Icon.placeholder))
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
