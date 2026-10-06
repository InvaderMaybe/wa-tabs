import SwiftUI
import WebKit

/// Держит все WebView одновременно и показывает только выбранный.
/// Свайп от левого края: «назад» в чате или открыть шторку.
struct WebStack: UIViewRepresentable {
    let ids: [UUID]
    let selected: UUID?
    let pool: WebViewPool
    let onEdgeSwipe: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .systemBackground
        let edge = UIScreenEdgePanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.edgePan(_:)))
        edge.edges = .left
        container.addGestureRecognizer(edge)
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        context.coordinator.onEdgeSwipe = onEdgeSwipe

        for id in ids {
            guard let webView = pool.webView(for: id) else { continue }
            if webView.superview !== container {
                webView.frame = container.bounds
                webView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                container.addSubview(webView)
            }
            webView.isHidden = id != selected
        }
        // WebView удалённых аккаунтов.
        for case let webView as WKWebView in container.subviews
        where !ids.contains(where: { pool.webView(for: $0) === webView }) {
            webView.removeFromSuperview()
        }
    }

    final class Coordinator: NSObject {
        var onEdgeSwipe: (() -> Void)?

        @objc func edgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
            guard gesture.state == .ended, let view = gesture.view else { return }
            if gesture.translation(in: view).x > 60 { onEdgeSwipe?() }
        }
    }
}
