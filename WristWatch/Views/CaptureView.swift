import SwiftUI

struct CaptureView: View {
    @EnvironmentObject private var capture: CaptureModel
    @EnvironmentObject private var recorder: AudioRecorder
    @EnvironmentObject private var link: WatchLink

    var body: some View {
        VStack(spacing: 6) {
            Button {
                Task { await capture.toggle() }
            } label: {
                OrbView(level: recorder.level, isActive: recorder.isRecording, symbolSize: 26)
                    .frame(width: 96, height: 96)
                    .padding(12)
            }
            .buttonStyle(.plain)

            Group {
                if let toast = capture.toast {
                    Label(toast, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.ember)
                } else if recorder.isRecording {
                    Text(recorder.elapsed.clock)
                        .monospacedDigit()
                        .foregroundStyle(.white)
                } else if capture.micDenied {
                    Text("Allow mic in Settings")
                        .foregroundStyle(.secondary)
                } else {
                    Text("Tap to capture")
                        .foregroundStyle(.secondary)
                }
            }
            .font(.footnote.weight(.medium))
            .lineLimit(1)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Wrist")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                TextFieldLink(prompt: Text("Say or scribble a note")) {
                    Image(systemName: "text.bubble")
                } onSubmit: { text in
                    capture.sendNote(text)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: link.isReachable ? "iphone" : "iphone.slash")
                    .foregroundStyle(link.isReachable ? Color.secondary : Theme.rose)
                    .overlay(alignment: .topTrailing) {
                        if link.pendingTransfers > 0 {
                            Circle().fill(Theme.ember).frame(width: 6, height: 6)
                        }
                    }
            }
        }
    }
}
