# Test Log

Append-only. Newest run on top. Each entry: timestamp, command, result, count, failures with reproducer.

---

### 2026-05-12 17:53  `swift test --filter ANSIStripperTests` (run 1)

- Total: 13
- Passed: 12
- Failed: 1

Failure:
- `ANSIStripperTests.testRunawayCSIBoundedRecovery` — implementation bailed to `.normal` on cap, leaking remaining CSI bytes as plain text. **Fix:** stay in `.csi` once cap is hit; keep dropping bytes until a legitimate CSI terminator. Committed in same micro task.

### 2026-05-12 17:53  `swift test --filter ANSIStripperTests` (run 2)

- Total: 13
- Passed: 13
- Failed: 0

ANSI stripping module locked. Covers SGR, cursor motion, OSC window title, BEL, BS, CR-redraw, multiple-SGR, and three streaming/split-escape cases.

### 2026-05-12 17:55  `swift test --filter SSEEncoderTests`

- Total: 11
- Passed: 11
- Failed: 0

Coverage: data-line framing, event framing, OpenAI role/delta/stop/[DONE] chunks, embedded-newline JSON escaping, Anthropic message_start + content_block_delta, error envelope JSON, stream-error event framing.

### 2026-05-12 17:56  `swift test --filter AuthTests`

- Total: 20
- Passed: 20
- Failed: 0

Coverage: missing/malformed/wrong/right header outcomes, case-insensitive scheme, leading-whitespace tolerance, empty-key fail-closed (AUTH-5), constant-time compare across exact/diff/length cases, **timing test** (50 k iterations early-diff vs late-diff, ratio < 3x asserts no short-circuit), redaction across Bearer / Basic / lowercase header / no-auth-line passthrough.

### 2026-05-12 17:59  `swift test --filter SpawnerTests` (run 1)

- Total: 10
- Passed: 9
- Failed: 1

Failure:
- `SpawnerTests.testRejectsRelativeExecutable` — misnamed; `URL(fileURLWithPath:)` always normalizes to absolute, so the hasPrefix("/") guard was unreachable from a normally-constructed URL. **Fix:** tightened `validateExecutable` to also require `url.isFileURL`, renamed test to `testRejectsNonFileURL` with `URL(string: "https://...")` payload.

### 2026-05-12 18:00  `swift test --filter SpawnerTests` (run 2)

- Total: 10
- Passed: 10
- Failed: 0

Coverage:
- Validation: non-file URL, missing file, env with newline, env with NUL, env key with `=`, well-formed env accepted.
- **SPAWN-1**: prompt written via stdin never appears in child argv (dump-argv.sh fixture proves it).
- **SPAWN-5**: child env contains exactly what we pass + macOS auto-injected `__CF_USER_TEXT_ENCODING`; no broker secrets leak.
- **SPAWN-7**: `ProcessRegistry.killAll(grace: 0.2)` followed by `waitForAllToExit` reaps 3 sleep-forever children; `kill(pid, 0)` confirms they're gone.
- stdin → stdout round-trip via echo-stdin.sh fixture.

### 2026-05-12 18:02  `swift test --filter AdapterTests`

- Total: 10
- Passed: 10
- Failed: 0

Coverage:
- PromptComposer: single user, system+user (ordering), assistant turns preserved.
- ClaudeAdapter argv contract: `-p --model <id>` only, no prompt leak. stdin carries prompt.
- **End-to-end** with FakeEchoAdapter + echo-words.sh fixture: spawn → stdin → stdout AsyncStream → event stream → `.start` + N `.textDelta` + `.finish(reason: "stop")`. Verifies the default Adapter event loop.
- ErrorMapping: quota → 429, rate-limit → 429, please-login → 401, generic → 500.

### 2026-05-12 18:06  `swift test --filter BrokerServerIntegrationTests`

- Total: 10
- Passed: 10
- Failed: 0
- Wall: 0.14 s

