import AVFoundation
import Combine

/// Records compact mono AAC audio and publishes a live level for the orb animation.
/// Used by both the watch and phone apps.
@MainActor
final class AudioRecorder: ObservableObject {
    struct Recording {
        let url: URL
        let duration: TimeInterval
        let startedAt: Date
    }

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    /// Smoothed input level, 0...1.
    @Published private(set) var level: Float = 0
    /// Recent levels for a scrolling waveform, oldest first.
    @Published private(set) var history: [Float] = Array(repeating: 0, count: 28)

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt = Date()

    static var directory: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        guard !isRecording else { return }
        let session = AVAudioSession.sharedInstance()
        #if os(iOS)
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        #else
        try session.setCategory(.playAndRecord, mode: .default, options: [])
        #endif
        try session.setActive(true)

        let url = Self.directory.appendingPathComponent("\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        guard recorder.record() else { throw RecorderError.couldNotStart }

        self.recorder = recorder
        startedAt = Date()
        elapsed = 0
        isRecording = true
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    @discardableResult
    func stop() -> Recording? {
        guard let recorder else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        timer?.invalidate()
        timer = nil
        self.recorder = nil
        isRecording = false
        level = 0
        history = Array(repeating: 0, count: history.count)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return Recording(url: recorder.url, duration: duration, startedAt: startedAt)
    }

    private func tick() {
        guard let recorder else { return }
        recorder.updateMeters()
        let power = recorder.averagePower(forChannel: 0) // -160...0 dB
        let normalized = max(0, min(1, (power + 50) / 50))
        level = level * 0.6 + normalized * 0.4
        history.removeFirst()
        history.append(level)
        elapsed = recorder.currentTime
    }

    enum RecorderError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { "The microphone couldn't start recording." }
    }
}
