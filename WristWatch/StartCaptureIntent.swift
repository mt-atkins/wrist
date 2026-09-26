import AppIntents

/// Lets you start a capture from the Action button (Ultra), Siri, or Shortcuts.
struct StartCaptureIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Capture"
    static var description = IntentDescription("Start recording a voice capture on your wrist.")
    static var openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        guard WatchLink.shared.isPro else { throw ProRequired() }
        await CaptureModel.shared.start()
        return .result()
    }
}

/// Shown by Siri/Shortcuts when capture-from-anywhere isn't unlocked.
struct ProRequired: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "Starting a capture from Siri, Shortcuts or the Action button is part of Wrist Pro. Unlock it in Wrist on your iPhone."
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