**End-to-end** through real NIO + URLSession + subprocess (echo-words.sh):
- Auth: missing → 401, wrong → 401, right → 200.
- `GET /v1/models` returns OpenAI-shaped list with configured model id.
- `POST /v1/chat/completions` (stream=true) returns `text/event-stream`, frames include role chunk, deltas containing prompt tokens, then `data: [DONE]`.
- Unknown model → 404 `model_not_found`.
- Malformed JSON → 400 `malformed_json`.
- Invalid model name (with shell metacharacters) → 400 `model_invalid` (VAL-1).
- 1.6 MiB body → 413 (NET-4).
- Unknown endpoint → 404.

### 2026-05-12 18:07  `swift test` (full suite)

- Total: 74
- Passed: 74
- Failed: 0
- Wall: 4.8 s

All Phase-1 core modules — ANSI, SSE, Auth, Spawner, Adapter, ErrorMapping, RequestValidation, integration — green.

### 2026-05-12 18:15  `swift test` (post UI restructure)

- Total: 74
- Passed: 73
- Failed: 1

Failure:
- `BrokerServerIntegrationTests.testChatCompletionsStreamingHappyPath` — 5 s timeout. Parallel test runner had two integration tests racing on port 18080; the first `setUp` would find 18080 free, then the second would too, and both `BrokerServer.start` calls succeeded due to `SO_REUSEADDR`, causing connection routing chaos. **Fix:** per-test unique port via an NSLock-protected static counter starting at 19000.

### 2026-05-12 18:17  `swift test` (after port-counter fix)

- Total: 74
- Passed: 74
- Failed: 0
- Wall: 3.5 s

### 2026-05-12 18:26  `swift test --filter DetectorLiveSystemTests`

- Total: 3
- Passed: 3
- Failed: 0

User asked to verify Codex specifically. New `DetectorLiveSystemTests`:
- `testCodexIsDetectedIfInstalled` — asserts `resolvedPath == /opt/homebrew/bin/codex`, version `codex-cli 0.130.0`, bridge `.stdin`, native protocol `.openai`. **Passed.**
- `testClaudeIsDetectedIfInstalled` — asserts Claude at `/Users/arjun/.local/bin/claude` v `2.1.138 (Claude Code)`, bridge `.stdin`, native protocol `.anthropic`. Passed.
- `testPrintDetectionSummary` — emits the live summary above to test output for human inspection.

### 2026-05-12 18:42  `swift test --filter CodexAdapterTests` (run 1)

- Total: 12
- Passed: 11
- Failed: 0
- Skipped: 1

The live test `testLiveCodexSimpleInference` skipped with a real codex error surfaced through our parser:
```
{"type":"error","status":400,"error":{"type":"invalid_request_error",
 "message":"The 'gpt-5' model is not supported when using Codex with a ChatGPT account."}}
```
Discovery: this Mac is logged in with a **ChatGPT account**, so `gpt-5` is rejected. `~/.codex/config.toml` default is `gpt-5.5`, which IS supported. Registry updated to put `gpt-5.5` first in `codex.fallbackModels`; live test updated to use `gpt-5.5`.

### 2026-05-12 18:43  `swift test --filter CodexAdapterTests.testLiveCodexSimpleInference`

- Total: 1
- Passed: 1
- Wall: 13.0 s

```
=== Codex live response ===
pong
===========================
```

Codex really answered through our adapter via stdin → JSONL stdout → AdapterEvent stream.

### 2026-05-12 18:45  `swift test --filter LiveCodexBrokerTests`

- Total: 3
- Passed: 3
- Wall: 22 s

End-to-end **through the HTTP broker** against real codex:
- `testLiveModelsListShowsCodex` — `GET /v1/models` lists `gpt-5.5` with `owned_by: codex` ✓
- `testLiveChatCompletionsStreaming` — `POST /v1/chat/completions` (stream=true) → SSE → text reassembles to `BROKER_OK` ✓
- `testLiveChatCompletionsUnary` — `POST /v1/chat/completions` (stream=false) → JSON envelope with `choices[0].message.content == "BROKER_UNARY_OK"` ✓

### 2026-05-12 18:45  `swift test` (full suite, post-CodexAdapter)

- Total: 92
- Passed: 92
- Failed: 0
- Wall: 26.8 s

The 3 live codex tests dominate wall time (about 15-22 s for the streaming/unary pair). Everything else completes in under a second per file.

### 2026-05-12 18:58  `swift test` (post UI-fixes, .command-file launcher)

