import SwiftUI
import osmBrokerCore

/// "What AI tools are running on this Mac right now?"
///
/// Phase-1.5 design: one card per installed CLI. No model toggles (those moved
/// to Models tab). No detail panel (was overkill). Empty state with install
/// command pills when nothing is detected. PRD §3.1, §3.2.
struct CLIPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHead(
                    eyebrow: "CLI",
                    title: "AI CLIs detected on this Mac.",
                    lede: "Each CLI installed in your PATH or common toolchain bins becomes an entry the broker can expose. Choose which models to actually serve in the Models tab."
                ) {
                    SecondaryButton(
                        title: state.isScanning ? "Scanning…" : "Rescan",
                        enabled: !state.isScanning
                    ) {
                        Task { await state.refreshDetection() }
                    }
                }

                ScanSummary()

                if let err = state.brokerError {
                    BrokerErrorBanner(message: err,
                                      suggestion: state.portConflictSuggestion)
                }

                if state.installedAgents.isEmpty {
                    EmptyState()
                } else {
                    VStack(spacing: 14) {
                        ForEach(state.installedAgents, id: \.id) { agent in
                            CLICard(agent: agent)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.never)
    }
}

// MARK: - Scan summary pills

private struct ScanSummary: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        let installed = state.installedAgents.count
        let total = state.detectedAgents.count
        let running = state.runningAgents.count

        HStack(spacing: 10) {
            Pill(text: "\(installed) of \(total) installed", variant: installed > 0 ? .ok : .neutral)
            if running > 0 {
                Pill(text: "\(running) currently running", variant: .ok, showDot: true)
            }
            if let when = state.lastScanAt {
                Pill(text: "scanned \(Self.relativeFormatter.localizedString(for: when, relativeTo: Date()))")
            } else {
                Pill(text: "not yet scanned", variant: .warn)
            }
            Spacer()
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()
}

// MARK: - CLI card

private struct CLICard: View {
    @EnvironmentObject private var state: AppState
    let agent: DetectedAgent

    // CLI card — purely informational. The per-CLI ToggleSwitch used to live
    // here but was removed in [[../05-Architecture/CLI-Toggle-Audit]]: it had
    // zero visible feedback, and the Models tab already provides per-model
    // control. Single source of truth wins.
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ProviderMonogram(letters: agent.def.monogram)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.def.name)
                            .font(Theme.Typeface.body(16, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Theme.Palette.fg)
                        Text(agent.def.subtitle)
                            .font(Theme.Typeface.body(12))
                            .foregroundStyle(Theme.Palette.muted)
                    }
                    Spacer(minLength: 0)
                }

                WrapHStack(spacing: 8) {
                    if let path = agent.resolvedPath {
                        Pill(text: prettyHomePath(path))
                    }
                    if let v = agent.version, !v.isEmpty {
                        Pill(text: v)
                    }
                    Pill(text: agent.def.bridge.rawValue)
                    if agent.isRunning {
                        let n = agent.processes.count
                        Pill(
                            text: n == 1 ? "1 process running" : "\(n) processes running",
                            variant: .ok,
                            showDot: true
                        )
                    }
                }

                HStack(spacing: 10) {
                    SecondaryButton(title: "Open in Terminal") {
                        openInTerminal(agent.resolvedPath ?? agent.def.bin)
                    }
                    Spacer()
                }
                .padding(.top, 2)
            }
        }
        .padding(18)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
        }
    }

    /// Lifted from NetworkPane (which is now ServePane). See [[Tab-Structure-v2]]
    /// — Open-in-Terminal is a CLI-level concern, so it lives on the CLI card.
    private func openInTerminal(_ binary: String) {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory
            .appendingPathComponent("osmbroker-launch-\(UUID().uuidString.prefix(8)).command")
        let escaped = binary.replacingOccurrences(of: "\"", with: "\\\"")
        let body = """
        #!/bin/sh
        # Auto-generated by osmBroker; safe to delete.
        exec "\(escaped)"
        """
        do {
            try body.write(to: tmp, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tmp.path)
        } catch { return }

        let opener = Process()
        opener.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        opener.arguments = ["-a", "Terminal", tmp.path]
        try? opener.run()

        DispatchQueue.global().asyncAfter(deadline: .now() + 60) {
            try? fm.removeItem(at: tmp)
        }
    }
}

// MARK: - Empty state

private struct EmptyState: View {
    var body: some View {
        CardSurface(padded: true) {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle(text: "No AI CLIs detected on this Mac yet.")
                Text("osmBroker scans your PATH and common toolchain bin directories. Head over to the More tab to see install commands for the supported set, then click Rescan.")
                    .font(Theme.Typeface.body(13))
                    .foregroundStyle(Theme.Palette.muted)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)

                WrapHStack(spacing: 8) {
                    ForEach(AgentRegistry.all, id: \.id) { def in
                        Pill(text: def.bin)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}
