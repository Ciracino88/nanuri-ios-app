import SwiftUI

/// 청구서 한 건을 처리하는 시트. 카드를 누르면 열린다.
///
/// 청구서로 할 수 있는 일은 **전부 여기 있다** — 영수증 보기 · 송금 · 거절 · 삭제.
/// 목록 카드는 정보만 보여준다 (`BillRowView`). 되돌릴 수 없는 두 개(거절·삭제)는
/// 여기서 확인을 한 번 더 받는다 (DESIGN.md 6번).
///
/// 같은 사람이 낸 다른 대기중 청구서(`siblings`)가 있으면 아래에 상자로 뜨고,
/// 고른 만큼 **금액이 합쳐져 토스는 한 번만 연다.** 열어 둔 건은 못 뺀다.
///
/// 송금은 이 시트가 직접 못 한다. 토스 앱을 열고 돌아와서 "송금했나요?"를 물어야
/// 하는데(`TossResultView`) 시트 위에 시트를 겹치면 두 개를 같이 닫아야 해서,
/// **이 시트는 닫히기만 하고 다음 시트는 `BillListView` 가 연다.**
struct BillDetailView: View {
    let bill: Bill
    /// 이름으로 찾은 계좌. 없으면 송금 대신 계좌 등록을 유도한다.
    let payee: Payee?
    /// 같은 사람의 다른 **대기중** 청구서. 묶어 보낼 후보다.
    let siblings: [Bill]
    @ObservedObject var viewModel: BillViewModel
    /// 토스로 넘어간다. 묶어서 보낼 청구서들을 넘기고, 시트를 닫는 것까지 이 클로저가 한다.
    let onTransfer: ([Bill]) -> Void
    /// 계좌부 등록 시트로 넘어간다. 계좌를 못 찾았을 때만 쓴다.
    let onRegisterPayee: () -> Void

    @Environment(\.dismiss) private var dismiss
    /// 영수증을 볼 청구서. 묶음 상자의 다른 건도 여기로 연다.
    @State private var receiptTarget: Bill?
    /// 묶어서 보내려고 고른 **다른** 건들. 열어 둔 건은 항상 들어가므로 여기 없다.
    @State private var extras: Set<UUID> = []
    @State private var showRejectAlert = false
    @State private var showDeleteAlert = false

    /// 지금 보낼 청구서들. 첫 번째는 언제나 열어 둔 그 건이다.
    private var selectedBills: [Bill] {
        [bill] + siblings.filter { extras.contains($0.id) }
    }

    private var selectedTotal: Int {
        selectedBills.reduce(0) { $0 + $1.amount }
    }

    /// 묶음 상자를 보일 때. 계좌가 없으면 송금 자체를 못 하므로 고를 이유도 없다.
    private var canGroup: Bool {
        bill.isPending && payee != nil && !siblings.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: DS.Spacing.section) {
                    header
                    amount
                    if canGroup { group }
                    details
                    ActionButton(title: "영수증 보기", kind: .tinted) { receiptTarget = bill }
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
        .sheet(item: $receiptTarget) { target in
            ReceiptSheetView(receiptUrl: target.receiptUrl)
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
    ///
    /// 묶음을 고르면 이 수가 **합계로 바뀐다.** 여기 적힌 금액이 곧 토스로 넘어가는
    /// 금액이어야 한다 — 제일 큰 글자가 실제로 보낼 돈과 다르면 그게 제일 위험하다.
    private var amount: some View {
        VStack(spacing: DS.Spacing.tight) {
            Text("\(selectedTotal.formatted())원")
                .heroAmount()
            Text(selectedBills.count == 1 ? bill.title : "\(selectedBills.count)건 합계")
                .sheetSubtext()
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 묶어 보내기

    /// 같은 사람의 대기중 청구서를 한 상자에 모아 고르게 한다.
    ///
    /// 사람이 다르면 여기 안 뜬다. 토스 딥링크가 수취인 한 명·금액 하나만 받아서
    /// 여러 사람을 한 번에 보낼 방법이 없기 때문이다 (`BillViewModel.openToss`).
    private var group: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.small) {
            Text("같은 사람의 대기중 청구서")
                .sheetSubtext()

            VStack(spacing: 0) {
                groupRow(bill, isLocked: true)
                ForEach(siblings) { sibling in
                    Divider().padding(.vertical, DS.Spacing.small)
                    groupRow(sibling, isLocked: false)
                }
            }
            .groupBox()
        }
    }

    /// 상자 안의 한 줄. 열어 둔 건(`isLocked`)은 표시만 하고 못 끈다 —
    /// 그 건을 빼려면 시트를 닫고 그 청구서를 열면 된다.
    @ViewBuilder
    private func groupRow(_ row: Bill, isLocked: Bool) -> some View {
        HStack(spacing: DS.Spacing.small) {
            if isLocked {
                groupLabel(row, isOn: true)
            } else {
                Button {
                    if extras.contains(row.id) { extras.remove(row.id) } else { extras.insert(row.id) }
                } label: {
                    groupLabel(row, isOn: extras.contains(row.id))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(extras.contains(row.id) ? [.isButton, .isSelected] : .isButton)
                .accessibilityHint("두 번 누르면 이 건을 합계에 넣거나 뺄 수 있어요")
            }

            // 묶어서 보내면 이 자리에서 승인되는 건이 여러 개다. 각 건의 영수증을
            // 여기서 바로 볼 수 있어야 확인하고 보낼 수 있다.
            Button { receiptTarget = row } label: {
                Image(systemName: "paperclip")
                    .font(.system(size: DS.Icon.inline))
                    .foregroundColor(DS.Palette.deposit)
                    .frame(width: DS.Size.iconButton, height: DS.Size.iconButton)
                    .background(DS.Palette.deposit.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.button))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(row.title) 영수증 보기")
        }
    }

    private func groupLabel(_ row: Bill, isOn: Bool) -> some View {
        HStack(spacing: DS.Spacing.medium) {
            Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                .font(.system(size: DS.Icon.feature))
                .foregroundColor(isOn ? DS.Palette.deposit : .secondary)
            VStack(alignment: .leading, spacing: DS.Spacing.tight) {
                Text(row.title)
                    .rowTitle()
                    .lineLimit(1)
                Text(row.createdAt.koreanShortDateString)
                    .rowSubtext()
            }
            Spacer(minLength: DS.Spacing.small)
            Text("\(row.amount.formatted())원")
                .rowTitle()
        }
        .contentShape(Rectangle())
    }

    // MARK: - 나머지 정보

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
                    // 묶었으면 몇 건을 보내는지 버튼에 적는다. 누르면 앱이 넘어가 버려서
                    // 여기가 건수를 확인할 수 있는 마지막 자리다.
                    ActionButton(
                        title: selectedBills.count == 1 ? "송금하기" : "\(selectedBills.count)건 송금하기",
                        kind: .primary
                    ) {
                        onTransfer(selectedBills)
                    }
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
