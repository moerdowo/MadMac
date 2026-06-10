import SwiftUI

// Mayar design-system tokens, ported from colors_and_type.css + the prototype's
// light/dark overrides. Every view reads colors through Theme so dark mode and
// the accent tweak cascade everywhere.

enum AccentChoice: String, CaseIterable, Identifiable {
    case blue = "Blue", magenta = "Magenta", emerald = "Emerald", violet = "Violet"
    var id: String { rawValue }
    var color: Color {
        switch self {
        case .blue: return Color(hex: 0x2D3DEC)
        case .magenta: return Color(hex: 0xE91E78)
        case .emerald: return Color(hex: 0x1FB36B)
        case .violet: return Color(hex: 0x7A5AE0)
        }
    }
}

enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system = "System", light = "Light", dark = "Dark"
    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum DashLayout: String, CaseIterable, Identifiable {
    case overview = "Overview", spotlight = "Spotlight", table = "Table"
    var id: String { rawValue }
}

enum Density: String, CaseIterable, Identifiable {
    case compact = "Compact", regular = "Regular", comfy = "Comfy"
    var id: String { rawValue }
    var padV: CGFloat { self == .compact ? 22 : self == .comfy ? 34 : 28 }
    var padH: CGFloat { self == .compact ? 24 : self == .comfy ? 40 : 32 }
}

struct Theme {
    let dark: Bool
    let accent: Color

    // ── surfaces ──
    var bg1: Color { dark ? Color(hex: 0x1B1C26) : .white }
    var bg2: Color { dark ? Color(hex: 0x131420) : Color(hex: 0xF8F9FC) }
    var bg3: Color { dark ? Color(hex: 0x262835) : Color(hex: 0xF1F3F9) }
    var bg4: Color { dark ? Color(hex: 0x393C50) : Color(hex: 0xE6E9F2) }
    var sidebar: Color { dark ? Color(hex: 0x15161F) : Color(hex: 0xEDF0F7) }

    // ── text ──
    var fg1: Color { dark ? Color(hex: 0xF2F3F8) : Color(hex: 0x0E0F1A) }
    var fg2: Color { dark ? Color(hex: 0xC3C7D8) : Color(hex: 0x3F4357) }
    var fg3: Color { dark ? Color(hex: 0x8E93AB) : Color(hex: 0x6B7088) }
    var fg4: Color { dark ? Color(hex: 0x646A85) : Color(hex: 0x9AA0B4) }

    var border: Color { dark ? Color.white.opacity(0.09) : Color(hex: 0x0E0F1A).opacity(0.08) }
    var borderStrong: Color { dark ? Color.white.opacity(0.17) : Color(hex: 0x0E0F1A).opacity(0.14) }

    // ── semantic ──
    var success: Color { Color(hex: 0x1FB36B) }
    var warning: Color { Color(hex: 0xF4A52A) }
    var danger: Color { Color(hex: 0xE5484D) }
    var brandBlue: Color { Color(hex: 0x2D3DEC) }
    var brandMagenta: Color { Color(hex: 0xE91E78) }

    var success100: Color { dark ? success.opacity(0.20) : Color(hex: 0xE5F7EE) }
    var warning100: Color { dark ? warning.opacity(0.20) : Color(hex: 0xFFF6E5) }
    var danger100: Color { dark ? danger.opacity(0.20) : Color(hex: 0xFCEBEC) }
    var brandBlue100: Color { dark ? brandBlue.opacity(0.26) : Color(hex: 0xEEF1FF) }

    var accentSoft: Color { accent.opacity(0.12) }
    var accentRing: Color { accent.opacity(0.22) }

    var shadowColor: Color { Color(hex: 0x0E0F1A).opacity(dark ? 0.4 : 0.07) }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue = Theme(dark: false, accent: AccentChoice.blue.color)
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

// Plus Jakarta Sans (bundled variable font registers its named instances).
func jakarta(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    let name: String
    switch weight {
    case .heavy, .black: name = "PlusJakartaSans-ExtraBold"
    case .bold: name = "PlusJakartaSans-Bold"
    case .semibold: name = "PlusJakartaSans-SemiBold"
    case .medium: name = "PlusJakartaSans-Medium"
    case .light: name = "PlusJakartaSans-Light"
    default: name = "PlusJakartaSans-Regular"
    }
    return .custom(name, size: size)
}

extension Font.Weight {
    static let extra = Font.Weight.heavy   // design's 800
}
