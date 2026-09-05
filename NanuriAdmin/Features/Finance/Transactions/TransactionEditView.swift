import SwiftUI

/// 분할 없는 **거래 하나**의 상세 화면. 목록에서 (조각이 아닌) 거래를 누르면 온다.
///
/// **상세다.** 값을 죽 나열하고, 고칠 수 있는 것만 chevron 을 달아 눌러서 필드별 시트로
/// 고친다. 거래내역서에서 온 거래는 금액·일시·통장이 통장의 기록이라 chevron 을 안 단다
/// — 레이아웃은 같고 그 세 줄만 잠긴 것처럼 보인다. 조각을 눌렀을 때는 `PieceEditView`.
///
/// 시트 편집은 **로컬 상태만** 바꾸고, DB 저장은 "저장" 이 `saveTransactionEdits` 로
/// 한 번에 한다. 거래내역서 거래의 잠긴 값은 화면이 chevron 을 안 다는 것과 별개로
/// 뷰모델이 한 번 더 막는다.
///
/// **통장 사이 이체 토글은 거래내역서 거래에만 있다.** 판정(적요 == 농협의
/// `statement_alias`)은 매처가 불러올 때 하지만, 못 잡거나 오탐일 때 사람이 고칠 수
/// 있어야 해서 거래내역서 거래 편집에는 토글이 남는다 — 은행이 말해 줄 수 없는 회계
/// 판단이라 그렇다. **수기 거래엔 없다**(추가·편집 모두): 이체는 반드시 모임통장을
/// 지나 거래내역서로 들어오므로, 손입력이 이체일 수 없다.
struct TransactionEditView: View {
    let row: LedgerRow
    let suggestions: [String]
    @ObservedObject var viewModel: FinanceViewModel

    private var transaction: BankTransaction { row.transaction }

    @State private var category: String
    @State private var descriptionText: String
    @State private var amountText: String
    @State private var isDeposit: Bool
    @State private var datetime: Date
    @State private var accountId: UUID
    @State private var counterAccountId: UUID?
    @State private var keptUrls: [String]
    @State private var pendingImages: [PendingImage]
    @State private var splitDrafts: [SplitDraft]
    @State private var editField: EditField?
    @State private var activeSplit: SplitDraft?
    @State private var showReceiptManager = false
    @State private var showDeleteConfirm = false
    @State private var showSplitMismatch = false
    @State private var isSaving = false
    @Environment(\.dismiss) var dismiss

    init(row: LedgerRow, suggestions: [String], viewModel: FinanceViewModel) {
        self.row = row
        self.suggestions = suggestions
        self.viewModel = viewModel
        let tx = row.transaction
        _category = State(initialValue: tx.category ?? "")
        _descriptionText = State(initialValue: tx.description ?? "")
        _amountText = State(initialValue: String(abs(tx.amount)))
        _isDeposit = State(initialValue: tx.isDeposit)
        _datetime = State(initialValue: tx.datetime)
        _accountId = State(initialValue: tx.accountId)
        _counterAccountId = State(initialValue: tx.counterAccountId)
        _keptUrls = State(initialValue: tx.receipts)
        _pendingImages = State(initialValue: [])
        _splitDrafts = State(initialValue: viewModel.splits(for: tx.id).map {
            SplitDraft(id: $0.id, category: $0.category ?? "", amount: $0.amount, description: $0.description ?? "")
        })
    }

    /// 금액·일시·통장을 이 화면에서 고칠 수 있나 — **손입력 거래일 때만.**
    private var isEditable: Bool { !transaction.isFromStatement }
    private var pieceCount: Int { splitDrafts.count }
    private var receiptCount: Int { keptUrls.count + pendingImages.count }

    private func accountName(_ id: UUID) -> String {
        viewModel.accounts.first { $0.id == id }?.name ?? "알 수 없음"
    }

    private var editedMagnitude: Int { Int(amountText) ?? 0 }

    /// 분할 합계와 견줄 거래액. 거래내역서 거래는 통장 값, 손입력은 입력 중인 값.
    private var txMagnitude: Int {
        transaction.isFromStatement ? abs(transaction.amount) : editedMagnitude
    }

    /// 히어로에 세울 부호 붙은 금액. 손입력은 입력 중인 값, 거래내역서는 통장 값.
    private var heroSignedAmount: Int {
        transaction.isFromStatement ? transaction.amount : (isDeposit ? editedMagnitude : -editedMagnitude)
    }

    /// 저장할 부호 붙은 금액.
    private var signedAmount: Int {
        guard !transaction.isFromStatement else { return transaction.amount }
        return isDeposit ? editedMagnitude : -editedMagnitude
    }

    private var canSave: Bool {
        transaction.isFromStatement || editedMagnitude > 0
    }
    private var splitSum: Int { splitDrafts.reduce(0) { $0 + $1.amount } }
    private var splitRemaining: Int { txMagnitude - splitSum }

