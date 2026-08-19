import SwiftUI
import ImageIO
import CryptoKit

/// 줄여서 디코드해 둔 이미지들. **뷰가 동기로 들여다볼 수 있어야 해서** actor 밖에 둔다
/// (`NSCache` 는 스레드 안전하다). 이게 없으면 시트를 다시 열 때마다 한 프레임이 빈다.
private let imageMemoryCache: NSCache<NSString, UIImage> = {
    let cache = NSCache<NSString, UIImage>()
    // 비트맵 기준 대략 64MB. 영수증 한 장이 화면 크기로 줄이면 5MB 안쪽이다.
    cache.totalCostLimit = 64 * 1024 * 1024
    return cache
}()

/// 원격 이미지를 세 겹으로 찾는다 — **메모리 → 디스크 → 네트워크**.
///
/// 영수증 URL 은 올릴 때마다 새로 만들어지고 **같은 URL 의 내용은 절대 안 바뀐다.**
/// 그래서 URL 을 키로 계속 들고 있어도 안전하다. 서버가 `Cache-Control` 을 안 줘도
/// 우리 쪽에서 다시 안 받는다는 뜻이다.
actor RemoteImageStore {
    static let shared = RemoteImageStore()

    private let directory: URL
    /// 같은 이미지를 두 곳에서 동시에 부르면 요청도 하나로 합친다.
    private var inFlight: [String: Task<UIImage?, Never>] = [:]
    private var didPrune = false

    init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        directory = caches.appendingPathComponent("RemoteImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// 메모리에 있으면 그 자리에서 돌려준다. 뷰가 첫 프레임에 부른다.
    nonisolated static func cached(_ url: URL, maxPixel: Int?) -> UIImage? {
        imageMemoryCache.object(forKey: cacheKey(url, maxPixel) as NSString)
    }

    func image(for url: URL, maxPixel: Int?) async -> UIImage? {
        let key = Self.cacheKey(url, maxPixel)
        if let hit = imageMemoryCache.object(forKey: key as NSString) { return hit }
        if let running = inFlight[key] { return await running.value }

        pruneOnce()

        let file = directory.appendingPathComponent(Self.fileName(for: key))
        let task = Task<UIImage?, Never> { [directory] in
            // 디스크에는 **줄여 놓은 것**이 들어 있다. 원본을 두면 켤 때마다 다시 줄여야 한다.
            if let data = try? Data(contentsOf: file),
               let image = Self.decode(data, maxPixel: maxPixel) {
                return image
            }
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse).map({ (200...299).contains($0.statusCode) }) ?? true,
                  let image = Self.decode(data, maxPixel: maxPixel)
            else { return nil }

            if let jpeg = image.jpegData(compressionQuality: 0.9) {
                try? jpeg.write(to: directory.appendingPathComponent(Self.fileName(for: key)), options: .atomic)
            }
            return image
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil

        if let image {
            imageMemoryCache.setObject(image, forKey: key as NSString, cost: Self.cost(of: image))
        }
        return image
    }

    /// 원본을 통째로 비트맵으로 펴지 않고 **그릴 크기만큼만** 디코드한다 (다운샘플링).
    ///
    /// 폼이 올리는 영수증은 긴 변 1600px 다. 파일은 300KB 남짓이지만 통째로 디코드하면
    /// 비트맵이 7MB 를 넘는다. 90pt 썸네일에 실제로 필요한 건 그 100분의 1이다.
    /// `maxPixel` 이 `nil` 이면 원본 그대로 — 확대해서 보는 화면에만 쓴다.
    nonisolated static func decode(_ data: Data, maxPixel: Int?) -> UIImage? {
        guard let maxPixel else { return UIImage(data: data) }
        guard let source = CGImageSourceCreateWithData(
            data as CFData,
            [kCGImageSourceShouldCache: false] as CFDictionary
        ) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            // EXIF 회전을 반영한다. 빼면 세로로 찍은 영수증이 눕는다.
            kCGImageSourceCreateThumbnailWithTransform: true,
            // 여기서 디코드까지 끝낸다. 미루면 첫 프레임을 그릴 때 끊긴다.
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - 캐시 살림

    private static func cacheKey(_ url: URL, _ maxPixel: Int?) -> String {
        "\(url.absoluteString)|\(maxPixel.map(String.init) ?? "orig")"
    }

    private static func fileName(for key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".jpg"
    }

    private static func cost(of image: UIImage) -> Int {
        guard let cg = image.cgImage else { return 0 }
        return cg.bytesPerRow * cg.height
    }

    /// 켠 뒤 한 번만, 30일 넘게 안 쓴 파일을 지운다.
    /// 지워진 청구서의 영수증까지 디스크에 남으면 캐시가 끝없이 는다.
    private func pruneOnce() {
        guard !didPrune else { return }
        didPrune = true

        let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, modified < cutoff {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}

// MARK: - 뷰

/// `AsyncImage` 를 대신하는 뷰. 캐시하고, 줄여서 디코드한다.
///
/// 기본 `AsyncImage` 는 세 가지가 아쉬웠다.
/// 1. 받은 걸 안 들고 있어서 **시트를 닫았다 열면 다시 받는다.**
/// 2. 부모가 재렌더되면 **처음부터 다시 시작한다.** Realtime 으로 목록이 자주
///    갱신되는 화면에서 사진이 아예 안 뜨던 원인이 이거였다 (`AvatarView` 참고).
/// 3. 1600px 원본을 **통째로 디코드한다.** 90pt 썸네일에도 7MB 짜리 비트맵을 편다.
///
/// 쓰는 쪽은 `AsyncImage` 와 거의 같다. 다른 건 `maxDimension` 하나뿐이다.
///
/// `Phase` 를 뷰 안에 중첩하지 않고 밖에 두는 건 취향이 아니다. 안에 두면 타입이
/// `CachedAsyncImage<Content>.Phase` 가 되는데, 그 `Content` 를 클로저 본문에서
/// 추론해야 해서 순환이 생긴다 (`generic parameter 'Content' could not be inferred`).
/// SwiftUI 의 `AsyncImagePhase` 가 밖에 나와 있는 이유도 같다.
enum CachedImagePhase {
    case empty
    case success(Image)
    case failure
}

struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    /// 그릴 최대 변(pt). 화면 배율을 곱한 픽셀로 줄여서 디코드한다.
    /// `nil` 이면 원본 그대로 — 손가락으로 확대하는 화면에만 준다.
    let maxDimension: CGFloat?
    let content: (CachedImagePhase) -> Content

    init(
        url: URL?,
        maxDimension: CGFloat? = nil,
        @ViewBuilder content: @escaping (CachedImagePhase) -> Content
    ) {
        self.url = url
        self.maxDimension = maxDimension
        self.content = content
    }

    @Environment(\.displayScale) private var displayScale
    @State private var loaded: UIImage?
    @State private var failed = false

    var body: some View {
        content(phase)
            .task(id: taskID) { await load() }
    }

    private var maxPixel: Int? {
        maxDimension.map { Int($0 * displayScale) }
    }

    private var taskID: String {
        "\(url?.absoluteString ?? "")|\(maxPixel.map(String.init) ?? "orig")"
    }

    private var phase: CachedImagePhase {
        if let loaded { return .success(Image(uiImage: loaded)) }
        // 메모리에 있으면 첫 프레임부터 그린다. 이게 없으면 다시 열 때마다 깜빡인다.
        if let url, let hit = RemoteImageStore.cached(url, maxPixel: maxPixel) {
            return .success(Image(uiImage: hit))
        }
        return failed ? .failure : .empty
    }

    private func load() async {
        guard let url else {
            failed = true
            return
        }
        failed = false
        if let hit = RemoteImageStore.cached(url, maxPixel: maxPixel) {
            loaded = hit
            return
        }
        let image = await RemoteImageStore.shared.image(for: url, maxPixel: maxPixel)
        if let image {
            loaded = image
        } else {
            failed = true
        }
    }
}
