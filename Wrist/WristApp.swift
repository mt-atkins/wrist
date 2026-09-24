import SwiftUI

@main
struct WristApp: App {
    @StateObject private var store = MemoStore.shared
    @StateObject private var recorder = AudioRecorder()

    init() {
        PhoneLink.shared.activate()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(recorder)
                .preferredColorScheme(.dark)
                .tint(Theme.ember)
                .onAppear {
                    recorder.onRecordingFinished = { recording in
                        store.ingestAudio(at: recording.url, createdAt: recording.startedAt, duration: recording.duration, source: .phone)
                    }
                }
        }
    }
}
