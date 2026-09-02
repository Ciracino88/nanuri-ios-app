import SwiftUI

/// UIActivityViewController(공유시트) 래퍼. 파일 앱 저장·메일·메신저 공유 등을 지원.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
