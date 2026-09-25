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
                .tint(Theme.orange)
        }
    }
}
