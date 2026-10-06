import Foundation

/// Срок действия подписи из embedded.mobileprovision, который кладёт в бандл SideStore/Sideloadly.
enum ProvisionInfo {
    static let expirationDate: Date? = {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .isoLatin1),
              let start = text.range(of: "<?xml"),
              let end = text.range(of: "</plist>"),
              let plistData = String(text[start.lowerBound..<end.upperBound]).data(using: .isoLatin1),
              let plist = try? PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }()

    static var statusText: String {
        guard let date = expirationDate else { return "Срок подписи неизвестен" }
        return "Действует до \(date.formatted(date: .abbreviated, time: .shortened))"
    }

    /// Предупреждение, если до истечения меньше двух дней.
    static var expiryWarning: String? {
        guard let date = expirationDate else { return nil }
        let left = date.timeIntervalSinceNow
        guard left < 2 * 24 * 3600 else { return nil }
        if left <= 0 { return "Подпись истекла: открой SideStore → Обновить" }
        let hours = Int(left / 3600)
        return "Подпись истекает через \(hours) ч: открой SideStore → Обновить"
    }
}
