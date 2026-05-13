# CLI Agent Detection And Broker Handover

This handover is for an AI agent that needs to reproduce or port Open Design's local CLI detection and CLI broker system into another codebase.

Source project: `nexu-io/open-design`, local checkout `/Users/arjun/Projects/open-design`.

Use "CLI broker" as the implementation term even though the repo usually calls it the agent adapter layer. The broker has two parts:

- Local CLI adapter broker: detects installed tools like Claude Code, Codex CLI, Gemini CLI, Cursor Agent, OpenCode, Pi, ACP agents, etc., discovers version/model metadata where possible, builds per-CLI spawn arguments, and normalizes each CLI's output stream.
- BYOK provider broker: routes API-mode requests to Anthropic/OpenAI-compatible/Azure/Google/Ollama providers, lists provider models where supported, and smoke-tests provider credentials.

## Architecture Map

Primary local CLI broker:

- `apps/daemon/src/agents.ts`
  - Owns the adapter registry, executable detection, model discovery, per-agent spawn args, env shaping, model validation, and install metadata.
  - `AGENT_DEFS` is the source of truth for supported CLI adapters.
  - `detectAgents()` returns all adapters with `available`, `path`, `version`, `models`, `reasoningOptions`, `installUrl`, and `docsUrl`.

Daemon API surface:

- `apps/daemon/src/server.ts`
  - `GET /api/agents` calls `detectAgents()` and returns `{ agents }`.
  - `POST /api/chat` is the actual brokered run path. It validates selected model/reasoning, resolves the same binary detection found, builds args, spawns the CLI, writes prompt over stdin when configured, and forwards normalized output through SSE.
  - `POST /api/provider/models` calls the BYOK provider model-discovery broker.
  - `POST /api/test/connection` smoke-tests either a BYOK provider or a local CLI adapter.
  - `POST /api/proxy/{anthropic,openai,azure,google,ollama}/stream` is the BYOK streaming proxy.

Shared contracts:

- `packages/contracts/src/api/registry.ts`
  - Defines `AgentInfo`, `AgentModelOption`, and `AgentsResponse`.
- `packages/contracts/src/api/providerModels.ts`
  - Defines the provider-model discovery request/response contract.
- `packages/contracts/src/api/connectionTest.ts`
  - Defines connection-test request/response contracts and base URL validation helpers.

Frontend wiring:

- `apps/web/src/providers/registry.ts`
  - `fetchAgents()` calls `GET /api/agents`.
- `apps/web/src/components/AgentPicker.tsx`
  - Displays available local CLIs in the top picker.
- `apps/web/src/components/SettingsDialog.tsx`
  - Shows local CLI cards, rescan, CLI connection test, model picker, reasoning picker, and configured CLI env overrides.
- `apps/web/src/components/modelOptions.tsx`
  - Groups `provider/model` IDs under provider optgroups in model dropdowns.
- `apps/web/src/providers/provider-models.ts`
  - Calls `POST /api/provider/models`.
- `apps/web/src/state/config.ts`
  - Contains static BYOK provider presets and model suggestions.

Stream parsers and protocol helpers:

- `apps/daemon/src/claude-stream.ts`
  - Parses Claude Code stream-json output into typed UI events.
- `apps/daemon/src/json-event-stream.ts`
  - Parses Codex, Gemini, OpenCode, Cursor Agent, and similar JSON-event streams.
- `apps/daemon/src/copilot-stream.ts`
  - Parses Copilot JSON output.
- `apps/daemon/src/qoder-stream.ts`
  - Parses Qoder stream-json output.
- `apps/daemon/src/acp.ts`
  - Drives Agent Client Protocol agents and detects ACP models.
- `apps/daemon/src/pi-rpc.ts`
  - Drives Pi JSON-RPC and parses `pi --list-models`.

Platform helper:

- `packages/platform/src`
  - Provides `createCommandInvocation()` and `wellKnownUserToolchainBins()`, used so POSIX/Windows command invocation and PATH extension behavior stay centralized.

## Complete Local CLI Adapter Inventory

Open Design currently declares 16 local AI CLI adapters in `AGENT_DEFS`.

