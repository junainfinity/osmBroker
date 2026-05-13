import SwiftUI
import osmBrokerCore

@MainActor
final class AppState: ObservableObject {

    // MARK: - Navigation

    @Published var selectedPane: Pane = .cli

    // MARK: - Detection

    /// All registry adapters, with detection results applied. Initially every
    /// adapter is in `.notInstalled` state until `refreshDetection()` runs.
    @Published var detectedAgents: [DetectedAgent] = AgentRegistry.all.map(DetectedAgent.notInstalled)

    /// Adapter the right-hand detail panel is showing. Defaults to the first
    /// installed agent; falls back to the first registry entry if nothing is
    /// installed.
    @Published var selectedAgentID: String = AgentRegistry.all.first?.id ?? ""

    @Published var isScanning: Bool = false
    @Published var lastScanAt: Date? = nil

    // MARK: - Toggles

    /// Whether the broker should expose each agent. Keyed by agent id.
    /// Default: every detected/installed agent on.
    @Published var agentExposed: [String: Bool] = [:]

    /// Whether the broker should expose each model. Keyed by model id.
    /// Default: every model on.
    @Published var modelExposed: [String: Bool] = [:]

    /// Per-agent models the user actually has, in priority order:
    /// `ConfigDiscovery` results first, then the registry's curated list as a
    /// safety net. Empty until `refreshDetection()` runs at least once.
    /// See [[AppState-Discovered-Models]].
    @Published var discoveredModels: [String: [String]] = [:]

    /// Per-agent config-discovered "default" model. Used for a "primary"
    /// badge in the Models pane.
    @Published var primaryModel: [String: String] = [:]

    // MARK: - Network

    /// LAN-facing IPv4 the broker would be reachable on from another device.
    /// Discovered via `getifaddrs`; `nil` until first lookup.
    @Published var lanIP: String? = nil

    @Published var host: String = "0.0.0.0"
    @Published var port: String = "8080"
    @Published var apiKey: String = "osm-local-dev"

    // MARK: - Broker state

    @Published var brokerRunning: Bool = false
    /// User-facing error string surfaced under the Start/Stop button.
    @Published var brokerError: String? = nil
    /// Suggested alternative when the chosen port is in use (PRD §7).
    @Published var portConflictSuggestion: Int? = nil

    private var brokerServer: BrokerServer? = nil

    // MARK: - Derived

    var installedAgents: [DetectedAgent] {
        detectedAgents.filter(\.isInstalled)
    }

    var notInstalledAgents: [DetectedAgent] {
        detectedAgents.filter { !$0.isInstalled }
    }

    var runningAgents: [DetectedAgent] {
        detectedAgents.filter(\.isRunning)
    }

    var allModels: [(modelID: String, agent: DetectedAgent)] {
        installedAgents.flatMap { agent in
            agent.models.map { (modelID: $0, agent: agent) }
        }
    }

    var enabledModelCount: Int {
        allModels.lazy.filter { self.modelExposed[$0.modelID] ?? false }.count
    }

    var selectedAgent: DetectedAgent? {
        detectedAgents.first { $0.id == selectedAgentID }
    }

    /// What other devices would type. When host is `0.0.0.0` we substitute the
    /// real LAN IP if we have one; otherwise fall back to `localhost` so we
    /// never lie about a non-existent address.
    var reachableHost: String {
        if host == "0.0.0.0" {
            return lanIP ?? "localhost"
        }
        return host
    }

    var baseURL: String { "http://\(reachableHost):\(port)" }
    var localhostURL: String { "http://localhost:\(port)" }

    var statusLine: String {
        if let ip = lanIP, host == "0.0.0.0" {
            return "Reachable at \(ip):\(port)"
        }
        if host == "0.0.0.0" {
            return "No LAN interface — localhost only"
        }
        return "Bound to \(host):\(port)"
    }

    /// First enabled model's spawn command — used in the routing diagram.
    var routeTargetText: String {
        guard let entry = allModels.first(where: { modelExposed[$0.modelID] ?? false }) else {
            return "no model enabled"
        }
        return "\(entry.agent.def.bin) --model \(entry.modelID)"
    }

    // MARK: - Detection lifecycle

    func refreshDetection() async {
        isScanning = true
        defer { isScanning = false }

        let agents = await CLIDetector.detectAll()
        applyDetection(agents)

        // Refresh LAN IP at the same time — interfaces can change (Wi-Fi flips,
        // VPN dial-up, etc.).
        lanIP = NetworkInfo.primaryLANAddress()
        lastScanAt = Date()
    }

    private func applyDetection(_ agents: [DetectedAgent]) {
        detectedAgents = agents

        // Default toggles: anything newly detected is on; preserve user choices.
        for agent in agents where agentExposed[agent.id] == nil {
            agentExposed[agent.id] = agent.isInstalled
        }

        // Layer config-discovered models on top of the registry's fallback list.
        // Discovered models sort first so the user's actual setting bubbles up.
        for agent in agents where agent.isInstalled {
            let cfg = configDiscoveryResult(for: agent.id)
            let union = Self.uniqueOrdered(cfg.discovered + agent.models)
            discoveredModels[agent.id] = union
            if let p = cfg.primary { primaryModel[agent.id] = p }

            // Auto-enable rule (see [[../05-Architecture/AppState-Discovered-Models#auto-enable-rules]]):
            //   - If discovery surfaced any models from the user's own config,
            //     trust THAT as the user's account-tier truth. Only auto-on the
            //     discovered set; registry-fallback models default OFF so we
            //     don't advertise things their account can't reach (e.g. gpt-5
            //     on a ChatGPT-account codex install).
            //   - If no config exists for this adapter (e.g. claude — there's no
            //     standard model config), auto-on everything from the registry
            //     since aliases like `sonnet`/`opus`/`haiku` are stable.
            let onlyDiscovered = !cfg.discovered.isEmpty
            for model in union where modelExposed[model] == nil {
                modelExposed[model] = onlyDiscovered ? cfg.discovered.contains(model) : true
            }
        }

        // Pick a sensible selection if the current one isn't installed.
        if let current = agents.first(where: { $0.id == selectedAgentID }), current.isInstalled {
            // keep current
        } else if let firstInstalled = agents.first(where: \.isInstalled) {
            selectedAgentID = firstInstalled.id
        } else if let first = agents.first {
            selectedAgentID = first.id
        }
    }

