import SwiftUI
import Kingfisher

/// 원격 이미지 한 장. 내려받기 · 캐시 · 다운샘플링은 전부 Kingfisher 가 한다.
///
/// 화면에서 `KFImage` 를 직접 쓰지 않고 이걸 거치는 이유는 둘이다.
/// 1. **실패 화면을 View 로 그리려고.** Kingfisher 의 `onFailureImage(_:)` 는
///    `UIImage` 만 받아서 "아이콘 + 문구" 같은 걸 못 그린다.
/// 2. **다운샘플링 설정을 한곳에 모으려고.** 프로세서만 주고 `scaleFactor` 를
///    빠뜨리면 3배 화면에서 뭉갠다. 호출부마다 두 줄을 반복하면 언젠가 빠진다.
///
/// `resizable()` 은 안에서 붙인다. 쓰는 쪽은 `.scaledToFit()` / `.scaledToFill()` 만 준다.
struct RemoteImage<Placeholder: View, Failure: View>: View {
    let url: URL?
    /// 그릴 최대 변(pt). 화면 배율을 곱한 픽셀로 **줄여서 디코드한다**.
    ///
    /// 폼이 올리는 영수증은 긴 변 1600px 다. 파일은 300KB 남짓이어도 통째로 펴면
    /// 비트맵이 7MB 를 넘는데, 90pt 썸네일에 필요한 건 그 100분의 1이다.
    /// `nil` 이면 원본 그대로 — 손가락으로 확대하는 화면에만 준다.
    let maxDimension: CGFloat?
    let placeholder: () -> Placeholder
    let failure: () -> Failure

    @Environment(\.displayScale) private var displayScale
    @State private var failed = false

    init(
        url: URL?,
        maxDimension: CGFloat? = nil,
        @ViewBuilder placeholder: @escaping () -> Placeholder,
        @ViewBuilder failure: @escaping () -> Failure
    ) {
        self.url = url
        self.maxDimension = maxDimension
        self.placeholder = placeholder
        self.failure = failure
    }

    var body: some View {
        Group {
            if url == nil || failed {
                failure()
            } else {
                image
                    .placeholder { placeholder() }
                    .onFailure { _ in failed = true }
                    .resizable()
            }
        }
        // 같은 자리에 다른 사진이 들어오면 실패 상태를 지운다.
        .onChange(of: url) { _, _ in failed = false }
    }

    private var image: KFImage {
        let base = KFImage(url)
        guard let maxDimension else { return base }
        // 크기는 pt 로 주고 배율은 따로 알려준다. 이 둘이 한 세트다.
        return base
            .setProcessor(
                DownsamplingImageProcessor(size: CGSize(width: maxDimension, height: maxDimension))
            )
            .scaleFactor(displayScale)
    }
}

// MARK: - 캐시 설정

enum RemoteImageCache {
    /// 앱을 켤 때 한 번 부른다. Kingfisher 기본값은 디스크 무제한 · 7일 만료다.
    ///
    /// 영수증은 URL 이 곧 그 파일이고 내용이 절대 안 바뀐다. 그래서 오래 들고 있어도
    /// 안전하고, 대신 **용량으로 끊는다** — 만료가 짧으면 지난달 청구서를 다시 볼 때
    /// 매번 새로 받게 된다.
    static func configure() {
        let cache = ImageCache.default
        // 비트맵 기준. 화면 크기로 줄인 영수증 한 장이 5MB 안쪽이다.
        cache.memoryStorage.config.totalCostLimit = 64 * 1024 * 1024
        cache.diskStorage.config.sizeLimit = 200 * 1024 * 1024
        cache.diskStorage.config.expiration = .days(90)
    }
}
