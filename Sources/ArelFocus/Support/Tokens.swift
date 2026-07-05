import SwiftUI

// Mirrors agents/DESIGN.md frontmatter. DESIGN.md is the source of truth;
// this file restates it for Swift. Keep them in sync by hand.

enum Space {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 20
    static let xl: CGFloat = 32
}

enum Radius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 10
    static let lg: CGFloat = 14
}

enum Elevation {
    static let card = ShadowToken(y: 1, blur: 2, opacity: 0.04)
    static let hero = ShadowToken(y: 2, blur: 8, opacity: 0.06)
}

struct ShadowToken {
    var y: CGFloat
    var blur: CGFloat
    var opacity: Double
}

extension View {
    func arelShadow(_ token: ShadowToken) -> some View {
        shadow(color: Color.black.opacity(token.opacity), radius: token.blur, x: 0, y: token.y)
    }
}

enum Gradients {
    static let heroBackground = LinearGradient(
        colors: [Palette.primary.opacity(0.10), Palette.secondary.opacity(0.06)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    static let accentMetric = LinearGradient(
        colors: [Palette.primary.opacity(0.18), Palette.primary.opacity(0.04)],
        startPoint: .top,
        endPoint: .bottom
    )
    static func projectBar(_ color: Color) -> LinearGradient {
        LinearGradient(
            colors: [color.opacity(0.95), color.opacity(0.55)],
            startPoint: .leading,
            endPoint: .trailing
        )
    }
}

enum Palette {
    static let primary   = Color(lightHex: "#2F6FED", darkHex: "#5B8DEF")
    static let secondary = Color(lightHex: "#21A67A", darkHex: "#3DC093")
    static let muted     = Color(lightHex: "#6B7280", darkHex: "#9BA3AD")
    static let border    = Color(lightHex: "#D6D8DC", darkHex: "#33363B")
}

enum AppFont {
    static let title    = Font.system(size: 17, weight: .semibold)
    static let section  = Font.system(size: 11, weight: .semibold).smallCaps()
    static let body     = Font.system(size: 13)
    static let bodyStrong = Font.system(size: 13, weight: .medium)
    static let caption  = Font.system(size: 11)
    static let metric   = Font.system(size: 22, weight: .semibold).monospacedDigit()
}