| Agent ID | Display name | Primary bin | Fallback bins | Model discovery | Prompt delivery | Stream handler |
|---|---|---|---|---|---|---|
| `claude` | Claude Code | `claude` | `openclaude` | static `fallbackModels`; probes `claude -p --help` for optional flags | stdin with `claude -p` | `claude-stream-json` via `createClaudeStreamHandler()` in `claude-stream.ts` |
| `codex` | Codex CLI | `codex` | none | static `fallbackModels`; has reasoning options | stdin with `codex exec --json` | `json-event-stream`, `eventParser: codex`, via `createJsonEventStreamHandler()` |
| `devin` | Devin for Terminal | `devin` | none | `fetchModels` through ACP handshake | ACP stdio session | `acp-json-rpc` via `attachAcpSession()` in `acp.ts` |
| `gemini` | Gemini CLI | `gemini` | none | static `fallbackModels` | stdin with `gemini --output-format stream-json --yolo` | `json-event-stream`, `eventParser: gemini` |
| `opencode` | OpenCode | `opencode-cli` | `opencode` | `listModels` using `opencode-cli models` | stdin with `opencode run --format json ... -` | `json-event-stream`, `eventParser: opencode` |
| `hermes` | Hermes | `hermes` | none | `fetchModels` through ACP handshake | ACP stdio session | `acp-json-rpc` via `attachAcpSession()` |
| `kimi` | Kimi CLI | `kimi` | none | `fetchModels` through ACP handshake | ACP stdio session | `acp-json-rpc` via `attachAcpSession()` |
| `cursor-agent` | Cursor Agent | `cursor-agent` | none | `listModels` using `cursor-agent models` | stdin with `cursor-agent --print --output-format stream-json` | `json-event-stream`, `eventParser: cursor-agent` |
| `qwen` | Qwen Code | `qwen` | none | static `fallbackModels` | stdin with `qwen --yolo -` | `plain`, raw stdout chunks |
| `qoder` | Qoder CLI | `qodercli` | none | static `fallbackModels` | stdin with `qodercli -p --output-format stream-json --yolo` | `qoder-stream-json` via `createQoderStreamHandler()` in `qoder-stream.ts` |
| `copilot` | GitHub Copilot CLI | `copilot` | none | static `fallbackModels` | stdin with `copilot --allow-all-tools --output-format json` | `copilot-stream-json` via `createCopilotStreamHandler()` in `copilot-stream.ts` |
| `pi` | Pi | `pi` | none | custom `fetchModels`; parses `pi --list-models` stderr with `parsePiModels()` | Pi RPC prompt command over stdin | `pi-rpc` via `attachPiRpcSession()` in `pi-rpc.ts` |
| `kiro` | Kiro CLI | `kiro-cli` | none | `fetchModels` through ACP handshake | ACP stdio session | `acp-json-rpc` via `attachAcpSession()` |
| `kilo` | Kilo | `kilo` | none | `fetchModels` through ACP handshake | ACP stdio session | `acp-json-rpc` via `attachAcpSession()` |
| `vibe` | Mistral Vibe CLI | `vibe-acp` | none | `fetchModels` through ACP handshake | ACP stdio session | `acp-json-rpc` via `attachAcpSession()` |
| `deepseek` | DeepSeek TUI | `deepseek` | none | static `fallbackModels` | argv prompt through `deepseek exec --auto` | `plain`, raw stdout chunks |

Notes:

- `claude` is the only adapter with `fallbackBins` for an argv-compatible fork: `openclaude`.
- `opencode` intentionally resolves `opencode-cli` before `opencode` because desktop installs may ship `opencode` as a GUI launcher rather than the headless CLI.
- `devin`, `hermes`, `kimi`, `kiro`, `kilo`, and `vibe` are ACP adapters. They share the same stream handler but differ in executable and ACP startup args.
- `hermes` and `kimi` set `mcpDiscovery: mature-acp`, allowing Open Design to expose the live-artifacts MCP server to them through ACP server descriptors.
- `pi` is the only current adapter that declares `supportsImagePaths: true`; `qoder` also forwards absolute image paths as repeatable `--attachment` args inside `buildArgs()`.
- `deepseek` is the only current adapter with `maxPromptArgBytes: 30000`; it does not use stdin prompt delivery, so the daemon applies argv budget checks before spawn.
- `qwen` and `deepseek` are plain-output adapters. They do not emit structured tool events through Open Design's parser layer.

## Adapter ID And Env Override Map

`AGENT_BIN_ENV_KEYS` allows Settings or persisted config to point an adapter at an absolute binary path. These are not shell commands; they must resolve to executable files.

