import SwiftUI
import osmBrokerCore

/// "Turn it on. Where can clients reach it?"
///
/// Phase-1.5: drastically simpler than the old NetworkPane. One big base-URL
/// card, port field, Start/Stop, and a Test key button when live. No more
/// interfaces card (moved to a diagnostics tooltip later) and no Quick
/// Launchers (those belong to CLI tab).
struct ServePane: View {
    @EnvironmentObject private var state: AppState
    @State private var testKeyResult: TestKeyResult? = nil
    @State private var testKeyInFlight: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PaneHead(
                    eyebrow: "Serve",
                    title: state.brokerRunning
                        ? "Live — devices on your network can connect."
                        : "Start the local API.",
                    lede: "When the broker is live, the models you enabled in the Models tab become available at the base URL below over plain HTTP. Anyone on this Wi-Fi or wired network can reach it with the API key as a Bearer token."
                ) {
                    if state.brokerRunning {
                        SecondaryButton(
                            title: testKeyInFlight ? "Testing…" : "Test key",
                            enabled: !testKeyInFlight
                        ) {
                            Task {
                                testKeyInFlight = true
                                await runTestKey()
                                testKeyInFlight = false
                            }
                        }
                        PrimaryButton(title: "Stop broker") {
                            Task { await state.stopBroker() }
                        }
                    } else {
                        PrimaryButton(title: "Start broker") {
                            Task { await state.startBroker() }
                        }
                    }
                }

                if let result = testKeyResult {
                    TestKeyBanner(result: result)
                }

                if let err = state.brokerError {
                    BrokerErrorBanner(message: err,
                                      suggestion: state.portConflictSuggestion)
                }

                BaseURLCard()
                PortAndKeyCard()
                ModelsServedCard()
                EndpointEmulationCard()
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .scrollIndicators(.never)
        .onChange(of: state.brokerRunning) { _, newValue in
            if !newValue { testKeyResult = nil }
        }
    }

    enum TestKeyResult: Equatable {
        case success
        case failure(String)
    }

    private func runTestKey() async {
        guard let portNum = Int(state.port) else {
            testKeyResult = .failure("Port is not a number.")
            return
        }
        let url = URL(string: "http://127.0.0.1:\(portNum)/v1/models")!
        var req = URLRequest(url: url)
        req.addValue("Bearer \(state.apiKey)", forHTTPHeaderField: "Authorization")
        req.timeoutInterval = 5
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 200 {
                    testKeyResult = .success
                } else if http.statusCode == 401 {
                    testKeyResult = .failure("Broker rejected the key (401).")
                } else {
                    testKeyResult = .failure("Broker responded \(http.statusCode).")
                }
            } else {
                testKeyResult = .failure("No HTTP response.")
            }
        } catch {
            testKeyResult = .failure("Couldn't reach broker: \(error.localizedDescription)")
        }
    }
}

// MARK: - Big base URL card

private struct BaseURLCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        CardSurface(padded: true) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: state.brokerRunning ? "circle.fill" : "circle")
                        .font(.system(size: 10))
                        .foregroundStyle(state.brokerRunning ? Theme.Palette.green : Theme.Palette.stone)
                    Text(state.brokerRunning ? "LIVE" : "IDLE")
                        .font(Theme.Typeface.body(11, weight: .semibold))
                        .tracking(0.96)
                        .foregroundStyle(state.brokerRunning ? Theme.Palette.green : Theme.Palette.stone)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("LAN reach")
                        .font(Theme.Typeface.body(11, weight: .medium))
                        .tracking(0.6)
                        .foregroundStyle(Theme.Palette.muted)
                    HStack(spacing: 10) {
                        Text(state.baseURL)
                            .font(Theme.Typeface.mono(18, weight: .semibold))
                            .foregroundStyle(Theme.Palette.fg)
                            .textSelection(.enabled)
                        Spacer(minLength: 0)
                        CopyButton(label: "Copy LAN URL", value: state.baseURL)
                    }
                }

                if state.host == "0.0.0.0" {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Same-Mac reach")
                            .font(Theme.Typeface.body(11, weight: .medium))
                            .tracking(0.6)
                            .foregroundStyle(Theme.Palette.muted)
                        HStack(spacing: 10) {
                            Text(state.localhostURL)
                                .font(Theme.Typeface.mono(15))
                                .foregroundStyle(Theme.Palette.muted)
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                            CopyButton(label: "Copy localhost URL", value: state.localhostURL)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Port + API key controls

private struct PortAndKeyCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        CardSurface(padded: true) {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Configuration")
                HStack(alignment: .top, spacing: 12) {
                    Field(label: "Port", text: $state.port)
                    Field(label: "API key", text: $state.apiKey)
                }
                Text("Changes take effect the next time you click Start broker. The broker doesn't restart automatically when these fields change while it's already running.")
                    .font(Theme.Typeface.body(12))
                    .foregroundStyle(Theme.Palette.muted)
            }
        }
    }
}

