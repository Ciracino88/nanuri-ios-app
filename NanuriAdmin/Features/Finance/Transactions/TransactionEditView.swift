import SwiftUI

/// 분할 없는 **거래 하나**를 고치는 화면. 목록에서 (조각이 아닌) 거래를 누르면 온다.
///
/// 손으로 넣은 거래는 금액·일시·종류·통장까지 고칠 수 있고, 거래내역서에서 온 거래는
/// 그 넷이 통장의 기록이라 잠긴다(화면이 잠그고 뷰모델이 한 번 더 막는다). 어느 쪽이든
/// **적요·카테고리·분할·영수증**은 고칠 수 있다. 조각을 눌렀을 때의 편집은
/// `PieceEditView` 가 맡는다.
struct TransactionEditView: View {
    let row: LedgerRow
    let suggestions: [String]
    @ObservedObject var viewModel: FinanceViewModel

    /// 편의 별칭. 아래 코드가 거래를 자주 참조한다.
    private var transaction: BankTransaction { row.transaction }

    @State private var category: String
    // 아래 다섯은 **손으로 넣은 거래에서만** 바뀐다. 거래내역서에서 온 거래는
    // 금액·일시·통장이 통장의 기록이라 화면이 잠그고, 뷰모델이 한 번 더 막는다.
    @State private var descriptionText: String
    @State private var amountText: String
    @State private var isDeposit: Bool
    @State private var datetime: Date
    @State private var accountId: UUID
    @State private var counterAccountId: UUID?
    @State private var showDeleteConfirm = false
    @State private var keptUrls: [String]           // 유지할 기존 영수증 (저장 시 확정)
    @State private var pendingImages: [PendingImage] // 새로 추가한, 아직 업로드 안 한 이미지
    @State private var showReceiptManager = false
    @State private var isSaving = false
    @State private var splitDrafts: [SplitDraft]
    @State private var showSplitMismatch = false
    @State private var activeSplit: SplitDraft?
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

    /// 부모 출금이 몇 조각인가. 삭제 안내문이 이걸 본다.
    private var pieceCount: Int { splitDrafts.count }
    /// 금액을 이 화면에서 고칠 수 있나 — **손입력 거래일 때만.**
    private var isEditableAmount: Bool { !transaction.isFromStatement }

    private func accountName(_ id: UUID) -> String {
        viewModel.accounts.first { $0.id == id }?.name ?? "알 수 없음"
    }

    private var receiptCount: Int { keptUrls.count + pendingImages.count }

    /// 입력된 금액(양수). 손으로 넣은 거래에서만 뜻이 있다.
    private var editedMagnitude: Int { Int(amountText) ?? 0 }

    /// 분할 합계와 견줄 거래액. **거래내역서에서 온 거래는 통장 값이 기준**이고,
    /// 손으로 넣은 거래는 지금 입력 중인 값이 기준이다 — 금액을 고치면 분할도
    /// 새 금액에 맞아야 한다.
    private var txMagnitude: Int {
        transaction.isFromStatement ? abs(transaction.amount) : editedMagnitude
    }

    /// 저장할 부호 붙은 금액.
    private var signedAmount: Int {
        guard !transaction.isFromStatement else { return transaction.amount }
        return isDeposit ? editedMagnitude : -editedMagnitude
    }

    private var canSave: Bool {
        // 손입력이면 금액이 있어야, 거래내역서 거래는 텍스트만 고치므로 늘 저장 가능.
        transaction.isFromStatement || editedMagnitude > 0
    }
    private var splitSum: Int { splitDrafts.reduce(0) { $0 + $1.amount } }
    private var splitRemaining: Int { txMagnitude - splitSum }

    /// 히어로 금액의 색. 목록 줄과 같은 규칙 — 입금 파랑 · 출금 검정 · 이체 회색.
    private var heroColor: Color {
        if transaction.isInternalTransfer { return DS.Ink.tertiary }
        // 거래내역서 거래는 통장 값이 정본, 손입력은 입력 중인 값.
        let deposit = transaction.isFromStatement ? transaction.isDeposit : isDeposit
        return deposit ? DS.Palette.deposit : DS.Palette.withdrawal
    }
    /// 금액 아래 한 단어. 부호 대신 성격을 말한다.
    private var heroCaption: String {
        if transaction.isInternalTransfer { return "통장 사이 이체" }
        let deposit = transaction.isFromStatement ? transaction.isDeposit : isDeposit
        return deposit ? "입금" : "출금"
    }

