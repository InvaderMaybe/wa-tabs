import AVFoundation
import UIKit

/// Не даёт iOS заморозить приложение в фоне: беззвучный звук в цикле нативно и в каждом WebView.
/// Пока приложение «играет звук», WhatsApp Web во всех аккаунтах остаётся на связи,
/// и приходят уведомления и входящие звонки.
@MainActor
final class BackgroundKeeper {
    static let shared = BackgroundKeeper()

    private var player: AVAudioPlayer?
    private weak var pool: WebViewPool?

    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "background.enabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "background.enabled")
            apply()
        }
    }

    func start(pool: WebViewPool) {
        self.pool = pool
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            // После звонка по сотовой или Siri звук останавливается: запускаем снова.
            let type = (note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt).flatMap(AVAudioSession.InterruptionType.init)
            if type == .ended { MainActor.assumeIsolated { self?.apply() } }
        }
        apply()
    }

    func apply() {
        pool?.setKeepAlive(enabled)
        if enabled { play() } else { stop() }
    }

    private func play() {
        let session = AVAudioSession.sharedInstance()
        // mixWithOthers: не прерывает музыку и не появляется как плеер.
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        if player == nil {
            player = try? AVAudioPlayer(data: Self.silentWav())
            player?.numberOfLoops = -1
            player?.volume = 0.01
        }
        player?.play()
    }

    private func stop() {
        player?.stop()
        player = nil
    }

    /// 1 секунда почти тишины, 8 кГц, 16 бит, моно.
    private static func silentWav() -> Data {
        let rate = 8000, samples = rate
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        data.append("RIFF".data(using: .ascii)!); append(UInt32(36 + samples * 2))
        data.append("WAVE".data(using: .ascii)!); data.append("fmt ".data(using: .ascii)!)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(1))
        append(UInt32(rate)); append(UInt32(rate * 2)); append(UInt16(2)); append(UInt16(16))
        data.append("data".data(using: .ascii)!); append(UInt32(samples * 2))
        for i in 0..<samples { append(Int16(i % 2 == 0 ? 1 : -1)) }
        return data
    }
}
