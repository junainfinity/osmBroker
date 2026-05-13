# Dark mode

## What the user asked

> add a toggle for dark and light mode for app and redesign accordingly.

## Scope

Three-position scheme: **System** (follow macOS), **Light**, **Dark**. Persists across launches. Toggle lives in the sidebar — small icon row at the bottom, just under the endpoint card.

## Where colors live today

Every visual decision in the app references `Theme.Palette.<name>`. The struct exposes 18-ish static `Color` constants — every one currently a *fixed* sRGB value (the warm cream palette from the HTML prototype). To support dark mode we need each `Color` to resolve differently based on the current `NSAppearance`.

## Two ways to do dynamic colors on macOS

1. **`Color(NSColor(name:dynamicProvider:))`** — Apple's official dynamic color API. The provider closure runs on every appearance change and returns the right `NSColor`. Composes cleanly with SwiftUI.
2. **`@Environment(\.colorScheme)` everywhere** — pull `.dark/.light` into each view and pick a color. Lots of repetition.

Option 1 is what we're doing. One helper:

```swift
extension Color {
    static func dynamic(light: Color, dark: Color) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(
                from: [.darkAqua, .vibrantDark,
                       .accessibilityHighContrastDarkAqua,
                       .accessibilityHighContrastVibrantDark]
            ) != nil
            return NSColor(isDark ? dark : light)
        })
    }
}
```

Then every `Theme.Palette` constant becomes `Color.dynamic(light: …, dark: …)`.

## Dark palette design

The light palette is warm cream + serif character. The dark palette mirrors that: warm dark grays (not pure black) + the same accent rust + cream-ish text.

| Token | Light (today) | Dark (new) | Rationale |
|---|---|---|---|
| `background`      | `#F5F4ED` | `#1B1B19` | Warm "paper" black, not pure |
| `surface`         | `#FAF9F5` | `#222220` | One step up from background for cards |
| `sidebarSurface`  | `#EFEDE3` | `#16161A` | Slightly darker than surface to recede |
| `cardSelected`    | `#FFFDF8` | `#2A2A26` | Selected provider card |
| `white`           | `#FFFFFF` | `#2C2C2A` | Pure-white surfaces flip to a slightly-lighter inner card |
| `fg`              | `#141413` | `#EDEAE0` | High-contrast text |
| `muted`           | `#5E5D59` | `#9F9D96` | Tagline / lede / muted body |
| `stone`           | `#87867F` | `#736E5C` | Stone-gray glyphs |
| `silver`          | `#B0AEA5` | `#B0AEA5` | Stays — used on dark backgrounds either way |
| `border`          | `#F0EEE6` | `#2F2F2C` | Subtle 1-px rings on white-ish cards |
| `borderStrong`    | `#E8E6DC` | `#3A3A36` | Stronger card borders |
| `accent`          | `#C96442` | `#D78060` | Slightly brighter rust for dark surfaces |
| `accentSoft`      | `#F2D8CC` | `#3D2820` | Used behind PRIMARY badges + error banners |
| `dark`            | `#30302E` | `#0F0F0E` | The dark "code block" surface — even darker in dark mode |
| `darkText`        | `#EDE9DB` | `#EDE9DB` | Stays — already designed for dark |
| `darkKey`         | `#F1B099` | `#F1B099` | JSON key color in dark blocks — stays |
| `darkString`      | `#D9D2B7` | `#D9D2B7` | JSON string color — stays |
| `green`           | `#3F7B56` | `#62A57F` | Status / "OK" pills — brighter for dark |
| `amber`           | `#9F6B24` | `#D49B4F` | Warning pills — brighter for dark |
| `red`             | `#B53333` | `#E66060` | Error pills — brighter for dark |
| `secondaryBg`     | `#E8E6DC` | `#3A3A36` | Ghost / secondary button bg |
| `secondaryFg`     | `#4D4C48` | `#D2CFC4` | Ghost / secondary button text |
| `ring`            | `#D1CFC5` | `#3D3D38` | Card-ring 1-px hairline |

## Persistence

```swift
@AppStorage("osmBroker.theme") private var theme: AppTheme = .system

enum AppTheme: String, CaseIterable {
    case system, light, dark
}
```

Maps to `.preferredColorScheme`:
- `.system` → `nil` (follow OS)
- `.light`  → `.light`
- `.dark`   → `.dark`

## UI placement

A tiny three-button segmented control under the endpoint card in the sidebar:

```
[ 􀆦  System ]  [ 􀆫  Light ]  [ 􀆭  Dark ]
```

Single line. Active option gets the accent ring. Persisted via `@AppStorage`. Reads as a thin row, not a big distracting toggle.

## What COULD'VE gone wrong (and didn't)

- **Re-rendering on appearance change.** `NSColor`'s dynamic provider fires automatically; SwiftUI views observing `Color` redraw. No manual `@Environment` subscription needed.
- **Asset bundle.** The logo PNGs are static for now. We ship a dark-mode variant (`osm-mark-dark.png`) but it doesn't kick in until step 2's `BrandRow` reads `Environment(\.colorScheme)` (already does — implemented earlier).
- **Test target colors.** Tests don't touch colors, so no test refactor needed.

## Cross-refs

- [[Logo-Branding]] — dark/light mark variants both shipped, BrandRow picks
- [[Sidebar-Card-Redesign]] — endpoint card colors flip automatically
- [[Theme]] *(file in `Sources/osmBroker/Theme.swift`)* — the change is centralised here
