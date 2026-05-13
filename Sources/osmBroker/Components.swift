import SwiftUI

// MARK: - Card surface

struct CardSurface<Content: View>: View {
    var padded: Bool = false
    var background: Color = Theme.Palette.surface
    var stroke: Color = Theme.Palette.borderStrong
    var corner: CGFloat = Theme.Radius.card
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .padding(padded ? 18 : 0)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: corner, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            }
    }
}

// MARK: - Pill (status + metric)

struct Pill: View {
    enum Variant { case neutral, ok, warn, bad }

    let text: String
    var variant: Variant = .neutral
    var showDot: Bool = false

    private var fg: Color {
        switch variant {
        case .neutral: return Theme.Palette.muted
        case .ok:      return Theme.Palette.green
        case .warn:    return Theme.Palette.amber
        case .bad:     return Theme.Palette.red
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            if showDot {
                Circle().fill(fg).frame(width: 6, height: 6)
            }
            Text(text)
                .font(Theme.Typeface.mono(12))
                .foregroundStyle(fg)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.Palette.white)
        .clipShape(Capsule())
        .overlay {
            Capsule().strokeBorder(Theme.Palette.border, lineWidth: 1)
        }
    }
}

// MARK: - Toggle switch (HTML look — 42x24, sliding 20x20 handle)

struct ToggleSwitch: View {
    @Binding var isOn: Bool
    var label: String = ""

    var body: some View {
        Button {
            isOn.toggle()
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(trackColor)
                    .overlay {
                        Capsule()
                            .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
                    }
                    .frame(width: 42, height: 24)

                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.18), radius: 1.5, y: 1)
                    .padding(.horizontal, 2)
            }
            .animation(.easeInOut(duration: 0.16), value: isOn)
            .accessibilityLabel(label.isEmpty ? "Toggle" : label)
            .accessibilityValue(isOn ? "On" : "Off")
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var trackColor: Color {
        // CSS uses color-mix(border-strong + green @ 65%) when on.
        if isOn {
            return Theme.Palette.green.opacity(0.78)
        } else {
            return Theme.Palette.borderStrong
        }
    }
}

// MARK: - Buttons

struct PrimaryButton: View {
    let title: String
    var enabled: Bool = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typeface.body(13, weight: .medium))
                .foregroundStyle(Theme.Palette.surface)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(enabled ? Theme.Palette.accent : Theme.Palette.stone)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

struct SecondaryButton: View {
    let title: String
    var enabled: Bool = true
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typeface.body(13, weight: .medium))
                .foregroundStyle(Theme.Palette.secondaryFg)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.Palette.secondaryBg.opacity(enabled ? 1.0 : 0.5))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// White button with 1px ring — used in the toolbar group and in install rows.
struct GhostButton: View {
    let title: String
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typeface.body(13, weight: .medium))
                .foregroundStyle(Theme.Palette.fg)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Theme.Palette.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
    }
}

/// Toolbar — a rounded container that wraps a small set of buttons, like the HTML's `.toolbar`.
struct ToolbarGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 8) { content() }
            .padding(6)
            .background(Theme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chunk, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.chunk, style: .continuous)
                    .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
            }
    }
}

// MARK: - Eyebrow / heading helpers

struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(Theme.Typeface.body(11, weight: .semibold))
            .tracking(0.88)
            .foregroundStyle(Theme.Palette.accent)
    }
}

struct SectionTitle: View {
    let text: String
    var size: CGFloat = 25
    var body: some View {
        Text(text)
            .font(Theme.Typeface.display(size))
            .tracking(-0.5)
            .foregroundStyle(Theme.Palette.fg)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct DisplayTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.Typeface.display(44))
            .tracking(-1.2)
            .foregroundStyle(Theme.Palette.fg)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct Lede: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.Typeface.body(15))
            .lineSpacing(4)
            .foregroundStyle(Theme.Palette.muted)
            .frame(maxWidth: 520, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Dark JSON-ish code block (key:value lines, syntax-tinted)

struct DarkCodeBlock: View {
    struct Line: Identifiable {
        let id = UUID()
        let key: String
        let value: AttributedString
    }
    let lines: [Line]

    init(_ entries: [(String, CodeValue)]) {
        self.lines = entries.map { key, value in
            Line(key: key, value: value.attributed)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(lines) { line in
                (
                    Text(line.key)
                        .foregroundStyle(Theme.Palette.darkKey)
                    + Text(": ")
                        .foregroundStyle(Theme.Palette.darkText)
                    + Text(line.value)
                )
                .font(Theme.Typeface.mono(12))
                .foregroundStyle(Theme.Palette.darkText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Palette.dark)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
    }
}

/// Discriminator so we can render strings vs. numbers vs. lists vs. raw mono words.
enum CodeValue {
    case string(String)
    case number(Int)
    case list([String])
    /// Already-formed AttributedString; pass through unchanged.
    case raw(AttributedString)

    var attributed: AttributedString {
        switch self {
        case .string(let s):
            var a = AttributedString("\"\(s)\"")
            a.foregroundColor = Theme.Palette.darkString
            return a
        case .number(let n):
            var a = AttributedString(String(n))
            a.foregroundColor = Theme.Palette.darkText
            return a
        case .list(let xs):
            var out = AttributedString("[")
            out.foregroundColor = Theme.Palette.darkText
            for (i, s) in xs.enumerated() {
                var item = AttributedString("\"\(s)\"")
                item.foregroundColor = Theme.Palette.darkString
                out += item
                if i < xs.count - 1 {
                    var sep = AttributedString(", ")
                    sep.foregroundColor = Theme.Palette.darkText
                    out += sep
                }
            }
            var close = AttributedString("]")
            close.foregroundColor = Theme.Palette.darkText
            out += close
            return out
        case .raw(let a):
            return a
        }
    }
}

// MARK: - Provider icon (rounded square with monogram in serif)

struct ProviderMonogram: View {
    let letters: String
    var body: some View {
        Text(letters)
            .font(Theme.Typeface.display(15, weight: .semibold))
            .foregroundStyle(Theme.Palette.fg)
            .frame(width: 42, height: 42)
            .background(Theme.Palette.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                    .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
            }
    }
}

// MARK: - Pulse dot (sidebar status / titlebar status)

struct PulseDot: View {
    var color: Color = Theme.Palette.green
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                Circle().stroke(color.opacity(0.18), lineWidth: 4)
            }
    }
}