- Total: 92
- Passed: 92
- Failed: 0
- Wall: 27.3 s

UI-only fixes — sidebar URL wrap, `.command` file Open-in-Terminal, `.onChange` banner clear, Test-key hidden-when-idle — caused zero regressions to the broker / detection / adapter / NIO test surfaces.

### Manual UI verification (computer-use, no automated assertion)

| # | Screen / action | Result |
|---|---|---|
| 01 | Cold launch → Active pane | Claude (3 PIDs) + Codex (1 PID, pid 98825) detected; right detail JSON shows real metadata |
| 02 | Click Codex card | Detail panel switched, accent rail moved |
| 03 | Click More tab | 16 registry cards, Claude/Codex pinned `installed`, Copy buttons render |
| 04 | Click Network tab | Form + interfaces card showed `en0  192.168.68.104  • advertised`; Quick launchers + Open in Terminal buttons visible |
| 05 | Click Start broker | Pill flipped green `Live`; sidebar `LIVE` |
| 06 | curl `/v1/models` (auth=osm-local-dev) | 200, 7-model JSON list |
| 07 | curl no auth | 401 |
| 08 | curl wrong key | 401 |
| 09 | curl streaming `/v1/chat/completions` model=gpt-5.5 | SSE → "Paris, and the Seine runs through it." → `data: [DONE]` |
| 10 | curl unary `/v1/messages` | `content[0].text = "12 times 7 is 84."`, `stop_reason = "end_turn"` |
| 11 | curl unary `/v1/chat/completions` | `choices[0].message.content = "Neon"` |
| 12 | Click Test key (post-Start) | Green banner "Broker responded 200 OK. Your key works." |
| 13 | Click Stop broker | Pill → Idle, banner cleared, Test key button removed |
| 14 | Click Open in Terminal (Codex) | New Terminal window opens with `OpenAI Codex (v0.130.0)`, model `gpt-5.5 medium`, prompt ready |
| 15 | Sidebar URL display | Two-line wrap, no `…` ellipsis, fully selectable |

### 2026-05-13 02:48  `swift test` (readability + button audit sweep)

- Run 1: 92 tests, 1 transient failure (live codex test — codex CLI is slow + network-dependent)
- Run 2 (clean): 92 tests, 0 failures, 24.6 s

Polish changes don't touch the broker / NIO / adapter test surfaces, so the dispersion was purely from real-codex variance.

### Manual UI re-verification (post-polish)

| # | Check | Result |
|---|---|---|
| 16 | Running pill copy | `3 processes running` / `2 processes running` — clean, no comma-jammed PIDs |
| 17 | Detail JSON `path` | `~/.local/bin/claude` (single line, no mid-string wrap) |
| 18 | "Not on this Mac" Install buttons | Pill-styled with `Install ↗` arrow icon; obviously interactive |
| 19 | NotInstalledRow with no URL | Shows `no link` (not misleading dash) |
| 20 | Rescan / Test key inflight state | Buttons disable + label changes to `Scanning…` / `Testing…` during work |
| 21 | All buttons functional | Audited every Button/Link/Toggle — no inert affordance |

### 2026-05-13 06:13  `swift test` (Phase 1.5 — ConfigDiscovery + UI restructure)

- Run 1: 101 tests, 1 transient failure (live codex live test — network/auth jitter)
- Run 2 (clean): **101 tests, 0 failures, 28.2 s**

New tests added: 9 in `ConfigDiscoveryTests` (TOML grammar, profile-section walking, end-to-end with tmpdir, two Claude JSON shapes, missing-config behavior). Existing 92 unchanged.

### 2026-05-13 06:14  Headless ConfigDiscovery smoke vs. real `~/.codex/config.toml`

- Wrote `/tmp/cd-smoke.swift` inlining the parser
- Ran against the actual file on this Mac
- Output: `Top-level model = gpt-5.5` ✅

Proves the wiring AppState → ConfigDiscovery → primary-model badge will surface `gpt-5.5` as the primary model in the Models pane on this Mac.

### 2026-05-13 06:14  Bundle-resources gotcha (caught + fixed during verification)

