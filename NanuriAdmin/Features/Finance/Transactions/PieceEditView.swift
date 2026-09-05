import SwiftUI

/// 분할된 **항목(조각) 하나**의 상세 화면. 목록에서 조각을 누르면 여기로 온다.
///
/// **상세다.** `TransactionEditView` 와 같은 레이아웃이되, 고칠 수 있는 건 그 조각의
/// **적요·카테고리**뿐이라 그 둘에만 chevron 이 붙는다. 금액·통장·일시는 조각의 것이
/// 아니라 부모 거래의 것이라 "속한 출금" 으로 읽기 전용이고, 영수증·삭제도 출금 전체에
/// 걸린다.
///
/// 저장은 거래 상세와 같은 `saveTransactionEdits` 로 수렴한다 — 거래 필드는 그대로
/// 두고 이 조각만 바꿔 넣으면 형제 조각은 그대로 다시 만들어진다.
struct PieceEditView: View {
    let row: LedgerRow
    let suggestions: [String]
    @ObservedObject var viewModel: FinanceViewModel

    private var transaction: BankTransaction { row.transaction }
    private var split: TransactionSplit? { row.split }

    @State private var category: String
    @State private var descriptionText: String
    @State private var keptUrls: [String]
    @State private var pendingImages: [PendingImage]
    /// 형제 조각까지 담아 둔다 — 저장은 조각을 통째로 다시 만들어 넣으므로, 눌린
    /// 하나만 고치고 나머지는 원래대로 다시 써야 한다.
    @State private var splitDrafts: [SplitDraft]
    @State private var editField: EditField?
    @State private var showReceiptManager = false
    @State private var showDeleteConfirm = false
    @State private var isSaving = false
    @Environment(\.dismiss) var dismiss

    init(row: LedgerRow, suggestions: [String], viewModel: FinanceViewModel) {
        self.row = row
        self.suggestions = suggestions
        self.viewModel = viewModel
        let tx = row.transaction
        _category = State(initialValue: (row.split?.category ?? tx.category) ?? "")
        _descriptionText = State(initialValue: (row.split?.description ?? tx.description) ?? "")
        _keptUrls = State(initialValue: tx.receipts)
        _pendingImages = State(initialValue: [])
        _splitDrafts = State(initialValue: viewModel.splits(for: tx.id).map {
            SplitDraft(id: $0.id, category: $0.category ?? "", amount: $0.amount, description: $0.description ?? "")
        })
    }

    private var pieceCount: Int { splitDrafts.count }
    private var receiptCount: Int { keptUrls.count + pendingImages.count }

    private func accountName(_ id: UUID) -> String {
        viewModel.accounts.first { $0.id == id }?.name ?? "알 수 없음"
    }

    private var accountLabel: String {
        guard let counter = transaction.counterAccountId else {
            return accountName(transaction.accountId)
        }
        return transaction.amount < 0
            ? "\(accountName(transaction.accountId)) → \(accountName(counter))"
            : "\(accountName(counter)) → \(accountName(transaction.accountId))"
    }

    private var heroColor: Color {
        if transaction.isInternalTransfer { return DS.Ink.tertiary }
        return transaction.isDeposit ? DS.Palette.deposit : DS.Palette.withdrawal
    }
    private var heroCaption: String {
        if transaction.isInternalTransfer { return "통장 사이 이체" }
        return transaction.isDeposit ? "입금" : "출금"
    }

    var body: some View {
        NavigationView {
            Form {
                AmountHeroSection(displayAmount: row.amount, color: heroColor, caption: heroCaption, onEdit: nil)
                Section {
                    DetailRow(label: "적요",
                              value: descriptionText.isEmpty ? "없음" : descriptionText,
                              isPlaceholder: descriptionText.isEmpty,
                              onEdit: { editField = .description })
                    DetailRow(label: "카테고리",
                              value: category.isEmpty ? "미지정" : category,
                              isPlaceholder: category.isEmpty,
                              onEdit: { editField = .category })
                } header: {
                    Text("항목")
                }
                parentContextSection
                ReceiptButtonSection(receiptCount: receiptCount, isSaving: isSaving) {
                    showReceiptManager = true
                }
                DeleteSection(
                    label: pieceCount > 1 ? "이 출금 전체 삭제" : "이 거래 삭제",
                    message: pieceCount > 1
                        ? "이 출금의 \(pieceCount)개 항목과 영수증이 모두 지워져요. 되돌릴 수 없어요."
                        : "분할 항목과 영수증도 같이 지워져요. 되돌릴 수 없어요.",
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
                        Button("저장") { save() }.fontWeight(.semibold)
                    }
                }
            }
            .sheet(item: $editField) { field in editSheet(field) }
            .sheet(isPresented: $showReceiptManager) {
                ReceiptManagerView(keptUrls: $keptUrls, pendingImages: $pendingImages, isSaving: isSaving)
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

    /// **이 조각이 속한 출금.** 총액·통장·일시는 조각의 것이 아니라 거래 전체의
    /// 것이라 chevron 없는 읽기 전용이다.
    @ViewBuilder
    private var parentContextSection: some View {
        Section {
            if pieceCount > 1 {
                DetailRow(label: "전체 출금", value: "\(abs(transaction.amount).formatted())원")
            }
            DetailRow(label: "통장", value: accountLabel)
            DetailRow(label: "일시", value: transaction.datetime.koreanDateTimeString)
        } header: {
            Text("이 항목이 속한 출금")
        } footer: {
            if pieceCount > 1 {
                Text("이 출금 한 건이 \(pieceCount)개 항목으로 나뉘어요. 금액·통장·일시는 출금 전체의 값이라 여기서 고치지 않아요.")
            }
        }
    }

    @ViewBuilder
    private func editSheet(_ field: EditField) -> some View {
        switch field {
        case .description:
            DescriptionEditSheet(text: descriptionText) { descriptionText = $0 }
        case .category:
            CategoryEditSheet(text: category, suggestions: suggestions) { category = $0 }
        default:
            EmptyView()   // 조각 상세에서 고칠 수 있는 건 적요·카테고리뿐이다.
        }
    }

    /// **거래 필드는 그대로 두고** 눌린 조각의 적요·카테고리만 바꿔 넣는다.
    private func save() {
        var drafts = splitDrafts
        if let i = drafts.firstIndex(where: { $0.id == split?.id }) {
            drafts[i].category = category
            drafts[i].description = descriptionText
        }
        Task {
            isSaving = true
            await viewModel.saveTransactionEdits(
                id: transaction.id,
                datetime: transaction.datetime,
                amount: transaction.amount,
                description: transaction.description,
                accountId: transaction.accountId,
                counterAccountId: transaction.counterAccountId,
                category: transaction.category,
                keptUrls: keptUrls,
                newImages: pendingImages.map(\.image),
                originalUrls: transaction.receipts,
                splits: drafts.map {
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