| Agent ID | Binary override env key |
|---|---|
| `claude` | `CLAUDE_BIN` |
| `codex` | `CODEX_BIN` |
| `copilot` | `COPILOT_BIN` |
| `cursor-agent` | `CURSOR_AGENT_BIN` |
| `deepseek` | `DEEPSEEK_BIN` |
| `devin` | `DEVIN_BIN` |
| `gemini` | `GEMINI_BIN` |
| `hermes` | `HERMES_BIN` |
| `kimi` | `KIMI_BIN` |
| `kiro` | `KIRO_BIN` |
| `kilo` | `KILO_BIN` |
| `opencode` | `OPENCODE_BIN` |
| `pi` | `PI_BIN` |
| `qoder` | `QODER_BIN` |
| `qwen` | `QWEN_BIN` |
| `vibe` | `VIBE_BIN` |

Settings also exposes non-binary CLI env preferences such as `CLAUDE_CONFIG_DIR` and `CODEX_HOME`; those flow through `agentCliEnvForAgent()` and `spawnEnvForAgent()`.

## Stream Handler Dispatch Map

The daemon's run path and connection-test path both dispatch child stdout using the adapter's `streamFormat`.

| `streamFormat` | Used by | Handler path |
|---|---|---|
| `claude-stream-json` | `claude` | `createClaudeStreamHandler()` from `apps/daemon/src/claude-stream.ts` |
| `json-event-stream` with `eventParser: codex` | `codex` | `createJsonEventStreamHandler('codex', ...)` from `apps/daemon/src/json-event-stream.ts` |
| `json-event-stream` with `eventParser: gemini` | `gemini` | `createJsonEventStreamHandler('gemini', ...)` |
| `json-event-stream` with `eventParser: opencode` | `opencode` | `createJsonEventStreamHandler('opencode', ...)` |
| `json-event-stream` with `eventParser: cursor-agent` | `cursor-agent` | `createJsonEventStreamHandler('cursor-agent', ...)` |
| `qoder-stream-json` | `qoder` | `createQoderStreamHandler()` from `apps/daemon/src/qoder-stream.ts` |
| `copilot-stream-json` | `copilot` | `createCopilotStreamHandler()` from `apps/daemon/src/copilot-stream.ts` |
| `acp-json-rpc` | `devin`, `hermes`, `kimi`, `kiro`, `kilo`, `vibe` | `attachAcpSession()` from `apps/daemon/src/acp.ts` |
| `pi-rpc` | `pi` | `attachPiRpcSession()` from `apps/daemon/src/pi-rpc.ts` |
| `plain` | `qwen`, `deepseek` | raw stdout forwarded as `stdout` chunks |

When porting, preserve this dispatch table exactly before adding new CLI adapters. Most bugs in this area come from adding a new `AGENT_DEFS` entry but forgetting the corresponding stream parser, or from using the wrong `eventParser` string for a `json-event-stream` adapter.

## Local CLI Detection Flow

The detection pipeline lives in `apps/daemon/src/agents.ts`.

1. `AGENT_DEFS` declares each supported adapter.

Each adapter definition includes some or all of:

- `id`: stable internal ID, for example `claude`, `codex`, `gemini`.
- `name`: display name.
- `bin`: primary executable name.
- `fallbackBins`: optional alternate executable names.
- `versionArgs`: usually `['--version']`.
- `helpArgs` and `capabilityFlags`: optional feature probing.
- `fallbackModels`: static model list when dynamic discovery is unavailable or fails.
- `listModels`: command spec for CLIs that expose model listing.
- `fetchModels`: custom dynamic model discovery for ACP/Pi-style agents.
- `reasoningOptions`: optional reasoning/thinking levels.
- `buildArgs()`: converts the selected model/reasoning/context into argv.
- `promptViaStdin`: true when prompt must be piped instead of passed as argv.
- `streamFormat` and `eventParser`: tells the daemon how to parse the child process output.
- `env`: adapter-owned, non-secret env vars, for example Gemini workspace trust.

2. `resolvePathDirs()` builds the search path.

It uses:

- `process.env.PATH`
- `wellKnownUserToolchainBins()` for common user-level CLI install locations
- `OD_AGENT_HOME` in tests to sandbox detection

Reason: GUI apps on macOS/Linux often inherit a minimal PATH, so the daemon searches common npm/Homebrew/version-manager bin locations too.

