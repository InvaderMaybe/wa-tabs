import Combine
import UIKit
import UserNotifications
import WebKit

/// По одному WKWebView на аккаунт. WebView живут всё время работы приложения,
/// поэтому переключение аккаунтов не перезагружает WhatsApp.
@MainActor
final class WebViewPool: ObservableObject {
    @Published private(set) var unread: [UUID: Int] = [:]
    @Published private(set) var inChat: [UUID: Bool] = [:]

    private(set) var sessions: [UUID: AccountSession] = [:]

    static let whatsappURL = URL(string: "https://web.whatsapp.com/")!
    // Десктопный Safari: тот же движок WebKit, WhatsApp Web его поддерживает.
    static let userAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    var zoom: Double {
        get { UserDefaults.standard.object(forKey: "zoom") as? Double ?? 1.0 }
        set {
            UserDefaults.standard.set(newValue, forKey: "zoom")
            sessions.values.forEach { $0.webView.pageZoom = newValue }
            objectWillChange.send()
        }
    }

    var totalUnread: Int { unread.values.reduce(0, +) }

    func webView(for id: UUID) -> WKWebView? { sessions[id]?.webView }

    /// Создаёт WebView для новых аккаунтов. Удалённые убирает `remove(_:)`.
    func sync(_ accounts: [Account]) {
        for account in accounts where sessions[account.id] == nil {
            sessions[account.id] = AccountSession(id: account.id, pool: self)
        }
        objectWillChange.send()
    }

    /// Закрывает WebView и стирает куки и вход этого аккаунта.
    func remove(_ id: UUID) async {
        if let session = sessions.removeValue(forKey: id) {
            session.tearDown()
        }
        unread[id] = nil
        inChat[id] = nil
        updateAppBadge()
        try? await WKWebsiteDataStore.remove(forIdentifier: id)
    }

    func back(_ id: UUID) {
        sessions[id]?.webView.evaluateJavaScript("window.__waMobile && window.__waMobile.back()")
    }

    func reload(_ id: UUID) {
        sessions[id]?.webView.load(URLRequest(url: Self.whatsappURL))
    }

    /// После обновления скрипта пересоздаёт user script во всех WebView и перезагружает их.
    func reinjectScript() {
        for session in sessions.values {
            session.installScript()
            session.webView.reload()
        }
    }

    fileprivate func setUnread(_ count: Int, for id: UUID) {
        guard unread[id] != count else { return }
        unread[id] = count
        updateAppBadge()
    }

    fileprivate func setInChat(_ value: Bool, for id: UUID) {
        guard inChat[id] != value else { return }
        inChat[id] = value
    }

    private func updateAppBadge() {
        UNUserNotificationCenter.current().setBadgeCount(totalUnread) { _ in }
    }
}

/// Один аккаунт: WebView, его хранилище и делегаты.
@MainActor
final class AccountSession: NSObject {
    let id: UUID
    let webView: WKWebView
    private weak var pool: WebViewPool?
    private var titleObservation: AnyCancellable?
    private var downloads: [ObjectIdentifier: URL] = [:]

    init(id: UUID, pool: WebViewPool) {
        self.id = id
        self.pool = pool

        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore(forIdentifier: id)
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        config.defaultWebpagePreferences.preferredContentMode = .mobile
        config.preferences.javaScriptCanOpenWindowsAutomatically = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = WebViewPool.userAgent
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = false
        webView.pageZoom = pool.zoom
        webView.backgroundColor = .systemBackground
        webView.isOpaque = false

        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.configuration.userContentController.add(WeakScriptHandler(self), name: "wa")
        installScript()

        titleObservation = webView.publisher(for: \.title)
            .receive(on: RunLoop.main)
            .sink { [weak self] title in self?.handleTitle(title) }

        webView.load(URLRequest(url: WebViewPool.whatsappURL))
    }

    func installScript() {
        let ucc = webView.configuration.userContentController
        ucc.removeAllUserScripts()
        ucc.addUserScript(WKUserScript(source: ScriptProvider.shared.source,
                                       injectionTime: .atDocumentEnd,
                                       forMainFrameOnly: true))
    }

    func tearDown() {
        titleObservation = nil
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "wa")
        webView.stopLoading()
        webView.removeFromSuperview()
    }

    /// «(74) WhatsApp» → 74
    private func handleTitle(_ title: String?) {
        var count = 0
        if let title, title.hasPrefix("("), let close = title.firstIndex(of: ")") {
            count = Int(title[title.index(after: title.startIndex)..<close]) ?? 0
        }
        pool?.setUnread(count, for: id)
    }

    fileprivate func handleMessage(_ body: Any) {
        guard let dict = body as? [String: Any], let type = dict["type"] as? String else { return }
        switch type {
        case "mode":
            pool?.setInChat(dict["chat"] as? Bool ?? false, for: id)
        default:
            break
        }
    }

    private static func isWhatsApp(_ url: URL) -> Bool {
        guard let host = url.host else { return true }   // blob:, data:, about:
        return host == "whatsapp.com" || host.hasSuffix(".whatsapp.com") || host.hasSuffix(".whatsapp.net")
    }
}

extension AccountSession: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.shouldPerformDownload { return .download }
        if let url = navigationAction.request.url,
           navigationAction.targetFrame?.isMainFrame ?? true,
           ["http", "https"].contains(url.scheme ?? ""),
           !Self.isWhatsApp(url) {
            _ = await UIApplication.shared.open(url)
            return .cancel
        }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        navigationResponse.canShowMIMEType ? .allow : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        // iOS выгрузил процесс страницы (обычно из-за памяти). Поднимаем заново, вход сохранится.
        webView.load(URLRequest(url: WebViewPool.whatsappURL))
    }
}

extension AccountSession: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(suggestedFilename)
        downloads[ObjectIdentifier(download)] = url
        return url
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        UIPresenter.share(url)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        downloads.removeValue(forKey: ObjectIdentifier(download))
    }
}

extension AccountSession: WKUIDelegate {
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        // target=_blank: внешние ссылки в Safari, ссылки WhatsApp в этой же вкладке.
        if let url = navigationAction.request.url {
            if Self.isWhatsApp(url) { webView.load(navigationAction.request) } else { UIApplication.shared.open(url) }
        }
        return nil
    }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType) async -> WKPermissionDecision {
        .grant
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async {
        await UIPresenter.alert(message, cancellable: false)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await UIPresenter.alert(message, cancellable: true)
    }
}

/// WKUserContentController держит обработчик сильной ссылкой, поэтому прокладка со слабой.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var session: AccountSession?
    init(_ session: AccountSession) { self.session = session }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { session?.handleMessage(message.body) }
    }
}
