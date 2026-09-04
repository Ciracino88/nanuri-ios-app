import SwiftUI
import PhotosUI

struct TransactionEditView: View {
    /// 탭한 **장부 줄.** 조각(`row.split != nil`)일 수도, 분할 없는 거래 전체일 수도
    /// 있다. 이 하나가 화면의 성격을 가른다.
    let row: LedgerRow
    let suggestions: [String]
    @ObservedObject var viewModel: FinanceViewModel

    /// 편의 별칭. 아래 코드가 거래를 자주 참조한다.
    private var transaction: BankTransaction { row.transaction }
    /// 눌린 조각. 없으면 거래 전체를 누른 것이다.
    private var split: TransactionSplit? { row.split }

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
    /// 영수증을 보고·더하는 시트. 레퍼런스처럼 편집창에는 버튼 하나만 두고,
    /// 실제 썸네일·추가·미리보기는 이 시트가 맡는다.
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
        // **조각을 눌렀으면 그 조각의 적요·분류를, 거래를 눌렀으면 거래의 것을 편집한다.**
        _category = State(initialValue: (row.split?.category ?? tx.category) ?? "")
        _descriptionText = State(initialValue: (row.split?.description ?? tx.description) ?? "")
        _amountText = State(initialValue: String(abs(tx.amount)))
        _isDeposit = State(initialValue: tx.isDeposit)
        _datetime = State(initialValue: tx.datetime)
        _accountId = State(initialValue: tx.accountId)
        _counterAccountId = State(initialValue: tx.counterAccountId)
        _keptUrls = State(initialValue: tx.receipts)
        _pendingImages = State(initialValue: [])
        // **원본 조각 id 를 지켜 담는다** — 눌린 조각을 이 안에서 되찾아 고치려면
        // 필요하다. 저장은 어차피 조각을 다시 만들어 넣으므로 이 id 는 화면용이다.
        _splitDrafts = State(initialValue: viewModel.splits(for: tx.id).map {
            SplitDraft(id: $0.id, category: $0.category ?? "", amount: $0.amount, description: $0.description ?? "")
        })
    }

    /// 조각을 눌렀나. 화면이 "조각 상세" 인지 "거래 편집" 인지 가른다.
    private var isPieceMode: Bool { split != nil }
    /// 부모 출금이 몇 조각인가. 2 이상이면 히어로(조각)와 총액이 달라 맥락이 필요하다.
    private var pieceCount: Int { splitDrafts.count }
    /// 금액을 이 화면에서 고칠 수 있나 — **분할 없는 손입력 거래일 때만.**
    private var isEditableAmount: Bool { !isPieceMode && !transaction.isFromStatement }
    /// 히어로에 세울 부호 붙은 금액. 조각이면 조각 금액, 아니면 거래 금액.
    private var heroSignedAmount: Int { isPieceMode ? row.amount : transaction.amount }

    private func accountName(_ id: UUID) -> String {
        viewModel.accounts.first { $0.id == id }?.name ?? "알 수 없음"
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
        // 조각 화면은 텍스트만 고치므로 늘 저장 가능. 거래 화면은 손입력이면 금액이 있어야.
        isPieceMode || transaction.isFromStatement || editedMagnitude > 0
    }
    private var splitSum: Int { splitDrafts.reduce(0) { $0 + $1.amount } }
    private var splitRemaining: Int { txMagnitude - splitSum }

    // MARK: - 금액 히어로

    /// **첫 섹션은 금액 하나를 크게 세운다** (토스 결제 결과 화면의 문법).
    /// 장부를 열어 가장 먼저 확인하는 건 결국 "얼마" 라, 그 수를 가운데 큰 글씨로
    /// 홀로 세우고 나머지 정보는 아래 섹션이 받는다.
    ///
    /// **부호는 색과 캡션이 대신 말한다.** 레퍼런스처럼 수는 절댓값으로 깔끔하게
    /// 두고(마이너스 기호를 큰 글씨에 얹지 않는다), 입금·출금·이체는 색과 그 아래
    /// 한 단어가 말한다. 손입력 거래는 이 수가 바로 **고치는 칸**이다.
    private var amountHeroSection: some View {
        Section {
            VStack(spacing: DS.Spacing.tight) {
                if !isEditableAmount {
                    Text("\(abs(heroSignedAmount).formatted())원")
                        .typeStyle(DS.Typo.display2)
                        .tabularAmount()
                        .foregroundColor(heroAmountColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: DS.Spacing.tight) {
                        TextField("0", text: $amountText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .typeStyle(DS.Typo.display2)
                            .tabularAmount()
                            .foregroundColor(heroAmountColor)
                            .fixedSize()
                        Text("원")
                            .typeStyle(DS.Typo.h3)
                            .foregroundColor(heroAmountColor)
                    }
                }
                Text(heroCaption)
                    .typeStyle(DS.Typo.body2)
                    .foregroundColor(DS.Ink.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Spacing.medium)
            // 카드 없이 화면 배경 위에 그대로 세운다 — 레퍼런스의 흰 바탕처럼.
            .listRowBackground(Color.clear)
        }
    }

    /// 히어로 금액의 색. 목록 줄(`LedgerRowView.amountColor`)과 같은 규칙이다 —
    /// 입금 파랑 · 출금 검정 · 통장 사이 이체 회색.
    private var heroAmountColor: Color {
        if transaction.isInternalTransfer { return DS.Ink.tertiary }
        // 조각·거래내역서 거래는 통장 값(`transaction.isDeposit`)이 정본, 손입력은 입력 중인 값.
        let deposit = (isPieceMode || transaction.isFromStatement) ? transaction.isDeposit : isDeposit
        return deposit ? DS.Palette.deposit : DS.Palette.withdrawal
    }

    /// 금액 아래 한 단어. 부호 대신 성격을 말한다.
    private var heroCaption: String {
        if transaction.isInternalTransfer { return "통장 사이 이체" }
        let deposit = (isPieceMode || transaction.isFromStatement) ? transaction.isDeposit : isDeposit
        return deposit ? "입금" : "출금"
    }

    // MARK: - 조각 상세

    /// 눌린 **조각**의 적요·분류. 이것만 이 화면에서 고친다.
    ///
    /// 매칭 거래의 조각은 금액·통장이 청구·통장에서 온 정본이라 여기서 못 고치고,
    /// 사람이 손볼 여지가 있는 건 **적요 문구와 분류** 뿐이다.
    private var pieceInfoSection: some View {
        Section {
            TextField("적요 (예: 파라솔 대여비)", text: $descriptionText)
            TextField("분류 (예: 행사비, 회비)", text: $category)
            CategorySuggestionChips(suggestions: suggestions, selected: $category)
        } header: {
            Text("내역")
        }
    }

    /// **이 조각이 속한 출금.** 총액·통장·일시는 조각의 것이 아니라 거래 전체의
    /// 것이라, 조각 화면에서는 읽기 전용 맥락으로만 둔다.
    ///
    /// 여러 조각이면 "이 6만원은 45.8만원 출금의 일부" 를 총액으로 말한다. 한 조각뿐이면
    /// 총액이 곧 히어로라 다시 적지 않는다.
    @ViewBuilder
    private var parentContextSection: some View {
        Section {
            if pieceCount > 1 {
                LabeledContent("전체 출금", value: "\(abs(transaction.amount).formatted())원")
            }
            LabeledContent("통장", value: accountLabel)
            LabeledContent("일시", value: transaction.datetime.koreanDateTimeString)
        } header: {
            Text("이 내역이 속한 출금")
        } footer: {
            if pieceCount > 1 {
                Text("이 출금 한 건이 \(pieceCount)개 내역으로 나뉘어요. 금액·통장·일시는 출금 전체의 값이라 여기서 고치지 않아요.")
            }
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

    /// **되돌릴 수 없는 것이라 빨강이고, 확인을 한 번 받는다.**
    private var deleteSection: some View {
        Section {
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                HStack {
                    Spacer()
                    // 조각을 눌러도 삭제는 **출금 전체**에 걸린다 — 조각 하나만
                    // 지우는 건 없다(합이 거래액과 어긋난다).
                    Text(isPieceMode && pieceCount > 1 ? "이 출금 전체 삭제" : "이 거래 삭제")
                    Spacer()
                }
            }
            .disabled(isSaving)
        } footer: {
            Text(isPieceMode && pieceCount > 1
                 ? "이 출금의 \(pieceCount)개 내역과 영수증이 모두 지워져요. 되돌릴 수 없어요."
                 : "분할 항목과 영수증도 같이 지워져요. 되돌릴 수 없어요.")
        }
    }

    var body: some View {
        NavigationView {
            Form {
                amountHeroSection
                if isPieceMode {
                    // **조각을 눌렀다.** 이 조각만 보여주고, 총액·통장·일시는 "속한
                    // 출금" 으로 밀어 둔다. 형제 조각은 다시 나열하지 않는다 —
                    // 목록이 이미 줄마다 펼쳐 놨다.
                    pieceInfoSection
                    parentContextSection
                } else {
                    // **분할 없는 거래 전체.** 지금까지의 편집 화면 그대로다.
                    detailsSection
                    // 메모 칸이 여기 있었는데 **어디에도 안 보이는 값**이었다 —
                    // 목록 줄도 보고서도 분석 화면도 안 읽었다. 적을 말이 있으면
                    // 분할 조각의 적요에 적는다. 그건 실제로 장부에 남는다.
                    Section("분류") {
                        TextField("카테고리 (예: 회비, 후원금, 행사비)", text: $category)
                        CategorySuggestionChips(suggestions: suggestions, selected: $category)
                    }
                    splitSection
                }
                receiptSection
                deleteSection
            }
            .navigationTitle(isPieceMode ? "내역 편집" : "거래 편집")
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

    private func save() {
        if isPieceMode { savePiece(); return }
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

    /// 조각 화면의 저장. **거래 필드는 그대로 두고**(금액·통장·일시·거래 분류·은행
    /// 적요) 눌린 조각의 적요·분류만 바꿔 넣는다. 저장 자체는 같은
    /// `saveTransactionEdits` 를 타므로 형제 조각은 그대로 다시 만들어진다.
    private func savePiece() {
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
                                Text(draft.category.isEmpty ? "미분류" : draft.category)
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

    /// 영수증은 편집창에 **버튼 하나**로만 둔다 (레퍼런스 문법). 있으면 "보기",
    /// 없으면 "추가" — 어느 쪽이든 같은 관리 시트(`ReceiptManagerView`)를 연다.
    /// 썸네일·추가·미리보기가 본문을 차지하면 금액·정보가 아래로 밀린다.
    private var receiptSection: some View {
        Section {
            Button {
                showReceiptManager = true
            } label: {
                if receiptCount > 0 {
                    Label("영수증 보기 (\(receiptCount)장)", systemImage: "paperclip")
                } else {
                    Label("영수증 추가", systemImage: "plus")
                }
            }
            .disabled(isSaving)
        } header: {
            Text("영수증")
        }
    }
}

/// 아직 업로드하지 않은 로컬 이미지 (편집 중 임시 보관).
struct PendingImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// 편집 중인 분할 항목 (저장 시 finance_splits로 반영).
///
/// `description` 이 **이 조각의 적요**다 — 보고서 상세 명세의 적요 칸에 그대로 찍힌다.
/// 거래에는 이런 자유 입력 칸이 없다 — 있었지만 어디에도 안 보여서 걷어냈다.
struct SplitDraft: Identifiable {
    var id = UUID()
    var category: String
    var amount: Int
    var description: String
}

/// 분할 항목 하나를 입력·편집하는 바텀 시트.
struct SplitEditSheet: View {
    let initial: SplitDraft
    let isNew: Bool
    let suggestions: [String]
    let txMagnitude: Int
    let otherSum: Int
    let onSave: (SplitDraft) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) var dismiss
    @State private var category: String
    @State private var amount: Int
    @State private var itemDescription: String

    init(initial: SplitDraft, isNew: Bool, suggestions: [String], txMagnitude: Int, otherSum: Int,
         onSave: @escaping (SplitDraft) -> Void, onDelete: @escaping () -> Void) {
        self.initial = initial
        self.isNew = isNew
        self.suggestions = suggestions
        self.txMagnitude = txMagnitude
        self.otherSum = otherSum
        self.onSave = onSave
        self.onDelete = onDelete
        _category = State(initialValue: initial.category)
        _amount = State(initialValue: initial.amount)
        _itemDescription = State(initialValue: initial.description)
    }

    private var remainingForFull: Int { max(txMagnitude - otherSum, 0) }

    var body: some View {
        NavigationView {
            Form {
                Section("카테고리") {
                    TextField("예: 회비, 식대, 시상품", text: $category)
                    CategorySuggestionChips(suggestions: suggestions, selected: $category)
                }
                Section("금액") {
                    TextField("금액", value: $amount, format: .number)
                        .keyboardType(.numberPad)
                    HStack {
                        Text("거래액 \(txMagnitude.formatted())원 · 다른 항목 \(otherSum.formatted())원")
                            .typeStyle(DS.Typo.body3)
                            .tabularAmount()
                            .foregroundColor(DS.Ink.secondary)
                        Spacer()
                        Button("남은 전액") { amount = remainingForFull }
                            .typeStyle(DS.Typo.labelS)
                            .foregroundColor(DS.Ink.brand)
                    }
                }
                // 이 칸이 보고서의 적요다 — 묶어 보낸 출금을 쪼갤 때 조각마다
                // 받는 사람이 다르므로, 여기가 비면 그 줄은 카테고리로만 불린다.
                Section("적요") {
                    TextField("예: 8월 수련회 식대 (홍길동)", text: $itemDescription, axis: .vertical)
                        .lineLimit(2...4)
                }
                if !isNew {
                    Section {
                        Button(role: .destructive) {
                            onDelete()
                            dismiss()
                        } label: {
                            Label("이 항목 삭제", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "항목 추가" : "항목 편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("취소") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(isNew ? "추가" : "완료") {
                        onSave(SplitDraft(id: initial.id, category: category,
                                          amount: amount, description: itemDescription))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

/// 영수증 출처 (업로드된 원격 URL 또는 아직 업로드 안 한 로컬 이미지).
/// 영수증을 보고·더하고·지우는 시트.
///
/// 예전에는 편집창 본문에 썸네일과 추가 버튼이 그대로 있었다. 레퍼런스처럼
/// 편집창에는 버튼 하나만 두고, 실제 관리는 여기로 옮겼다. 영수증은 자주 열지
/// 않는 자리라 한 단계 안이 알맞고, 본문은 금액·정보에 내준다.
///
/// **거래는 아직 저장하지 않는다.** 여기서 더한 이미지는 `pendingImages` 로,
/// 남긴 것은 `keptUrls` 로 부모에 그대로 반영되고, 실제 업로드·삭제는 편집창의
/// "저장" 이 `saveTransactionEdits` 로 한 번에 확정한다.
struct ReceiptManagerView: View {
    @Binding var keptUrls: [String]
    @Binding var pendingImages: [PendingImage]
    let isSaving: Bool

    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var previewReceipt: ReceiptPreview?

    private var receiptCount: Int { keptUrls.count + pendingImages.count }

    var body: some View {
        NavigationView {
            Form {
                if receiptCount > 0 {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DS.Spacing.small) {
                                ForEach(keptUrls, id: \.self) { urlString in
                                    thumbnailFrame(
                                        onTap: { previewReceipt = ReceiptPreview(source: .remote(urlString)) },
                                        onDelete: { keptUrls.removeAll { $0 == urlString } }
                                    ) {
                                        RemoteImage(
                                            url: URL(string: urlString),
                                            maxDimension: DS.Size.thumbnail
                                        ) {
                                            loadingTile
                                        } failure: {
                                            fallbackTile
                                        }
                                        .scaledToFill()
                                    }
                                }
                                ForEach(pendingImages) { pending in
                                    thumbnailFrame(
                                        onTap: { previewReceipt = ReceiptPreview(source: .local(pending.image)) },
                                        onDelete: { pendingImages.removeAll { $0.id == pending.id } }
                                    ) {
                                        Image(uiImage: pending.image).resizable().scaledToFill()
                                    }
                                }
                            }
                            .padding(.vertical, DS.Spacing.tight)
                        }
                        .listRowInsets(EdgeInsets(top: DS.Spacing.small, leading: DS.Spacing.s4,
                                                  bottom: DS.Spacing.small, trailing: DS.Spacing.s4))
                    } footer: {
                        Text("영수증을 눌러 크게 봐요. 오른쪽 위 ✕ 로 지워요. 저장을 눌러야 반영돼요.")
                    }
                }

                Section {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("앨범에서 추가", systemImage: "photo")
                    }
                    .disabled(isSaving)
                    Button {
                        showCamera = true
                    } label: {
                        Label("카메라로 촬영", systemImage: "camera")
                    }
                    .disabled(isSaving)
                }
            }
            .navigationTitle(receiptCount == 0 ? "영수증" : "영수증 (\(receiptCount)장)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("완료") { dismiss() }.fontWeight(.semibold)
                }
            }
            .onChange(of: photoItem) { item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        pendingImages.append(PendingImage(image: image))
                    }
                    photoItem = nil
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraPicker { image in
                    pendingImages.append(PendingImage(image: image))
                }
                .ignoresSafeArea()
            }
            .fullScreenCover(item: $previewReceipt) { preview in
                ReceiptViewerView(source: preview.source)
            }
        }
    }

    private var fallbackTile: some View {
        Image(systemName: "exclamationmark.triangle")
            .foregroundColor(DS.Ink.placeholder)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Surface.secondary)
    }

    private var loadingTile: some View {
        ProgressView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(DS.Surface.secondary)
    }

    private func thumbnailFrame<Content: View>(
        onTap: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let size = DS.Size.thumbnail
        return ZStack(alignment: .topTrailing) {
            content()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.l))
                .contentShape(RoundedRectangle(cornerRadius: DS.Radius.l))
                .onTapGesture(perform: onTap)

            Button(action: onDelete) {
                Image(systemName: "xmark.circle.fill")
                    .font(DS.Icon.font(DS.Icon.action))
                    .foregroundStyle(.white, .black.opacity(0.55))
            }
            .buttonStyle(.plain)
            .padding(DS.Spacing.tight)
            .disabled(isSaving)
        }
        .frame(width: size, height: size)
    }
}

enum ReceiptSource {
    case remote(String)
    case local(UIImage)
}

/// 전체화면 영수증 뷰어에 넘기기 위한 래퍼.
struct ReceiptPreview: Identifiable {
    let id = UUID()
    let source: ReceiptSource
}

/// 영수증 전체화면 뷰어 (핀치 줌 / 더블탭 줌 / 닫기).
struct ReceiptViewerView: View {
    let source: ReceiptSource
    @Environment(\.dismiss) var dismiss
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            zoomableImage
            closeButton
        }
    }

    @ViewBuilder
    private var zoomableImage: some View {
        switch source {
        case .remote(let url):
            // 손가락으로 확대하는 화면이라 줄이지 않는다 (`maxDimension` 없음).
            // 줄여 두면 확대했을 때 뭉갠 게 그대로 보인다.
            zoomable(
                RemoteImage(url: URL(string: url)) {
                    ProgressView().tint(.white)
                } failure: {
                    Text("영수증을 불러오지 못했어요")
                        .typeStyle(DS.Typo.body2)
                        .foregroundColor(.white)
                }
            )
        case .local(let image):
            zoomable(Image(uiImage: image).resizable())
        }
    }

    private func zoomable<Content: View>(_ content: Content) -> some View {
        content.scaledToFit()
            .scaleEffect(scale)
            .gesture(
                MagnificationGesture()
                    .onChanged { value in scale = max(1, lastScale * value) }
                    .onEnded { _ in lastScale = scale }
            )
            .onTapGesture(count: 2) {
                withAnimation {
                    scale = scale > 1 ? 1 : 2.5
                    lastScale = scale
                }
            }
    }

    private var closeButton: some View {
        VStack {
            HStack {
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(DS.Icon.font(DS.Icon.feature))
                        .foregroundStyle(.white, .white.opacity(0.3))
                }
                .padding()
            }
            Spacer()
        }
    }
}

/// UIImagePickerController 기반 카메라 촬영 래퍼.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onImage(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
