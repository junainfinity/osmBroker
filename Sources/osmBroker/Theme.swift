import SwiftUI
import AppKit

enum Theme {
    /// Every theme color resolves dynamically against the current
    /// `NSAppearance`, so a single `Theme.Palette.foo` works in both light and
    /// dark mode. See [[Dark-Mode]].
    enum Palette {
        // Backgrounds
        static let background      = dyn(light: 0xF5F4ED, dark: 0x1B1B19)
        static let surface         = dyn(light: 0xFAF9F5, dark: 0x222220)
        static let sidebarSurface  = dyn(light: 0xEFEDE3, dark: 0x16161A)
        static let cardSelected    = dyn(light: 0xFFFDF8, dark: 0x2A2A26)
        static let white           = dyn(light: 0xFFFFFF, dark: 0x2C2C2A)

        // Text
        static let fg              = dyn(light: 0x141413, dark: 0xEDEAE0)
        static let muted           = dyn(light: 0x5E5D59, dark: 0x9F9D96)
        static let stone           = dyn(light: 0x87867F, dark: 0x736E5C)
        static let silver          = dyn(light: 0xB0AEA5, dark: 0xB0AEA5)

        // Borders
        static let border          = dyn(light: 0xF0EEE6, dark: 0x2F2F2C)
        static let borderStrong    = dyn(light: 0xE8E6DC, dark: 0x3A3A36)
        static let ring            = dyn(light: 0xD1CFC5, dark: 0x3D3D38)

        // Accent
        static let accent          = dyn(light: 0xC96442, dark: 0xD78060)
        static let accentSoft      = dyn(light: 0xF2D8CC, dark: 0x3D2820)

        // Dark "code block" surface — even darker in dark mode for separation.
        static let dark            = dyn(light: 0x30302E, dark: 0x0F0F0E)
        static let darkText        = staticHex(0xEDE9DB)
        static let darkKey         = staticHex(0xF1B099)
        static let darkString      = staticHex(0xD9D2B7)

        // Status
        static let green           = dyn(light: 0x3F7B56, dark: 0x62A57F)
        static let amber           = dyn(light: 0x9F6B24, dark: 0xD49B4F)
        static let red             = dyn(light: 0xB53333, dark: 0xE66060)

        // Secondary button (cream-on-cream → warm-on-warm)
        static let secondaryBg     = dyn(light: 0xE8E6DC, dark: 0x3A3A36)
        static let secondaryFg     = dyn(light: 0x4D4C48, dark: 0xD2CFC4)

        // MARK: - helpers

        private static func staticHex(_ rgb: UInt32) -> Color {
            Color(
                .sRGB,
                red:   Double((rgb >> 16) & 0xFF) / 255,
                green: Double((rgb >>  8) & 0xFF) / 255,
                blue:  Double( rgb        & 0xFF) / 255,
                opacity: 1
            )
        }

        /// Returns a SwiftUI `Color` whose underlying NSColor flips between
        /// the two values when the system appearance changes.
        private static func dyn(light: UInt32, dark: UInt32) -> Color {
            let lightNS = nsColor(from: light)
            let darkNS  = nsColor(from: dark)
            return Color(nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [
                    .darkAqua,
                    .vibrantDark,
                    .accessibilityHighContrastDarkAqua,
                    .accessibilityHighContrastVibrantDark
                ]) != nil
                return isDark ? darkNS : lightNS
            })
        }

        private static func nsColor(from rgb: UInt32) -> NSColor {
            NSColor(
                srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255,
                green:   CGFloat((rgb >>  8) & 0xFF) / 255,
                blue:    CGFloat( rgb        & 0xFF) / 255,
                alpha: 1
            )
        }
    }

    enum Typeface {
        /// Georgia for display, mirroring `--font-display` in the CSS.
        static func display(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
            .custom("Georgia", size: size).weight(weight)
        }

        /// SF Mono via system monospaced design.
        static func mono(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight, design: .monospaced)
        }

        /// Body sans, mirroring `--font-body`.
        static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }
    }

    enum Radius {
        static let pill: CGFloat   = 999
        static let card: CGFloat   = 16
        static let inner: CGFloat  = 12
        static let chunk: CGFloat  = 14
        static let button: CGFloat = 10
        static let window: CGFloat = 22
    }
}

/// Persistent user choice for light/dark/system. Read by `ContentView` to set
/// `.preferredColorScheme`. See [[Dark-Mode]].
enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var sfSymbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light:  return "sun.max"
        case .dark:   return "moon"
        }
    }

    var preferredScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}
