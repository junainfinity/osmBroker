import SwiftUI
import AppKit
import osmBrokerCore

struct Sidebar: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            BrandRow()
                .padding(.horizontal, 8)
                .padding(.top, 4)

            VStack(spacing: 6) {
                ForEach(Pane.allCases) { pane in
                    NavItem(pane: pane,
                            isActive: state.selectedPane == pane,
                            count: count(for: pane))
                }
            }

            Spacer(minLength: 0)

            EndpointCard()
            ThemeSwitcher()
        }
        // Extra top padding so the brand row clears the OS traffic lights.
        // With TopBar removed (see [[Top-Space-Removal]]), the lights now
        // overlay the sidebar's top-left corner directly.
        .padding(.horizontal, 14)
        .padding(.top, 32)
        .padding(.bottom, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.Palette.sidebarSurface)
    }

    private func count(for pane: Pane) -> String {
        switch pane {
        case .cli:
            return String(state.installedAgents.count)
        case .models:
            return String(state.enabledModelCount)
        case .serve:
            return state.brokerRunning ? "LIVE" : "IDLE"
        case .more:
            return String(AgentRegistry.all.count)
        }
    }
}

// MARK: - Brand row (logo + wordmark + tiny tagline)
//
// Logo loading is more involved than it looks. SwiftPM emits a sidecar
// `osmBroker_osmBroker.bundle/` next to the executable; the generated
// `Bundle.module` accessor expects to find it at `Bundle.main.bundleURL.
// appendingPathComponent("osmBroker_osmBroker.bundle")`. That works for
// `swift run` (binary sits next to the sidecar) but our hand-rolled `.app`
// structure puts the binary inside `Contents/MacOS/` and `Bundle.main`
// becomes the .app itself — so the SPM-derived path looks for
// `osmBroker.app/osmBroker_osmBroker.bundle/` which doesn't exist.
//
// Solution: probe several plausible URLs and fall back to a textual mark if
// the PNGs really aren't reachable. Also handled in `Scripts/make-app-bundle.sh`
// which now copies the resource bundle into BOTH Contents/MacOS/ AND
// Contents/Resources/ for maximum cross-version robustness.

private struct BrandRow: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 10) {
            BrandMark(name: colorScheme == .dark ? "osm-mark-dark" : "osm-mark-light")
            VStack(alignment: .leading, spacing: 0) {
                Text("osmBroker")
                    .font(Theme.Typeface.display(22))
                    .tracking(-0.4)
                    .foregroundStyle(Theme.Palette.fg)
                Text("Local AI router")
                    .font(Theme.Typeface.body(11))
                    .foregroundStyle(Theme.Palette.muted)
            }
            Spacer(minLength: 0)
        }
    }
}

/// Tries every plausible bundle location and falls back to a serif "o" if
/// the PNG resource genuinely can't be located.
private struct BrandMark: View {
    let name: String

    var body: some View {
        if let nsImage = Self.loadImage(named: name) {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: 32, height: 32)
                .accessibilityLabel("osmBroker logo")
        } else {
            Text("o")
                .font(Theme.Typeface.display(28, weight: .bold))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 32, height: 32)
                .background(Theme.Palette.accentSoft.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .accessibilityLabel("osmBroker logo (fallback)")
        }
    }

    private static func loadImage(named name: String) -> NSImage? {
        for url in candidateURLs(named: name) {
            if let img = NSImage(contentsOf: url) { return img }
        }
        return nil
    }

    private static func candidateURLs(named name: String) -> [URL] {
        let main = Bundle.main
        let mainURL = main.bundleURL
        var urls: [URL] = []

        // 1) Loose file inside Contents/Resources/ of the .app (most reliable
        //    when our bundle script copied PNGs there directly).
        if let resourceURL = main.url(forResource: name, withExtension: "png") {
            urls.append(resourceURL)
        }

        // 2) SwiftPM's generated Bundle.module — works for `swift run` and
        //    for builds where the sidecar sits next to the executable.
        if let moduleURL = Bundle.module.url(forResource: name, withExtension: "png") {
            urls.append(moduleURL)
        }

        // 3) Hand-search the well-known SPM sidecar paths inside the .app.
        let candidates: [URL] = [
            mainURL.appendingPathComponent("Contents/Resources/osmBroker_osmBroker.bundle/\(name).png"),
            mainURL.appendingPathComponent("Contents/MacOS/osmBroker_osmBroker.bundle/\(name).png"),
            mainURL.appendingPathComponent("osmBroker_osmBroker.bundle/\(name).png"),
            mainURL.deletingLastPathComponent().appendingPathComponent("osmBroker_osmBroker.bundle/\(name).png")
        ]
        urls.append(contentsOf: candidates)
        return urls
    }
}

