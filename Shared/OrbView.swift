import SwiftUI

/// The glowing capture button. Breathes when idle, reacts to your voice while recording.
struct OrbView: View {
    var level: Float
    var isActive: Bool
    var symbolSize: CGFloat = 28

    @State private var breathe = false
    @State private var spin = false

    var body: some View {
        let lvl = CGFloat(level)
        ZStack {
            ForEach(0..<3, id: \.self) { ring in
                let r = CGFloat(ring)
                Circle()
                    .stroke(Theme.orb, lineWidth: 1.5)
                    .opacity(isActive ? 0.55 - Double(ring) * 0.15 : 0.18 - Double(ring) * 0.04)
                    .scaleEffect(isActive ? 1.05 + lvl * (0.18 + r * 0.14) + r * 0.08 : (breathe ? 1.06 : 1.0) + r * 0.07)
            }

            Circle()
                .fill(Theme.orb)
                .rotationEffect(.degrees(spin ? 360 : 0))
                .overlay(
                    Circle().fill(
                        RadialGradient(colors: [.white.opacity(0.45), .clear], center: .init(x: 0.35, y: 0.3), startRadius: 0, endRadius: 60)
                    )
                )
                .shadow(color: Theme.rose.opacity(isActive ? 0.9 : 0.5), radius: isActive ? 14 + lvl * 22 : 10)
                .scaleEffect(isActive ? 0.92 + lvl * 0.14 : (breathe ? 1.0 : 0.95))

            Image(systemName: isActive ? "stop.fill" : "waveform")
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.white)
                .contentTransition(.symbolEffect(.replace))
        }
        .animation(.easeOut(duration: 0.12), value: level)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: isActive)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.6).repeatForever(autoreverses: true)) { breathe = true }
            withAnimation(.linear(duration: 14).repeatForever(autoreverses: false)) { spin = true }
        }
        .accessibilityLabel(isActive ? "Stop capture" : "Start capture")
    }
}

/// Compact bar waveform driven by `AudioRecorder.history`.
struct WaveformView: View {
    var levels: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: 3, height: max(3, CGFloat(level) * 28))
            }
        }
        .frame(height: 28)
        .animation(.linear(duration: 0.05), value: levels)
    }
}