3. `resolveOnPath(bin)` searches the computed dirs.

On Windows it also walks `PATHEXT`.

4. `configuredExecutableOverride(def, configuredEnv)` checks user-configured absolute binary overrides.

These env keys are declared in `AGENT_BIN_ENV_KEYS`, for example:

- `CLAUDE_BIN`
- `CODEX_BIN`
- `GEMINI_BIN`
- `CURSOR_AGENT_BIN`

Overrides must be absolute executable files.

5. `resolveAgentExecutable(def, configuredEnv)` returns the executable path.

Order:

- configured absolute override
- `def.bin`
- each entry in `def.fallbackBins`
- `null` if no executable is found

6. `probe(def, configuredEnv)` builds the public `AgentInfo`.

If no executable is found:

- returns adapter metadata with `available: false`
- includes fallback model metadata
- includes HTTPS install/docs URLs from `AGENT_INSTALL_LINKS`

If executable is found:

- runs `versionArgs` with timeout
- probes `helpArgs` for capability flags
- calls `fetchModels(def, resolvedBin, probeEnv)`
- returns `available: true`, `path`, `version`, `models`, `reasoningOptions`, and install/docs URLs

7. `detectAgents(configuredEnvByAgent)` probes every adapter in parallel.

It also refreshes the live model validation cache through `rememberLiveModels()`.

## Local CLI Model Discovery

Model discovery is part of the local CLI broker, not a separate service.

`fetchModels(def, resolvedBin, env)` does this:

- If adapter defines `fetchModels`, call it.
- Else if adapter defines `listModels`, execute that CLI command and parse stdout.
- Else use `fallbackModels`.
- If dynamic listing fails, times out, or parses empty, use `fallbackModels`.

Important adapter patterns:

- Claude Code:
  - No model list command.
  - Uses curated `fallbackModels`.
  - Supports model selection through `--model`.
- Codex CLI:
  - No model list command.
  - Uses curated `fallbackModels`.
  - Exposes `reasoningOptions`.
  - `buildArgs()` maps reasoning to `-c model_reasoning_effort=...`.
- Gemini CLI:
  - Uses curated `fallbackModels`.
  - Sets `GEMINI_CLI_TRUST_WORKSPACE=true`.
  - Uses stdin prompt plus `--output-format stream-json --yolo`.
- OpenCode and Cursor Agent:
  - Use `listModels` with `<bin> models`.
  - Parse one model ID per line through `parseLineSeparatedModels()`.
  - Models often look like `provider/model`.
- ACP agents such as Devin, Hermes, Kimi, Kiro, Kilo, Mistral Vibe:
  - Use `fetchModels` with `detectAcpModels()` from `apps/daemon/src/acp.ts`.
  - This performs an ACP handshake and extracts available models.
- Pi:
  - Uses custom `fetchModels`.
  - Runs `pi --list-models`.
  - Parses provider/model TSV rows from stderr using `parsePiModels()` in `apps/daemon/src/pi-rpc.ts`.
  - Produces IDs like `anthropic/claude-sonnet-4-5`.

Frontend model display:

- The UI receives `AgentInfo.models`.
- `SettingsDialog.tsx` shows the model dropdown for the selected local CLI.
- `modelOptions.tsx` groups `provider/model` strings into `<optgroup label="provider">`.

## Local CLI Brokered Run Flow

The real run path is in `startChatRun()` inside `apps/daemon/src/server.ts`.

1. The web app sends a daemon chat request with:

- `agentId`
- user message/history
- selected `model`
- selected `reasoning`
- project/cwd metadata
- skill/design-system IDs
- attachments

2. Server loads the adapter definition with `getAgentDef(agentId)`.

3. Server validates model and reasoning:

- `isKnownModel(def, model)` checks the last `/api/agents` live model cache plus static fallback models.
- Unknown model IDs can pass only if `sanitizeCustomModel()` accepts them.
- Reasoning must exist in `def.reasoningOptions`.

4. Server composes the actual prompt.

The prompt combines:

- daemon system/runtime instructions
- active skill body
- active design system body
- cwd hint
- linked dir hints
- project attachment hints
- user request
- image attachment hints when supported

5. Server resolves the same binary path again.

