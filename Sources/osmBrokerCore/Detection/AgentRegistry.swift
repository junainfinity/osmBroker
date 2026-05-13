import Foundation

/// How the broker talks to the child process. Matches the streamFormat dispatch
/// table in the handover doc (apps/daemon/src/agents.ts).
public enum Bridge: String, Sendable, CaseIterable {
    case stdin   = "stdin bridge"
    case socket  = "socket bridge"
    case stdout  = "stdout stream"
    case acp     = "ACP JSON-RPC"
    case piRPC   = "Pi RPC"
}

/// Which API protocol(s) the broker can present this CLI as.
/// In practice the broker translates either way for any CLI, but we record the
/// "native shape" so the UI can hint which translation is cheapest.
public enum APIProtocol: String, Sendable, CaseIterable {
    case openai    = "OpenAI"
    case anthropic = "Anthropic"
}

public struct AgentDef: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let monogram: String
    public let subtitle: String

    /// Primary binary name searched on PATH.
    public let bin: String
    /// Additional binary names tried if `bin` resolves to nothing.
    public let fallbackBins: [String]

    public let bridge: Bridge
    public let nativeProtocol: APIProtocol

    public let installURL: String?
    /// Shell command the user can run to install this CLI (PRD §3.2 empty state).
    /// Optional — set when there's a canonical one-liner.
    public let installCommand: String?

    /// Curated fallback model IDs. Real model discovery (e.g. `pi --list-models`,
    /// ACP handshake, `opencode-cli models`) will replace this once wired up.
    public let fallbackModels: [String]

    public init(
        id: String,
        name: String,
        monogram: String,
        subtitle: String,
        bin: String,
        fallbackBins: [String],
        bridge: Bridge,
        nativeProtocol: APIProtocol,
        installURL: String?,
        installCommand: String? = nil,
        fallbackModels: [String]
    ) {
        self.id = id
        self.name = name
        self.monogram = monogram
        self.subtitle = subtitle
        self.bin = bin
        self.fallbackBins = fallbackBins
        self.bridge = bridge
        self.nativeProtocol = nativeProtocol
        self.installURL = installURL
        self.installCommand = installCommand
        self.fallbackModels = fallbackModels
    }
}

