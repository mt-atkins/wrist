import AVFoundation
import Combine
#if os(iOS)
import UIKit
#elseif os(watchOS)
import WatchKit
#endif

/// Foreground capture only; interrupted captures are retained for the owner to consume.
@MainActor
final class AudioRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    struct Recording {
        let url: URL
        let duration: TimeInterval
        let startedAt: Date
    }

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var level: Float = 0
    @Published private(set) var history: [Float] = Array(repeating: 0, count: 28)
    /// Owners should observe this and call stop() to consume an automatically ended capture.
    @Published private(set) var pendingRecording: Recording?
    @Published private(set) var errorMessage: String?
    /// Set by the capture owner to persist/send automatically ended audio exactly once.
    /// Without a handler it remains in pendingRecording and can be consumed via stop().
    var onRecordingFinished: ((Recording) -> Bool)?

    private static weak var activeRecorder: AudioRecorder?
    static var hasActiveRecording: Bool { activeRecorder != nil }

    private var recorder: AVAudioRecorder?
    private var timer: Timer?
    private var startedAt = Date()
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] notification in
            guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  raw == AVAudioSession.InterruptionType.began.rawValue else { return }
            MainActor.assumeIsolated { self?.endAutomatically("Recording stopped because audio was interrupted.") }
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.endAutomatically("Recording stopped because audio services restarted.") }
        })
        #if os(iOS)
        let background = UIApplication.didEnterBackgroundNotification
        #elseif os(watchOS)
        let background = WKExtension.applicationDidEnterBackgroundNotification
        #endif
        observers.append(center.addObserver(forName: background, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.endAutomatically("Recording stopped when Wrist moved to the background.") }
        })
    }

    deinit {
        timer?.invalidate()
        recorder?.stop()
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        if recorder != nil { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
    }

    nonisolated static var directory: URL {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func requestPermission() async -> Bool {
        return await AVAudioApplication.requestRecordPermission()
    }

    func start() throws {
        guard !isRecording else { return }
        guard !Self.hasActiveRecording else { throw RecorderError.couldNotStart }
        // Never overwrite an interrupted capture before its owner has saved it.
        guard pendingRecording == nil else { throw RecorderError.pendingCapture }
        #if os(iOS)
        guard UIApplication.shared.applicationState == .active else { throw RecorderError.notForeground }
        #elseif os(watchOS)
        guard WKExtension.shared().applicationState == .active else { throw RecorderError.notForeground }
        #endif
        let session = AVAudioSession.sharedInstance()
        let url = Self.directory.appendingPathComponent("\(UUID().uuidString).m4a")
        do {
            #if os(iOS)
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            #else
            try session.setCategory(.playAndRecord, mode: .default, options: [])
            #endif
            try session.setActive(true)
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
            ])
            recorder.delegate = self
            recorder.isMeteringEnabled = true
            guard recorder.record() else { throw RecorderError.couldNotStart }
            self.recorder = recorder
            startedAt = Date()
            elapsed = 0
            errorMessage = nil
            isRecording = true
            Self.activeRecorder = self
            timer?.invalidate()
            timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
        } catch {
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    @discardableResult
    func stop() -> Recording? {
        if let pendingRecording {
            self.pendingRecording = nil
            return pendingRecording
        }
        guard let recorder else { return nil }
        let duration = max(elapsed, recorder.currentTime)
        self.recorder = nil
        recorder.delegate = nil
        recorder.stop()
        timer?.invalidate()
        timer = nil
        isRecording = false
        Self.activeRecorder = nil
        level = 0
        history = Array(repeating: 0, count: history.count)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        return Recording(url: recorder.url, duration: duration, startedAt: startedAt)
    }

    func retainForRetry(_ recording: Recording) { pendingRecording = recording }

    private func endAutomatically(_ message: String) {
        guard recorder != nil else { return }
        let recording = stop()
        errorMessage = message
        if let recording, let onRecordingFinished {
            if !onRecordingFinished(recording) { pendingRecording = recording }
        } else {
            pendingRecording = recording
        }
    }

    private func tick() {
        guard let recorder else { return }
        guard recorder.isRecording else {
            endAutomatically("Recording stopped unexpectedly.")
            return
        }
        recorder.updateMeters()
        let normalized = max(0, min(1, (recorder.averagePower(forChannel: 0) + 50) / 50))
        level = level * 0.6 + normalized * 0.4
        history.removeFirst()
        history.append(level)
        elapsed = recorder.currentTime
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard self?.recorder === recorder else { return }
            self?.endAutomatically(flag ? "Recording finished." : "Recording failed; the partial audio was retained.")
        }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor [weak self] in
            guard self?.recorder === recorder else { return }
            self?.endAutomatically("Audio encoding failed; the partial audio was retained.")
        }
    }

    enum RecorderError: LocalizedError {
        case couldNotStart, pendingCapture, notForeground
        var errorDescription: String? {
            switch self {
            case .couldNotStart: "The microphone couldn't start recording."
            case .pendingCapture: "Save the interrupted capture before starting another recording."
            case .notForeground: "Open Wrist to start recording."
            }
        }
    }
}