It calls `resolveAgentBin(agentId, configuredAgentEnv)` so spawn uses the exact executable path detection would report. This avoids `ENOENT` issues where detection found a binary through an augmented PATH but raw `spawn(def.bin)` would fail.

6. Server calls `def.buildArgs(...)`.

Inputs:

- composed prompt
- image paths
- extra allowed dirs for skill/design-system assets
- `{ model, reasoning }`
- runtime context such as `{ cwd }`

The adapter owns all CLI-specific flags.

7. Server runs argv budget guards.

Important for Windows and argv-bound adapters:

- `checkPromptArgvBudget()`
- `checkWindowsCmdShimCommandLineBudget()`
- `checkWindowsDirectExeCommandLineBudget()`

Most modern adapters set `promptViaStdin: true` to avoid command-line length issues.

8. Server spawns the process.

It uses:

- `createCommandInvocation()` from `@open-design/platform`
- `spawn(..., { shell: false, stdio: [stdinMode, 'pipe', 'pipe'], cwd })`
- `spawnEnvForAgent()` for adapter-specific env safety
- `OD_BIN`, `OD_NODE_BIN`, `OD_DAEMON_URL`, `OD_PROJECT_ID`, `OD_PROJECT_DIR` so agents can call Open Design tools/media helpers

9. Server sends prompt to stdin when required.

For `promptViaStdin`, the prompt is written to child stdin. This is the normal path for Codex, Gemini, OpenCode, Cursor Agent, Qwen, Qoder, Pi, and many others.

10. Server parses output based on `def.streamFormat`.

Stream format examples:

- `claude-stream-json`: use Claude parser.
- `json-event-stream` plus `eventParser`: use JSON-event parser for Codex/Gemini/OpenCode/Cursor.
- `qoder-stream-json`: use Qoder parser.
- `copilot-stream-json`: use Copilot parser.
- `acp-json-rpc`: attach ACP session.
- `pi-rpc`: attach Pi RPC session.
- `plain`: forward stdout chunks.

11. Server emits normalized SSE events back to the web UI.

The browser receives agent status, text deltas, tool events, usage, errors, and completion regardless of underlying CLI protocol.

## BYOK Provider Broker

This is separate from local CLI detection.

Core files:

- `apps/daemon/src/providerModels.ts`
- `apps/daemon/src/connectionTest.ts`
- API proxy routes in `apps/daemon/src/server.ts`
- frontend static presets in `apps/web/src/state/config.ts`

Provider model discovery:

- `POST /api/provider/models`
- Calls `listProviderModels()` in `providerModels.ts`.
- Supports:
  - OpenAI-compatible: `GET /v1/models`
  - Anthropic: `GET /v1/models?limit=1000`
  - Google: `GET /v1beta/models?key=...`
- Azure returns unsupported because deployment discovery is not available from the inference endpoint.
- Ollama is accepted in route validation but provider-model discovery does not implement it in `providerModels.ts`; UI shows an unsupported hint.

Provider connection test:

- `POST /api/test/connection` with `mode: 'provider'`
- Calls `testProviderConnection()` in `connectionTest.ts`.
- Sends a tiny "Reply with only: ok" completion request.
- Maps common failures to categorized kinds such as auth failure, forbidden, invalid base URL, not-found model, rate limit, timeout, etc.
- For loopback OpenAI-compatible servers, it optionally checks `/models` first and reports if the requested model is absent.

Provider streaming proxy:

- `POST /api/proxy/anthropic/stream`
- `POST /api/proxy/openai/stream`
- `POST /api/proxy/azure/stream`
- `POST /api/proxy/google/stream`
- `POST /api/proxy/ollama/stream`

Responsibilities:

- Avoid browser CORS issues by proxying through the daemon.
- Validate base URLs with SSRF-safe rules.
- Normalize upstream streaming chunks into Open Design's `delta/end/error` event shape.
- Disable upstream redirects.
- Allow loopback local providers while blocking non-loopback private/link-local/CGNAT/multicast/reserved hosts.

Static BYOK provider data:

- `apps/web/src/state/config.ts` defines `KNOWN_PROVIDERS`.
- Each preset has:
  - `label`
  - `protocol`
  - `baseUrl`
  - default `model`
  - optional static `models`

The UI can use static model suggestions immediately and replace/extend them with fetched provider models when `/api/provider/models` succeeds.

## How To Port This To Another Codebase

Port in this order.

1. Define shared contracts first.

