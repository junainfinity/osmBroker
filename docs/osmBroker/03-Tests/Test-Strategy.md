# Test Strategy

Testing is split by layer. Each layer has a fixed scope; we don't paper over weak unit tests with thick integration tests.

## Layers

### 1. Unit (XCTest against `osmBrokerCore`)

Targets: pure functions, encoders, parsers, registries, validators.

| File | What it covers |
|---|---|
| `ANSIStripperTests.swift` | All ANSI escape variants — CSI, OSC, CSR, progress carriage-return overdraw |
| `SSEEncoderTests.swift` | Data/event/done frames, multiline, embedded JSON |
| `AuthTests.swift` | Bearer parsing, constant-time compare, redaction |
| `ModelValidationTests.swift` | Regex acceptance + rejection, length cap, injection patterns |
| `AgentRegistryTests.swift` | 16 entries present, no duplicate bins, install URLs are https |
| `NetworkInfoTests.swift` | LAN IP discovery on stub `ifaddrs` |
| `ErrorMappingTests.swift` | "Quota exceeded" → 429, "Please login" → 401, generic → 500 |
| `RegistryTests.swift` | Bridge enum coverage, native protocol mapping |

### 2. Integration (XCTest spawning real subprocesses)

| File | What it covers |
|---|---|
| `BrokerServerIntegrationTests.swift` | Real NIO server bound to ephemeral port, real HTTP requests via URLSession |
| `SpawnerIntegrationTests.swift` | Spawn a fixture echo binary, write to stdin, read stdout, verify event stream |
| `ProcessRegistryIntegrationTests.swift` | Spawn N children, call `killAll`, verify all gone |
| `EndToEndChatCompletionsTests.swift` | Full path: POST request → fake adapter → SSE stream back |

We use a fixture script (`Tests/Fixtures/echo.sh`) as a stand-in CLI so tests don't depend on Claude/Codex being installed.

### 3. Security (subset of integration)

Marked with `@MainActor` and `securityTest` tag where supported. Cataloged in [[Security-Tests]].

### 4. UI smoke (manual + `swift run`)

Not automated yet — XCTest with SwiftUI views is fragile. We rely on `swift run` + a manual checklist:

- [ ] Window opens at 1200×780, sidebar 240pt
- [ ] Real LAN IP visible in sidebar dark card, monospace
- [ ] Start broker → status pill flips to green "live on :8080"
- [ ] `curl http://127.0.0.1:8080/v1/models -H "Authorization: Bearer <key>"` returns JSON
- [ ] Bad key → 401
- [ ] Wrong model → 404 envelope
- [ ] Quit app → no leftover processes (`pgrep claude` etc. should not show broker children)

## Coverage targets

| Component | Target | Rationale |
|---|---|---|
| Auth | 100% line | Security-critical; small surface |
| ANSI stripper | ≥ 95% line | Many input variants |
| SSE encoder | 100% line | Tiny module |
| Process spawner | ≥ 80% line | Hard to unit-test fully without OS hooks |
| HTTP handlers | ≥ 80% line | Mix of unit + integration |
| UI (SwiftUI views) | Not measured | Manual smoke only |

## Test data

- Fake echo CLI: `Tests/Fixtures/echo-stream.sh` — emits one JSON line per word
- Crash fixture: `Tests/Fixtures/crash-after-n.sh` — emits N tokens then `exit 1`
- Slow fixture: `Tests/Fixtures/slow.sh` — `sleep 30` then emit (for timeout tests)

## Conventions

- Use `XCTAssertEqual` over `==` so failures show both values
- Async tests use `XCTestExpectation` or Swift Concurrency `await`
- Each test is independent; no shared setup between cases except `setUp`/`tearDown`
- File-scope `private` types in tests are fine — keeps the public surface clean
- No sleep() to "wait for the server" — use deterministic readiness signals
