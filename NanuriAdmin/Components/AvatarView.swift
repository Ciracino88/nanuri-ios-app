import SwiftUI
import Combine

struct AvatarView: View {
    let url: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let url, let parsed = URL(string: url) {
                CachedAvatarImage(url: parsed)
            } else {
                AvatarView.defaultIcon
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    static var defaultIcon: some View {
        Image(systemName: "person.circle.fill")
            .resizable()
            .foregroundColor(Color(.systemGray3))
    }
}

/// 한 번 받은 이미지를 전역 캐시에 저장하고, 재렌더에도 상태가 유지되는 로더.
/// 기본 AsyncImage는 뷰가 재생성될 때마다 다운로드를 다시 시작해,
/// Realtime 등으로 부모가 자주 재렌더되면 사진이 표시되지 않는 문제가 있다.
private final class AvatarImageLoader: ObservableObject {
    @Published var image: UIImage?

    private static let cache = NSCache<NSURL, UIImage>()
    private var loadedURL: URL?

    func load(_ url: URL) {
        // 이미 같은 URL을 로드했으면 아무것도 하지 않는다.
        if loadedURL == url, image != nil { return }
        loadedURL = url

        if let cached = AvatarImageLoader.cache.object(forKey: url as NSURL) {
            image = cached
            return
        }

        Task { [weak self] in
            guard
                let (data, _) = try? await URLSession.shared.data(from: url),
                let downloaded = UIImage(data: data)
            else { return }
            AvatarImageLoader.cache.setObject(downloaded, forKey: url as NSURL)
            await MainActor.run { self?.image = downloaded }
        }
    }
}

private struct CachedAvatarImage: View {
    let url: URL
    @StateObject private var loader = AvatarImageLoader()

    var body: some View {
        Group {
            if let image = loader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                AvatarView.defaultIcon
            }
        }
        .onAppear { loader.load(url) }
        .onChange(of: url) { newURL in loader.load(newURL) }
    }
}
