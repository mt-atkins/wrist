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

    func toggle() async {
        if recorder.isRecording { finish() } else { await start() }
    }

    func start() async {
        guard !recorder.isRecording else { return }
        guard await recorder.requestPermission() else {
            micDenied = true
            WKInterfaceDevice.current().play(.failure)
            return
        }
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
        WatchLink.shared.send(recording)
        show(WatchLink.shared.isReachable ? "Sent to iPhone" : "Queued for iPhone")
    }

    func sendNote(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        WatchLink.shared.sendNote(trimmed)
        WKInterfaceDevice.current().play(.success)
        show("Note sent")
    }

    private func show(_ message: String) {
        toastTask?.cancel()
        withAnimation { toast = message }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            withAnimation { toast = nil }
        }
    }
}
