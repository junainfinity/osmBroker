# Phase 1 — HTTP Broker

Goal: a real, authenticated HTTP server that can serve `GET /v1/models`, `POST /v1/chat/completions`, and `POST /v1/messages` against the **Claude Code** CLI (per PRD Phase 1, §8).

Definition of done for this milestone:

1. `curl -s http://127.0.0.1:8080/v1/models -H "Authorization: Bearer <key>"` returns JSON with all enabled models.
2. `curl -N -X POST http://127.0.0.1:8080/v1/chat/completions -H "Authorization: Bearer <key>" -H "Content-Type: application/json" -d '{"model":"claude-sonnet-4-5","messages":[{"role":"user","content":"hi"}],"stream":true}'` streams OpenAI-shaped SSE.
3. Bad/missing bearer → 401 envelope. Unknown model → 404 envelope. Malformed JSON → 400 envelope.
4. Port conflict surfaces in UI without crashing.
5. App quit kills all spawned children (no zombies).
6. Unit + integration tests pass (`swift test`).

## Task ledger (live)

- [x] Plan documented (this file, [[../01-Planning/Architecture-Decisions]], [[../01-Planning/Security-Requirements]])
- [ ] **m1.1 Package restructure** (in progress)
  - [ ] Split into `osmBrokerCore` library + `osmBroker` exec + `osmBrokerCoreTests` target
  - [ ] Add `swift-nio` and `swift-log` deps
  - [ ] Move `Detection/*` to `osmBrokerCore`
  - [ ] Adjust SwiftUI imports
- [ ] **m1.2 ANSIStripper** — implement + unit tests
- [ ] **m1.3 SSEEncoder** — implement + unit tests
- [ ] **m1.4 Auth** — bearer parse + constant-time compare + redaction + tests
- [ ] **m1.5 ProcessSpawner + ProcessRegistry** — spawn / kill-on-quit + tests
- [ ] **m1.6 Adapter framework + ClaudeAdapter** — protocol + Claude `-p` invocation + plain stream handler
- [ ] **m1.7 NIO HTTP Server** — bootstrap, body cap, route dispatch, error envelopes
- [ ] **m1.7a Handler: GET /v1/models**
- [ ] **m1.7b Handler: POST /v1/chat/completions** (OpenAI shape)
- [ ] **m1.7c Handler: POST /v1/messages** (Anthropic shape)
- [ ] **m1.8 UI wiring** — Start/Stop button, broker state in sidebar pill
- [ ] **m1.9 Lifecycle** — NSApplication termination observer + Unix signal handler
- [ ] **Integration test** — end-to-end with fixture echo CLI
- [ ] **Security pass** — every Security-Requirements rule has a test
- [ ] **Smoke run** — manual checklist from [[../03-Tests/Test-Strategy]] §"UI smoke"

## Dependencies between tasks

```
m1.1  →  everything else (restructure first)
m1.2 (ANSI)        ┐
m1.3 (SSE)         ├→ m1.6 (Adapter uses ANSI+SSE) ┐
m1.4 (Auth)        │                                ├→ m1.7 (Server)
m1.5 (Spawner)  ───┤                                │
                                                    │
m1.7 ───────────────────────────────────────────────┤
                                                    ├→ m1.8 (UI wiring)
                                                    │
m1.9 (Lifecycle) ───────────────────────────────────┘
```

m1.2 / m1.3 / m1.4 are leaf — buildable and testable in any order. m1.5 is leaf too. After all four are in, m1.6 and m1.7 can land in parallel.

## Open questions

- **OpenAI streaming usage stats** — do we synthesize `usage` (prompt_tokens/completion_tokens) by counting bytes, or omit? **Decision:** omit for Phase 1; many compatible clients don't require it. Documented in [[../05-Architecture/SSE-Normalization]].
- **`/v1/messages` (Anthropic) format** — handle the slightly different streaming envelope (`content_block_delta` etc.). **Decision:** support, since the PRD §4.1 explicitly lists `POST /v1/messages` and it's a one-time mapping.
- **Tool calls** — handover doc says Claude Code emits tool events. Phase 1 **collapses** tool events into text deltas. Tool-call relay is Phase 4 (MCP).

## Risks

| Risk | Mitigation |
|---|---|
| `swift test` slow to first run after NIO add | Warn user in Dev Log; subsequent runs are cached |
| `claude -p` behaviour differs across versions | Pin a `--version` minimum; document; fail with clear error |
| Children survive crash of broker | Signal handler + `setpgid`-equivalent; teardown test |
| NIO concurrency mismatch with `@MainActor` AppState | Bridge via `Task { @MainActor in … }` at the publish boundary |

## Cross-refs

- [[../01-Planning/Architecture-Decisions]] ADRs 1–10
- [[../01-Planning/Security-Requirements]] AUTH-1..5, NET-1..6, SPAWN-1..7, VAL-1..3
- [[../03-Tests/Test-Strategy]] all layers
- [[../04-Logs/Dev-Log]] running diary
