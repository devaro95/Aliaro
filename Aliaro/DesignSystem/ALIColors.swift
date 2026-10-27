import SwiftUI
import UIKit

/// Aliaro's raw pastel palette.
enum ALIPalette {
    // Warm, almost cream background — never pure white, so it feels homey.
    static let creamBackground = Color(hex: 0xFFF9F3)
    static let plumBackground = Color(hex: 0x211E2A)

    static let surfaceLight = Color(hex: 0xFFFFFF)
    static let surfaceDark = Color(hex: 0x2A2635)
    static let surfaceVariantLight = Color(hex: 0xF6EEFB)
    static let surfaceVariantDark = Color(hex: 0x342F42)

    static let inkLight = Color(hex: 0x2E2A38)
    static let inkDark = Color(hex: 0xF6F1FA)
    static let mutedInkLight = Color(hex: 0x7C7488)
    static let mutedInkDark = Color(hex: 0xB6AFC4)

    static let outlineLight = Color(hex: 0xEDE3F5)
    static let outlineDark = Color(hex: 0x3D3850)

    // Pastel accents — the app's "fun" identity.
    static let coral = Color(hex: 0xFFAF9E)     // primary action / shopping list
    static let mint = Color(hex: 0x8FD9C4)      // success / marked as done
    static let lavender = Color(hex: 0xC7B6EC)  // house tasks
    static let sky = Color(hex: 0x9FD3F0)       // family calendar
    static let sun = Color(hex: 0xFFD98E)       // details / highlights
    static let blush = Color(hex: 0xFF8FA3)     // errors / delete
    static let turquoise = Color(hex: 0x4ECDC4) // days with activity on the calendar
    static let rose = Color(hex: 0xFFC1CC)      // people / family group
    static let pistachio = Color(hex: 0xB8D9A0) // finances
    static let apricot = Color(hex: 0xFFC49B)   // recipes
    static let periwinkle = Color(hex: 0xB5C0F5) // board
    static let leaf = Color(hex: 0xA9DFA0)       // places
}

/// Semantic palette, dynamic based on light/dark mode.
enum ALIColors {
    static let background = Color.dynamic(light: ALIPalette.creamBackground, dark: ALIPalette.plumBackground)
    static let surface = Color.dynamic(light: ALIPalette.surfaceLight, dark: ALIPalette.surfaceDark)
    static let surfaceVariant = Color.dynamic(light: ALIPalette.surfaceVariantLight, dark: ALIPalette.surfaceVariantDark)

    static let ink = Color.dynamic(light: ALIPalette.inkLight, dark: ALIPalette.inkDark)
    static let mutedInk = Color.dynamic(light: ALIPalette.mutedInkLight, dark: ALIPalette.mutedInkDark)
    static let outline = Color.dynamic(light: ALIPalette.outlineLight, dark: ALIPalette.outlineDark)

    static let primary = ALIPalette.coral
    static let onPrimary = ALIPalette.inkLight

    static let success = ALIPalette.mint
    static let error = ALIPalette.blush
    static let sun = ALIPalette.sun
    static let onAccent = ALIPalette.inkLight
    static let calendarActivity = ALIPalette.turquoise

    // Pastel identity for each tab.
    static let shoppingAccent = ALIPalette.coral
    static let houseTasksAccent = ALIPalette.lavender
    static let familyAccent = ALIPalette.sky
    static let weeklyMenuAccent = ALIPalette.sun
    static let remindersAccent = ALIPalette.mint
    static let peopleAccent = ALIPalette.rose
    static let economiaAccent = ALIPalette.pistachio
    static let recipesAccent = ALIPalette.apricot
    static let boardAccent = ALIPalette.periwinkle
    static let placesAccent = ALIPalette.leaf

    // Distinguish lunch/dinner at a glance within the weekly menu.
    static let mealLunchAccent = ALIPalette.sun
    static let mealDinnerAccent = ALIPalette.lavender
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(red: r, green: g, blue: b)
    }

    /// Color that automatically switches between light/dark based on the system.
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
        })
    }
}

/// The 30 colors a house task or family event can be tagged with, stored
/// as "RRGGBB" (nil = the section's default accent). Same list on Android.
enum ALIItemColors {
    static let palette: [String] = [
        "FF8FA3", "FFAF9E", "FFC1CC", "F67280", "E85D75", "C06C84",
        "FFC49B", "FFD98E", "F8B259", "F4A261", "E9C46A", "FFE066",
        "B8D9A0", "8FD9C4", "4ECDC4", "6BCB77", "2A9D8F", "A3C4BC",
        "9FD3F0", "5DADE2", "3A86FF", "B5C0F5", "6C8EBF", "264653",
        "C7B6EC", "A78BFA", "8E7DBE", "D291BC", "9D4EDD", "7C7488",
    ]

    /// The stored color, or `fallback` when there's none (or it's invalid).
    static func color(_ hex: String?, fallback: Color) -> Color {
        guard let hex, let value = UInt32(hex, radix: 16) else { return fallback }
        return Color(hex: value)
    }
}