Create equivalents of:

- `AgentModelOption`
- `AgentInfo`
- `AgentsResponse`
- `ProviderModelsRequest`
- `ProviderModelsResponse`
- `ConnectionTestRequest`
- `ConnectionTestResponse`

Keep these in a shared package/module so daemon/server and UI cannot drift.

2. Port platform-safe command invocation.

Bring over or recreate:

- `createCommandInvocation()`
- Windows `.cmd` / `.bat` handling
- `wellKnownUserToolchainBins()`
- augmented PATH search for GUI-launched apps

Do not rely on raw `which` alone. GUI-launched desktop apps often inherit a reduced PATH.

3. Port the adapter registry.

Start with `AGENT_DEFS` shape:

```ts
type AgentDef = {
  id: string;
  name: string;
  bin: string;
  fallbackBins?: string[];
  versionArgs: string[];
  helpArgs?: string[];
  capabilityFlags?: Record<string, string>;
  fallbackModels?: AgentModelOption[];
  listModels?: {
    args: string[];
    parse: (stdout: string) => AgentModelOption[] | null;
    timeoutMs?: number;
  };
  fetchModels?: (resolvedBin: string, env: NodeJS.ProcessEnv) => Promise<AgentModelOption[] | null>;
  reasoningOptions?: AgentModelOption[];
  buildArgs: (
    prompt: string,
    imagePaths: string[],
    extraAllowedDirs: string[],
    options: { model?: string | null; reasoning?: string | null },
    runtimeContext: { cwd?: string },
  ) => string[];
  promptViaStdin?: boolean;
  streamFormat: string;
  eventParser?: string;
  env?: Record<string, string>;
};
```

4. Implement detection helpers.

Required functions:

- `resolvePathDirs()`
- `resolveOnPath(bin)`
- `configuredExecutableOverride(def, configuredEnv)`
- `resolveAgentExecutable(def, configuredEnv)`
- `probe(def, configuredEnv)`
- `fetchModels(def, resolvedBin, env)`
- `detectAgents(configuredEnvByAgent)`
- `getAgentDef(id)`
- `resolveAgentBin(id, configuredEnv)`

5. Expose `GET /api/agents`.

Return:

```json
{
  "agents": [
    {
      "id": "codex",
      "name": "Codex CLI",
      "bin": "codex",
      "available": true,
      "path": "/absolute/path/to/codex",
      "version": "codex ...",
      "models": [{ "id": "default", "label": "Default (CLI config)" }],
      "reasoningOptions": [{ "id": "default", "label": "Default" }]
    }
  ]
}
```

6. Port the brokered run path.

The minimum viable run path needs:

- request accepts `agentId`, `message`, `model`, `reasoning`, and `cwd`
- `getAgentDef()`
- model/reasoning validation
- `resolveAgentBin()`
- `def.buildArgs()`
- `spawnEnvForAgent()`
- `createCommandInvocation()`
- child process spawn
- stdin prompt writing when `promptViaStdin`
- stream parser dispatch by `streamFormat`
- SSE or equivalent streaming to UI
- cancellation and inactivity timeout

7. Port parsers gradually.

Start simple:

- `plain`: forward stdout text
- `json-event-stream`: line-delimited JSON parser for Codex/Gemini-like tools
- `claude-stream-json`: Claude parser if Claude is a first target

Then add:

- ACP JSON-RPC
- Pi RPC
- Copilot/Qoder custom streams

8. Port BYOK provider broker only if needed.

Minimum:

- static provider presets
- provider connection test
- streaming proxy for target protocols

Full:

- provider model discovery endpoint
- SSRF-safe base URL validation
- OpenAI/Anthropic/Google model list parsing
- Azure unsupported discovery message
- UI fetch-models button and status display

## Add A New CLI Adapter Checklist

1. Add install/docs URL to `AGENT_INSTALL_LINKS`.
2. Add a new entry to `AGENT_DEFS`.
3. Choose detection binary and optional fallback binaries.
4. Add `versionArgs`.
5. Add dynamic model discovery if the CLI supports it; otherwise provide `fallbackModels`.
6. Add `reasoningOptions` if the CLI exposes thinking/reasoning controls.
7. Implement `buildArgs()`.
8. Prefer `promptViaStdin: true` unless the CLI cannot read from stdin.
9. Set `streamFormat` and add/choose a parser.
10. Add custom env only for documented non-secret adapter behavior.
11. Add tests in `apps/daemon/tests/agents.test.ts`.
12. Add stream parser tests if a new format is introduced.
13. Verify `GET /api/agents`, Settings model picker, connection test, and one real generation.

