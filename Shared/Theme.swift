import SwiftUI

enum Theme {
    static let ember = Color(red: 1.00, green: 0.48, blue: 0.22)
    static let rose = Color(red: 1.00, green: 0.24, blue: 0.47)
    static let violet = Color(red: 0.52, green: 0.32, blue: 1.00)
    static let ink = Color(red: 0.05, green: 0.04, blue: 0.08)
    static let card = Color.white.opacity(0.06)
    static let hairline = Color.white.opacity(0.08)

    static let orb = AngularGradient(
        colors: [ember, rose, violet, rose, ember],
        center: .center
    )
    static let accent = LinearGradient(colors: [ember, rose], startPoint: .leading, endPoint: .trailing)
    static let background = LinearGradient(
        colors: [Color(red: 0.10, green: 0.05, blue: 0.12), ink, .black],
        startPoint: .top,
        endPoint: .bottom
    )
}

extension TimeInterval {
    /// 75 -> "1:15"
    var clock: String {
        let total = Int(self.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
