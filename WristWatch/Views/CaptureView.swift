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
                        .foregroundStyle(Theme.orange)
                } else if recorder.isRecording {
                    Text(recorder.elapsed.clock)
                        .font(.system(.body, design: .monospaced).weight(.semibold))
                        .foregroundStyle(Theme.paper)
                } else if capture.micDenied {
                    Text("Allow mic in Settings")
                        .foregroundStyle(Theme.machineGrey)
                } else {
                    Text("TAP TO CAPTURE")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .kerning(1.2)
                        .foregroundStyle(Theme.machineGrey)
                }
            }
            .font(.footnote.weight(.medium))
            .lineLimit(1)
            .transition(.opacity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Wrist")
        .onChange(of: link.lastDeliveredID) { _, id in
            if id != nil { capture.show("Saved on iPhone") }
        }
        .safeAreaInset(edge: .bottom) {
            if let error = link.lastError {
                Text(error).font(.caption2).foregroundStyle(Theme.red).lineLimit(3)
            } else if link.pendingTransfers > 0 {
                Text("\(link.pendingTransfers) waiting for iPhone").font(.caption2).foregroundStyle(Theme.softInk)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                TextFieldLink(prompt: Text("Say or scribble a note")) {
                    Image(systemName: "text.bubble").foregroundStyle(.white)
                } onSubmit: { text in
                    capture.sendNote(text)
                }
                .accessibilityLabel("Dictate a note")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Image(systemName: link.isReachable ? "iphone" : "iphone.slash")
                    .foregroundStyle(link.isReachable ? Theme.machineGrey : Theme.red)
                    .overlay(alignment: .topTrailing) {
                        if link.pendingTransfers > 0 {
                            Circle().fill(Theme.orange).frame(width: 6, height: 6)
                        }
                    }
            }
        }
    }
}
