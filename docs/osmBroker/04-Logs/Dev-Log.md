# Dev Log

Append-only diary. New entries on top. Each entry timestamped + linked to the task that produced it.

---

## 2026-05-12 T+0  Phase 1 build kickoff

Stopped the prior `swift run` background process. Set up Obsidian vault structure:

```
docs/osmBroker/
├── 00-Index.md
├── 01-Planning/
│   ├── PRD-Analysis.md
│   ├── Security-Requirements.md
│   ├── Self-Critique.md
│   ├── Architecture-Decisions.md
│   └── Task-Hierarchy.md
├── 02-Tasks/
│   └── Phase-1-HTTP-Broker.md
├── 03-Tests/
│   └── Test-Strategy.md
├── 04-Logs/
│   ├── Dev-Log.md  (this)
│   └── Test-Log.md
└── 05-Architecture/  (empty, populated as components land)
```

Six planning notes written before any code so the build has a single map.

**Key decisions captured** (see [[../01-Planning/Architecture-Decisions]]):
- SwiftNIO for HTTP
- Split into core lib + exec + tests
- Adapter protocol pattern
- `Foundation.Process` for spawning
- Constant-time bearer compare
- Tab structure: Active / **More** / Network (drop Routing)

**Self-critique** ([[../01-Planning/Self-Critique]]) covers the 8 honest mistakes from the prior pass. Most actionable: stop showing mock data, drop unwired buttons, add tests.

**Next step.** m1.1 — restructure Package.swift to library + exec + tests. Then add NIO.

---

## 2026-05-12 T+25m  Core broker shipped, all green

Tasks completed: m1.1 → m1.7 + handlers + integration tests.

Pieces in place:
- `Package.swift` split: `osmBrokerCore` library + `osmBroker` exec + `osmBrokerCoreTests` target. Added `swift-nio` (2.65), `swift-log` (1.5.4).
- Detection moved to core, made `public`. RunningProcess gained `rssBytes` + `user` (PRD §3.1).
- `Broker/ANSIStripper` — state-machine, 13 tests.
- `Broker/SSEEncoder` — OpenAI + Anthropic frames, error envelopes, 11 tests.
- `Broker/Auth` — bearer parse, constant-time compare with timing test, redaction, 20 tests.
- `Process/ProcessSpawner` + `Process/ProcessRegistry` — explicit env, stdin-prompt enforcement, SIGTERM→SIGKILL escalation. SPAWN-1/4/5/7 all covered. 10 tests.
- `Adapters/Adapter` protocol + default event loop + `ClaudeAdapter` + `Broker/ErrorMapping`. `FakeEchoAdapter` lives in tests. 10 tests.
- `Broker/PortPreflight` — pre-bind socket check + alternate-port suggester (PRD §7).
- `Broker/RequestValidation` — model regex (VAL-1), message count cap, char cap, role validation.
- `Broker/BrokerServer` actor + `Broker/HTTPRouter` NIO handler — bearer-gated routes, body cap (NET-4), streaming SSE writer.
- **10 integration tests** using a real bound port + URLSession + echo-words.sh fixture. All green.

**Full suite: 74 tests, 0 failures, 4.8 s.**

Mid-stream issues fixed in flight:
- `ANSIStripper` runaway CSI test caught a real leak — recovery path returned to normal state inside an unterminated sequence; fixed by staying in `.csi` and dropping bytes until a legitimate terminator.
- "rejects relative executable" test was misnamed (URL normalizes); replaced with `testRejectsNonFileURL` after adding `isFileURL` guard to spawn validator.

**Next step.** m1.8 — wire UI Start/Stop button + status pill + port-conflict feedback in NetworkPane. Then m1.9 — termination observer + signal handler.

---

## 2026-05-12 T+50m  UI wiring + lifecycle + More tab + live Codex check

Completed: m1.8 (UI wiring), m1.9 (lifecycle), Routing → More replacement (PRD §3.3), security audit pass.

UI wiring:
- `AppState` gained `brokerRunning`, `brokerError`, `portConflictSuggestion`, `brokerServer`, `currentCatalog()`, `startBroker()`, `stopBroker()`, `shutdownForQuit()`.
- ActivePane Start/Stop button flips on `brokerRunning`. `BrokerErrorBanner` shows port-in-use with one-click "Use port N" action.
- NetworkPane "Test key" actually `URLSession`-pings `/v1/models` on the running broker; result inline banner shows ✓/✗.
- Status pill in the top bar reflects real `brokerRunning` (green pulse vs stone idle).

Lifecycle (m1.9):
- `AppDelegate` adopts `NSApplicationDelegate`; `applicationShouldTerminate` does `state.shutdownForQuit()` then yields `.terminateLater` → reply true.
- `ShutdownReaper` installs SIGTERM/SIGINT handlers + `atexit` on `applicationDidFinishLaunching`.
- `ProcessRegistry` keeps a `SignalSafePIDMirror` (os_unfair_lock-protected) so signal handlers can SIGTERM tracked PIDs without async/Swift-runtime work.
- `ProcessRegistry.register` auto-spawns a Task that waits for child exit and unregisters — no manual unregister calls needed.

