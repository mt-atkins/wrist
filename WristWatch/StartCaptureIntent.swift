import AppIntents

/// Lets you start a capture from the Action button (Ultra), Siri, or Shortcuts.
struct StartCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Capture"
    static var description = IntentDescription("Start recording a voice capture on your wrist.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        await CaptureModel.shared.start()
        return .result()
    }
}

struct WristShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartCaptureIntent(),
            phrases: [
                "Capture with \(.applicationName)",
                "Start a \(.applicationName) capture",
            ],
            shortTitle: "Capture",
            systemImageName: "waveform"
        )
    }
}