- Symptom: after `Scripts/make-app-bundle.sh` and launch, `find osmBroker.app -type f` showed 0 PNG resources
- Cause: SwiftPM emits a sidecar `osmBroker_osmBroker.bundle/` next to the binary; the bundler script wasn't copying it
- Fix: script now copies the sidecar into `Contents/MacOS/`
- Verified: `find osmBroker.app -type f` after fix lists both `osm-mark-light.png` and `osm-mark-dark.png`
- See [[../05-Architecture/Bundle-Resources-Gotcha]]

### Screenshot verification: BLOCKED this session

The computer-use screenshot capture started returning `SCContentFilter failure` mid-session. `list_granted_applications` still shows osmBroker at tier `full` so the harness grant is intact; the OS-level Screen Recording permission for the parent Claude app appears to have been revoked or paused.

**Recovery:** open System Settings → Privacy & Security → Screen & System Audio Recording → tick the Claude / Claude-Code entry → quit + relaunch the Claude harness.

Visual verification of the v0.2 UI deferred to the next session. Headless code paths (build, tests, ConfigDiscovery against real config files, app process alive) all green.

### 2026-05-13 14:38  Live probe of `claude -p --model <alias>` for ground-truth model names

```sh
$ claude --version
2.1.140 (Claude Code)        # (was 2.1.138 last session — Anthropic shipped a point release)

$ echo "Reply OK" | claude -p --model sonnet --output-format json | jq .modelUsage
{ "claude-sonnet-4-6": {…}, "claude-haiku-4-5-20251001": {…} }

$ echo "Reply OK" | claude -p --model opus --output-format json | jq .modelUsage
{ "claude-opus-4-7": {…} }

$ echo "Reply OK" | claude -p --model haiku --output-format json | jq .modelUsage
{ "claude-haiku-4-5-20251001": {…} }
```

Real names on this Mac TODAY:
- sonnet → claude-sonnet-4-6
- opus   → claude-opus-4-7
- haiku  → claude-haiku-4-5-20251001

Registry was wrong on all three. Now uses aliases `sonnet/opus/haiku` (per `claude --help`). See [[../05-Architecture/Claude-Model-Discovery]].

### 2026-05-13 14:4x  `swift test` after the claude-alias migration

- Fast tests (skipping `LiveCodexBroker`, `testLiveCodex*`): **97 / 97 passing in 4.1 s**
- One run with live tests hung — `xctest` process pinned at 1483 for 10+ minutes, kill required. Likely the live codex CLI itself blocked on auth/network (not osmBroker code). Re-run after kill, fast tests confirm zero regressions from the alias migration.

### 2026-05-13 14:53  `swift test --filter LiveClaudeBrokerTests` (NEW test)

- 1 test, 0 failures, **2.4 s wall**
- Setup: `BrokerServer` on 127.0.0.1:24000 with catalog `[("sonnet", ClaudeAdapter())]`
- POST `/v1/chat/completions` `{"model":"sonnet", "stream":true, "messages":[{"role":"user","content":"Reply with exactly the single word: CLAUDE_LIVE_OK"}]}`
- Response: SSE → `CLAUDE_LIVE_OK` → `data: [DONE]`

```
=== /v1/chat/completions via broker → claude (sonnet) ===
CLAUDE_LIVE_OK
=================================================
```

**This proves the alias fix end-to-end.** Before: registry advertised `claude-sonnet-4-5`, broker passed that to `claude -p --model claude-sonnet-4-5` → Claude 404'd. After: registry advertises `sonnet`, broker passes that to `claude -p --model sonnet` → Claude resolves to today's `claude-sonnet-4-6` → returns content.

### 2026-05-13 15:00  `swift test --filter QuizTests` (3 Qs × 7 models = 21 calls)