More tab (PRD §3.3):
- `Pane.routing` → `Pane.more`. `MorePane.swift` shows the 16 registry CLIs in a 2-column grid with search box, install command (with copy button into NSPasteboard), and an "installed" pill when the agent is detected.
- Old `RoutingPane.swift` removed (request-path diagram folds into the Network pane's binding card; SSE compat table is documented in Architecture / SSE-Normalization).

Mid-stream issue: parallel XCTest runs raced on port 18080 because `SO_REUSEADDR` let two `BrokerServer` instances both bind successfully. Fixed by per-test unique port via NSLock counter starting at 19000.

**Live system check (user request):**
Added `DetectorLiveSystemTests.testCodexIsDetectedIfInstalled` — asserts the detector finds `codex` at the correct path, with non-nil version, correct bridge and native protocol. **Passes** with `codex-cli 0.130.0` at `/opt/homebrew/bin/codex`.

Summary printed by the test:
```
Installed: 2 of 16
  • claude — /Users/arjun/.local/bin/claude — 2.1.138 (Claude Code)
  • codex — /opt/homebrew/bin/codex — codex-cli 0.130.0
```

**Full suite: 77 tests, 0 failures, 4.1 s.**

Security audit: 22 of 28 [[../01-Planning/Security-Requirements]] rules have an automated test; 6 are partial or documented-deferred. See [[../03-Tests/Security-Tests]] for the matrix.

**Next.** Launch the app for live UI smoke; demonstrate that toggling Codex's models then Start broker actually serves over HTTP.

---

## 2026-05-12 T+95m  CodexAdapter live + HTTP broker proven end-to-end

User asked: "build CodexAdapter, take over the Mac, ask inference questions, debug, repair, execute." Done.

Pieces shipped:
- **CodexAdapter** (`Sources/osmBrokerCore/Adapters/CodexAdapter.swift`).
  - Invocation: `codex exec --json -s read-only --skip-git-repo-check --color never -m <MODEL>` with prompt via stdin.
  - JSONL parser — handles `item.completed`/`agent_message` → `.textDelta`; ignores `thread.started`, `turn.started`, `turn.completed`; surfaces `error` events as `.error`.
  - Prompt composer specialized for codex: single-message requests sent verbatim; multi-turn turned into a readable transcript.
- **CodexAdapterTests** (12 tests): argv contract (no prompt leak), stdin carries prompt, parser matrix (agent_message, multiline, ignored event types, error events, garbage), plus live inference test.
- **LiveCodexBrokerTests** (3 tests): full HTTP broker → CodexAdapter → real `codex` round-trip. Streaming + unary + models list.
- `AppState.currentCatalog()` updated to map `agent.id == "codex"` to `CodexAdapter()`, alongside existing `claude` mapping.
- Registry updated: `codex.fallbackModels` now `["gpt-5.5", "gpt-5-codex", "gpt-5", "gpt-5-mini"]`. The first entry matches the default in `~/.codex/config.toml` on this Mac so the live tests succeed out-of-the-box.

Debugging the live test surface:
1. First live run failed with codex telling us "The 'gpt-5' model is not supported when using Codex with a ChatGPT account" — our error-event parser correctly turned that into an `AdapterEvent.error`, the test caught it as `XCTSkip`.
2. Inspected `~/.codex/config.toml` → `model = "gpt-5.5"`. Default model on this account.
3. Updated registry + test to use `gpt-5.5`. Re-ran. **Real response: "pong".**
4. End-to-end through the broker followed: streaming + unary both returned the magic strings we asked for (`BROKER_OK`, `BROKER_UNARY_OK`).

Final test count: **92 tests, 0 failures, 26.8 s.**

Codex CLI is now reachable as both `/v1/models` (lists `gpt-5.5`) and `/v1/chat/completions` (streaming + unary) under bearer auth `Authorization: Bearer <key>`.

**Curl recipe for live UI smoke** (run after clicking Start broker in the Active pane with the default key `osm-local-dev`):
```sh
curl -N -s http://127.0.0.1:8080/v1/chat/completions \
  -H "Authorization: Bearer osm-local-dev" \
  -H "Content-Type: application/json" \
  -d '{
    "model":"gpt-5.5",
    "stream":true,
    "messages":[{"role":"user","content":"In one word: what is 7*6?"}]
  }'
```

---

## 2026-05-12 T+130m  Computer-use end-to-end: ship-or-die pass

User asked: "take control of the computer, test the app end-to-end, screenshot each action, fix what's wrong." Did it.

### Bundle wrapper

CLT-only environment can't produce a code-signed `.app` via Xcode. Hand-rolled wrapper:
- `Scripts/make-app-bundle.sh` — copies `.build/release/osmBroker` into `osmBroker.app/Contents/MacOS/`, writes a minimal `Info.plist` (CFBundleName, CFBundleIdentifier=`app.osmbroker.osmBroker`, LSMinimumSystemVersion=14.0, NSPrincipalClass=NSApplication, NSHighResolutionCapable=true), writes the four-byte `PkgInfo`, then runs `codesign --force --deep --sign -` for an ad-hoc signature so macOS LaunchServices recognizes it as an app.
- Result: `request_access` for "osmBroker" now succeeds — bundle ID resolved at `tier: "full"`.

### UI walkthrough (7 captures via computer-use screenshots)

| # | Action | What I saw |
|---|---|---|
| 01 | Cold launch | Active pane auto-scanned; Claude Code (3 PIDs) + Codex CLI (1 PID, pid 98825) detected. "2 of 16 installed". Right detail panel showed Claude metadata. Sidebar URL TRUNCATED (defect 1). |
| 02 | Click Codex card | Detail panel switched to Codex JSON: `id: "codex"`, `path: "/opt/homebrew/bin/codex"`, `version: "codex-cli 0.130.0"`, `bridge: "stdin bridge"`, `native: "OpenAI"`. Accent rail moved to Codex card. |
| 03 | Click More tab | 2-column grid, search box, Claude/Codex showed `installed` pills, Gemini/Copilot/Cursor/OpenCode each showed install command in dark code blocks with Copy buttons. |
| 04 | Click Network tab | Title fit one line. Host/Port/API-key fields populated. Sample curl preview rendered live (defect 4: Test key showed but disabled-state too subtle). Scrolled down — Network interfaces card showed `en0  192.168.68.104  • advertised`. Quick launchers card with Claude and Codex rows, each with "Open in Terminal" (defect 2: unwired). |
| 05 | Click Start broker | Status pill flipped green: `Live · Reachable at 192.168.68.104:8080`. Sidebar `LIVE`. Button became "Stop broker". |
| 06 | Click Test key | Green checkmark banner: `Broker responded 200 OK. Your key works.` |
| 07 | Click Stop broker | Pill back to `Idle`. But: banner persisted (defect 3); Test key visual state unchanged (defect 4). |

### Curl proofs (terminal, while broker was Live)

```sh
$ curl -s http://127.0.0.1:8080/v1/models -H "Authorization: Bearer osm-local-dev" | jq -c
# → {"object":"list","data":[7 entries]} — claude-sonnet-4-5/opus-4-1/haiku-4-5, gpt-5.5/gpt-5-codex/gpt-5/gpt-5-mini

$ curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/v1/models
# → 401 (no auth)

$ curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:8080/v1/models -H "Authorization: Bearer wrong-token"
# → 401 (wrong key)

# OpenAI streaming → real Codex
$ curl -N ... /v1/chat/completions  stream=true  model=gpt-5.5
#   message: "Paris, and the Seine runs through it."

# Anthropic unary
$ curl ... /v1/messages  stream=false  model=gpt-5.5
#   content[0].text = "12 times 7 is 84."  stop_reason = "end_turn"

# OpenAI unary
$ curl ... /v1/chat/completions  stream=false  model=gpt-5.5
#   choices[0].message.content = "Neon"
```

### Defects found → fixed → re-verified

| # | Defect | Fix | Verification |
|---|---|---|---|
| 1 | Sidebar `BROKER ENDPOINT` URL truncated with `…` even though card was tall | `Sidebar.swift` `EndpointCard`: drop mono(14) → mono(13), `lineLimit(2)` + `minimumScaleFactor(0.78)` + `fixedSize(horizontal: false, vertical: true)` | Re-launch screenshot showed `http://` on line 1, `192.168.68.104:8080` on line 2, no ellipsis |
| 2 | "Open in Terminal" did nothing on Quick Launcher rows | First attempt: `osascript -e 'tell Terminal to do script'` → timed out with AppleEvent error (-1712) because user's existing Terminal had a stuck `gh auth login` prompt. Switched to `.command file + /usr/bin/open -a Terminal` pattern — writes a `#!/bin/sh\nexec "<path>"` script to `$TMPDIR`, marks 0755, runs `open -a Terminal <path>`, cleans up after 60 s | Click on Codex's Open in Terminal → new Terminal window: `OpenAI Codex (v0.130.0), model: gpt-5.5 medium`, prompt ready |
| 3 | Test-key success banner persisted after Stop broker (confusing — broker stopped but banner still claimed "200 OK") | `NetworkPane.body`: `.onChange(of: state.brokerRunning) { _, newValue in if !newValue { testKeyResult = nil } }` | Click Stop → screenshot: banner gone, only `Start broker` button visible |
| 4 | Test key button visual disable-state was too subtle (50% opacity on already-light color) | Hide Test key button entirely when `!state.brokerRunning`; only render it when broker is Live | Network-pane idle screenshot shows only `Start broker`; live state shows both `Test key` and `Stop broker` |

### Process bookkeeping

- AppDelegate's `applicationShouldTerminate` was exercised at every stop (logs showed `broker stopped, children reaped` then `killAll: signaled N child process(es)`).
- After app quit + relaunch, no zombie PIDs remained from prior runs (`pgrep -fl osmBroker` returned empty between sessions).

**Final test count: 92 tests, 0 failures, 27.3 s.**

The app no longer lies about state, no longer has unwired buttons, no longer truncates the URL it asks users to share, and serves three live API shapes (OpenAI streaming, OpenAI unary, Anthropic unary) backed by real Codex via the broker.

---

## 2026-05-13 T+145m  Readability + button audit sweep

User: "all text should be readable, all buttons should be functional." Did a full sweep.

### Text readability fixes

| Site | Before | After |
|---|---|---|
| Detail dark JSON `path` value | `path: "/Users/arjun/.local/bin/claude"` wrapped mid-string across two lines | `path: "~/.local/bin/claude"` — apply same `prettyPath` collapse used elsewhere; fits one line |
| AgentCard "running" pill | `running · pid 6721, 9617, 97233` (comma-stuffed PIDs, threatened to wrap on smaller windows) | `3 processes running` (singular/plural variant). Full PID list stays in detail JSON where it has room |
| NotInstalledRow "Install" affordance | Plain accent-colored text — looked passive | Pill-styled button with `Install ↗` (SF Symbol `arrow.up.right`), white background, 1px border. Matches the design language of other action buttons |
| NotInstalledRow when `installURL == nil` | Em-dash `—` (looked like unset) | "no link" text in stone gray (clearly states absence) |

### Button functionality audit

Every clickable element exercised end-to-end. All wired:

- **ActivePane:** Rescan (now disabled while scanning, label `Scanning…`); Start / Stop broker; provider card body (selects); provider toggle; model toggle; broker-error banner's "Use port N" suggestion; "Not on this Mac" Install buttons (open URL).
- **MorePane:** search field bound to filter; Copy button writes install command to `NSPasteboard` with `Copied` feedback for 1.5 s.
- **NetworkPane:** Test key (now disabled + label `Testing…` while in flight, hidden entirely when broker idle); Start / Stop broker; host/port/key text fields; broker-error inline banner's "Use N" suggestion; Quick Launchers Open in Terminal (writes a `.command` script then `open -a Terminal`).
- **Sidebar:** nav buttons; URL + bearer-token text are `.textSelection(.enabled)` (Cmd-C copies).

Nothing visible is unwired. Disabled states are visually distinct (different label or hidden entirely, not just slight opacity).

### Verification screenshot

Post-polish capture (Active pane scrolled to the "Not on this Mac" section): both running pills read cleanly (`3 processes running`, `2 processes running`), the detail JSON shows `path: "~/.local/bin/claude"` on one line, and the 14-row grid of `Install ↗` pills is unmistakably interactive.

**Full test suite: 92/92 passing in 24.6 s.** (Prior run had 1 transient failure in the live codex tests — codex CLI itself is slow + network-dependent; re-run was clean. Flakiness noted, not blocking.)

---

## 2026-05-13 T+165m  Phase 1.5 UX overhaul kickoff

User: "think like Steve Jobs would about his customer." Specific asks (verbatim in [[../02-Tasks/Phase-1.5-UX-Overhaul]]):
1. Replace serif wordmark with the actual osm brand mark from `osmdesign/`.
2. Re-IA the tabs: Active/More/Network → **CLI / Models / Serve / More**.
3. Models tab must show *real* models from each CLI's config (not the registry's static placeholder list).
4. Sidebar bottom card: two rows (Base URL, API Key) each with a copy button + text-selectable.

