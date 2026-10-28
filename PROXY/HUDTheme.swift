import SwiftUI

/// Scandinavian automotive luxury HUD themes inspired by Volvo digital instrument clusters.
enum HUDThemePreset: String, CaseIterable, Identifiable {
    case ice = "Ice"       // Cool Volvo blue accent (default)
    case bloom = "Bloom"   // Soft candy pink accent
    case mint = "Mint"     // Fresh mint green accent
    case ember = "Ember"   // Warm amber accent

    var id: String { rawValue }
}

struct HUDTheme {
    let preset: HUDThemePreset
    let accent: Color
    let accentSoft: Color
    let warning: Color
    let text: Color
    let textSecondary: Color
    let glassTint: Color

    static func theme(for preset: HUDThemePreset, prestige: Int = 0) -> HUDTheme {
        let base: HUDTheme
        switch preset {
        case .ice:
            base = HUDTheme(
                preset: .ice,
                accent: Color(red: 0.40, green: 0.72, blue: 0.96),       // Volvo luminous ice cyan/blue
                accentSoft: Color(red: 0.40, green: 0.72, blue: 0.96).opacity(0.30),
                warning: Color(red: 0.98, green: 0.48, blue: 0.42),      // Soft coral
                text: Color.white,
                textSecondary: Color.white.opacity(0.68),
                glassTint: Color.white.opacity(0.06)
            )
        case .bloom:
            base = HUDTheme(
                preset: .bloom,
                accent: Color(red: 0.96, green: 0.50, blue: 0.70),       // Soft candy pink
                accentSoft: Color(red: 0.96, green: 0.50, blue: 0.70).opacity(0.30),
                warning: Color(red: 0.98, green: 0.48, blue: 0.42),
                text: Color.white,
                textSecondary: Color.white.opacity(0.68),
                glassTint: Color.white.opacity(0.06)
            )
        case .mint:
            base = HUDTheme(
                preset: .mint,
                accent: Color(red: 0.38, green: 0.88, blue: 0.65),       // Fresh mint green
                accentSoft: Color(red: 0.38, green: 0.88, blue: 0.65).opacity(0.30),
                warning: Color(red: 0.98, green: 0.48, blue: 0.42),
                text: Color.white,
                textSecondary: Color.white.opacity(0.68),
                glassTint: Color.white.opacity(0.06)
            )
        case .ember:
            base = HUDTheme(
                preset: .ember,
                accent: Color(red: 0.98, green: 0.68, blue: 0.28),       // Warm amber
                accentSoft: Color(red: 0.98, green: 0.68, blue: 0.28).opacity(0.30),
                warning: Color(red: 0.98, green: 0.48, blue: 0.42),
                text: Color.white,
                textSecondary: Color.white.opacity(0.68),
                glassTint: Color.white.opacity(0.06)
            )
        }

        // Prestige desaturation: calm automotive drains into high-contrast military thermal
        if prestige == 1 {
            return HUDTheme(
                preset: preset,
                accent: base.accent.opacity(0.85),
                accentSoft: base.accentSoft.opacity(0.6),
                warning: base.warning,
                text: base.text,
                textSecondary: base.textSecondary.opacity(0.8),
                glassTint: Color.white.opacity(0.04)
            )
        } else if prestige == 2 {
            return HUDTheme(
                preset: preset,
                accent: Color(white: 0.86),
                accentSoft: Color(white: 0.55).opacity(0.28),
                warning: Color(red: 0.95, green: 0.52, blue: 0.45),
                text: Color.white,
                textSecondary: Color.white.opacity(0.62),
                glassTint: Color.black.opacity(0.20)
            )
        } else if prestige >= 3 {
            // White-hot FLIR thermal (monochrome, high-contrast)
            return HUDTheme(
                preset: preset,
                accent: Color.white,
                accentSoft: Color.white.opacity(0.40),
                warning: Color.white,
                text: Color.white,
                textSecondary: Color.white.opacity(0.80),
                glassTint: Color.black.opacity(0.40)
            )
        }
        return base
    }
}
