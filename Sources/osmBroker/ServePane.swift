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