    var body: some View {
        NavigationView {
            Form {
                AmountHeroSection(amountText: isEditableAmount ? $amountText : nil,
                                  displayAmount: transaction.amount,
                                  color: heroColor, caption: heroCaption)
                detailsSection
                // 메모 칸이 여기 있었는데 **어디에도 안 보이는 값**이었다 —
                // 목록 줄도 보고서도 분석 화면도 안 읽었다. 적을 말이 있으면
                // 분할 조각의 적요에 적는다. 그건 실제로 장부에 남는다.
                Section("카테고리") {
                    TextField("카테고리 (예: 회비, 후원금, 행사비)", text: $category)
                    CategorySuggestionChips(suggestions: suggestions, selected: $category)
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
            .navigationTitle("거래 편집")
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
            .sheet(isPresented: $showReceiptManager) {
                ReceiptManagerView(keptUrls: $keptUrls,
                                   pendingImages: $pendingImages,
                                   isSaving: isSaving)
            }
            .alert("분할 금액 불일치", isPresented: $showSplitMismatch) {
                Button("확인") {}
            } message: {
                Text("분할 금액의 합(\(splitSum.formatted())원)이 거래액(\(txMagnitude.formatted())원)과 같아야 저장할 수 있어요.")
            }
            .sheet(item: $activeSplit) { draft in
                let isNew = !splitDrafts.contains { $0.id == draft.id }
                let otherSum = splitDrafts.filter { $0.id != draft.id }.reduce(0) { $0 + $1.amount }
                SplitEditSheet(
                    initial: draft,
                    isNew: isNew,
                    suggestions: suggestions,
                    txMagnitude: txMagnitude,
                    otherSum: otherSum,
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

    /// **금액을 뺀 나머지 정보를 나열한다** (레퍼런스의 이름·수신처·날짜 줄).
    ///
    /// **거래내역서에서 온 거래는 일시·통장이 잠긴다.** 통장에 찍힌 기록이라 고치면
    /// 통장과 어긋나 대조가 뜻을 잃는다. **적요는 둘 다 고칠 수 있다** — 통장이 주는
    /// 적요는 예금주·가맹점 이름(`홍길동` · `우성볼링장`)이라 장부에 그대로 적을 수
    /// 없고, 장부에 적히는 건 "아침식사" 같은 **뜻**이다.
    ///
    /// 통장 사이 이체 토글(`transferRows`)은 아직 여기 남겨 둔다 — 다음 라운드에서
    /// 손본다. 지금 빼면 내부 이체를 고칠 길이 사라진다.
    private var detailsSection: some View {
        Section {
            TextField("적요 (예: 아침식사, 8월 헌금)", text: $descriptionText)

            if transaction.isFromStatement {
                LabeledContent("일시", value: transaction.datetime.koreanDateTimeString)
                LabeledContent("통장", value: accountLabel)
                transferRows
            } else {
                DatePicker("일시", selection: $datetime, displayedComponents: [.date])

                Picker("종류", selection: $isDeposit) {
                    Text("입금").tag(true)
                    Text("출금").tag(false)
                }
                .pickerStyle(.segmented)

                Picker("통장", selection: $accountId) {
                    ForEach(viewModel.accounts) { Text($0.name).tag($0.id) }
                }

                transferRows
            }
        } header: {
            Text("거래 정보")
        } footer: {
            if transaction.isFromStatement {
                Text("거래내역서에서 불러온 거래예요. 금액·일시·통장은 통장에 찍힌 기록이라 고칠 수 없어요. 통장 사이 이체인지는 통장이 말해 주지 않아서 여기서 정해요.")
            }
        }
    }

    /// 어느 통장의 거래인가. **내부 이체면 방향까지 보여준다** ("농협 → 모임").
    ///
    /// `amount` 는 `accountId` 기준이라, 음수면 거기서 나가 상대 통장으로 들어간 것이다.
    private var accountLabel: String {
        guard let counter = transaction.counterAccountId else {
            return accountName(transaction.accountId)
        }
        return transaction.amount < 0
            ? "\(accountName(transaction.accountId)) → \(accountName(counter))"
            : "\(accountName(counter)) → \(accountName(transaction.accountId))"
    }

    /// 내부 이체 표시. **한 줄이 양쪽 통장을 안다** — 두 줄로 적으면 그 둘이 같은
    /// 사건이라는 걸 따로 짝지어야 하고, 짝이 깨지면 조용히 틀어진다.
    @ViewBuilder
    private var transferRows: some View {
        let others = viewModel.accounts.filter { $0.id != accountId }
        if let fallback = others.first {
            Toggle("통장 사이 이체", isOn: Binding(
                get: { counterAccountId != nil },
                set: { counterAccountId = $0 ? fallback.id : nil }
            ))

            if counterAccountId != nil {
                Picker("상대 통장", selection: Binding(
                    get: { counterAccountId ?? fallback.id },
                    set: { counterAccountId = $0 }
                )) {
                    ForEach(others) { Text($0.name).tag($0.id) }
                }
            }
        }
    }

    // MARK: - 분할

    private var splitSection: some View {
        Section {
            if splitDrafts.isEmpty {
                Button {
                    // 전액짜리 첫 항목을 만들고 바로 편집 시트를 연다.
                    // 카테고리·금액만 물려준다. 거래의 **메모**를 조각의 **적요**로
                    // 옮기면 성격이 다른 두 칸이 섞인다 (메모는 거래에 남는다).
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
                                    Text(draft.description)
                                        .rowSubtext()
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
                .onDelete { indexSet in
                    splitDrafts.remove(atOffsets: indexSet)
                }

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
                    // 맞으면 완료색, 아니면 아직 손봐야 한다는 뜻이라 주의색이다.
                    // 빨강을 쓰지 않는다 — 빨강은 되돌릴 수 없는 것에만 남긴다.
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

    private func save() {
        // 분할이 있으면 합이 거래액과 일치해야 한다.
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
                // 자기 자신과의 이체는 이체가 아니다 (DB 에도 check 가 걸려 있다).
                // 통장을 바꾸면 상대 통장이 같아질 수 있어서 여기서 한 번 턴다.
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
