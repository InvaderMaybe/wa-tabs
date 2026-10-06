import UIKit

/// Показ системных окон (поделиться, alert) поверх SwiftUI.
@MainActor
enum UIPresenter {
    static var top: UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive } ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
        var vc = scene?.keyWindow?.rootViewController
        while let presented = vc?.presentedViewController { vc = presented }
        return vc
    }

    static func share(_ url: URL) {
        guard let top else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = top.view
        top.present(sheet, animated: true)
    }

    @discardableResult
    static func alert(_ message: String, cancellable: Bool) async -> Bool {
        guard let top else { return false }
        return await withCheckedContinuation { continuation in
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            if cancellable {
                alert.addAction(UIAlertAction(title: "Отмена", style: .cancel) { _ in continuation.resume(returning: false) })
            }
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in continuation.resume(returning: true) })
            top.present(alert, animated: true)
        }
    }
}
