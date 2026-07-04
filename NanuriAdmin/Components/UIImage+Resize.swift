import UIKit

extension UIImage {
    /// 긴 변이 maxDimension(px)을 넘지 않도록 축소한다. 원본이 더 작으면 그대로 반환.
    /// 업로드 용량 절감용 — 영수증처럼 글자 가독성만 필요한 이미지에 적합.
    func resized(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }

        let scale = maxDimension / longest
        let newSize = CGSize(width: size.width * scale, height: size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1 // 결과 픽셀 크기를 newSize로 고정 (retina 배율로 다시 커지는 것 방지)
        let renderer = UIGraphicsImageRenderer(size: newSize, format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}
