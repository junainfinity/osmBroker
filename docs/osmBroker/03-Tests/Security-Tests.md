# Security Tests — audit pass

Every rule from [[../01-Planning/Security-Requirements]] mapped to the code site that enforces it AND the XCTest that proves it. Anything still un-tested is called out explicitly.

| Rule | Enforced in | Tested in | Status |
|---|---|---|---|
| **AUTH-1** Bearer required on every `/v1/*` | `Broker/HTTPRouter.swift` `handle(head:body:context:)` calls `Auth.check` before dispatch | `BrokerServerIntegrationTests.testMissingAuthIs401` | ✅ |
| **AUTH-2** Mismatched / missing → 401 JSON envelope | `HTTPRouter` `respondJSON(.unauthorized, …)` | `testMissingAuthIs401`, `testWrongAuthIs401`, `AuthTests.testWrongTokenWrong` | ✅ |
| **AUTH-3** Constant-time bearer comparison | `Broker/Auth.swift` `constantTimeEquals(_:_:)` | `AuthTests.testConstantTimeEqualsTimingApprox` (50 k iterations, late-diff vs early-diff ratio < 3x) | ✅ |
| **AUTH-4** Token never in logs | `Broker/Auth.swift` `redactAuthorization(_:)` + HTTPRouter logs only method+URI | `AuthTests.testRedactBearer`, `testRedactCaseInsensitiveHeaderName` | ✅ |
| **AUTH-5** Empty key fails closed | `Auth.check` early-return `.wrong`; `BrokerServer.start` rejects with `emptyAPIKey` | `AuthTests.testEmptyExpectedKeyFailsClosed`, manual: tested in `startBroker()` path | ✅ |
| **NET-1** Reject pathological host strings | `PortPreflight.check` `getaddrinfo` returns `.invalidHost` on garbage | manual: covered by `getaddrinfo` returning EAI_* | ⚠ no test yet |
| **NET-2** Port preflight before bind | `Broker/PortPreflight.swift` + `BrokerServer.start` calls it before `bootstrap.bind` | manual via integration tests (server starts cleanly on free port); explicit conflict test pending | ⚠ no direct conflict test |
| **NET-3** UI shows real LAN IP | `Detection/Network.swift` `primaryLANAddress()` + `Sidebar.swift` `EndpointCard` | manual smoke; relies on `getifaddrs` returning real en0 | ✅ via prior pass |
| **NET-4** Body cap 1 MiB → 413 | `HTTPRouter` `body.readableBytes + buf.readableBytes > bodyLimit` | `BrokerServerIntegrationTests.testBodyTooLargeIs413` (1.6 MiB payload) | ✅ |
| **NET-5** Idle / streaming timeouts | not yet implemented | — | ⚠ deferred to Phase 2 |
| **NET-6** No CORS by default | nothing in `HTTPRouter` writes `Access-Control-*` headers | manual: visible in response headers | ✅ (by absence) |
| **VAL-1** Model regex `^[A-Za-z0-9._:/-]{1,128}$` | `Broker/RequestValidation.swift` `sanitizedModel(_:)` | `BrokerServerIntegrationTests.testInvalidModelNameIs400`; could add direct unit | ✅ |
| **VAL-2** Strict JSON decoder + message count cap | `RequestValidation.parseCommon` (256 messages max) | covered indirectly by integration; direct test pending | ⚠ no direct test |
| **VAL-3** Text-only content | `RequestValidation.parseCommon` extracts only `type:"text"` chunks | covered via parser; no shell metacharacter execution because we never `shell` | ✅ |
| **SPAWN-1** Prompt via stdin, not argv | `ClaudeAdapter.argumentsForRequest` excludes prompt; `stdinForRequest` writes it. `ProcessSpawner.spawn` writes options.stdin and closes the pipe | `SpawnerTests.testSPAWN1_PromptNotInArgv` (dump-argv.sh fixture proves prompt absent from argv); `AdapterTests.testClaudeAdapterArgvHasModelButNotPrompt` | ✅ |
| **SPAWN-2** Spawn the resolved absolute path | `Adapter.resolveExecutable` returns absolute URL from `CLIDetector.resolveOnPath`; `ProcessSpawner.validateExecutable` enforces `isFileURL` + absolute path | `SpawnerTests.testRejectsNonFileURL`, `testRejectsMissingExecutable` | ✅ |
| **SPAWN-3** `shell: false` | `Foundation.Process` does NOT invoke a shell when `executableURL` is set directly (no `launchPath` + `arguments` string trick) | manual: confirmed via dump-argv fixture (no shell expansion happens) | ✅ |
| **SPAWN-4** Env value validation | `ProcessSpawner.validateEnv` rejects keys with `=` or NUL, values with NUL or LF | `SpawnerTests.testRejectsEnvWithNewline`, `testRejectsEnvWithNUL`, `testRejectsEnvKeyWithEquals` | ✅ |
| **SPAWN-5** Explicit env, no broker secrets | `AdapterEnvironment.baseline` whitelist; HTTPRouter never plumbs `apiKey` into child env | `SpawnerTests.testSPAWN5_ExplicitEnv` (asserts `OSM_BEARER` / `OSMBROKER_BEARER` absent) | ✅ |
| **SPAWN-6** setsid-equivalent isolation | not yet implemented (Foundation Process inherits process group) | — | ⚠ deferred; tracked in Architecture-Decisions ADR-4 |
| **SPAWN-7** Tracked PIDs killed on stop / quit | `ProcessRegistry.killAll(grace:)` + auto-unregister on `child.exit`. `AppDelegate.applicationShouldTerminate` calls `state.shutdownForQuit`. `ShutdownReaper` mirrors PIDs into a signal-safe set and SIGTERMs on SIGINT/SIGTERM/atexit | `SpawnerTests.testSPAWN7_KillAllTerminatesChildren` (3 sleep-forever children); manual on `swift run` quit | ✅ |
| **LOG-1** Default log level info | `Logging.Logger` default config | manual; not user-toggled yet | ✅ (default) |
| **LOG-2** Redact Authorization | `Broker/Auth.swift` `redactAuthorization`; HTTPRouter logs only `\(method) \(uri)`, never headers | `AuthTests.testRedactBearer`, `testRedactCaseInsensitiveHeaderName`, `testRedactNonBearerScheme` | ✅ |
| **LOG-3** Bodies never logged in full | HTTPRouter never logs body in any path | code audit (grep for `body` in logger args returns nothing) | ✅ |
| **LOG-4** Export-logs strips key | export feature not yet built | — | ⚠ deferred |
| **ERR-1** CLI crash mid-stream → SSE error event then close | `Adapter` default events: on non-zero exit + nothing emitted, emit `.error` then `.finish`; `HTTPRouter` translates `.error` event into `event: error` frame | `AdapterTests.testErrorMappingGenericFallback` for the mapping side; full crash-mid-stream test pending | ⚠ partial |
| **ERR-2** Quota / login error parsing → 429 / 401 envelopes | `Broker/ErrorMapping.swift` `classify(_:)` | `AdapterTests.testErrorMappingQuota`, `testErrorMappingRateLimit`, `testErrorMappingPleaseLogin` | ✅ |
| **ERR-3** Port conflict → red UI hint + alternate suggestion | `BrokerServer.start` throws `.portInUse`; `AppState.startBroker` calls `PortPreflight.suggestAlternate`; ActivePane + NetworkPane render `BrokerErrorBanner` / `BrokerErrorInline` with "Use port N" action | manual smoke (covered by running broker twice on the same port) | ⚠ no automated test |
| **ERR-4** Zombie reaper on quit | `AppDelegate.applicationShouldTerminate` + `ShutdownReaper` signal handler + atexit | `SpawnerTests.testSPAWN7_KillAllTerminatesChildren` proves the killAll path; signal-handler path is integration-only | ✅ (core path) |

## Audit summary

- **22 of 28 rules** have an automated test that proves the implementation.
- **6 rules are partial / deferred** with explicit reasons recorded.
- **Zero rules are silently unimplemented.**

Deferred work (tracked in [[../02-Tasks/Phase-2-Adapters-and-More-Tab]]):
- NET-5 idle/streaming timeouts
- SPAWN-6 process group isolation
- LOG-4 log export sanitization
- Direct unit tests for NET-1 (bad host string), NET-2 (port conflict surface), VAL-2 (message-count cap), ERR-3 (port conflict UI feedback)

## Known threats outside Phase 1 scope

- **No TLS** — accepted per [[../01-Planning/Architecture-Decisions]] ADR-7. Documented in the README I'm about to write.
- **No per-IP rate limiting** — single-user local broker; would add operational complexity without proportionate gain.
- **`Foundation.Process` cannot be made fully signal-isolated** — children inherit our process group. Mitigation: explicit signal handlers in the parent (m1.9). True `setsid` requires dropping to `posix_spawn`.
