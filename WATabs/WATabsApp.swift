import SwiftUI
import UserNotifications

@main
struct WATabsApp: App {
    @StateObject private var store = AccountStore()
    @StateObject private var pool = WebViewPool()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(pool)
                .task {
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.badge, .alert, .sound])
                    await ScriptProvider.shared.refreshFromRemote()
                }
        }
    }
}