## Security And Safety Rules To Preserve

- Never pass API secrets into logs. Use redaction helpers.
- Do not pass user prompts through argv when stdin is supported.
- Do not spawn raw `def.bin` if detection resolved an absolute path elsewhere.
- Keep `shell: false`.
- Use platform command wrappers for Windows shims.
- Validate model IDs so custom model strings cannot smuggle flags.
- Treat adapter env overrides as absolute executable paths only.
- Keep daemon internals out of shared contracts.
- Keep UI talking to daemon through HTTP contracts, not daemon-private imports.
- Use SSRF-safe validation for BYOK provider URLs.
- Block non-loopback private/internal network targets for provider proxying.
- Disable upstream redirects for provider calls.

## Validation Commands

For docs-only handover changes:

```bash
git diff --check
```

For adapter or broker code changes:

```bash
pnpm --filter @open-design/daemon test
pnpm --filter @open-design/web test
pnpm typecheck
pnpm guard
```

For local runtime smoke:

```bash
pnpm --filter @open-design/daemon build
pnpm --filter @open-design/web build
pnpm tools-dev start web
pnpm tools-dev status --json
curl -fsS http://127.0.0.1:<daemon-port>/api/health
curl -fsS http://127.0.0.1:<daemon-port>/api/agents
```

For a real CLI broker test:

1. Open Settings.
2. Select Local CLI.
3. Click Rescan.
4. Confirm installed CLIs show as available.
5. Select one CLI.
6. Confirm model/reasoning picker is populated.
7. Click Test.
8. Send a tiny project prompt and confirm streamed output arrives.

For a BYOK provider broker test:

1. Open Settings.
2. Select API mode.
3. Select protocol/provider preset.
4. Enter API key and model.
5. Click Fetch models where supported.
6. Click Test.
7. Send a tiny prompt and confirm streamed output arrives through `/api/proxy/.../stream`.

## Exact Source Anchors

Use these source anchors first:

- Local CLI registry and broker metadata: `apps/daemon/src/agents.ts`
- CLI detection API: `apps/daemon/src/server.ts`, route `GET /api/agents`
- Brokered local CLI execution: `apps/daemon/src/server.ts`, `startChatRun()`
- Shared agent contract: `packages/contracts/src/api/registry.ts`
- Local CLI frontend fetch: `apps/web/src/providers/registry.ts`, `fetchAgents()`
- Local CLI frontend picker: `apps/web/src/components/AgentPicker.tsx`
- Local CLI Settings surface: `apps/web/src/components/SettingsDialog.tsx`
- Model option grouping: `apps/web/src/components/modelOptions.tsx`
- BYOK provider model discovery: `apps/daemon/src/providerModels.ts`
- BYOK provider discovery contract: `packages/contracts/src/api/providerModels.ts`
- BYOK connection tests: `apps/daemon/src/connectionTest.ts`
- BYOK proxy routes: `apps/daemon/src/server.ts`, `/api/proxy/*/stream`
- ACP model discovery: `apps/daemon/src/acp.ts`, `detectAcpModels()`
- Pi provider/model parsing: `apps/daemon/src/pi-rpc.ts`, `parsePiModels()`
- Provider presets: `apps/web/src/state/config.ts`, `KNOWN_PROVIDERS`
- Reference design doc: `docs/agent-adapters.md`
- Architecture context: `docs/architecture.md`, "Agent adapter pool"

## What To Tell The Next Agent

Do not start by inventing a broker abstraction. First port the exact `AgentDef` registry pattern, because it keeps detection, model discovery, invocation, and stream parsing colocated per CLI. The key invariant is that `GET /api/agents` and `POST /api/chat` must use the same resolver path, the same model metadata, and the same adapter definition. If those drift, the UI may show a CLI as available while chat spawn fails, or a model picker option may be accepted by Settings but rejected by the run path.

Treat BYOK provider support as adjacent, not the same thing. Local CLI broker model discovery asks installed tools what they can run; BYOK provider discovery asks remote HTTP APIs what models are available. They share UI concepts (`id`, `label`, model dropdowns), but they have different security risks and different failure modes.
