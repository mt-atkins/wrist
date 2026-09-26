import SwiftUI
import WatchKit

/// Owns the watch's recorder so the UI, App Intents and complications all drive the same capture.
@MainActor
final class CaptureModel: ObservableObject {
    static let shared = CaptureModel()

    let recorder = AudioRecorder()
    @Published var toast: String?
    @Published var micDenied = false

    private var toastTask: Task<Void, Never>?
    private var isStarting = false

    init() {
        recorder.onRecordingFinished = { recording in WatchLink.shared.send(recording) }
    }

    func toggle() async {
        if recorder.isRecording || recorder.pendingRecording != nil { finish() } else { await start() }
    }

    func start() async {
        guard !recorder.isRecording, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        guard await recorder.requestPermission() else {
            micDenied = true
            WKInterfaceDevice.current().play(.failure)
            return
        }
        micDenied = false
        do {
            try recorder.start()
            WKInterfaceDevice.current().play(.start)
        } catch {
            show(error.localizedDescription)
        }
    }

    func finish() {
        guard let recording = recorder.stop() else { return }
        WKInterfaceDevice.current().play(.stop)
        guard recording.duration >= 1 else {
            try? FileManager.default.removeItem(at: recording.url)
            show("Too short — hold on a sec longer")
            return
        }
        if WatchLink.shared.send(recording) {
            show("Queued for iPhone")
        } else {
            recorder.retainForRetry(recording)
            show("Save failed. Tap to retry.")
        }
    }

    func sendNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if WatchLink.shared.sendNote(trimmed) {
            WKInterfaceDevice.current().play(.success)
            show("Note queued")
        } else {
            WKInterfaceDevice.current().play(.failure)
            show("Could not save note")
        }
    }

    func show(_ message: String) {
        toastTask?.cancel()
        withAnimation { toast = message }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }
}
