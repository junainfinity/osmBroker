import Foundation

/// Phase 1 adapter for OpenAI's Codex CLI.
///
/// Invocation derived live from `codex exec --help` on `codex-cli 0.130.0`:
///
/// ```
/// codex exec --json -s read-only --skip-git-repo-check --color never \
///            -m <MODEL>
/// ```
///
/// - `--json` makes codex emit one JSONL event per line on stdout.
/// - `-s read-only` is the safest sandbox; codex won't touch the FS for inference-only prompts.
/// - `--skip-git-repo-check` lets codex run from any cwd.
/// - `--color never` keeps the output ANSI-free.
///
/// Prompt is read from stdin (SPAWN-1). Event shape (verified live):
/// ```jsonl
/// {"type":"thread.started", "thread_id":"..."}
/// {"type":"turn.started"}
/// {"type":"item.completed", "item":{"type":"agent_message", "text":"<answer>"}}
/// {"type":"turn.completed", "usage": {...}}
/// ```
public struct CodexAdapter: Adapter {

    public let def: AgentDef

    public init() {
        guard let codexDef = AgentRegistry.def(for: "codex") else {
            self.def = AgentDef(
                id: "codex", name: "Codex CLI", monogram: "Cx",
                subtitle: "OpenAI Codex terminal agent",
                bin: "codex", fallbackBins: [],
                bridge: .stdin, nativeProtocol: .openai,
                installURL: nil, installCommand: nil,
                fallbackModels: []
            )
            return
        }
        self.def = codexDef
    }

    public func argumentsForRequest(_ request: AdapterRequest) -> [String] {
        // SPAWN-1: prompt is NOT here — it's on stdin.
        [
            "exec",
            "--json",
            "-s", "read-only",
            "--skip-git-repo-check",
            "--color", "never",
            "-m", request.model
        ]
    }

    public func stdinForRequest(_ request: AdapterRequest) -> Data? {
        // Codex `exec` reads stdin as the user's prompt. Plain text, no role
        // markers — codex doesn't parse chat history natively, so we join
        // turns with a clear separator. Single-message requests just send the
        // user content unwrapped.
        let body = CodexAdapter.composeForCodex(request.messages)
        return Data(body.utf8)
    }

    public func environmentAdditions() -> [String: String] {
        // CODEX_HOME could be threaded through user settings later.
        [:]
    }

    /// Override the default text-stream event loop with a JSONL parser.
    public func events(stdout: AsyncStream<Data>,
                       stderr: AsyncStream<Data>,
                       exit: @escaping () async -> Termination) -> AsyncStream<AdapterEvent> {
        AsyncStream { continuation in
            let task = Task { [exit] in
                continuation.yield(.start)

                // Drain stderr in parallel so the child never back-pressures
                // and so we can show the user a real error if it bombs.
                let stderrTask = Task { () -> String in
                    var s = ""
                    for await chunk in stderr {
                        s += String(data: chunk, encoding: .utf8) ?? ""
                    }
                    return s
                }

                var lineBuffer = ""
                var emittedAny = false

                for await chunk in stdout {
                    guard let str = String(data: chunk, encoding: .utf8) else { continue }
                    lineBuffer += str
                    while let nl = lineBuffer.firstIndex(of: "\n") {
                        let line = String(lineBuffer[..<nl])
                        lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
                        if let event = CodexAdapter.parseLine(line) {
                            continuation.yield(event)
                            if case .textDelta = event { emittedAny = true }
                        }
                    }
                }
                // Tail: any trailing partial line
                if !lineBuffer.isEmpty, let event = CodexAdapter.parseLine(lineBuffer) {
                    continuation.yield(event)
                    if case .textDelta = event { emittedAny = true }
                }

                let stderrText = await stderrTask.value
                let outcome = await exit()
                switch outcome {
                case .exited(let code) where code == 0:
                    continuation.yield(.finish(reason: "stop"))
                case .exited(let code):
                    let mapping = ErrorMapping.classify(
                        stderrText.isEmpty ? "codex exited \(code)" : stderrText
                    )
                    if !emittedAny {
                        continuation.yield(.error(
                            message: mapping.message,
                            type: mapping.type,
                            code: mapping.code
                        ))
                    }
                    continuation.yield(.finish(reason: "error"))
                case .signaled, .forcedKill:
                    continuation.yield(.error(
                        message: "codex terminated unexpectedly",
                        type: "internal_server_error", code: nil
                    ))
                    continuation.yield(.finish(reason: "error"))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Helpers

    /// Public so unit tests can exercise the parser independently of subprocess
    /// spawning.
    public static func parseLine(_ line: String) -> AdapterEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("{") else { return nil }
        guard let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              let dict = obj as? [String: Any],
              let type = dict["type"] as? String else { return nil }

        switch type {
        case "item.completed":
            if let item = dict["item"] as? [String: Any],
               (item["type"] as? String) == "agent_message",
               let text = item["text"] as? String {
                return .textDelta(text)
            }
            return nil
        case "turn.completed", "thread.completed":
            // These come AFTER the agent_message; we treat the agent_message
            // arrival as the stream content. The natural process exit handles
            // .finish(reason: "stop") for us.
            return nil
        case "error":
            if let message = dict["message"] as? String {
                return .error(message: message, type: "internal_server_error", code: nil)
            }
            return nil
        default:
            return nil
        }
    }

    /// Plain prompt composition for codex. Codex doesn't parse role markers,
    /// so we send user content directly. For multi-turn we delimit turns with
    /// a separator that signals previous conversation context.
    public static func composeForCodex(_ messages: [AdapterRequest.Message]) -> String {
        // Common case: a single user message → send verbatim.
        if messages.count == 1, messages[0].role.lowercased() == "user" {
            return messages[0].content
        }
        // Multi-turn: build a transcript-like prompt.
        var pieces: [String] = []
        for msg in messages {
            switch msg.role.lowercased() {
            case "system":
                pieces.append("System note: \(msg.content)")
            case "assistant":
                pieces.append("Assistant said: \(msg.content)")
            default:
                pieces.append(msg.content)
            }
        }
        return pieces.joined(separator: "\n\n")
    }
}
