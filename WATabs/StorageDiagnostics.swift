import WebKit

/// Проверка, в какой конфигурации WKWebView доступен IndexedDB.
/// Перебирает хранилище (общее / раздельное / временное) и ограничение App-Bound Domains.
@MainActor
final class StorageDiagnostics: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var webView: WKWebView?

    static let testURL = URL(string: "https://web.whatsapp.com/robots.txt")!
    static let probe = "[typeof indexedDB, typeof caches, typeof localStorage, typeof SharedWorker, navigator.userAgent.indexOf('Mobile') >= 0 ? 'mobileUA' : 'desktopUA'].join(' ')"

    func run() async -> [String] {
        let probeID = UUID(uuidString: "00000000-0000-0000-0000-00000000D1A6")!
        let stores: [(String, () -> WKWebsiteDataStore)] = [
            ("default", { .default() }),
            ("identifier", { WKWebsiteDataStore(forIdentifier: probeID) }),
            ("nonPersistent", { .nonPersistent() })
        ]
        // Режим блокировки iOS отключает часть веб-API во всех WebView приложения.
        var lines: [String] = ["lockdown=\(WKWebpagePreferences().isLockdownModeEnabled)"]
        for (name, makeStore) in stores {
            for appBound in [true, false] {
                let result = await probe(store: makeStore(), appBound: appBound)
                lines.append("\(name) appBound=\(appBound): \(result)")
            }
        }
        try? await WKWebsiteDataStore.remove(forIdentifier: probeID)
        return lines
    }

    private func probe(store: WKWebsiteDataStore, appBound: Bool) async -> String {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = store
        config.limitsNavigationsToAppBoundDomains = appBound
        let wv = WKWebView(frame: CGRect(x: 0, y: 0, width: 10, height: 10), configuration: config)
        wv.navigationDelegate = self
        webView = wv
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            continuation = c
            wv.load(URLRequest(url: Self.testURL))
            // Страховка от зависания.
            DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.finish() }
        }
        let result: String
        do {
            let value = try await wv.evaluateJavaScript(Self.probe)
            result = "\(value ?? "nil")"
        } catch {
            result = "js error: \(error.localizedDescription)"
        }
        webView = nil
        return result
    }

    private func finish() {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finish() }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finish() }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finish() }
}