private struct Field: View {
    let label: String
    @Binding var text: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(Theme.Typeface.body(12))
                .foregroundStyle(Theme.Palette.muted)
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typeface.mono(13))
                .foregroundStyle(Theme.Palette.fg)
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Theme.Palette.white)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                        .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
                }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Models served card
//
// Shows the exact model IDs the broker is currently exposing under each CLI,
// grouped by the originating agent. The point is to be unambiguous: if a user
// is configuring AnythingLLM / Open WebUI / Claude Desktop / their own code,
// they need to know the *exact* string to paste into the "model" field. The
// broker doesn't translate aliases — what you see here is what gets matched.

// File-private rather than nested-private so ServedAgentRow can name the type.
fileprivate struct AgentBucket: Identifiable {
    let agent: DetectedAgent
    let enabledModels: [String]
    var id: String { agent.id }
}

private struct ModelsServedCard: View {
    @EnvironmentObject private var state: AppState

    /// Walks every installed agent, pulls its currently-exposed (enabled) model
    /// IDs, and drops agents with zero enabled models. Order matches the
    /// sidebar so the visual hierarchy is consistent.
    private var buckets: [AgentBucket] {
        state.installedAgents.compactMap { agent in
            let enabled = state.modelsFor(agent)
                .filter { state.modelExposed[$0] ?? false }
            return enabled.isEmpty ? nil : AgentBucket(agent: agent, enabledModels: enabled)
        }
    }

    var body: some View {
        CardSurface(padded: true) {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Models served")

                if buckets.isEmpty {
                    EmptyModelsHint()
                } else {
                    Text("These are the exact strings to paste into the **model** field of any OpenAI-compatible client (AnythingLLM, Open WebUI, LiteLLM, your own code). Grouped by which CLI on this Mac will actually handle the request.")
                        .font(Theme.Typeface.body(12))
                        .foregroundStyle(Theme.Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(spacing: 12) {
                        ForEach(buckets) { bucket in
                            ServedAgentRow(bucket: bucket)
                        }
                    }

                    ClientHints()
                }
            }
        }
    }
}

private struct ServedAgentRow: View {
    let bucket: AgentBucket

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                Text(bucket.agent.def.monogram)
                    .font(Theme.Typeface.body(11, weight: .semibold))
                    .foregroundStyle(Theme.Palette.fg)
                    .frame(width: 26, height: 22)
                    .background(Theme.Palette.white)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
                    }
                Text(bucket.agent.def.name)
                    .font(Theme.Typeface.body(13, weight: .semibold))
                    .foregroundStyle(Theme.Palette.fg)
                Text("·")
                    .foregroundStyle(Theme.Palette.muted)
                Text(bucket.agent.def.nativeProtocol.rawValue + "-shape")
                    .font(Theme.Typeface.body(11))
                    .foregroundStyle(Theme.Palette.muted)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.Palette.white)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule().strokeBorder(Theme.Palette.border, lineWidth: 1)
                    }
                Spacer(minLength: 0)
                Text("\(bucket.enabledModels.count) model\(bucket.enabledModels.count == 1 ? "" : "s")")
                    .font(Theme.Typeface.body(11))
                    .foregroundStyle(Theme.Palette.muted)
            }

            // Wrap of model-ID chips. Each chip is its own copy button so the
            // user can grab the exact string in one click.
            FlowLayout(spacing: 6) {
                ForEach(bucket.enabledModels, id: \.self) { modelID in
                    ModelIDChip(text: modelID)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chunk, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.chunk, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        }
    }
}