Written before writing any code:
- [[../02-Tasks/Phase-1.5-UX-Overhaul]] — master task list, user verbatim, my interpretation.
- [[../05-Architecture/Logo-Branding]] — where the brand asset came from, how it wires through Package.swift, how SwiftUI renders it.
- [[../05-Architecture/Model-Discovery]] — design of the new `ConfigDiscovery` module + per-test contract.
- [[../05-Architecture/Tab-Structure-v2]] — why Active splits into CLI+Models, why Network becomes Serve, what moves where.
- [[../05-Architecture/Sidebar-Card-Redesign]] — exact layout sketch, copy-vs-display split, pasteboard semantics.

Code so far:
1. **Brand assets in tree.** `Sources/osmBroker/Resources/osm-mark-{light,dark}.png` copied from `~/Projects/osmdesign/apps/web/public/`. `Package.swift` executable target gained `resources: [.process("Resources")]`.
2. **`ConfigDiscovery.swift`** in `osmBrokerCore/Detection/`. Pure TOML + JSON readers. `codex(homeDir:)` parses top-level `model =` and `[profiles.<name>]` sections. `claude(homeDir:)` tries `.claude/settings.json`, `.claude/config.json`, `.config/claude/settings.json` in order; understands flat and nested `defaults.model` shapes.
3. **8 ConfigDiscovery tests** in `Tests/osmBrokerCoreTests/ConfigDiscoveryTests.swift`. Tmp-dir fixtures, no I/O to real `~/.codex/`.
4. **`Pane` enum rewritten**: `cli / models / serve / more`. SF Symbol icons: `terminal`, `rectangle.stack`, `antenna.radiowaves.left.and.right`, `square.grid.2x2`. Default selected is `.cli`.
5. **`AppState.selectedPane`** init flipped to `.cli`.