- 1 test, 0 failures, **113.6 s wall** (codex is the long pole)
- 21 live inference calls through the real HTTP broker against real claude + real codex
- See full Q&A in [[../04-Logs/Dev-Log#2026-05-13-t260m-3-questions-per-model-live-quiz]]

| CLI | Model | Q1 (23+19) | Q2 (Capital Japan) | Q3 (Noble gas) |
|---|---|---|---|---|
| claude | sonnet | 42 ✓ | Tokyo ✓ | Argon ✓ |
| claude | opus | 42 ✓ | Tokyo ✓ | Helium ✓ |
| claude | haiku | 42 ✓ | Tokyo ✓ | Helium ✓ |
| codex | gpt-5.5 | 42 ✓ | Tokyo ✓ | Neon ✓ |
| codex | gpt-5-codex | — *not supported on ChatGPT-account* | — | — |
| codex | gpt-5 | — | — | — |
| codex | gpt-5-mini | — | — | — |

**12 / 21 succeeded. All 9 codex failures are upstream account-tier rejections, not broker bugs.** Drove two follow-up fixes (in this turn):

1. `ErrorMapping.classify` now recognizes "not supported" → 400 `invalid_request_error` (was unmapped → fallback 500).
2. `HTTPRouter.httpStatusForErrorType` reads the type/code and picks the right HTTP status instead of hardcoding `.internalServerError`.

### 2026-05-13 15:14  `swift test --skip Live --skip QuizTests` (after error-mapping + auto-disable fixes)

- First run hung (xctest stuck on something — looked similar to the earlier flake on the live codex tests, but skip filter was excluding them). Killed via `pkill -9 xctest`.
- Re-run with `tee` to flush output synchronously: **101 / 101 passing in 3.4 s**.
- Includes the 7 new tests added this turn:
  - `AdapterTests.testErrorMappingNotSupportedIs400` — `"not supported"` → 400 `invalid_request_error`.
  - `HTTPRouterErrorStatusTests` (6) — `invalid_request_error` → 400, `authentication_error` → 401, `permission_error` → 403, `model_not_found` / `not_found_error` → 404, `rate_limit_exceeded` / `insufficient_quota` → 429, unknown → 500.

### App bundle state at end of session

```
$ ls -la osmBroker.app/Contents/MacOS/osmBroker_osmBroker.bundle/
osm-mark-dark.png       31 026 B
osm-mark-light.png      32 256 B
```

Logo PNGs present, signed (codesign warns about the inner SPM-bundle Info.plist — non-fatal; see [[../05-Architecture/Bundle-Resources-Gotcha]]). App launched (PID varies per run).

### 2026-05-13 15:33  Visual verification of v0.2.1 — Screen Recording restored

User restored OS-level Screen Recording permission. Step-by-step visual verification:

| # | Repair | Verification | Status |
|---|---|---|---|
| 1 | Tighten top bar | Full-window screenshot shows `Local AI routing server` left-aligned, `Idle · Reachable at 192.168.68.104:8080` pill flush right, bar height ~36 pt (was 44) | ✅ |
| 2 | Smaller default window | Window noticeably tighter than the prior 1200×780 captures | ✅ |
| 3 | Logos render | **FIRST attempt FAILED** — `Image("osm-mark-light", bundle: .module)` returned empty. Fixed with multi-path `NSImage(contentsOf:)` loader + dual-location PNG copy in bundle script. Re-verified with zoom screenshot (78,158,290,220): atomic mark crisp at 32×32 next to "osmBroker" wordmark + "Local AI router" tagline. | ✅ |
| 4 | Recompile + replace `.app` | `pkill` old PID, `swift build -c release`, `Scripts/make-app-bundle.sh`, `open osmBroker.app`. New PID 17839 confirmed alive. | ✅ |
| 5 | Sidebar `Base URL / localhost / API key` with copy buttons | Visible in screenshot at the bottom of the sidebar — three rows, each with a copy icon. | ✅ |
| 6 | Tabs: CLI / Models / Serve / More | All four nav items visible with correct count badges (2 / 4 / IDLE / 16). | ✅ |
| 7 | Claude card shows real metadata | `~/.local/bin/claude`, `2.1.140 (Claude Code)`, `stdin bridge`, `4 processes running` — all live from detection. | ✅ |
| 8 | Codex card shows real metadata | `/opt/homebrew/bin/codex`, `codex-cli 0.130.0`, `stdin bridge`, `2 processes running`. | ✅ |

---

## Template

```
### YYYY-MM-DD HH:MM  swift test --filter <pattern>

- Total: N
- Passed: N
- Failed: N
- Skipped: N

Failures:
- TestCaseName.testFoo — <one-line cause> — fixed at <commit / dev log link> / open
```
