import AVFoundation

@MainActor
final class AudioPlayer: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var progress: Double = 0

    private var player: AVAudioPlayer?
    private var timer: Timer?

    func toggle(url: URL) {
        if isPlaying { pause() } else { play(url: url) }
    }

    func play(url: URL) {
        do {
            if player?.url != url {
                try AVAudioSession.sharedInstance().setCategory(.playback)
                player = try AVAudioPlayer(contentsOf: url)
            }
            try AVAudioSession.sharedInstance().setActive(true)
            player?.play()
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } catch {
            isPlaying = false
        }
    }

    func pause() {
        player?.pause()
        timer?.invalidate()
        isPlaying = false
    }

    private func tick() {
        guard let player else { return }
        progress = player.duration > 0 ? player.currentTime / player.duration : 0
        if !player.isPlaying {
            timer?.invalidate()
            isPlaying = false
            if progress > 0.98 || player.currentTime == 0 { progress = 0 }
        }
    }
}