private struct ModelIDChip: View {
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(text, forType: .string)
            copied = true
            Task {
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                copied = false
            }
        } label: {
            HStack(spacing: 6) {
                Text(text)
                    .font(Theme.Typeface.mono(12))
                    .foregroundStyle(Theme.Palette.fg)
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(copied ? Theme.Palette.green : Theme.Palette.muted)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Theme.Palette.white)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Copy model ID \(text)")
    }
}

private struct EmptyModelsHint: View {
    var body: some View {
        Text("No models are currently enabled. Open the **Models** tab and toggle on at least one per CLI.")
            .font(Theme.Typeface.body(12))
            .foregroundStyle(Theme.Palette.muted)
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.Palette.white)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chunk, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.chunk, style: .continuous)
                    .strokeBorder(Theme.Palette.border, lineWidth: 1)
            }
    }
}

/// Tiny hint block telling users exactly which fields to fill in their client.
private struct ClientHints: View {
    @EnvironmentObject private var state: AppState

    private struct Hint: Identifiable {
        let id = UUID()
        let client: String
        let baseURLLabel: String
        let modelLabel: String
        let keyLabel: String
    }

    private let hints: [Hint] = [
        Hint(client: "AnythingLLM",
             baseURLLabel: "LLM Preference → Generic OpenAI → Base URL",
             modelLabel: "Generic OpenAI → Chat Model Name",
             keyLabel: "Generic OpenAI → API Key"),
        Hint(client: "Open WebUI",
             baseURLLabel: "Admin Panel → Connections → OpenAI API → Base URL",
             modelLabel: "Pick from the dropdown — IDs above appear automatically",
             keyLabel: "Admin Panel → Connections → OpenAI API → API Key"),
        Hint(client: "LiteLLM proxy",
             baseURLLabel: "config.yaml — model_list.litellm_params.api_base",
             modelLabel: "config.yaml — model_list.litellm_params.model: openai/<id>",
             keyLabel: "config.yaml — model_list.litellm_params.api_key"),
        Hint(client: "OpenAI Python SDK",
             baseURLLabel: "OpenAI(base_url=…)",
             modelLabel: "client.chat.completions.create(model=\"<id>\")",
             keyLabel: "OpenAI(api_key=…)"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to plug this into a client")
                .font(Theme.Typeface.body(11, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(Theme.Palette.muted)

            VStack(spacing: 10) {
                ForEach(hints) { h in
                    ClientHintRow(client: h.client,
                                  baseURLLabel: h.baseURLLabel,
                                  modelLabel: h.modelLabel,
                                  keyLabel: h.keyLabel)
                }
            }
        }
        .padding(.top, 4)
    }
}

private struct ClientHintRow: View {
    @EnvironmentObject private var state: AppState
    let client: String
    let baseURLLabel: String
    let modelLabel: String
    let keyLabel: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(client)
                .font(Theme.Typeface.body(12, weight: .semibold))
                .foregroundStyle(Theme.Palette.fg)
            HStack(alignment: .top, spacing: 6) {
                Text("Base URL")
                    .font(Theme.Typeface.body(11))
                    .foregroundStyle(Theme.Palette.muted)
                    .frame(width: 70, alignment: .leading)
                Text(state.baseURL)
                    .font(Theme.Typeface.mono(11))
                    .foregroundStyle(Theme.Palette.fg)
                Text("·")
                    .foregroundStyle(Theme.Palette.muted)
                Text(baseURLLabel)
                    .font(Theme.Typeface.body(11))
                    .foregroundStyle(Theme.Palette.muted)
            }
            HStack(alignment: .top, spacing: 6) {
                Text("Model")
                    .font(Theme.Typeface.body(11))
                    .foregroundStyle(Theme.Palette.muted)
                    .frame(width: 70, alignment: .leading)
                Text("(any ID above)")
                    .font(Theme.Typeface.mono(11))
                    .foregroundStyle(Theme.Palette.fg)
                Text("·")
                    .foregroundStyle(Theme.Palette.muted)
                Text(modelLabel)
                    .font(Theme.Typeface.body(11))
                    .foregroundStyle(Theme.Palette.muted)
            }
            HStack(alignment: .top, spacing: 6) {
                Text("API key")
                    .font(Theme.Typeface.body(11))
                    .foregroundStyle(Theme.Palette.muted)
                    .frame(width: 70, alignment: .leading)
                Text(state.apiKey)
                    .font(Theme.Typeface.mono(11))
                    .foregroundStyle(Theme.Palette.fg)
                Text("·")
                    .foregroundStyle(Theme.Palette.muted)
                Text(keyLabel)
                    .font(Theme.Typeface.body(11))
                    .foregroundStyle(Theme.Palette.muted)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.white)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        }
    }
}

