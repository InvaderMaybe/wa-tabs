import UIKit
import UserNotifications

/// Локальные уведомления о новых сообщениях. Нажатие открывает нужный аккаунт.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()

    weak var store: AccountStore?

    func start(store: AccountStore) {
        self.store = store
        UNUserNotificationCenter.current().delegate = self
    }

    func message(account: Account, chat: String, preview: String) {
        let content = UNMutableNotificationContent()
        content.title = chat
        content.subtitle = account.name
        content.body = preview.isEmpty ? "Новое сообщение" : preview
        content.sound = .default
        content.threadIdentifier = account.id.uuidString
        content.userInfo = ["account": account.id.uuidString]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// На экране баннер только если открыт другой аккаунт или приложение свёрнуто.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        let raw = notification.request.content.userInfo["account"] as? String
        let visible = await MainActor.run {
            UIApplication.shared.applicationState == .active && raw == self.store?.selectedID?.uuidString
        }
        return visible ? [] : [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["account"] as? String,
              let id = UUID(uuidString: raw) else { return }
        await MainActor.run {
            if self.store?.accounts.contains(where: { $0.id == id }) == true { self.store?.select(id) }
        }
    }
}
