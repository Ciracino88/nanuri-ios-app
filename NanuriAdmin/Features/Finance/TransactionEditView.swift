import SwiftUI
import PhotosUI

struct TransactionEditView: View {
    let transaction: BankTransaction
    let suggestions: [String]
    @ObservedObject var viewModel: FinanceViewModel

    @State private var category: String
    @State private var memo: String
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
        _memo = State(initialValue: transaction.memo ?? "")
        _keptUrls = State(initialValue: transaction.receipts)
        _pendingImages = State(initialValue: [])
        _splitDrafts = State(initialValue: viewModel.splits(for: transaction.id).map {
            SplitDraft(category: $0.category ?? "", amount: $0.amount, memo: $0.memo ?? "")
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
    private var txMagnitude: Int { abs(transaction.amount) }
    private var splitSum: Int { splitDrafts.reduce(0) { $0 + $1.amount } }
    private var splitRemaining: Int { txMagnitude - splitSum }

    var body: some View {
        NavigationView {
            Form {
                Section("거래 정보") {
                    LabeledContent("내용", value: transaction.description ?? "-")
                    LabeledContent("금액", value: "\(transaction.amount.formatted())원")
                    LabeledContent("일시", value: transaction.datetime.koreanDateTimeString)
                    // 예전에는 "거래 후 잔액" 이 여기 있었다. 통장이 둘이 되면서 그 값이
                    // 어느 통장의 잔액도 아니게 되어 없앴다. 대신 **어느 통장인지**를
                    // 보여준다 — 한 건을 들여다볼 때 정작 알아야 하는 건 그쪽이다.
                    LabeledContent("통장", value: accountLabel)
                }
                Section("분류") {
                    TextField("카테고리 (예: 회비, 후원금, 행사비)", text: $category)
                    CategorySuggestionChips(suggestions: suggestions, selected: $category)
                    TextField("메모", text: $memo, axis: .vertical)
                        .lineLimit(3...6)
                }
                splitSection
                receiptSection
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
                        Button("저장") { save() }.fontWeight(.semibold)
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
                category: category.isEmpty ? nil : category,
                memo: memo.isEmpty ? nil : memo,
                keptUrls: keptUrls,
                newImages: pendingImages.map(\.image),
                originalUrls: transaction.receipts,
                splits: splitDrafts.map {
                    (category: $0.category.isEmpty ? nil : $0.category,
                     amount: $0.amount,
                     memo: $0.memo.isEmpty ? nil : $0.memo)
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
                    let first = SplitDraft(category: category, amount: txMagnitude, memo: memo)
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
                                if !draft.memo.isEmpty {
                                    Text(draft.memo)
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
                    activeSplit = SplitDraft(category: "", amount: max(splitRemaining, 0), memo: "")
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
struct SplitDraft: Identifiable {
    var id = UUID()
    var category: String
    var amount: Int
    var memo: String
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
    @State private var memo: String

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
        _memo = State(initialValue: initial.memo)
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
                Section("내용") {
                    TextField("메모", text: $memo, axis: .vertical)
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
                        onSave(SplitDraft(id: initial.id, category: category, amount: amount, memo: memo))
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
