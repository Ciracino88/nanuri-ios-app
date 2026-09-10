import SwiftUI
import PhotosUI

/// 아직 업로드하지 않은 로컬 이미지 (편집 중 임시 보관).
struct PendingImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

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
        VStack(spacing: 0) {
            // 타이틀이 있어 시트가 아니라 풀스크린이다 (DESIGN.md §1). 변경은 바인딩에
            // 바로 반영되고, 닫으면 부모가 저장한다.
            AdminHeaderView(
                showsNotifications: false,
                center: { Text(receiptCount == 0 ? "영수증" : "영수증 (\(receiptCount)장)").headerTitle() },
                leading: { HeaderBackButton(label: "완료") { dismiss() } },
                trailing: { EmptyView() }
            )
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
            .scrollContentBackground(.hidden)
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
        .screenBackground(DS.Surface.page)
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