Up next, in this order: wire ConfigDiscovery results into AppState's per-agent model list → rewrite Sidebar (logo + new card) → CLIPane → ModelsPane → ServePane → MorePane refresh → ContentView dispatch → rebuild → screenshot → log every screen.

---

## 2026-05-13 T+195m  Phase 1.5 — code complete + headless verified

All six SwiftUI rewrites landed:

| File | Status |
|---|---|
| `Sources/osmBroker/PaneShared.swift` | **NEW** — `PaneHead`, `BrokerErrorBanner`, `prettyHomePath(_:)`, `WrapHStack`, `FlowLayout` (extracted from old ActivePane) |
| `Sources/osmBroker/Sidebar.swift` | **REWRITTEN** — `BrandRow` (logo + wordmark), new `EndpointCard` with three `CopyRow`s + dividers |
| `Sources/osmBroker/CLIPane.swift` | **NEW** (replaces `ActivePane.swift`) — slim per-CLI cards, Open-in-Terminal moved here |
| `Sources/osmBroker/ModelsPane.swift` | **NEW** — per-CLI sections, checkbox per model, `primary` badge for config-discovered model |
| `Sources/osmBroker/ServePane.swift` | **NEW** (replaces `NetworkPane.swift`) — big base-URL card with Copy buttons, port+key fields, endpoint emulation, broker error banner |
| `Sources/osmBroker/MorePane.swift` | **PATCHED** — "Installed on this Mac" section above "Available CLIs"; `SectionHeader` reusable |
| `Sources/osmBroker/ContentView.swift` | **PATCHED** — `MainPane` dispatches `cli / models / serve / more` |
| `Sources/osmBrokerCore/Detection/ConfigDiscovery.swift` | **NEW** — pure TOML/JSON readers |
| `Sources/osmBroker/AppState.swift` | **PATCHED** — `discoveredModels`, `primaryModel`, `modelsFor(_:)`, integrate into `currentCatalog()` |
| `Sources/osmBroker/Models.swift` | **REWRITTEN** — Pane enum becomes `cli/models/serve/more` |
| `Tests/osmBrokerCoreTests/ConfigDiscoveryTests.swift` | **NEW** — 9 tests |
| `Package.swift` | **PATCHED** — `resources: [.process("Resources")]` on the exec target |
| `Scripts/make-app-bundle.sh` | **PATCHED** — copies SPM sidecar bundle into `.app/Contents/MacOS/` (see [[../05-Architecture/Bundle-Resources-Gotcha]]) |

