import Foundation

/// Phase 1 adapter for Anthropic's Claude Code CLI.
///
/// Handover doc, `claude` row of `AGENT_DEFS`:
/// - `bin: "claude"`, fallback `"openclaude"`
/// - Prompt delivery: stdin with `claude -p`
/// - Stream format: `claude-stream-json` (Phase 4 lands the structured parser)
///
/// For Phase 1 we run `claude -p --model <model>` and treat stdout as plain
/// text deltas. ANSI stripping handles any spinner/color noise.
public struct ClaudeAdapter: Adapter {

    public let def: AgentDef

    public init() {
        guard let claudeDef = AgentRegistry.def(for: "claude") else {
            // Registry construction would fail at startup if "claude" were
            // missing; this fallback never runs in practice.
            self.def = AgentDef(
                id: "claude", name: "Claude Code", monogram: "Cl",
                subtitle: "Anthropic terminal agent",
                bin: "claude", fallbackBins: ["openclaude"],
                bridge: .stdin, nativeProtocol: .anthropic,
                installURL: nil, installCommand: nil,
                fallbackModels: []
            )
            return
        }
        self.def = claudeDef
    }

    public func argumentsForRequest(_ request: AdapterRequest) -> [String] {
        // Per PRD §5 Claude Code Profile: leverage `claude -p` print mode.
        // SPAWN-1: prompt is NOT here — it goes through stdin.
        ["-p", "--model", request.model]
    }

    public func stdinForRequest(_ request: AdapterRequest) -> Data? {
        // Compose system prompt + chat history into a single text payload.
        // Claude Code's `-p` reads the prompt from stdin until EOF.
        Data(PromptComposer.composePlain(request).utf8)
    }

    public func environmentAdditions() -> [String: String] {
        // CLAUDE_CONFIG_DIR could be set here if the user wanted a custom one;
        // for Phase 1 we let claude use its default.
        [:]
    }
}

/// Helper that flattens a chat history into a single prompt string. Adequate
/// for plain-text Phase-1 invocations. Phase 4 replaces this with structured
/// stream-json input when we wire up MCP-aware sessions.
public enum PromptComposer {
    public static func composePlain(_ request: AdapterRequest) -> String {
        var out = ""
        for msg in request.messages {
            switch msg.role.lowercased() {
            case "system":
                if !out.isEmpty { out += "\n\n" }
                out += "[SYSTEM]\n\(msg.content)"
            case "assistant":
                if !out.isEmpty { out += "\n\n" }
                out += "[ASSISTANT]\n\(msg.content)"
            default:    // "user" or anything else
                if !out.isEmpty { out += "\n\n" }
                out += "[USER]\n\(msg.content)"
            }
        }
        return out
    }
}
