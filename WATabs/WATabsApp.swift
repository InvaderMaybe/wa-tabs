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
                    pool.store = store
                    Notifier.shared.start(store: store)
                    CallManager.shared.start(pool: pool, store: store)
                    BackgroundKeeper.shared.start(pool: pool)
                    _ = try? await UNUserNotificationCenter.current()
                        .requestAuthorization(options: [.badge, .alert, .sound])
                    await ScriptProvider.shared.refreshFromRemote()
                }
        }
    }
}
