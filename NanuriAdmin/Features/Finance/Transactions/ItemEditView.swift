import SwiftUI

/// 장부 **항목 하나**의 상세·편집 화면. 목록에서 줄을 누르면 온다.
///
/// **항목이 곧 장부 줄이라** 거래·조각 구분 없이 이 화면 하나가 다 받는다.
/// 값을 죽 나열하고 고칠 수 있는 것에만 chevron 을 달아 눌러서 필드별 시트로 고친다.
///
/// **무엇을 고칠 수 있나는 은행 증명 유무가 정한다.**
///   - 농협 수기 항목(`sourceTransactionId == nil`): 금액·일시·통장까지 전부 열림.
///   - 거래내역서에서 온 항목(모임): 금액·일시·통장은 은행 값이라 chevron 을 안 단다
///     (잠긴 것처럼 보인다). 카테고리·적요·영수증만 열린다.
///
/// 분할을 다시 쪼개거나 이체 판정을 바꾸는 건 여기 없다 — 그건 분할 UX(추후)가 맡는다.
struct ItemEditView: View {
    let row: LedgerRow
    let suggestions: [String]
    @ObservedObject var viewModel: FinanceViewModel

    private var item: FinanceItem { row.item }
    /// 농협 수기 항목이면 금액·일시·통장까지 고칠 수 있다.
    private var editable: Bool { !item.isBankBacked }
    private var isTransfer: Bool { item.isInternalTransfer }

    @State private var category: String
    @State private var descriptionText: String
    @State private var amountText: String
    @State private var isDeposit: Bool
    @State private var datetime: Date
    @State private var accountId: UUID
    @State private var keptUrls: [String]
    @State private var pendingImages: [PendingImage]
    @State private var editField: EditField?
    @State private var showReceiptManager = false
    @State private var showDeleteConfirm = false
    @State private var isSaving = false
    @Environment(\.dismiss) var dismiss

    init(row: LedgerRow, suggestions: [String], viewModel: FinanceViewModel) {
        self.row = row
        self.suggestions = suggestions
        self.viewModel = viewModel
        let item = row.item
        _category = State(initialValue: item.category ?? "")
        _descriptionText = State(initialValue: item.description ?? "")
        _amountText = State(initialValue: String(abs(item.amount)))
        _isDeposit = State(initialValue: item.isDeposit)
        _datetime = State(initialValue: item.datetime)
        _accountId = State(initialValue: item.accountId)
        _keptUrls = State(initialValue: item.receipts)
        _pendingImages = State(initialValue: [])
    }

    private var editedMagnitude: Int { Int(amountText) ?? 0 }
    private var receiptCount: Int { keptUrls.count + pendingImages.count }
    private var canSave: Bool { !editable || editedMagnitude > 0 }

    /// 이 항목이 속한 은행 거래의 형제 항목 수. 2 이상이면 "속한 출금" 맥락을 보인다.
    private var siblings: [FinanceItem] {
        guard let txId = item.sourceTransactionId else { return [item] }
        return viewModel.items.filter { $0.sourceTransactionId == txId }
    }
    private var pieceCount: Int { siblings.count }

    private func accountName(_ id: UUID) -> String {
        viewModel.accounts.first { $0.id == id }?.name ?? "알 수 없음"
    }

    /// 어느 통장인가. **내부 이체면 방향까지** ("농협 → 모임").
    private var accountLabel: String {
        guard isTransfer, let other = viewModel.accounts.first(where: { $0.id != item.accountId })?.id else {
            return accountName(editable ? accountId : item.accountId)
        }
        return item.amount < 0
            ? "\(accountName(item.accountId)) → \(accountName(other))"
            : "\(accountName(other)) → \(accountName(item.accountId))"
    }

    private var heroSignedAmount: Int { editable ? (isDeposit ? editedMagnitude : -editedMagnitude) : item.amount }

    private var heroColor: Color {
        if isTransfer { return DS.Ink.tertiary }
        let deposit = editable ? isDeposit : item.isDeposit
        return deposit ? DS.Palette.deposit : DS.Palette.withdrawal
    }
    private var heroCaption: String {
        if isTransfer { return "통장 사이 이체" }
        return (editable ? isDeposit : item.isDeposit) ? "입금" : "출금"
    }

