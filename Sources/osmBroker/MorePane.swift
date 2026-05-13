import SwiftUI
import osmBrokerCore

/// PRD §3.3 — Discovery & Marketplace tab.
///
/// Phase-1 shape:
/// - Search/filter field across the registry of supported CLIs.
/// - Grid of cards, one per CLI, with subtitle + install command + install URL.
/// - "Copy install command" action — the on-ramp to getting a CLI installed.
///
/// Future (Phase 2/3):
/// - Fetch a remote curated JSON registry for fresher entries.
/// - Deep integration descriptions for marquee CLIs (Kimi ACP, Perplexity RAG,
///   DeepSeek context caching) — see PRD §3.3 bullets.
struct MorePane: View {
    @EnvironmentObject private var state: AppState
    @State private var query: String = ""

    private var filtered: [AgentDef] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return AgentRegistry.all }
        return AgentRegistry.all.filter {
            $0.name.lowercased().contains(q) ||
            $0.id.lowercased().contains(q) ||
            $0.subtitle.lowercased().contains(q) ||
            $0.bin.lowercased().contains(q)
        }
    }

    private var installedDefs: [AgentDef] {
        filtered.filter { isInstalled($0.id) }
    }
    private var availableDefs: [AgentDef] {
        filtered.filter { !isInstalled($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHead(
                    eyebrow: "More",
                    title: "Add more AI CLIs.",
                    lede: "Browse every CLI osmBroker can broker. Installed ones are pinned at the top; the rest each come with a one-line install command you can copy."
                ) {
                    EmptyView()
                }

                SearchField(text: $query)

                if filtered.isEmpty {
                    EmptyResults(query: query)
                } else {
                    if !installedDefs.isEmpty {
                        SectionHeader(title: "Installed on this Mac",
                                      count: installedDefs.count)
                        registryGrid(installedDefs)
                    }
                    if !availableDefs.isEmpty {
                        SectionHeader(title: "Available CLIs",
                                      count: availableDefs.count)
                            .padding(.top, installedDefs.isEmpty ? 0 : 4)
                        registryGrid(availableDefs)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.never)
    }

    private func isInstalled(_ id: String) -> Bool {
        state.detectedAgents.first { $0.id == id }?.isInstalled ?? false
    }

    @ViewBuilder
    private func registryGrid(_ defs: [AgentDef]) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 14),
                GridItem(.flexible(), spacing: 14)
            ],
            spacing: 14
        ) {
            ForEach(defs, id: \.id) { def in
                RegistryCard(def: def, installed: isInstalled(def.id))
            }
        }
    }
}

/// Section heading used between the "Installed" and "Available" grids.
private struct SectionHeader: View {
    let title: String
    let count: Int
    var body: some View {
        HStack {
            Text(title)
                .font(Theme.Typeface.display(20))
                .tracking(-0.4)
                .foregroundStyle(Theme.Palette.fg)
            Spacer()
            Text("\(count)")
                .font(Theme.Typeface.mono(12))
                .foregroundStyle(Theme.Palette.stone)
        }
    }
}

// MARK: - Search field

private struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.Palette.stone)
            TextField("Search CLIs…", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typeface.body(14))
                .foregroundStyle(Theme.Palette.fg)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(Theme.Palette.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
        }
    }
}

// MARK: - Registry card

private struct RegistryCard: View {
    let def: AgentDef
    let installed: Bool
    @State private var copied = false

    var body: some View {
        CardSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    ProviderMonogram(letters: def.monogram)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(def.name)
                                .font(Theme.Typeface.body(16, weight: .semibold))
                                .tracking(-0.2)
                                .foregroundStyle(Theme.Palette.fg)
                            if installed {
                                Pill(text: "installed", variant: .ok, showDot: true)
                            }
                        }
                        Text(def.subtitle)
                            .font(Theme.Typeface.body(12))
                            .foregroundStyle(Theme.Palette.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                metricsRow

                if let cmd = def.installCommand {
                    InstallCommand(command: cmd, copied: $copied)
                } else if let url = def.installURL {
                    HStack {
                        Text("Install instructions:")
                            .font(Theme.Typeface.body(12))
                            .foregroundStyle(Theme.Palette.muted)
                        Link(destination: URL(string: url)!) {
                            Text(url)
                                .font(Theme.Typeface.mono(12))
                                .foregroundStyle(Theme.Palette.accent)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                } else {
                    Text("No install command available.")
                        .font(Theme.Typeface.body(12))
                        .foregroundStyle(Theme.Palette.stone)
                }
            }
            .padding(16)
        }
    }

    private var metricsRow: some View {
        WrapHStack(spacing: 8) {
            Pill(text: def.bin)
            Pill(text: def.bridge.rawValue)
            Pill(text: "native: \(def.nativeProtocol.rawValue)")
        }
    }
}

private struct InstallCommand: View {
    let command: String
    @Binding var copied: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(command)
                .font(Theme.Typeface.mono(12))
                .foregroundStyle(Theme.Palette.darkText)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(command, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copied = false
                }
            } label: {
                Text(copied ? "Copied" : "Copy")
                    .font(Theme.Typeface.body(12, weight: .medium))
                    .foregroundStyle(Theme.Palette.darkText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.1))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Theme.Palette.dark)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
    }
}

// MARK: - Empty results

private struct EmptyResults: View {
    let query: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("No matches for \"\(query)\"")
                .font(Theme.Typeface.body(14, weight: .semibold))
                .foregroundStyle(Theme.Palette.fg)
            Text("The registry has \(AgentRegistry.all.count) CLIs. Try \"claude\", \"kimi\", or a binary name.")
                .font(Theme.Typeface.body(12))
                .foregroundStyle(Theme.Palette.muted)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
        }
    }
}
