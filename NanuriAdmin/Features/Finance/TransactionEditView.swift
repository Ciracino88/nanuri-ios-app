import SwiftUI
import PhotosUI

struct TransactionEditView: View {
    let transaction: BankTransaction
    let suggestions: [String]
    @ObservedObject var viewModel: FinanceViewModel

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
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var previewReceipt: ReceiptPreview?
    @State private var isSaving = false
    @State private var splitDrafts: [SplitDraft]
    @State private var showSplitMismatch = false
    @State private var activeSplit: SplitDraft?
    @Environment(\.dismiss) var dismiss

    init(transaction: BankTransaction, suggestions: [String], viewModel: FinanceViewModel) {
        self.transaction = transaction
        self.suggestions = suggestions
        self.viewModel = viewModel
        _category = State(initialValue: transaction.category ?? "")
        _descriptionText = State(initialValue: transaction.description ?? "")
        _amountText = State(initialValue: String(abs(transaction.amount)))
        _isDeposit = State(initialValue: transaction.isDeposit)
        _datetime = State(initialValue: transaction.datetime)
        _accountId = State(initialValue: transaction.accountId)
        _counterAccountId = State(initialValue: transaction.counterAccountId)
        _keptUrls = State(initialValue: transaction.receipts)
        _pendingImages = State(initialValue: [])
        _splitDrafts = State(initialValue: viewModel.splits(for: transaction.id).map {
            SplitDraft(category: $0.category ?? "", amount: $0.amount, description: $0.description ?? "")
        })
    }

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
        transaction.isFromStatement || editedMagnitude > 0
    }
    private var splitSum: Int { splitDrafts.reduce(0) { $0 + $1.amount } }
    private var splitRemaining: Int { txMagnitude - splitSum }

    // MARK: - 거래 정보

    /// **거래내역서에서 온 거래는 금액·일시·통장이 잠긴다.** 그 셋은 통장에 찍힌
    /// 기록이라 고치면 통장과 어긋나 대조가 뜻을 잃는다.
    ///
    /// **적요는 둘 다 고칠 수 있다.** 통장이 주는 적요는 예금주나 가맹점 이름
    /// (`이충성` · `우성볼링장` · `ATM현금`)이라 장부에 그대로 적을 수 없다.
    /// 장부에 적히는 건 "아침식사" · "볼링 게임 16명" 같은 **뜻**이다.
    private var infoSection: some View {
        Section {
            TextField("적요 (예: 아침식사, 8월 헌금)", text: $descriptionText)

            if transaction.isFromStatement {
                LabeledContent("금액", value: "\(transaction.amount.formatted())원")
                LabeledContent("일시", value: transaction.datetime.koreanDateTimeString)
                LabeledContent("통장", value: accountLabel)
                // **이체 표시는 잠기지 않는다.** 은행은 이게 통장 사이 이체인지
                // 말해 주지 않는다 — 적요를 보고 사람이 정하는 회계 판단이다.
                transferRows
            } else {
                DatePicker("일시", selection: $datetime, displayedComponents: [.date])

                Picker("종류", selection: $isDeposit) {
                    Text("입금").tag(true)
                    Text("출금").tag(false)
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("금액")
                    Spacer()
                    TextField("0", text: $amountText)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                    Text("원").foregroundColor(DS.Ink.secondary)
                }

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
                    Text("이 거래 삭제")
                    Spacer()
                }
            }
            .disabled(isSaving)
        } footer: {
            Text("분할 항목과 영수증도 같이 지워져요. 되돌릴 수 없어요.")
        }
    }

    var body: some View {
        NavigationView {
            Form {
                infoSection
                // 메모 칸이 여기 있었는데 **어디에도 안 보이는 값**이었다 —
                // 목록 줄도 보고서도 분석 화면도 안 읽었다. 적을 말이 있으면
                // 분할 조각의 적요에 적는다. 그건 실제로 장부에 남는다.
                Section("분류") {
                    TextField("카테고리 (예: 회비, 후원금, 행사비)", text: $category)
                    CategorySuggestionChips(suggestions: suggestions, selected: $category)
                }
                splitSection
                receiptSection
                deleteSection
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

    private var receiptSection: some View {
        Section(receiptCount == 0 ? "영수증" : "영수증 (\(receiptCount)장)") {
            if receiptCount > 0 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
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
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

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
