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
    /// Журнал страницы по аккаунтам (последние 300 строк), см. logScript.
    private(set) var logs: [UUID: [String]] = [:]

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        return f
    }()

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

    /// Анимации WhatsApp Web выключены по умолчанию: на телефоне они тормозят.
    var reduceMotion: Bool {
        get { UserDefaults.standard.object(forKey: "reduceMotion") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "reduceMotion")
            for id in sessions.keys {
                run("window.__waMobile && window.__waMobile.reduceMotion && window.__waMobile.reduceMotion(\(newValue))", in: id)
            }
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

    weak var store: AccountStore?

    func back(_ id: UUID) {
        run("window.__waMobile && window.__waMobile.back()", in: id)
    }

    func run(_ js: String, in id: UUID) {
        sessions[id]?.webView.evaluateJavaScript(js)
    }

    func setKeepAlive(_ on: Bool) {
        for id in sessions.keys { run("window.__waMobile && window.__waMobile.keepAlive(\(on))", in: id) }
    }

    func appendLog(_ text: String, level: String, for id: UUID) {
        var entries = logs[id, default: []]
        entries.append("\(Self.timeFormatter.string(from: Date())) [\(level)] \(text)")
        if entries.count > 300 { entries.removeFirst(entries.count - 300) }
        logs[id] = entries
    }

    fileprivate func handleMessage(_ dict: [String: Any], from id: UUID) {
        switch dict["type"] as? String {
        case "log":
            appendLog(dict["text"] as? String ?? "", level: dict["level"] as? String ?? "info", for: id)
        case "mode":
            setInChat(dict["chat"] as? Bool ?? false, for: id)
        case "ready":
            // Страница (пере)загрузилась: фоновый звук и анимации по настройкам.
            run("window.__waMobile && window.__waMobile.keepAlive(\(BackgroundKeeper.shared.enabled))", in: id)
            run("window.__waMobile && window.__waMobile.reduceMotion && window.__waMobile.reduceMotion(\(reduceMotion))", in: id)
        case "message":
            guard let account = store?.accounts.first(where: { $0.id == id }) else { return }
            Notifier.shared.message(account: account,
                                    chat: dict["chat"] as? String ?? "",
                                    preview: dict["preview"] as? String ?? "")
        case "call":
            CallManager.shared.handle(state: dict["state"] as? String ?? "none",
                                      caller: dict["caller"] as? String ?? "",
                                      video: dict["video"] as? Bool ?? false,
                                      account: id)
        default:
            break
        }
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
        config.limitsNavigationsToAppBoundDomains = true

        webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = WebViewPool.userAgent
        webView.isInspectable = true
        webView.allowsBackForwardNavigationGestures = false
        webView.pageZoom = pool.zoom
        webView.backgroundColor = .systemBackground
        webView.isOpaque = false
        // WhatsApp Web сам прокручивает свои колонки. Если даёт прокручиваться и внешнему скроллу WebView,
        // iOS при открытии клавиатуры сдвигает всю страницу вверх, а SwiftUI ещё и ужимает её под клавиатуру.
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.bounces = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        super.init()
        webView.scrollView.delegate = self

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
        ucc.addUserScript(WKUserScript(source: Self.logScript, injectionTime: .atDocumentStart, forMainFrameOnly: true))
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
        guard let dict = body as? [String: Any] else { return }
        pool?.handleMessage(dict, from: id)
    }

    /// Журнал страницы: ошибки JS, WebSocket, service worker. Смотреть в «Управление → Журнал страницы».
    static let logScript = """
    (function () {
      if (window.__waLog) return;
      window.__waLog = true;
      function send(level, text) {
        try { window.webkit.messageHandlers.wa.postMessage({ type: 'log', level: level, text: String(text).slice(0, 500) }); } catch (e) {}
      }
      function fmt(args) {
        return Array.prototype.map.call(args, function (a) {
          if (a instanceof Error) return a.name + ': ' + a.message;
          if (typeof a === 'object') { try { return JSON.stringify(a).slice(0, 200); } catch (e) { return String(a); } }
          return String(a);
        }).join(' ');
      }
      ['error', 'warn'].forEach(function (level) {
        var orig = console[level];
        console[level] = function () { send(level, fmt(arguments)); return orig.apply(console, arguments); };
      });
      window.addEventListener('error', function (e) { send('error', 'onerror: ' + e.message + ' @' + (e.filename || '') + ':' + (e.lineno || '')); });
      window.addEventListener('unhandledrejection', function (e) { send('error', 'rejection: ' + fmt([e.reason])); });
      var WS = window.WebSocket;
      window.WebSocket = function (url, protocols) {
        var ws = protocols === undefined ? new WS(url) : new WS(url, protocols);
        send('info', 'ws connect ' + url);
        ws.addEventListener('open', function () { send('info', 'ws open ' + url); });
        ws.addEventListener('close', function (e) { send('warn', 'ws close ' + e.code + ' ' + (e.reason || '') + ' ' + url); });
        ws.addEventListener('error', function () { send('error', 'ws error ' + url); });
        return ws;
      };
      window.WebSocket.prototype = WS.prototype;
      ['CONNECTING', 'OPEN', 'CLOSING', 'CLOSED'].forEach(function (k) { window.WebSocket[k] = WS[k]; });
      send('info', 'start ' + location.href + ' sw=' + ('serviceWorker' in navigator) + ' idb=' + ('indexedDB' in window) + ' subtle=' + !!(window.crypto && crypto.subtle) + ' shared=' + ('SharedWorker' in window));
      if ('serviceWorker' in navigator) {
        navigator.serviceWorker.ready.then(function () { send('info', 'sw ready'); });
      }
    })();
    """

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

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        pool?.appendLog("navigation failed: \(error.localizedDescription)", level: "error", for: id)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        pool?.appendLog("load failed: \(error.localizedDescription)", level: "error", for: id)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        pool?.appendLog("loaded \(webView.url?.absoluteString ?? "")", level: "info", for: id)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        pool?.appendLog("web process terminated, reloading", level: "error", for: id)
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

extension AccountSession: UIScrollViewDelegate {
    /// Внешний скролл WebView всегда в нуле: иначе при фокусе на поле ввода iOS сдвигает страницу.
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset != .zero { scrollView.contentOffset = .zero }
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { nil }
}

/// WKUserContentController держит обработчик сильной ссылкой, поэтому прокладка со слабой.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var session: AccountSession?
    init(_ session: AccountSession) { self.session = session }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        MainActor.assumeIsolated { session?.handleMessage(message.body) }
    }
}
