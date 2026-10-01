import SwiftUI
import AppKit

struct ThemeStyle {
    let window: Color
    let card: Color
    let border: Color
    let bar: Color
}

enum Theme: String, CaseIterable, Identifiable {
    case system, light, dark, slate, midnight, nocturne

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        case .slate: return "Slate"
        case .midnight: return "Midnight"
        case .nocturne: return "Nocturne"
        }
    }

    var blurb: String {
        switch self {
        case .system: return "Follows macOS"
        case .light: return "Translucent"
        case .dark: return "Translucent"
        case .slate: return "Solid grey-blue"
        case .midnight: return "Near-black"
        case .nocturne: return "Deep indigo"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark, .slate, .midnight, .nocturne: return NSAppearance(named: .darkAqua)
        }
    }

    /// Opaque themes paint their own background rather than letting the desktop
    /// show through a vibrancy view. `nil` means "use materials".
    var style: ThemeStyle? {
        switch self {
        case .system, .light, .dark:
            return nil
        case .slate:
            return ThemeStyle(
                window: Color(red: 0.072, green: 0.082, blue: 0.100),
                card: Color(red: 0.113, green: 0.126, blue: 0.150),
                border: Color.white.opacity(0.085),
                bar: Color(red: 0.092, green: 0.103, blue: 0.125)
            )
        case .midnight:
            return ThemeStyle(
                window: Color(white: 0.020),
                card: Color(white: 0.075),
                border: Color.white.opacity(0.080),
                bar: Color(white: 0.042)
            )
        case .nocturne:
            return ThemeStyle(
                window: Color(red: 0.047, green: 0.047, blue: 0.086),
                card: Color(red: 0.086, green: 0.086, blue: 0.145),
                border: Color(red: 0.55, green: 0.55, blue: 1.0).opacity(0.14),
                bar: Color(red: 0.063, green: 0.063, blue: 0.113)
            )
        }
    }

    /// Two-tone swatch for the settings picker.
    var preview: (window: Color, card: Color) {
        if let style { return (style.window, style.card) }
        switch self {
        case .light: return (Color(white: 0.92), Color(white: 0.99))
        case .dark: return (Color(white: 0.14), Color(white: 0.22))
        default: return (Color(white: 0.55), Color(white: 0.80))
        }
    }

    var isDark: Bool { self != .light }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = .system
}

extension EnvironmentValues {
    var theme: Theme {
        get { self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