    var body: some View {
        NavigationView {
            Form {
                AmountHeroSection(displayAmount: heroSignedAmount, color: heroColor, caption: heroCaption,
                                  onEdit: editable ? { editField = .amount } : nil)
                if !isTransfer { infoSection }
                contextSection
                if !isTransfer {
                    ReceiptButtonSection(receiptCount: receiptCount, isSaving: isSaving) {
                        showReceiptManager = true
                    }
                }
                DeleteSection(label: deleteLabel, message: deleteMessage, isSaving: isSaving) {
                    showDeleteConfirm = true
                }
            }
            .navigationTitle("항목 상세")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isSaving {
                        ProgressView()
                    } else if !isTransfer {
                        Button("저장") { Task { await save() } }
                            .fontWeight(.semibold)
                            .disabled(!canSave)
                    }
                }
            }
            .sheet(item: $editField) { field in editSheet(field) }
            .sheet(isPresented: $showReceiptManager) {
                ReceiptManagerView(keptUrls: $keptUrls, pendingImages: $pendingImages, isSaving: isSaving)
            }
            .confirmationDialog("이 항목을 삭제할까요?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
                Button("삭제", role: .destructive) {
                    Task {
                        isSaving = true
                        await viewModel.deleteItem(item)
                        isSaving = false
                        dismiss()
                    }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
        }
    }

    /// 적요·일시·통장·카테고리. 편집 가능 여부는 은행 증명 유무가 정한다.
    @ViewBuilder
    private var infoSection: some View {
        Section {
            DetailRow(label: "적요",
                      value: descriptionText.isEmpty ? "없음" : descriptionText,
                      isPlaceholder: descriptionText.isEmpty,
                      onEdit: { editField = .description })
            DetailRow(label: "카테고리",
                      value: category.isEmpty ? "미지정" : category,
                      isPlaceholder: category.isEmpty,
                      onEdit: { editField = .category })
            DetailRow(label: "일시",
                      value: (editable ? datetime : item.datetime).koreanDateString,
                      onEdit: editable ? { editField = .date } : nil)
            DetailRow(label: "통장", value: accountLabel,
                      onEdit: editable ? { editField = .account } : nil)
        } header: {
            Text("항목")
        } footer: {
            if !editable {
                Text("금액·일시·통장은 거래내역서에 찍힌 값이라 고칠 수 없어요. 적요·카테고리·영수증만 고쳐요.")
            }
        }
    }

    /// 은행 적요와, 여러 항목으로 나뉜 출금이면 그 전체 맥락.
    @ViewBuilder
    private var contextSection: some View {
        if let tx = row.transaction {
            Section {
                if pieceCount > 1 {
                    DetailRow(label: "전체 출금", value: "\(abs(tx.amount).formatted())원")
                }
                DetailRow(label: "은행 적요", value: tx.description ?? "-")
                if isTransfer {
                    DetailRow(label: "통장", value: accountLabel)
                    DetailRow(label: "일시", value: item.datetime.koreanDateTimeString)
                }
            } header: {
                Text(pieceCount > 1 ? "이 항목이 속한 출금" : "은행 증명")
            } footer: {
                if pieceCount > 1 {
                    Text("이 출금 한 건이 \(pieceCount)개 항목으로 나뉘어요. 금액·통장·일시는 출금 전체의 값이에요.")
                }
            }
        }
    }

    private var deleteLabel: String {
        if item.sourceTransactionId != nil {
            return pieceCount > 1 ? "이 출금 전체 삭제" : "이 거래 삭제"
        }
        return "이 항목 삭제"
    }
    private var deleteMessage: String {
        if item.sourceTransactionId != nil && pieceCount > 1 {
            return "이 출금의 \(pieceCount)개 항목과 영수증이 모두 지워져요. 되돌릴 수 없어요."
        }
        return "이 항목과 영수증이 지워져요. 되돌릴 수 없어요."
    }

    @ViewBuilder
    private func editSheet(_ field: EditField) -> some View {
        switch field {
        case .amount:
            AmountEditSheet(magnitude: editedMagnitude, isDeposit: isDeposit) { m, d in
                amountText = String(m); isDeposit = d
            }
        case .date:
            DateEditSheet(date: datetime) { datetime = $0 }
        case .account:
            AccountEditSheet(title: "통장", choices: viewModel.accounts, selected: accountId) { accountId = $0 }
        case .description:
            DescriptionEditSheet(text: descriptionText) { descriptionText = $0 }
        case .category:
            CategoryEditSheet(text: category, suggestions: suggestions) { category = $0 }
        }
    }

    private func save() async {
        isSaving = true
        let newImages = pendingImages.map { $0.image }
        let cat = category.isEmpty ? nil : category
        let desc = descriptionText.isEmpty ? nil : descriptionText
        if editable {
            await viewModel.saveManualItem(
                id: item.id, accountId: accountId, datetime: datetime,
                amount: isDeposit ? editedMagnitude : -editedMagnitude,
                category: cat, description: desc,
                keptUrls: keptUrls, newImages: newImages, originalUrls: item.receipts
            )
        } else {
            await viewModel.saveItemFields(
                id: item.id, category: cat, description: desc,
                keptUrls: keptUrls, newImages: newImages, originalUrls: item.receipts
            )
        }
        isSaving = false
        if viewModel.error == nil { dismiss() }
    }
}
