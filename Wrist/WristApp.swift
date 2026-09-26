import SwiftUI

@main
struct WristApp: App {
    @StateObject private var store = MemoStore.shared
    @StateObject private var recorder = AudioRecorder()
    @StateObject private var pro = ProStore.shared
    @StateObject private var settings = AppSettings.shared
    @StateObject private var obsidian = ObsidianExporter.shared

    init() {
        PhoneLink.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(recorder)
                .environmentObject(pro)
                .environmentObject(settings)
                .environmentObject(obsidian)
                .preferredColorScheme(.dark)
                .tint(Theme.orange)
                .onAppear {
                    recorder.onRecordingFinished = { recording in
                        store.ingestAudio(at: recording.url, createdAt: recording.startedAt, duration: recording.duration, source: .phone)
                    }
                }
        }
    }
}
