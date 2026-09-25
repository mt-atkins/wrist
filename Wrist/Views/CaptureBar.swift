import SwiftUI

/// Floating capture control so the phone can record too (handy for testing without a watch).
struct CaptureBar: View {
    @EnvironmentObject private var recorder: AudioRecorder
    @EnvironmentObject private var store: MemoStore
    @State private var error: String?

    var body: some View {
        HStack(spacing: 16) {
            if recorder.isRecording {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        StatusDot(color: Theme.orange)
                        Text(recorder.elapsed.clock)
                            .font(.system(size: 20, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Theme.paper)
                    }
                    WaveformView(levels: recorder.history)
                }
                .transition(.move(edge: .leading).combined(with: .opacity))
                Spacer(minLength: 0)
            }

            Button {
                Task { await toggle() }
            } label: {
                OrbView(level: recorder.level, isActive: recorder.isRecording, symbolSize: 24)
                    .frame(width: 72, height: 72)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, recorder.isRecording ? 20 : 0)
        .padding(.vertical, recorder.isRecording ? 14 : 0)
        .background {
            if recorder.isRecording {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Theme.line))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
        .animation(.spring(response: 0.45, dampingFraction: 0.8), value: recorder.isRecording)
        .alert("Couldn't record", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func toggle() async {
        if recorder.isRecording {
            guard let recording = recorder.stop() else { return }
            guard recording.duration >= 1 else {
                try? FileManager.default.removeItem(at: recording.url)
                return
            }
            store.ingestAudio(at: recording.url, createdAt: recording.startedAt, duration: recording.duration, source: .phone)
        } else {
            guard await recorder.requestPermission() else {
                error = "Allow microphone access for Wrist in Settings."
                return
            }
            do {
                try recorder.start()
            } catch {
                self.error = error.localizedDescription
            }
        }
    }
}