public enum AgentRegistry {
    /// All 16 CLIs from the handover doc, in display order.
    public static let all: [AgentDef] = [
        AgentDef(
            id: "claude", name: "Claude Code", monogram: "Cl",
            subtitle: "Anthropic terminal agent with MCP integration",
            bin: "claude", fallbackBins: ["openclaude"],
            bridge: .stdin, nativeProtocol: .anthropic,
            installURL: "https://docs.anthropic.com/claude/docs/claude-code",
            installCommand: "npm install -g @anthropic-ai/claude-code",
            // Claude Code's own `--help` says: "Provide an alias for the
            // latest model (e.g. 'sonnet' or 'opus')". Aliases auto-track
            // Anthropic's current models — see [[Claude-Model-Discovery]].
            fallbackModels: ["sonnet", "opus", "haiku"]
        ),
        AgentDef(
            id: "codex", name: "Codex CLI", monogram: "Cx",
            subtitle: "OpenAI Codex terminal agent",
            bin: "codex", fallbackBins: [],
            bridge: .stdin, nativeProtocol: .openai,
            installURL: "https://github.com/openai/codex",
            installCommand: "brew install codex",
            fallbackModels: ["gpt-5.5", "gpt-5-codex", "gpt-5", "gpt-5-mini"]
        ),
        AgentDef(
            id: "gemini", name: "Gemini CLI", monogram: "Gm",
            subtitle: "Google ReAct-loop terminal agent",
            bin: "gemini", fallbackBins: [],
            bridge: .stdin, nativeProtocol: .openai,
            installURL: "https://github.com/google-gemini/gemini-cli",
            installCommand: "npm install -g @google/gemini-cli",
            fallbackModels: ["gemini-2.5-pro", "gemini-2.5-flash"]
        ),
        AgentDef(
            id: "copilot", name: "GitHub Copilot CLI", monogram: "Co",
            subtitle: "GitHub Copilot terminal interface",
            bin: "copilot", fallbackBins: [],
            bridge: .stdin, nativeProtocol: .openai,
            installURL: "https://github.com/github/copilot-cli",
            installCommand: "npm install -g @github/copilot",
            fallbackModels: ["gpt-5", "sonnet"]   // alias resolves to latest Anthropic sonnet
        ),
        AgentDef(
            id: "cursor-agent", name: "Cursor Agent", monogram: "Cu",
            subtitle: "Cursor's headless agent",
            bin: "cursor-agent", fallbackBins: [],
            bridge: .stdin, nativeProtocol: .openai,
            installURL: "https://docs.cursor.com/cli",
            installCommand: "curl https://cursor.com/install -fsS | bash",
            fallbackModels: []
        ),
        AgentDef(
            id: "opencode", name: "OpenCode", monogram: "Oc",
            subtitle: "Headless open-source coding agent",
            bin: "opencode-cli", fallbackBins: ["opencode"],
            bridge: .stdin, nativeProtocol: .openai,
            installURL: "https://opencode.ai",
            installCommand: "npm install -g opencode-ai",
            fallbackModels: []
        ),
        AgentDef(
            id: "qwen", name: "Qwen Code", monogram: "Qw",
            subtitle: "Alibaba Qwen terminal coder",
            bin: "qwen", fallbackBins: [],
            bridge: .stdin, nativeProtocol: .openai,
            installURL: "https://github.com/QwenLM/qwen-code",
            installCommand: "npm install -g @qwen-code/qwen-code",
            fallbackModels: ["qwen3-coder-plus", "qwen3-coder-flash"]
        ),
        AgentDef(
            id: "qoder", name: "Qoder CLI", monogram: "Qd",
            subtitle: "Qoder coding agent",
            bin: "qodercli", fallbackBins: [],
            bridge: .stdin, nativeProtocol: .openai,
            installURL: "https://qoder.com",
            installCommand: nil,
            fallbackModels: []
        ),
        AgentDef(
            id: "pi", name: "Pi", monogram: "Pi",
            subtitle: "Multi-provider router CLI",
            bin: "pi", fallbackBins: [],
            bridge: .piRPC, nativeProtocol: .openai,
            installURL: "https://github.com/inflection-ai/pi",
            installCommand: nil,
            fallbackModels: []
        ),
        AgentDef(
            id: "deepseek", name: "DeepSeek TUI", monogram: "Ds",
            subtitle: "DeepSeek terminal interface",
            bin: "deepseek", fallbackBins: [],
            bridge: .stdout, nativeProtocol: .openai,
            installURL: "https://deepseek.com",
            installCommand: nil,
            fallbackModels: ["deepseek-v3.2", "deepseek-r1"]
        ),
        AgentDef(
            id: "devin", name: "Devin for Terminal", monogram: "Dv",
            subtitle: "Cognition Devin terminal agent",
            bin: "devin", fallbackBins: [],
            bridge: .acp, nativeProtocol: .anthropic,
            installURL: "https://devin.ai",
            installCommand: nil,
            fallbackModels: []
        ),
        AgentDef(
            id: "hermes", name: "Hermes", monogram: "Hr",
            subtitle: "Hermes ACP agent",
            bin: "hermes", fallbackBins: [],
            bridge: .acp, nativeProtocol: .anthropic,
            installURL: nil,
            installCommand: nil,
            fallbackModels: []
        ),
        AgentDef(
            id: "kimi", name: "Kimi CLI", monogram: "Km",
            subtitle: "Moonshot Kimi terminal agent",
            bin: "kimi", fallbackBins: [],
            bridge: .acp, nativeProtocol: .openai,
            installURL: "https://kimi.moonshot.cn",
            installCommand: "pip install -U kimi-cli",
            fallbackModels: []
        ),
        AgentDef(
            id: "kiro", name: "Kiro CLI", monogram: "Kr",
            subtitle: "Kiro ACP agent",
            bin: "kiro-cli", fallbackBins: [],
            bridge: .acp, nativeProtocol: .openai,
            installURL: nil,
            installCommand: nil,
            fallbackModels: []
        ),
        AgentDef(
            id: "kilo", name: "Kilo", monogram: "Kl",
            subtitle: "Kilo ACP agent",
            bin: "kilo", fallbackBins: [],
            bridge: .acp, nativeProtocol: .openai,
            installURL: nil,
            installCommand: nil,
            fallbackModels: []
        ),
        AgentDef(
            id: "vibe", name: "Mistral Vibe CLI", monogram: "Vb",
            subtitle: "Mistral Vibe ACP agent",
            bin: "vibe-acp", fallbackBins: [],
            bridge: .acp, nativeProtocol: .openai,
            installURL: "https://mistral.ai",
            installCommand: nil,
            fallbackModels: []
        )
    ]

    public static func def(for id: String) -> AgentDef? {
        all.first { $0.id == id }
    }

    /// Find the adapter that natively owns this model ID, by scanning fallback
    /// model lists in registry order. Returns nil if no adapter declares it.
    public static func adapter(forModel modelID: String) -> AgentDef? {
        all.first { $0.fallbackModels.contains(modelID) }
    }
}