// MARK: - Nav item

private struct NavItem: View {
    @EnvironmentObject private var state: AppState
    let pane: Pane
    let isActive: Bool
    let count: String

    var body: some View {
        Button {
            state.selectedPane = pane
        } label: {
            HStack(spacing: 10) {
                Image(systemName: pane.sidebarIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 20, alignment: .center)
                    .foregroundStyle(isActive ? Theme.Palette.fg : Theme.Palette.stone)

                Text(pane.sidebarTitle)
                    .font(Theme.Typeface.body(13, weight: isActive ? .semibold : .regular))
                    .foregroundStyle(isActive ? Theme.Palette.fg : Theme.Palette.muted)

                Spacer()

                Text(count)
                    .font(Theme.Typeface.mono(11))
                    .foregroundStyle(Theme.Palette.stone)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(isActive ? Theme.Palette.surface : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous))
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: Theme.Radius.button, style: .continuous)
                        .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Endpoint card (Base URL + API Key with copy buttons)
// Detailed design lives in [[Sidebar-Card-Redesign]].

private struct EndpointCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // STATUS row — replaces the old top-bar status pill.
            cardLabel("STATUS")
            HStack(spacing: 8) {
                PulseDot(color: state.brokerRunning ? Theme.Palette.green : Theme.Palette.silver)
                // `darkText` (#EDE9DB) is always the high-contrast color on the
                // intentionally-dark endpoint card background. `Palette.surface`
                // was wrong here — in dark mode it flips to a dark gray and
                // disappears against the card.
                Text(state.brokerRunning
                     ? "Live · \(state.reachableHost):\(state.port)"
                     : "Idle")
                    .font(Theme.Typeface.body(11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.darkText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.top, 6)

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.vertical, 12)

            cardLabel("BASE URL")

            CopyRow(
                display: "\(state.reachableHost):\(state.port)",
                copyValue: state.baseURL,
                accessibilityLabel: "Copy LAN base URL"
            )
            .padding(.top, 8)

            if state.host == "0.0.0.0" {
                CopyRow(
                    display: "localhost:\(state.port)",
                    copyValue: state.localhostURL,
                    accessibilityLabel: "Copy localhost URL",
                    tone: .muted
                )
                .padding(.top, 4)
            }

            Divider()
                .overlay(Color.white.opacity(0.08))
                .padding(.vertical, 12)

            cardLabel("API KEY")

            CopyRow(
                display: state.apiKey,
                copyValue: state.apiKey,
                accessibilityLabel: "Copy API key"
            )
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Palette.dark)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func cardLabel(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typeface.body(10, weight: .medium))
            .tracking(0.96)
            .foregroundStyle(Theme.Palette.silver)
    }
}

/// One row with a selectable monospace value and a copy button.
/// Used three times in `EndpointCard` (LAN URL, localhost URL, API key).
private struct CopyRow: View {
    enum Tone { case primary, muted }
    let display: String
    let copyValue: String
    let accessibilityLabel: String
    var tone: Tone = .primary
    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            Text(display)
                .font(Theme.Typeface.mono(tone == .primary ? 12 : 11,
                                          weight: tone == .primary ? .semibold : .regular))
                // `darkText` is always the bright value on the dark card,
                // regardless of theme; `surface` would flip dark on us.
                .foregroundStyle(tone == .primary
                                 ? Theme.Palette.darkText
                                 : Theme.Palette.silver)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(copied ? Theme.Palette.green : Theme.Palette.silver)
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .help(accessibilityLabel)
        }
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(copyValue, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copied = false
        }
    }
}

// MARK: - Theme switcher (System / Light / Dark)
// See [[Dark-Mode]] for design.

private struct ThemeSwitcher: View {
    @AppStorage("osmBroker.theme") private var themeRaw: String = AppTheme.system.rawValue

    private var theme: AppTheme {
        AppTheme(rawValue: themeRaw) ?? .system
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTheme.allCases) { option in
                Button {
                    themeRaw = option.rawValue
                } label: {
                    Image(systemName: option.sfSymbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(option == theme ? Theme.Palette.fg : Theme.Palette.stone)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(option == theme ? Theme.Palette.surface : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        .overlay {
                            if option == theme {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
                            }
                        }
                        .help(option.displayName)
                        .accessibilityLabel("\(option.displayName) theme")
                        .accessibilityAddTraits(option == theme ? [.isSelected] : [])
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(Theme.Palette.sidebarSurface)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        }
    }
}
