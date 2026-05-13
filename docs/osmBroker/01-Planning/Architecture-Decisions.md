# Architecture Decisions

ADRs in the lightweight Michael Nygard style: context, decision, consequences. Each ADR is small enough to fit one screen.

---

## ADR-1 — SwiftNIO for the HTTP server

**Context.** The PRD names SwiftNIO or Vapor. We need a long-running server that handles streaming, doesn't pull in a whole web framework, and is officially supported by Apple.

**Decision.** Use `swift-nio` (and `nio-http1`, `nio-posix`) directly. Skip Vapor.

**Why not Vapor.** Vapor is a full framework with its own DI, routing, middleware, and ORM hooks. Overkill for ten endpoints. Increases bundle size and build time, hides what's happening.

**Why not Network.framework.** Apple-native, no deps, but you write the HTTP parser yourself or pull in a third party. SwiftNIO is what Apple writes when they want HTTP.

**Consequences.** First build will be ~2-3 min while NIO compiles. Source code structure looks more like a NIO sample than a Vapor app. The trade is fewer abstractions to learn and clearer code paths.

---

## ADR-2 — Split into `osmBrokerCore` library + `osmBroker` executable

**Context.** SwiftUI views in an `executableTarget` cannot be cleanly unit-tested (no way to depend on the exec from a test target). The prior pass had everything in one exec and zero tests as a result.

**Decision.** Create `osmBrokerCore` library target with: detection, broker server, adapters, process spawning, ANSI stripper, SSE encoder, auth, error mapping, registries. `osmBroker` exec depends on it and adds only SwiftUI + AppState. Tests depend only on `osmBrokerCore`.

**Consequences.** Clean separation, all logic unit-testable. Exec target shrinks to a few SwiftUI files and an `@StateObject` that calls into core. Core has no `import SwiftUI`.

---

## ADR-3 — Adapter protocol with per-CLI implementations

**Context.** PRD §5 lists per-CLI profiles (Codex, Claude, Kimi, Gemini) each with idiosyncratic invocation: `claude -p`, `codex exec --json`, `kimi acp`, Gemini with reasoning filter. Handover doc §"Complete Local CLI Adapter Inventory" has 16 of these. We need a clean dispatch.

**Decision.** Adapter protocol:

```swift
public protocol Adapter: Sendable {
    var def: AgentDef { get }
    func buildArguments(prompt: String, model: String, options: AdapterOptions) -> [String]
    var promptViaStdin: Bool { get }
    func streamHandler(...) -> AdapterStreamHandler   // parses CLI output → AdapterEvent
}
```

`AdapterStreamHandler` is per-adapter (one for stream-json, one for plain stdout, one for ACP JSON-RPC, etc.). Server flow is adapter-agnostic: look up adapter for model, build args, spawn, write stdin, attach stream handler, emit events.

**Consequences.** Adding an adapter = one Swift file with no server changes. Mirrors the handover doc's `AGENT_DEFS` pattern. Each adapter is independently testable with a fake binary.

---

## ADR-4 — Foundation `Process` for subprocess spawning (not posix_spawn directly)

**Context.** We need to spawn child CLIs with stdin/stdout/stderr pipes and signal management. `Process` is high-level but battle-tested. `posix_spawn` is lower-level but reinvents file-descriptor plumbing.

**Decision.** Use `Process` with explicit `Pipe()` for the three FDs. Track the underlying `processIdentifier` for signal escalation. Set environment explicitly (whitelist). Use `terminationHandler` for crash detection.

**Consequences.** Easy to reason about. Mockable in tests. Loses some fine-grained FD control (e.g. cannot easily set `O_CLOEXEC` on all FDs) — accepted for Phase 1; revisit if we see FD leaks.

---

## ADR-5 — Hand-roll the SSE encoder

**Context.** SSE format is trivial: `data: <json>\n\n`. Pulling in a library is overkill.

**Decision.** Internal `SSEEncoder` type emits `event` / `data` / `retry` lines per the spec. Unit tested with table-driven cases.

**Consequences.** ~30 lines of code we own and test.

---

## ADR-6 — Constant-time bearer comparison with `timingsafe_bcmp`

**Context.** Naive `==` on Strings is short-circuit; an attacker can measure response time to discover the token prefix byte by byte over many requests. Real attack on real APIs.

**Decision.** Compare the raw bytes with `timingsafe_bcmp` (available on Darwin via `Security` / libcompiler-rt) or a Swift loop that XORs every byte and OR-accumulates. Test exercises both equal-prefix-differ-late and equal-length-no-match cases.

**Consequences.** One small function. One test. Sleeps soundly.

---

## ADR-7 — No TLS in Phase 1

**Context.** TLS adds cert management we don't want to take on. The PRD doesn't require it.

**Decision.** Phase 1 ships plaintext HTTP on the LAN. The README and the UI both make this explicit ("Plaintext HTTP — use only on trusted networks").

**Mitigations.** Bearer auth is required (AUTH-1). LAN-only by default. User can put nginx/Caddy in front for TLS if they want.

**Consequences.** Easier delivery. Documented trade-off. Tracked in [[Phase-3-Polish-and-Marketplace]] for a later milestone.

---

## ADR-8 — Tab structure: Active / More / Network

**Context.** PRD §3.3 explicitly calls for an Active dashboard and a More marketplace. Prior pass had Active / Routing / Network. Routing is a visualization of the engine, not a tab destination.

**Decision.** Replace Routing tab with More tab. Routing visualization (request path diagram, model toggles, SSE compat table) folds into:
- The model toggles → into Active pane's right-side detail panel
- The request path diagram + SSE compat table → into Network pane (where the technical wiring lives)

**Consequences.** UI matches the PRD. Prior Routing components are reused rather than discarded.

---

## ADR-9 — Continuous detection polling at 5 s

**Context.** PRD §3.1 requires continuous polling. Too frequent = wakes idle CPUs (problem on battery). Too infrequent = stale UI.

**Decision.** Background task on AppState polls every 5 s. Only updates `@Published` state if the result diff'd from last time (avoid view rebuild churn). Pauses when window is not key. Can be triggered manually via Rescan.

**Consequences.** Five-second worst-case staleness; battery-friendly. One async task per AppState instance.

---

## ADR-10 — App quit teardown via NSApplicationWillTerminateNotification

**Context.** Zombie processes are an explicit PRD §7 concern.

**Decision.** ProcessRegistry observes `NSApplication.willTerminateNotification` and sends SIGTERM to every tracked PID, waits up to 2 s, then SIGKILL. Also wired to the broker's explicit Stop button and to a Unix signal handler for SIGTERM/SIGINT of the broker itself.

**Consequences.** Three independent teardown paths converge on the same code. Each is tested.
