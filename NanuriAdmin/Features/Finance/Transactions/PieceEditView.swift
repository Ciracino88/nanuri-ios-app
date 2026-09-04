import SwiftUI

/// 분할된 **항목(조각) 하나**를 고치는 화면. 목록에서 조각을 누르면 여기로 온다.
///
/// 고치는 건 그 조각의 **적요·카테고리**뿐이다 — 금액·통장·일시는 조각의 것이 아니라
/// 부모 거래의 것이라 "속한 출금" 맥락으로 읽기 전용이고, 영수증·삭제도 출금 전체에
/// 걸린다. 매칭 거래의 조각은 금액·통장이 청구·통장에서 온 정본이라 여기서 못 고친다.
///
/// 저장은 거래 편집과 같은 `saveTransactionEdits` 로 수렴한다 — 거래 필드는 그대로
/// 두고 이 조각만 바꿔 넣으면 형제 조각은 그대로 다시 만들어진다.
struct PieceEditView: View {
    let row: LedgerRow
    let suggestions: [String]
    @ObservedObject var viewModel: FinanceViewModel

    private var transaction: BankTransaction { row.transaction }
    /// 눌린 조각.
    private var split: TransactionSplit? { row.split }

    @State private var category: String
    @State private var descriptionText: String
    @State private var keptUrls: [String]            // 유지할 기존 영수증 (저장 시 확정)
    @State private var pendingImages: [PendingImage]  // 새로 추가한, 아직 업로드 안 한 이미지
    /// 형제 조각까지 그대로 담아 둔다 — 저장은 조각을 통째로 다시 만들어 넣으므로,
    /// 눌린 하나만 고치고 나머지는 원래대로 다시 써야 한다.
    @State private var splitDrafts: [SplitDraft]
    @State private var showDeleteConfirm = false
    @State private var showReceiptManager = false
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

    /// 부모 출금이 몇 조각인가. 2 이상이면 히어로(조각)와 총액이 달라 맥락이 필요하다.
    private var pieceCount: Int { splitDrafts.count }
    private var receiptCount: Int { keptUrls.count + pendingImages.count }

    private func accountName(_ id: UUID) -> String {
        viewModel.accounts.first { $0.id == id }?.name ?? "알 수 없음"
    }

    /// 어느 통장의 거래인가. **내부 이체면 방향까지 보여준다** ("농협 → 모임").
    private var accountLabel: String {
        guard let counter = transaction.counterAccountId else {
            return accountName(transaction.accountId)
        }
        return transaction.amount < 0
            ? "\(accountName(transaction.accountId)) → \(accountName(counter))"
            : "\(accountName(counter)) → \(accountName(transaction.accountId))"
    }

    /// 히어로 금액의 색. 목록 줄과 같은 규칙 — 입금 파랑 · 출금 검정 · 이체 회색.
    /// 조각은 늘 통장 값(`transaction.isDeposit`)이 정본이다.
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
                // 히어로는 조각 금액을, 아래 맥락은 출금 전체를 말한다.
                AmountHeroSection(amountText: nil, displayAmount: row.amount,
                                  color: heroColor, caption: heroCaption)
                pieceInfoSection
                parentContextSection
                ReceiptButtonSection(receiptCount: receiptCount, isSaving: isSaving) {
                    showReceiptManager = true
                }
                DeleteSection(
                    // 조각을 눌러도 삭제는 **출금 전체**에 걸린다 — 조각 하나만
                    // 지우는 건 없다(합이 거래액과 어긋난다).
                    label: pieceCount > 1 ? "이 출금 전체 삭제" : "이 거래 삭제",
                    message: pieceCount > 1
                        ? "이 출금의 \(pieceCount)개 항목과 영수증이 모두 지워져요. 되돌릴 수 없어요."
                        : "분할 항목과 영수증도 같이 지워져요. 되돌릴 수 없어요.",
                    isSaving: isSaving
                ) { showDeleteConfirm = true }
            }
            .navigationTitle("항목 편집")
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
            .sheet(isPresented: $showReceiptManager) {
                ReceiptManagerView(keptUrls: $keptUrls,
                                   pendingImages: $pendingImages,
                                   isSaving: isSaving)
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

    /// 눌린 조각의 적요·카테고리. 이것만 이 화면에서 고친다.
    private var pieceInfoSection: some View {
        Section {
            TextField("적요 (예: 파라솔 대여비)", text: $descriptionText)
            TextField("카테고리 (예: 행사비, 회비)", text: $category)
            CategorySuggestionChips(suggestions: suggestions, selected: $category)
        } header: {
            Text("항목")
        }
    }

    /// **이 조각이 속한 출금.** 총액·통장·일시는 조각의 것이 아니라 거래 전체의
    /// 것이라 읽기 전용 맥락으로만 둔다.
    @ViewBuilder
    private var parentContextSection: some View {
        Section {
            if pieceCount > 1 {
                LabeledContent("전체 출금", value: "\(abs(transaction.amount).formatted())원")
            }
            LabeledContent("통장", value: accountLabel)
            LabeledContent("일시", value: transaction.datetime.koreanDateTimeString)
        } header: {
            Text("이 항목이 속한 출금")
        } footer: {
            if pieceCount > 1 {
                Text("이 출금 한 건이 \(pieceCount)개 항목으로 나뉘어요. 금액·통장·일시는 출금 전체의 값이라 여기서 고치지 않아요.")
            }
        }
    }

    /// **거래 필드는 그대로 두고** 눌린 조각의 적요·카테고리만 바꿔 넣는다.
    /// 저장은 거래 편집과 같은 `saveTransactionEdits` 를 타므로 형제 조각은 그대로
    /// 다시 만들어진다.
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