// MARK: - Endpoint emulation card

private struct EndpointEmulationCard: View {
    var body: some View {
        CardSurface(padded: true) {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(text: "Endpoint emulation")
                VStack(spacing: 10) {
                    EndpointRow(title: "/v1/models",
                                copy: "Returns the merged model catalog from enabled CLI adapters.")
                    EndpointRow(title: "/v1/chat/completions",
                                copy: "OpenAI-shaped streaming inference, normalized to SSE.")
                    EndpointRow(title: "/v1/messages",
                                copy: "Anthropic-shaped streaming inference; same routing layer.")
                    EndpointRow(title: "Bearer token required",
                                copy: "Rejects requests without the configured local API key.")
                }
            }
        }
    }
}

private struct EndpointRow: View {
    let title: String
    let copy: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.Typeface.mono(13))
                .foregroundStyle(Theme.Palette.fg)
            Text(copy)
                .font(Theme.Typeface.body(12))
                .foregroundStyle(Theme.Palette.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.Palette.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.chunk, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.chunk, style: .continuous)
                .strokeBorder(Theme.Palette.border, lineWidth: 1)
        }
    }
}

// MARK: - Test key result banner

private struct TestKeyBanner: View {
    let result: ServePane.TestKeyResult
    var body: some View {
        let isOk: Bool
        let message: String
        switch result {
        case .success:
            isOk = true
            message = "Broker responded 200 OK. Your key works."
        case .failure(let m):
            isOk = false
            message = m
        }
        return HStack(spacing: 10) {
            Image(systemName: isOk ? "checkmark.circle.fill" : "xmark.octagon.fill")
                .foregroundStyle(isOk ? Theme.Palette.green : Theme.Palette.red)
            Text(message)
                .font(Theme.Typeface.body(13))
                .foregroundStyle(Theme.Palette.fg)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                .strokeBorder((isOk ? Theme.Palette.green : Theme.Palette.red).opacity(0.4),
                              lineWidth: 1)
        }
    }
}

// MARK: - Reusable copy button (inline-ish)

private struct CopyButton: View {
    let label: String
    let value: String
    @State private var copied = false

    var body: some View {
        Button(action: copy) {
            HStack(spacing: 5) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 10, weight: .semibold))
                Text(copied ? "Copied" : "Copy")
                    .font(Theme.Typeface.body(12, weight: .medium))
            }
            .foregroundStyle(copied ? Theme.Palette.green : Theme.Palette.fg)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.Palette.white)
            .clipShape(Capsule())
            .overlay {
                Capsule().strokeBorder(Theme.Palette.borderStrong, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(value, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copied = false
        }
    }
}
