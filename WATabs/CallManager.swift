import CallKit
import UIKit

/// Входящие звонки WhatsApp Web показываются нативным экраном звонка iOS (CallKit).
/// «Принять» / «Отклонить» на этом экране нажимают соответствующие кнопки в WhatsApp Web.
@MainActor
final class CallManager: NSObject, CXProviderDelegate {
    static let shared = CallManager()

    private let provider: CXProvider
    private let controller = CXCallController()
    private weak var pool: WebViewPool?
    private weak var store: AccountStore?

    /// Текущий звонок: id в CallKit → аккаунт.
    private var calls: [UUID: UUID] = [:]

    override init() {
        let config = CXProviderConfiguration()
        config.supportsVideo = true
        config.maximumCallGroups = 1
        config.maximumCallsPerCallGroup = 1
        config.includesCallsInRecents = false
        config.supportedHandleTypes = [.generic]
        provider = CXProvider(configuration: config)
        super.init()
        provider.setDelegate(self, queue: .main)
    }

    func start(pool: WebViewPool, store: AccountStore) {
        self.pool = pool
        self.store = store
    }

    /// Состояние звонка из wa-mobile.js: none / incoming / active.
    func handle(state: String, caller: String, video: Bool, account: UUID) {
        let existing = calls.first { $0.value == account }?.key
        switch state {
        case "incoming":
            guard existing == nil else { return }
            let callID = UUID()
            calls[callID] = account
            let update = CXCallUpdate()
            let accountName = store?.accounts.first { $0.id == account }?.name ?? "WhatsApp"
            let name = caller.isEmpty ? "WhatsApp" : caller
            update.remoteHandle = CXHandle(type: .generic, value: name)
            update.localizedCallerName = "\(name) · \(accountName)"
            update.hasVideo = video
            update.supportsHolding = false
            update.supportsGrouping = false
            update.supportsUngrouping = false
            update.supportsDTMF = false
            provider.reportNewIncomingCall(with: callID, update: update) { error in
                guard error != nil else { return }
                DispatchQueue.main.async { CallManager.shared.calls[callID] = nil }
            }
        case "active":
            // Приняли прямо в WhatsApp Web, а не на экране CallKit: убираем экран звонка iOS.
            if let existing, !answered.contains(existing) {
                provider.reportCall(with: existing, endedAt: nil, reason: .answeredElsewhere)
                calls[existing] = nil
            }
        default:
            // Звонок завершён или пропущен в самом WhatsApp.
            if let existing {
                provider.reportCall(with: existing, endedAt: nil, reason: .remoteEnded)
                calls[existing] = nil
                answered.remove(existing)
            }
        }
    }

    private var answered: Set<UUID> = []

    // MARK: CXProviderDelegate

    nonisolated func providerDidReset(_ provider: CXProvider) {
        MainActor.assumeIsolated {
            calls.removeAll()
            answered.removeAll()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXAnswerCallAction) {
        MainActor.assumeIsolated {
            guard let account = calls[action.callUUID] else { action.fail(); return }
            answered.insert(action.callUUID)
            store?.select(account)
            pool?.run("window.__waMobile && window.__waMobile.acceptCall()", in: account)
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXEndCallAction) {
        MainActor.assumeIsolated {
            answered.remove(action.callUUID)
            if let account = calls.removeValue(forKey: action.callUUID) {
                pool?.run("window.__waMobile && window.__waMobile.endCall()", in: account)
            }
            action.fulfill()
        }
    }

    nonisolated func provider(_ provider: CXProvider, perform action: CXSetMutedCallAction) {
        action.fulfill()
    }
}
