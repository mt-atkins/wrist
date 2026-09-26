import AVFoundation
import Combine
import UIKit

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0
    @Published private(set) var errorMessage: String?

    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []

    init() {
        for name in [AVAudioSession.interruptionNotification,
                     AVAudioSession.mediaServicesWereResetNotification,
                     UIApplication.didEnterBackgroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.pause() }
            })
        }
    }

    deinit {
        timer?.invalidate()
        let wasPlaying = player?.isPlaying == true
        player?.stop()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        if wasPlaying, AVAudioSession.sharedInstance().category == .playback {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func toggle(url: URL) {
        if isPlaying && player?.url == url { pause() } else { play(url: url) }
    }

    func play(url: URL) {
        pause()
        do {
            // Don't steal the shared audio session from a capture.
            guard !AudioRecorder.hasActiveRecording else {
                errorMessage = "Finish recording before playing audio."
                return
            }
            if player?.url != url {
                player?.stop()
                player = try AVAudioPlayer(contentsOf: url)
                progress = 0
            }
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            guard let player, player.play() else { throw PlaybackError.couldNotStart }
            errorMessage = nil
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } catch {
            errorMessage = error.localizedDescription
            pause()
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    func pause() {
        let wasPlaying = isPlaying
        player?.pause()
        timer?.invalidate()
        timer = nil
        isPlaying = false
        // A recorder may have taken over the shared session in the meantime.
        if wasPlaying, AVAudioSession.sharedInstance().category == .playback {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }

    private func tick() {
        guard let player else { pause(); return }
        progress = player.duration > 0 ? min(1, max(0, player.currentTime / player.duration)) : 0
        if !player.isPlaying {
            pause()
            progress = 0
        }
    }

    private enum PlaybackError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { "The audio couldn't be played." }
    }
}
