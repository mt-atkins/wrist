import SwiftUI

@main
struct WristWatchApp: App {
    @StateObject private var link = WatchLink.shared
    @StateObject private var capture = CaptureModel.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView()
                .environmentObject(link)
                .environmentObject(capture)
                .environmentObject(capture.recorder)
        }
    }
}