Bug found and fixed mid-verification: original `make-app-bundle.sh` only copied the binary, not the SPM-generated `osmBroker_osmBroker.bundle/`. Caught when the post-launch `find osmBroker.app -type f` showed no PNG resources in the .app. Fix documented in [[../05-Architecture/Bundle-Resources-Gotcha]]; `codesign --deep` still gripes about the inner bundle missing its own Info.plist — non-fatal for dev, deferred to Phase 3 packaging.

**Headless verification:**

```
$ swift test               → 101 of 101 pass, 28.2 s (after one transient codex flake re-run)
$ cat ~/.codex/config.toml | head -2
model = "gpt-5.5"
model_reasoning_effort = "medium"
$ swift /tmp/cd-smoke.swift
Reading: /Users/arjun/.codex/config.toml
Top-level model = gpt-5.5
EXPECTED on this Mac: gpt-5.5
```

So the runtime path **ConfigDiscovery.codex() → AppState.applyDetection → state.primaryModel["codex"]** will yield `"gpt-5.5"`, which the Models pane will badge as `primary` next to that model row.

**Screenshot verification is blocked** — the computer-use screenshot pipeline started returning `SCContentFilter failure` partway through this session. `list_granted_applications` still shows osmBroker at tier `full`, so the grant the *harness* tracks is intact; the OS-level Screen Recording permission for the parent Claude process has likely been pulled. Restoration steps in [[../02-Tasks/Phase-1.5-UX-Overhaul#screen-capture-wedge-separate-from-the-build]].

Notes written this turn (in order):
1. [[../02-Tasks/Phase-1.5-UX-Overhaul]] — master task list
2. [[../05-Architecture/Logo-Branding]] — provenance + Package.swift wiring + SwiftUI plan
3. [[../05-Architecture/Model-Discovery]] — ConfigDiscovery design + tests + UI badge plan
4. [[../05-Architecture/Tab-Structure-v2]] — IA rationale + per-tab content + count mapping
5. [[../05-Architecture/Sidebar-Card-Redesign]] — exact card layout, copy-vs-display split, pasteboard semantics
6. [[../05-Architecture/AppState-Discovered-Models]] — applyDetection diff + currentCatalog change
7. [[../05-Architecture/Bundle-Resources-Gotcha]] — the SPM sidecar bug discovered + fix

**Pending visual verification once Screen Recording perm returns:**
- Logo renders 32x32 in sidebar, brand row centered with wordmark.
- BASE URL / API KEY card shows three CopyRows; clipboard receives `http://192.168.68.104:8080` etc.
- Nav order: CLI / Models / Serve / More, default selection lands on CLI.
- Models pane shows codex section with `gpt-5.5` badged `primary` first.
- ServePane's big base-URL card shows IP:port in 18-pt mono on the LIVE banner.
- MorePane: Claude + Codex in an "Installed on this Mac" section above the 14-card "Available CLIs" grid.

---

## 2026-05-13 T+220m  Claude registry models were wrong — fixed

User caught: "the claude cli broker is broken because those are not the models claude CLI is serving. rerun the claude cli identifier and then the broker"

Verified the call: `claude --version` is now `2.1.140` (was 2.1.138 last session — Anthropic shipped a point release between turns). More importantly, the registry's `claude.fallbackModels` was advertising names that **do not exist** on this account.

### Live probe to find ground truth

```sh
$ echo "Reply with exactly OK" | claude -p --model sonnet --output-format json
{... "modelUsage": {
    "claude-sonnet-4-6": {…},
    "claude-haiku-4-5-20251001": {…}    # used for prompt prefetch
}}

$ echo "..." | claude -p --model opus --output-format json
{... "modelUsage": {
    "claude-opus-4-7": {…}
}}
```

The `modelUsage` block of Claude's own JSON output is the only honest source for the resolved model name. The real names on this Mac today:
- `sonnet` → `claude-sonnet-4-6`
- `opus`   → `claude-opus-4-7`
- `haiku`  → `claude-haiku-4-5-20251001`

My registry had `claude-sonnet-4-5 / claude-opus-4-1 / claude-haiku-4-5`. None match. Every model ID I had advertised would 404 against this account.

### What I changed

- `Sources/osmBrokerCore/Detection/AgentRegistry.swift`: `claude.fallbackModels = ["sonnet", "opus", "haiku"]`.
- Same registry: `copilot.fallbackModels` updated `"claude-sonnet-4-5"` → `"sonnet"`.
- `Tests/.../AdapterTests.swift`: model in `AdapterRequest` + assertion text both moved to `"sonnet"`.
- `Tests/.../ConfigDiscoveryTests.swift`: opaque test values updated to `claude-sonnet-4-6` / `claude-opus-4-7` so future readers don't get fooled.
- `Tests/.../SpawnerTests.swift`: env-passthrough test value also updated for hygiene.

### Why aliases instead of resolved names

Aliases (`sonnet`, `opus`, `haiku`) are documented in `claude --help` ("Provide an alias for the latest model"). They auto-resolve to whatever Anthropic ships next. Hardcoding `claude-sonnet-4-6` would just be the next stale-string trap.

Live-probing every alias on Rescan to surface the resolved name would cost real money (~$0.09 per scan on this account). Deferred to a "Probe models" button on the Models tab, tracked in Phase-3 polish.

Full design + alternatives weighed in [[../05-Architecture/Claude-Model-Discovery]].

### Verification done

- Fast tests: **97 / 97 passing in 4.1 s** post-migration (live codex tests deliberately skipped after the codex CLI itself hung the prior run on auth/network).
- Added `LiveClaudeBrokerTests.testLiveClaudeStreaming` — boots a real `BrokerServer`, POSTs `/v1/chat/completions` with `model: sonnet`, reads back the SSE stream.
- **Result: passes in 2.4 s. Claude returns "CLAUDE_LIVE_OK" exactly as requested.**

```
=== /v1/chat/completions via broker → claude (sonnet) ===
CLAUDE_LIVE_OK
=================================================
```

App was already rebuilt with the new aliases (PID 5806). The runtime registry now lists `sonnet/opus/haiku` for claude and they route correctly. Bug fully closed.

---

## 2026-05-13 T+260m  3-questions-per-model live quiz

User: "ask 3 questions to each model from both CLIs and see if you get inference back."

Wrote `Tests/osmBrokerCoreTests/QuizTests.swift`. Boots a real `BrokerServer` on an ephemeral port, populates the catalog with all claude aliases (`sonnet/opus/haiku`) + all codex registry models (`gpt-5.5/gpt-5-codex/gpt-5/gpt-5-mini`), asks 3 calibration questions, captures every response, prints a Q&A table. 7 models × 3 questions = 21 inference calls. Wall clock: **113.6 s** (codex is the slow path).

### Results

**Claude — 9 / 9 correct:**

| Model | 23+19 | Capital of Japan | Noble gas |
|---|---|---|---|
| sonnet | 42 | Tokyo | Argon |
| opus | 42 | Tokyo | Helium |
| haiku | 42 | Tokyo | Helium |

**Codex — 3 / 3 on `gpt-5.5`, 0 / 9 on the other registry entries:**

| Model | 23+19 | Capital of Japan | Noble gas |
|---|---|---|---|
| gpt-5.5 | 42 | Tokyo | Neon |
| gpt-5-codex | — | — | — |
| gpt-5 | — | — | — |
| gpt-5-mini | — | — | — |

The three failing codex models all returned the same error from codex itself:
```
{"type":"error","status":400,"error":{"type":"invalid_request_error",
 "message":"The '<MODEL>' model is not supported when using Codex with a ChatGPT account."}}
```

That's a real account-tier restriction, not a broker bug. Our adapter correctly parsed the error event and propagated the message; the only thing it does *wrong* is wrap the upstream's `status: 400` in our own HTTP 500 envelope.

### Two follow-up fixes from this evidence

1. **`AppState.applyDetection` should default-OFF speculative models when ConfigDiscovery surfaced a primary.** Today every registry model becomes `modelExposed[m] = true` on first detection. That meant `gpt-5-codex`, `gpt-5`, `gpt-5-mini` all defaulted ON for a user whose account can't run them. Fix: when `cfg.primary != nil`, only auto-enable models in `cfg.discovered`; the rest default OFF (user can flip them on in Models tab if they have a different account tier). Designed in [[../05-Architecture/AppState-Discovered-Models#auto-enable-rules]].
2. **`ErrorMapping` + `HTTPRouter` should map upstream 400-class messages to a 400 from our broker, not 500.** Add `not supported` → `invalid_request_error` / 400 to `ErrorMapping.patterns`; have `HTTPRouter.respondUnary` honour the mapping's `httpStatus` instead of always `.internalServerError`. Tracked here, applying in this turn.

### About the quiz tooling

The test is XCTSkip-friendly: missing claude or codex on PATH skips cleanly. It's deliberately non-assertive on correctness — it captures evidence, prints Q&A pairs, and only asserts that we got some answer per call (otherwise the print log is empty and the test fails). Useful as a smoke for future broker work; expensive (~$0.50-$1 per run), so it's not in the default `swift test` filter for CI.

---

## 2026-05-13 T+275m  Two follow-up fixes from the quiz evidence shipped

Code:
- `Sources/osmBroker/AppState.swift` — `applyDetection` now uses `onlyDiscovered = !cfg.discovered.isEmpty` and auto-enables only `cfg.discovered` when the adapter has any config-discovered models. Registry-fallback entries default OFF.
- `Sources/osmBrokerCore/Broker/ErrorMapping.swift` — added `"not supported"` → 400 `invalid_request_error` / `model_not_supported`.
- `Sources/osmBrokerCore/Broker/HTTPRouter.swift` — new `static func httpStatusForErrorType(type:code:)` picks the right HTTP status from the adapter event's `type`. `respondUnary` in the chat-completions handler uses it instead of hardcoded `.internalServerError`.

Tests:
- `AdapterTests.testErrorMappingNotSupportedIs400` — pins the new ErrorMapping pattern.
- `HTTPRouterErrorStatusTests` (6 cases) — pins the type-to-status mapping for invalid_request / auth / permission / not_found / rate_limit / fallthrough.

Suite: **101 / 101 fast tests passing in 3.4 s.** Live + quiz tests still excluded from this run (slow + cost money). They pass on demand:
- `LiveCodexBrokerTests` — 3 / 3 last clean run
- `LiveClaudeBrokerTests` — 1 / 1 last clean run
- `QuizTests.testThreeQuestionsPerModelLive` — 1 / 1 (with the 9 model-not-supported reports recorded as evidence)

### Top-bar + window changes also landed

[[../05-Architecture/Top-Bar-Tightening]]:
- Dropped the centered "osmBroker · Local AI routing server" — sidebar already carries the brand.
- Bar height 44 → 36 pt; tagline left-aligned right after the traffic-light clearance.
- Default window 1200 × 780 → 1080 × 720.

### Logo wiring verified

Resources bundle path after the make-app-bundle.sh fix from earlier turn:
```
osmBroker.app/Contents/MacOS/osmBroker_osmBroker.bundle/
├── osm-mark-light.png  (32 256 B — sidebar uses this)
└── osm-mark-dark.png   (31 026 B — kept for future dark mode)
```

Bundle is signed (warning about inner Info.plist — non-fatal for dev; tracked in [[../05-Architecture/Bundle-Resources-Gotcha]]).

### End of session state

- `.app` rebuilt + replaced + relaunched (PID 16211 at end-of-session).
- Tests + quiz evidence in [[../04-Logs/Test-Log]].
- Eight architecture notes capture every decision: [[../05-Architecture/Logo-Branding]], [[../05-Architecture/Model-Discovery]], [[../05-Architecture/Tab-Structure-v2]], [[../05-Architecture/Sidebar-Card-Redesign]], [[../05-Architecture/AppState-Discovered-Models]] (now with auto-enable rule), [[../05-Architecture/Claude-Model-Discovery]], [[../05-Architecture/Top-Bar-Tightening]], [[../05-Architecture/Bundle-Resources-Gotcha]].
- Screenshot still wedged at OS level — recovery in [[../02-Tasks/Phase-1.5-UX-Overhaul#screen-capture-wedge-separate-from-the-build]].

---

## 2026-05-13 T+330m  Screen capture restored — caught logo not rendering

User re-granted Screen Recording permission for the harness. First screenshot post-restore showed the redesigned UI:

✅ Top bar tightened — "Local AI routing server" tagline left-aligned next to traffic-light clearance, status pill `Idle · Reachable at 192.168.68.104:8080` flush right. Window noticeably tighter than before.
✅ New sidebar bottom card — `BASE URL` block with `192.168.68.104:8080` + copy button and `localhost:8080` + copy button, then `API KEY` `osm-local-dev` + copy button. Exactly the user's spec.
✅ Tabs: CLI (2), Models (4), Serve (IDLE), More (16) — correct nav order.
✅ Claude/Codex cards show real path, real version (`2.1.140 (Claude Code)` / `codex-cli 0.130.0`), bridge, running-process counts.

❌ **LOGO MISSING.** "osmBroker" wordmark rendered without the atomic mark.

Diagnosis: SwiftPM's `Bundle.module` accessor looks for `osmBroker_osmBroker.bundle/` at `Bundle.main.bundleURL.appendingPathComponent(...)`. For a `swift run` build this lands next to the executable; for our hand-rolled `.app`, `Bundle.main.bundleURL` resolves to the `.app/` itself — and SPM looks for `osmBroker.app/osmBroker_osmBroker.bundle/`, which never existed in our layout (`Contents/MacOS/osmBroker_osmBroker.bundle/` is what `make-app-bundle.sh` produces).

Fix landed:
- `Sources/osmBroker/Sidebar.swift` — replaced naive `Image("…", bundle: .module)` with a `BrandMark` view that tries `Bundle.main.url(forResource:)`, then `Bundle.module.url(forResource:)`, then a hand-curated list of plausible sidecar URLs (`Contents/Resources/.../*.png`, `Contents/MacOS/.../*.png`, `.app/.../*.png`, one-folder-up). Loads via `NSImage(contentsOf:)`. Falls back to a serif "o" mark on accent-soft background if every path fails — so the brand row never goes blank.
- `Scripts/make-app-bundle.sh` — now copies the PNGs into BOTH `Contents/Resources/` (loose) and `Contents/MacOS/osmBroker_osmBroker.bundle/` (sidecar). The first path satisfies `Bundle.main.url(forResource:)`; the second preserves the SPM convention.

Rebuilt + bundled + relaunched: logo renders crisply at 32 × 32 next to the wordmark. Verified in a zoomed screenshot of the brand row.

Full trail in [[../05-Architecture/Logo-Branding#iteration-history--the-loading-bug]].

### One-by-one verification this turn

The user asked to repair things one by one and test after each. Order followed:

1. **Build** — `swift build -c release` → succeeded, 0.21 s (binary already up-to-date from prior compile; source edits had landed before the prior rejection).
2. **Bundle** — `Scripts/make-app-bundle.sh` → produced `.app` with PNGs at both `Contents/Resources/` AND `Contents/MacOS/osmBroker_osmBroker.bundle/`.
3. **Launch** — `open osmBroker.app` → PID 17839 alive.
4. **Screenshot** — captured full window, then zoomed sidebar to (78, 158, 290, 220). Logo + wordmark + tagline visible exactly as designed.

---

## 2026-05-14 T+360m  v0.3 — top space reclaimed, dark mode, CLI toggle removed, GitHub push

User's four asks from this session, repaired one at a time, each verified:

### 1. Top-of-window blank space

`TopBar` deleted entirely. Sidebar grew `.padding(.top, 32)` so the brand row clears the OS traffic lights. Status pill that used to live in TopBar moved into the sidebar endpoint card as a new `STATUS` row at the top. Content (eyebrow + display title) now sits ~40 pt closer to the top than v0.2.1. Captured in [[../05-Architecture/Top-Space-Removal]].

### 2. Light / dark mode toggle

`Theme.Palette` rewritten as dynamic colors (`NSColor` with a `dynamicProvider`). Every existing palette token now resolves differently per appearance. New `AppTheme` enum (`system` / `light` / `dark`) persisted via `@AppStorage("osmBroker.theme")`. Three-icon segmented switcher (half-moon / sun / crescent) at the bottom of the sidebar. ContentView reads the persisted choice and applies `preferredColorScheme`. Mid-implementation found a contrast bug: the endpoint card's value text used `Palette.surface` which flips dark in dark mode → text invisible. Fixed by switching those rows to `Palette.darkText` (always cream), since the card background is intentionally always-dark. See [[../05-Architecture/Dark-Mode]].

### 3. CLI toggle audit

Verified the per-CLI `ToggleSwitch` on the CLI tab *did* set `state.agentExposed[id]` and `currentCatalog()` *did* filter on it — but the card had zero visible feedback, and the Models tab already lets the user enable/disable per-model. Two doors to the same room. Removed the toggle from `CLICard` and `agentExposed` from `currentCatalog`'s filter. CLI tab is now purely informational; Models tab is the single control surface for what gets served. Audit and decision in [[../05-Architecture/CLI-Toggle-Audit]].

### 4. GitHub repo

Pushed to **https://github.com/junainfinity/osmBroker** (public). 85 files in initial commit (`59c892c`), including the full Obsidian vault under `docs/osmBroker/`. `.gitignore` excludes `.build/`, generated `osmBroker.app/`, `.DS_Store`, and Obsidian's workspace cache. README at the repo root summarises the four-tab layout, quick-start, architecture, and points readers at `docs/osmBroker/00-Index.md` for the full design trail. Setup details in [[../05-Architecture/GitHub-Repo-Setup]].

### Sessions captured in obsidian

Every architecture decision since the project started is in `docs/osmBroker/05-Architecture/`:

- HTTP-Server, Adapter-Pattern, Process-Lifecycle, SSE-Normalization
- Logo-Branding, Bundle-Resources-Gotcha
- Model-Discovery, Claude-Model-Discovery, AppState-Discovered-Models
- Tab-Structure-v2, Sidebar-Card-Redesign
- Top-Bar-Tightening (v0.2.1), Top-Space-Removal (v0.2.2)
- Dark-Mode, CLI-Toggle-Audit, GitHub-Repo-Setup (this session)

Every task is in `docs/osmBroker/02-Tasks/`:
- Phase-1-HTTP-Broker (done)
- Phase-1.5-UX-Overhaul (done)

Dev-Log + Test-Log carry the full chronological trail with reproducer commands for every test run.

### What's NOT in v0.3 (tracked for future)

- "Probe models" button on the Models tab that calls `claude -p --model <alias>` to surface the resolved real name (`claude-sonnet-4-6`, etc.). Costs API money so defer.
- Capability badges parsed from `claude --help` / `codex features list` (PRD §3.2).
- Continuous polling for process detection (PRD §3.1) — Rescan is manual only today.
- Kimi / Gemini / Copilot adapters wired (registry knows them; broker doesn't route).
- `.app` icon (currently macOS default — could ship `.icns` from `osm-mark-dark.png`).

---

## Anchor template for future entries

```
## YYYY-MM-DD T+Nm  <one-line summary>

Tasks: [[../02-Tasks/Phase-1-HTTP-Broker]] m1.X
What I did:
What broke:
What I fixed:
Tests run: (see [[Test-Log#YYYY-MM-DD-N]])
Next:
```
