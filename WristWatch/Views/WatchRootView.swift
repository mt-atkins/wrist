import SwiftUI

struct WatchRootView: View {
    var body: some View {
        NavigationStack {
            TabView {
                CaptureView()
                InboxView()
                AskView()
            }
            .tabViewStyle(.verticalPage)
            .background(Theme.background.ignoresSafeArea())
        }
        .tint(Theme.orange)
    }
}
