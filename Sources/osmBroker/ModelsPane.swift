import SwiftUI
import osmBrokerCore

/// "Which specific models do I want this Mac to serve?"
///
/// Per-CLI section. Each section lists the union of discovered (from the
/// CLI's own config) and registry-fallback models. Discovered ones sort first
/// and carry a "primary" badge when they match `state.primaryModel[agent.id]`.
/// See [[Model-Discovery]] and [[Tab-Structure-v2]].
struct ModelsPane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHead(
                    eyebrow: "Models",
                    title: "Choose what to serve.",
                    lede: "Models discovered from each CLI's own config sort first; the registry's known-supported set follows. Only models you toggle on appear in `/v1/models` and accept inference requests."
                ) {
                    SecondaryButton(
                        title: state.isScanning ? "Rescanning…" : "Rescan",
                        enabled: !state.isScanning
                    ) {
                        Task { await state.refreshDetection() }
                    }
                }

                EnabledSummary()

                if state.installedAgents.isEmpty {
                    NothingToConfigureCard()
                } else {
                    VStack(spacing: 14) {
                        ForEach(state.installedAgents, id: \.id) { agent in
                            AgentModelsCard(agent: agent)
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

private struct EnabledSummary: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        HStack(spacing: 10) {
            let total = state.allModels.count
            let on = state.enabledModelCount
            Pill(text: "\(on) of \(total) models on",
                 variant: on > 0 ? .ok : .neutral,
                 showDot: on > 0)
            if state.brokerRunning {
                Pill(text: "broker is live — toggles apply on next request", variant: .warn)
            }
            Spacer()
        }
    }
}

// MARK: - Per-agent models card

private struct AgentModelsCard: View {
    @EnvironmentObject private var state: AppState
    let agent: DetectedAgent

    var body: some View {
        let models = state.modelsFor(agent)
        let primary = state.primaryModel[agent.id]

        return CardSurface(padded: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ProviderMonogram(letters: agent.def.monogram)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(agent.def.name)
                            .font(Theme.Typeface.body(16, weight: .semibold))
                            .tracking(-0.2)
                            .foregroundStyle(Theme.Palette.fg)
                        if let path = agent.resolvedPath {
                            Text(prettyHomePath(path))
                                .font(Theme.Typeface.mono(11))
                                .foregroundStyle(Theme.Palette.muted)
                        }
                    }
                    Spacer(minLength: 0)
                    enabledCountPill(models: models)
                }

                if models.isEmpty {
                    Text("No models known yet. Edit `~/.codex/config.toml` (or your CLI's equivalent) and Rescan.")
                        .font(Theme.Typeface.body(12))
                        .foregroundStyle(Theme.Palette.muted)
                } else {
                    VStack(spacing: 8) {
                        ForEach(models, id: \.self) { model in
                            ModelCheckRow(
                                model: model,
                                isPrimary: model == primary
                            )
                        }
                    }
                }
            }
        }
    }

    private func enabledCountPill(models: [String]) -> some View {
        let on = models.filter { state.modelExposed[$0] ?? false }.count
        let total = models.count
        return Pill(text: "\(on)/\(total) on",
                    variant: on > 0 ? .ok : .neutral)
    }
}

// MARK: - One model row with checkbox

private struct ModelCheckRow: View {
    @EnvironmentObject private var state: AppState
    let model: String
    let isPrimary: Bool

    private var isOn: Bool { state.modelExposed[model] ?? false }

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.square.fill" : "square")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(isOn ? Theme.Palette.accent : Theme.Palette.stone)
                    .frame(width: 22, alignment: .center)

                HStack(spacing: 8) {
                    Text(model)
                        .font(Theme.Typeface.mono(13))
                        .foregroundStyle(Theme.Palette.fg)
                        .textSelection(.enabled)
                    if isPrimary {
                        PrimaryBadge()
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Theme.Palette.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                    .strokeBorder(isOn ? Theme.Palette.borderStrong : Theme.Palette.border,
                                  lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(isOn ? "Disable" : "Enable") model \(model)\(isPrimary ? " (primary)" : "")")
    }

    private func toggle() {
        state.modelExposed[model] = !isOn
    }
}

private struct PrimaryBadge: View {
    var body: some View {
        Text("primary")
            .font(Theme.Typeface.body(10, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(Theme.Palette.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.Palette.accentSoft.opacity(0.6))
            .clipShape(Capsule())
            .help("This is the model your CLI's config file currently points to.")
    }
}

// MARK: - Empty state when no CLI is detected

private struct NothingToConfigureCard: View {
    var body: some View {
        CardSurface(padded: true) {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle(text: "No models to configure yet.")
                Text("Install a supported AI CLI first — check the More tab for one-line install commands. Once it's on your PATH, click Rescan and its models will show up here.")
                    .font(Theme.Typeface.body(13))
                    .foregroundStyle(Theme.Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
