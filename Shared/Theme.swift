import SwiftUI

/// Distyll house style — shared with Baseline, Notch and Loyal.
/// Graphite surfaces, one signal orange, platform sans for language and mono for measurements.
enum Theme {
    // Graphite stack
    static let graphite = Color(hex: 0x111316)
    static let rail = Color(hex: 0x17191D)
    static let surface = Color(hex: 0x1C1F24)
    static let raised = Color(hex: 0x24282E)
    static let line = Color(hex: 0x343941)

    // Ink
    static let paper = Color(hex: 0xF1F3F5)
    static let softInk = Color(hex: 0xC0C6CE)
    static let machineGrey = Color(hex: 0x8D96A2)

    // Signals — orange marks the current action; the rest are semantic only.
    static let orange = Color(hex: 0xFF5A1F)
    static let blue = Color(hex: 0x5DA9E9)
    static let green = Color(hex: 0x6FD09B)
    static let amber = Color(hex: 0xF1B85B)
    static let red = Color(hex: 0xEF8585)

    /// The icon/background gradient used across Distyll apps.
    static let background = LinearGradient(
        colors: [Color(hex: 0x1F2229), Color(hex: 0x15171B)],
        startPoint: .top,
        endPoint: .bottom
    )

    enum Radius {
        static let tag: CGFloat = 4
        static let control: CGFloat = 10
        static let panel: CGFloat = 14
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

extension TimeInterval {
    /// 75 -> "1:15"
    var clock: String {
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

// MARK: - Components

/// "Wrist." — bold wordmark with the Distyll orange full stop.
struct Wordmark: View {
    var size: CGFloat = 28

    var body: some View {
        (Text("Wrist").foregroundStyle(Theme.paper) + Text(".").foregroundStyle(Theme.orange))
            .font(.system(size: size, weight: .bold))
            .kerning(-size * 0.02)
            .accessibilityLabel("Wrist")
    }
}

/// Spaced mono label for section headings and metadata ("DAILY HABITS", "11 AUG 2026").
struct SectionLabel: View {
    let text: String
    var color: Color = Theme.machineGrey

    init(_ text: String, color: Color = Theme.machineGrey) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .kerning(1.6)
            .foregroundStyle(color)
    }
}

/// Health is a dot plus explicit text — never colour alone.
struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle().fill(color).frame(width: 6, height: 6)
    }
}

/// Faint horizontal rules used behind hero panels in Distyll apps.
struct Scanlines: View {
    var spacing: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(Path(CGRect(x: 0, y: y, width: size.width, height: 1)), with: .color(.white.opacity(0.035)))
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// Flat graphite panel with a one-pixel machine line. Depth comes from tone, not shadow.
    func panel(padding: CGFloat = 16, radius: CGFloat = Theme.Radius.panel) -> some View {
        self
            .padding(padding)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).stroke(Theme.line, lineWidth: 1))
    }
}