    private func configDiscoveryResult(for id: String) -> ConfigDiscovery.Result {
        switch id {
        case "codex":  return ConfigDiscovery.codex()
        case "claude": return ConfigDiscovery.claude()
        default:       return .init(discovered: [], primary: nil)
        }
    }

    private static func uniqueOrdered(_ xs: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for x in xs where seen.insert(x).inserted { out.append(x) }
        return out
    }

    /// What the Models pane iterates: per agent, the union of discovered
    /// + registry models. Falls back to `agent.models` if discovery never ran.
    func modelsFor(_ agent: DetectedAgent) -> [String] {
        discoveredModels[agent.id] ?? agent.models
    }

    // MARK: - Bindings

    func binding(forModel id: String) -> Binding<Bool> {
        Binding(
            get: { self.modelExposed[id] ?? false },
            set: { self.modelExposed[id] = $0 }
        )
    }

    func binding(forAgent id: String) -> Binding<Bool> {
        Binding(
            get: { self.agentExposed[id] ?? false },
            set: { self.agentExposed[id] = $0 }
        )
    }

    func enabledModelCount(for agentID: String) -> Int {
        guard let agent = detectedAgents.first(where: { $0.id == agentID }) else { return 0 }
        return agent.models.lazy.filter { self.modelExposed[$0] ?? false }.count
    }

    // MARK: - Broker lifecycle

    /// Build the catalogue of enabled (modelID → adapter) entries. Phase 1
    /// wires Claude Code and Codex CLI; further adapters land as their
    /// implementations arrive.
    func currentCatalog() -> BrokerServer.ModelCatalog {
        var entries: [BrokerServer.ModelCatalog.Entry] = []
        let claude = ClaudeAdapter()
        let codex  = CodexAdapter()

        // `agentExposed` is no longer consulted — the per-CLI toggle was
        // removed from the CLI pane (see [[../05-Architecture/CLI-Toggle-Audit]]).
        // Models tab is now the single control point for what's served.
        for agent in installedAgents {
            let adapter: Adapter? = {
                switch agent.id {
                case "claude": return claude
                case "codex":  return codex
                default:       return nil   // not yet implemented
                }
            }()
            guard let adapter else { continue }
            // Use the discovered-models union, not just the registry list.
            // This is what makes config-only models (e.g. a user's local
            // `model =` setting) actually appear in /v1/models.
            for model in modelsFor(agent) where modelExposed[model] ?? false {
                entries.append(.init(modelID: model, adapter: adapter))
            }
        }
        return BrokerServer.ModelCatalog(entries: entries)
    }

    func startBroker() async {
        brokerError = nil
        portConflictSuggestion = nil
        guard let portNum = Int(port), (1...65535).contains(portNum) else {
            brokerError = "Port must be a number between 1 and 65535."
            return
        }
        guard !apiKey.isEmpty else {
            brokerError = "Set an API key before starting the broker."
            return
        }
        let catalog = currentCatalog()
        guard !catalog.entries.isEmpty else {
            brokerError = "No models are enabled. Toggle at least one in the Models tab."
            return
        }
        let server = BrokerServer()
        do {
            try await server.start(.init(
                host: host, port: portNum, apiKey: apiKey, modelCatalog: catalog
            ))
            brokerServer = server
            brokerRunning = true
        } catch BrokerServer.ServerError.portInUse(let p) {
            let suggestion = PortPreflight.suggestAlternate(host: host, after: p)
            portConflictSuggestion = suggestion
            if let s = suggestion {
                brokerError = "Port \(p) is already in use. Try \(s)."
            } else {
                brokerError = "Port \(p) is already in use. No nearby free port found."
            }
        } catch BrokerServer.ServerError.portPermissionDenied(let p) {
            brokerError = "Port \(p) requires elevated privileges. Pick a port ≥ 1024."
        } catch BrokerServer.ServerError.emptyAPIKey {
            brokerError = "API key cannot be empty."
        } catch BrokerServer.ServerError.alreadyRunning {
            brokerError = "Broker is already running."
        } catch BrokerServer.ServerError.bindFailed(let detail) {
            brokerError = "Bind failed: \(detail)"
        } catch {
            brokerError = "Failed to start broker: \(error)"
        }
    }

    func stopBroker() async {
        guard let server = brokerServer else {
            brokerRunning = false
            return
        }
        await server.stop()
        brokerServer = nil
        brokerRunning = false
        brokerError = nil
        portConflictSuggestion = nil
    }

    /// Called from the App's terminate observer (m1.9). Idempotent.
    func shutdownForQuit() async {
        await stopBroker()
        await ProcessRegistry.shared.killAll(grace: 1.0)
        await ProcessRegistry.shared.waitForAllToExit(timeout: 2.0)
    }
}
