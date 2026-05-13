import Foundation

/// Inbound request shape — provider-neutral. The broker translates either an
/// OpenAI `/v1/chat/completions` body or an Anthropic `/v1/messages` body into
/// this struct before handing off to an adapter.
public struct AdapterRequest: Sendable, Equatable {
    public struct Message: Sendable, Equatable {
        public let role: String      // "system" | "user" | "assistant"
        public let content: String
        public init(role: String, content: String) {
            self.role = role
            self.content = content
        }
    }

    public let model: String
    public let messages: [Message]
    /// If true, requester expected SSE; if false, return a single JSON object.
    public let stream: Bool

    public init(model: String, messages: [Message], stream: Bool) {
        self.model = model
        self.messages = messages
        self.stream = stream
    }
}

/// Adapter output events. The broker maps these onto OpenAI- or Anthropic-
/// shaped SSE frames via [[SSEEncoder]].
public enum AdapterEvent: Sendable, Equatable {
    /// Sent once at the start so OpenAI clients see `delta.role = "assistant"`.
    case start
    /// A chunk of assistant text. Always after ANSI stripping.
    case textDelta(String)
    /// Stream finished cleanly.
    case finish(reason: String)
    /// Stream finished due to a recoverable error parsed from the CLI output
    /// (e.g. quota exceeded). Mapped to PRD §7 / ERR-2.
    case error(message: String, type: String, code: String?)
}

/// What an adapter must provide for the broker to spawn it and translate its
/// output. Mirrors the `AdapterDef.buildArgs` / `streamFormat` shape from the
/// handover doc.
public protocol Adapter: Sendable {
    var def: AgentDef { get }

    /// Resolve the absolute path to the executable. Returns nil if the CLI is
    /// not installed (PATH search + fallback bins). Caller should 404 the
    /// request when nil.
    func resolveExecutable() -> URL?

    /// Spawn the CLI for this request and register the child so it's reaped
    /// on shutdown. Returns the live handle.
    ///
    /// Default implementation uses ProcessSpawner with `argumentsForRequest`,
    /// `stdinForRequest`, and `environmentForRequest`.
    func spawn(_ request: AdapterRequest,
               registry: ProcessRegistry) async throws -> ChildHandle

    /// Build the argv (excluding executable) for this request. SPAWN-1: must
    /// NOT include the user prompt — that goes via stdin.
    func argumentsForRequest(_ request: AdapterRequest) -> [String]

    /// Build the stdin payload for this request, or nil if the CLI takes the
    /// prompt some other way (e.g. ACP).
    func stdinForRequest(_ request: AdapterRequest) -> Data?

    /// Adapter-specific environment additions on top of the broker baseline.
    /// SPAWN-5: keep this tight; nothing secret.
    func environmentAdditions() -> [String: String]

    /// Translate a stdout byte stream into broker events. Phase 1 plain
    /// implementation: ANSI-strip, split on lines, emit each as `textDelta`.
    func events(stdout: AsyncStream<Data>,
                stderr: AsyncStream<Data>,
                exit: @escaping () async -> Termination) -> AsyncStream<AdapterEvent>
}

// MARK: - Default implementation (plain stdout + ANSI strip)

public extension Adapter {
    func resolveExecutable() -> URL? {
        if let path = CLIDetector.resolveOnPath(def.bin) {
            return URL(fileURLWithPath: path)
        }
        for fallback in def.fallbackBins {
            if let path = CLIDetector.resolveOnPath(fallback) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    func spawn(_ request: AdapterRequest,
               registry: ProcessRegistry) async throws -> ChildHandle {
        guard let executable = resolveExecutable() else {
            throw AdapterError.notInstalled(def.id)
        }
        let options = ProcessSpawner.Options(
            executable: executable,
            arguments: argumentsForRequest(request),
            environment: AdapterEnvironment.baseline(adding: environmentAdditions()),
            stdin: stdinForRequest(request)
        )
        let child = try ProcessSpawner.spawn(options)
        await registry.register(child)
        return child
    }

    func environmentAdditions() -> [String: String] { [:] }

    /// Default events: plain stdout, ANSI-stripped, each non-empty line is a
    /// `textDelta`. `finish` event is emitted when stdout closes; if exit was
    /// non-zero, an `error` event precedes finish.
    func events(stdout: AsyncStream<Data>,
                stderr: AsyncStream<Data>,
                exit: @escaping () async -> Termination) -> AsyncStream<AdapterEvent> {
        AsyncStream { continuation in
            let task = Task { [exit] in
                continuation.yield(.start)
                var stripper = ANSIStripper.Stripper()

                // Buffer stderr separately so we can include it in error.
                let stderrTask = Task { () -> String in
                    var s = ""
                    for await chunk in stderr {
                        s += String(data: chunk, encoding: .utf8) ?? ""
                    }
                    return s
                }

                var emittedAny = false
                for await chunk in stdout {
                    guard let str = String(data: chunk, encoding: .utf8) else { continue }
                    let cleaned = stripper.append(str)
                    if !cleaned.isEmpty {
                        emittedAny = true
                        continuation.yield(.textDelta(cleaned))
                    }
                }

                let stderrText = await stderrTask.value
                let outcome = await exit()
                switch outcome {
                case .exited(let code) where code == 0:
                    continuation.yield(.finish(reason: "stop"))
                case .exited(let code):
                    // PRD §7 — translate known error strings into typed events.
                    let parsed = ErrorMapping.classify(stderrText.isEmpty ? "exit \(code)" : stderrText)
                    if !emittedAny {
                        continuation.yield(.error(message: parsed.message,
                                                  type: parsed.type,
                                                  code: parsed.code))
                    }
                    continuation.yield(.finish(reason: "error"))
                case .signaled, .forcedKill:
                    continuation.yield(.error(message: "CLI terminated unexpectedly",
                                              type: "internal_server_error",
                                              code: nil))
                    continuation.yield(.finish(reason: "error"))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

public enum AdapterError: Error, Equatable {
    case notInstalled(String)
    case unknownModel(String)
    case spawn(SpawnError)
}

// MARK: - Environment baseline

/// SPAWN-5: every spawn starts from this minimal env. Adapters can layer their
/// own non-secret additions on top. The broker's own bearer token is NEVER in
/// this env; we explicitly do not include `OSM_*`.
public enum AdapterEnvironment {
    public static func baseline(adding extras: [String: String]) -> [String: String] {
        var env: [String: String] = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "HOME": NSHomeDirectory(),
            "USER": NSUserName(),
            "LANG": "en_US.UTF-8",
            "LC_ALL": "en_US.UTF-8",
            // TERM=dumb forces most CLIs to skip ANSI/colour output, which
            // saves the stripper work.
            "TERM": "dumb"
        ]
        for (k, v) in extras { env[k] = v }
        return env
    }
}