    /// 어느 통장의 거래인가. **내부 이체면 방향까지** ("농협 → 모임").
    private var accountLabel: String {
        guard let counter = counterAccountId else { return accountName(accountId) }
        return heroSignedAmount < 0
            ? "\(accountName(accountId)) → \(accountName(counter))"
            : "\(accountName(counter)) → \(accountName(accountId))"
    }

    private var heroColor: Color {
        if counterAccountId != nil { return DS.Ink.tertiary }
        let deposit = transaction.isFromStatement ? transaction.isDeposit : isDeposit
        return deposit ? DS.Palette.deposit : DS.Palette.withdrawal
    }
    private var heroCaption: String {
        if counterAccountId != nil { return "통장 사이 이체" }
        let deposit = transaction.isFromStatement ? transaction.isDeposit : isDeposit
        return deposit ? "입금" : "출금"
    }

    var body: some View {
        NavigationView {
            Form {
                AmountHeroSection(displayAmount: heroSignedAmount, color: heroColor, caption: heroCaption,
                                  onEdit: isEditable ? { editField = .amount } : nil)
                infoSection
                Section("카테고리") {
                    DetailRow(label: "카테고리",
                              value: category.isEmpty ? "미지정" : category,
                              isPlaceholder: category.isEmpty,
                              onEdit: { editField = .category })
                }
                splitSection
                ReceiptButtonSection(receiptCount: receiptCount, isSaving: isSaving) {
                    showReceiptManager = true
                }
                DeleteSection(
                    label: "이 거래 삭제",
                    message: "분할 항목과 영수증도 같이 지워져요. 되돌릴 수 없어요.",
                    isSaving: isSaving
                ) { showDeleteConfirm = true }
            }
            .navigationTitle("항목 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("저장") { save() }
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                    }
                }
            }
            .sheet(item: $editField) { field in editSheet(field) }
            .sheet(isPresented: $showReceiptManager) {
                ReceiptManagerView(keptUrls: $keptUrls, pendingImages: $pendingImages, isSaving: isSaving)
            }
            .sheet(item: $activeSplit) { draft in splitSheet(draft) }
            .alert("분할 금액 불일치", isPresented: $showSplitMismatch) {
                Button("확인") {}
            } message: {
                Text("분할 금액의 합(\(splitSum.formatted())원)이 거래액(\(txMagnitude.formatted())원)과 같아야 저장할 수 있어요.")
            }
            .confirmationDialog("이 거래를 삭제할까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    Task {
                        isSaving = true
                        await viewModel.deleteTransaction(transaction)
                        isSaving = false
                        dismiss()
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("분할 항목과 영수증도 같이 지워져요. 되돌릴 수 없어요.")
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    // MARK: - 거래 정보

    /// **거래내역서에서 온 거래는 일시·통장에 chevron 이 없다** — 통장의 기록이라
    /// 고치면 통장과 어긋나 대조가 뜻을 잃는다. 적요·카테고리는 둘 다 고칠 수 있고,
    /// **통장 사이 이체 토글은 거래내역서 거래에만** 뜬다 — 은행이 말해 줄 수 없는
    /// 회계 판단이라 매처가 못 잡은 것을 사람이 여기서 고친다.
    @ViewBuilder
    private var infoSection: some View {
        Section {
            DetailRow(label: "적요",
                      value: descriptionText.isEmpty ? "없음" : descriptionText,
                      isPlaceholder: descriptionText.isEmpty,
                      onEdit: { editField = .description })
            DetailRow(label: "일시",
                      value: isEditable ? datetime.koreanDateString : transaction.datetime.koreanDateTimeString,
                      onEdit: isEditable ? { editField = .date } : nil)
            DetailRow(label: "통장",
                      value: accountLabel,
                      onEdit: isEditable ? { editField = .account } : nil)
            // 이체 판정은 매처가 하지만, 못 잡거나 오탐일 때 사람이 고쳐야 한다.
            // 수기 거래는 이체일 수 없어(내역서로 들어옴) 거래내역서 거래에만 둔다.
            if transaction.isFromStatement {
                Toggle("통장 사이 이체", isOn: Binding(
                    get: { counterAccountId != nil },
                    set: { on in
                        counterAccountId = on ? viewModel.accounts.first { $0.id != accountId }?.id : nil
                    }
                ))
            }
        } header: {
            Text("거래 정보")
        } footer: {
            if transaction.isFromStatement {
                Text("거래내역서에서 불러온 거래예요. 금액·일시·통장은 통장에 찍힌 기록이라 고칠 수 없어요. 통장 사이 이체인지는 통장이 말해 주지 않아서 여기서 정해요.")
            }
        }
    }

    // MARK: - 분할

    private var splitSection: some View {
        Section {
            if splitDrafts.isEmpty {
                Button {
                    let first = SplitDraft(category: category, amount: txMagnitude, description: "")
                    splitDrafts = [first]
                    activeSplit = first
                } label: {
                    Label("이 거래를 항목별로 분할", systemImage: "square.split.1x2")
                }
            } else {
                ForEach(splitDrafts) { draft in
                    Button {
                        activeSplit = draft
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: DS.Spacing.s1 / 2) {
                                Text(draft.category.isEmpty ? "미지정" : draft.category)
                                    .typeStyle(DS.Typo.body2)
                                    .foregroundColor(DS.Ink.primary)
                                if !draft.description.isEmpty {
                                    Text(draft.description).rowSubtext()
                                }
                            }
                            Spacer()
                            Text("\(draft.amount.formatted())원")
                                .typeStyle(DS.Typo.body2)
                                .tabularAmount()
                                .foregroundColor(DS.Ink.secondary)
                            Image(systemName: "chevron.right")
                                .font(DS.Icon.font(DS.Icon.m))
                                .foregroundColor(DS.Ink.placeholder)
                        }
                    }
                    .buttonStyle(.plain)
                }
                .onDelete { splitDrafts.remove(atOffsets: $0) }

                Button {
                    activeSplit = SplitDraft(category: "", amount: max(splitRemaining, 0), description: "")
                } label: {
                    Label("항목 추가", systemImage: "plus")
                }

                HStack {
                    Text("합계 \(splitSum.formatted())원 / 거래액 \(txMagnitude.formatted())원")
                        .typeStyle(DS.Typo.body3)
                        .tabularAmount()
                        .foregroundColor(DS.Ink.secondary)
                    Spacer()
                    Text(splitRemaining == 0 ? "일치 ✓" : "남은 \(splitRemaining.formatted())원")
                        .typeStyle(DS.Typo.labelS)
                        .tabularAmount()
                        .foregroundColor(splitRemaining == 0 ? DS.Palette.done : DS.Palette.pending)
                }
            }
        } header: {
            Text("분할")
        } footer: {
            Text("한 거래가 여러 항목의 합일 때 나눠서 기입해요. 항목을 눌러 편집합니다. 분할 금액의 합이 거래액과 같아야 저장돼요.")
        }
    }

    // MARK: - 시트 라우팅

    @ViewBuilder
    private func editSheet(_ field: EditField) -> some View {
        switch field {
        case .amount:
            AmountEditSheet(magnitude: editedMagnitude, isDeposit: isDeposit) { m, d in
                amountText = String(m)
                isDeposit = d
            }
        case .date:
            DateEditSheet(date: datetime) { datetime = $0 }
        case .account:
            AccountEditSheet(title: "통장", choices: viewModel.accounts, selected: accountId) { newId in
                accountId = newId
                // 상대 통장이 새 통장과 같아지면 이체가 성립 안 하므로 턴다.
                if counterAccountId == newId { counterAccountId = nil }
            }
        case .description:
            DescriptionEditSheet(text: descriptionText) { descriptionText = $0 }
        case .category:
            CategoryEditSheet(text: category, suggestions: suggestions) { category = $0 }
        }
    }

    @ViewBuilder
    private func splitSheet(_ draft: SplitDraft) -> some View {
        let isNew = !splitDrafts.contains { $0.id == draft.id }
        let otherSum = splitDrafts.filter { $0.id != draft.id }.reduce(0) { $0 + $1.amount }
        SplitEditSheet(
            initial: draft, isNew: isNew, suggestions: suggestions,
            txMagnitude: txMagnitude, otherSum: otherSum,
            onSave: { updated in
                if let idx = splitDrafts.firstIndex(where: { $0.id == updated.id }) {
                    splitDrafts[idx] = updated
                } else {
                    splitDrafts.append(updated)
                }
            },
            onDelete: { splitDrafts.removeAll { $0.id == draft.id } }
        )
    }

    private func save() {
        if !splitDrafts.isEmpty && splitSum != txMagnitude {
            showSplitMismatch = true
            return
        }
        Task {
            isSaving = true
            await viewModel.saveTransactionEdits(
                id: transaction.id,
                datetime: datetime,
                amount: signedAmount,
                description: descriptionText.isEmpty ? nil : descriptionText,
                accountId: accountId,
                counterAccountId: counterAccountId == accountId ? nil : counterAccountId,
                category: category.isEmpty ? nil : category,
                keptUrls: keptUrls,
                newImages: pendingImages.map(\.image),
                originalUrls: transaction.receipts,
                splits: splitDrafts.map {
                    (category: $0.category.isEmpty ? nil : $0.category,
                     amount: $0.amount,
                     description: $0.description.isEmpty ? nil : $0.description)
                }
            )
            isSaving = false
            dismiss()
        }
    }
}
