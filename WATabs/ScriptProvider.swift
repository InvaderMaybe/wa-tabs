import Foundation

/// Отдаёт wa-mobile.js: свежую версию из репозитория (если она новее встроенной), иначе встроенную.
/// Так обёртку можно чинить после изменений в вёрстке WhatsApp без переустановки приложения.
@MainActor
final class ScriptProvider {
    static let shared = ScriptProvider()

    static let remoteURL = URL(string: "https://raw.githubusercontent.com/InvaderMaybe/wa-tabs/main/WATabs/Resources/wa-mobile.js")!

    private let cacheURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("wa-mobile.js")
    }()

    private let bundled: String = {
        guard let url = Bundle.main.url(forResource: "wa-mobile", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }()

    /// Текущий скрипт, который внедряется в новые WebView.
    var source: String {
        if let cached = try? String(contentsOf: cacheURL, encoding: .utf8),
           Self.version(of: cached) > Self.version(of: bundled) {
            return cached
        }
        return bundled
    }

    var version: Int { Self.version(of: source) }

    /// Возвращает true, если скачана более новая версия.
    @discardableResult
    func refreshFromRemote() async -> Bool {
        var request = URLRequest(url: Self.remoteURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8),
              Self.version(of: text) > version else { return false }
        try? text.write(to: cacheURL, atomically: true, encoding: .utf8)
        return true
    }

    /// Номер версии из первой строки вида `// wa-mobile v3`.
    static func version(of script: String) -> Int {
        guard let line = script.split(separator: "\n", maxSplits: 1).first,
              let range = line.range(of: "wa-mobile v") else { return 0 }
        return Int(line[range.upperBound...].prefix { $0.isNumber }) ?? 0
    }
}
