import SwiftUI
import WebKit

/// 재정 보고서를 앱 안에서 보는 화면.
///
/// 표를 다시 그리지 않고 `FinanceReportExporter` 가 만든 **PDF와 같은 HTML** 을 띄운다.
/// 집계 로직(같은 날짜·카테고리 합산, 월·일 반복 생략, 좌우 대응)이 한 벌뿐이라
/// 화면과 출력물이 어긋날 수 없다. 화면 전용 CSS만 `forScreen` 으로 얹힌다.
///
/// 보고서는 DS 규칙 밖이다 (`DESIGN.md` 5번) — 색·글자 크기가 HTML 안에 있다.
struct FinanceReportPreviewView: View {
    let html: String
    let title: String
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ReportWebView(html: html)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("닫기") { dismiss() }
                    }
                }
        }
    }
}

/// 보고서 HTML 전용 웹뷰. 원격 로딩이 없어 `RemoteImage` 규칙과는 무관하다.
struct ReportWebView: UIViewRepresentable {
    let html: String

    func makeUIView(context: Context) -> WKWebView {
        let view = WKWebView()
        // 보고서는 우리가 만든 문자열뿐이다. 외부 페이지로 새는 길을 막아 둔다.
        view.navigationDelegate = context.coordinator
        view.isOpaque = false
        view.backgroundColor = .clear
        view.scrollView.backgroundColor = .clear
        view.loadHTMLString(html, baseURL: nil)
        return view
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        if context.coordinator.loadedHTML != html {
            context.coordinator.loadedHTML = html
            uiView.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.loadedHTML = html
        return coordinator
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loadedHTML: String?

        /// 최초 HTML 적재만 허용한다. 링크 탭 등 다른 이동은 전부 막는다.
        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.navigationType == .other ? .allow : .cancel)
        }
    }
}
