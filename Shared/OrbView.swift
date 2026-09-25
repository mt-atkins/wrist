import SwiftUI

/// The capture button: a flat Distyll-orange disc inside concentric machine-line rings.
/// Idle it breathes gently; while recording the rings pick up your voice.
struct OrbView: View {
    var level: Float
    var isActive: Bool
    var symbolSize: CGFloat = 28

    @State private var breathe = false

    var body: some View {
        let lvl = CGFloat(level)
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                let r = CGFloat(ring)
                Circle()
                    .stroke(isActive ? Theme.orange : Theme.line, lineWidth: 1)
                    .opacity(isActive ? 0.7 - Double(ring) * 0.2 : 1 - Double(ring) * 0.25)
                    .scaleEffect(1.12 + r * 0.14 + (isActive ? lvl * (0.1 + r * 0.08) : 0))
            }

            Circle()
                .fill(Theme.orange)
                .shadow(color: Theme.orange.opacity(isActive ? 0.55 : 0.25), radius: isActive ? 8 + lvl * 16 : 6)
                .scaleEffect(isActive ? 0.94 + lvl * 0.1 : (breathe ? 1.0 : 0.96))

            Image(systemName: isActive ? "stop.fill" : "waveform")
                .font(.system(size: symbolSize, weight: .bold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: isActive)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
        }
        .accessibilityLabel(isActive ? "Stop capture" : "Start capture")
    }
}

/// Compact bar waveform driven by `AudioRecorder.history`.
struct WaveformView: View {
    var levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                Capsule()
                    .fill(index == levels.count - 1 ? Theme.orange : Theme.paper.opacity(0.85))
                    .frame(width: 3, height: max(3, CGFloat(level) * 28))
            }
        }
        .frame(height: 28)
        .animation(.linear(duration: 0.05), value: levels)
    }
}
