# Security Requirements

Synthesized from PRD §3.5, §7, the `cli-agent-broker-handover.md` §"Security And Safety Rules To Preserve", and standard macOS app threat model. Every requirement below is testable — see [[../03-Tests/Security-Tests]].

## Threat model (short)

osmBroker runs on the user's Mac and exposes an authenticated HTTP API to:
- Other apps on the same Mac (loopback)
- Other devices on the LAN (when host = `0.0.0.0`)

Adversaries we explicitly defend against:

| Adversary | Surface | Defended? |
|---|---|---|
| Curious LAN neighbour scanning for open ports | HTTP `:8080` | Bearer auth, constant-time compare |
| Malicious model name with shell metacharacters | `model` field in request body | Strict regex validation, no shell, no argv prompt |
| Bad payload trying to OOM us | request body size | Length cap before body read |
| CLI crashing or hanging | spawned subprocess | Inactivity timeout + SIGTERM → SIGKILL escalation |
| Subprocess exfiltrating env | child env | Whitelisted env passthrough; no `*_BIN`/secrets unless adapter-declared |
| Process zombies after quit | spawned subprocesses | atexit hook + signal handler kills tracked PIDs |
| Logs leaking the bearer token or prompts | console / log files | Redaction helper; never log `Authorization` headers or request bodies verbatim |

Adversaries we explicitly do **not** defend against:
- Local root on the same Mac (out of scope)
- Network MITM (no TLS in Phase 1 — see [[Architecture-Decisions]] ADR-7)

## Authentication

- **AUTH-1** Bearer token required on every `/v1/*` request. Header: `Authorization: Bearer <token>`.
- **AUTH-2** Mismatched / missing token → `401 Unauthorized` with JSON `{"error":{"type":"invalid_api_key", ...}}`.
- **AUTH-3** Token comparison uses **constant-time byte comparison**, not `==` on Strings. Prevents timing oracles for short prefixes.
- **AUTH-4** The token never appears in logs, error messages, or telemetry. Logging code redacts `Authorization` headers to `Bearer <…N chars elided…>`.
- **AUTH-5** When the user provides an empty API key, the broker refuses to start and surfaces a UI error. We do not run an unauthenticated server, even on loopback.

## Network binding

- **NET-1** UI offers `127.0.0.1`, `0.0.0.0`, and any explicit host. We reject other special values that don't bind correctly (broadcast, multicast).
- **NET-2** Before bind, we test the port with a throw-away `bind()` and report conflicts to the UI without starting the server (PRD §7).
- **NET-3** When host = `0.0.0.0`, the UI sidebar must show the actual LAN address users would connect to (no fake placeholder, no `192.168.1.50`).
- **NET-4** Cap incoming request body size at **1 MiB**. Larger requests get `413 Payload Too Large`. Prevents memory exhaustion.
- **NET-5** Cap idle connection time at **120 s** for non-streaming requests; streaming responses have inactivity timeout of **30 s** between writes.
- **NET-6** No CORS by default — this is a private-network local server, not a public web API. (Future: optional allowlist setting.)

## Input validation

- **VAL-1** Model IDs validated with regex `^[A-Za-z0-9._:/-]{1,128}$`. Anything else → `400`.
- **VAL-2** JSON body parsed with strict decoder; unknown top-level keys ignored, but `messages` array length ≤ 256, total characters ≤ 256 KiB.
- **VAL-3** `messages[].content` is treated as text only — no executable inclusion, no file paths, no shell metacharacters honored.

## Subprocess spawning (per handover doc §"Security And Safety Rules To Preserve")

- **SPAWN-1** **Never pass the user prompt via argv** when stdin works. argv is visible in `ps -ef` and shell history — leaks. Adapters MUST set `promptViaStdin: true` unless physically impossible (and then we cap argv ≤ 30 KiB).
- **SPAWN-2** **Never spawn raw `def.bin`** if detection resolved an absolute path. Always use the resolved path so PATH-augmented detection results match runtime invocation.
- **SPAWN-3** Set `shell: false` (Foundation `Process` is shell-false by default — we explicitly do not invoke `/bin/sh`).
- **SPAWN-4** Validate adapter env overrides as absolute executable paths only — reject anything starting with `-` or containing `\0` / `\n`.
- **SPAWN-5** Child env is **explicitly constructed**: PATH, HOME, USER, LANG, TERM=dumb — plus any whitelisted vars the adapter declared. We do **not** pass our own bearer token down to children.
- **SPAWN-6** Children get `setsid()`-equivalent isolation where possible so a CLI's signal handlers don't tangle with the broker's.
- **SPAWN-7** Every spawned PID is tracked in a registry. On broker stop or app quit, every tracked PID is SIGTERM'd, then SIGKILL'd after 2 s if still alive.

## Logging and redaction

- **LOG-1** Logging level configurable; default `info`. `debug` may log full request paths but **never** bodies or `Authorization` headers.
- **LOG-2** Helper `redactAuthorization(_:)` replaces `Bearer <token>` with `Bearer ***` in any string passed to the logger.
- **LOG-3** Request/response bodies are never logged in full. If a body is logged at debug level, it's truncated to 256 bytes.
- **LOG-4** When the user clicks "Export logs" (future), we strip the API key the same way.

## Error handling (PRD §7)

- **ERR-1** CLI crash (exit ≠ 0) mid-stream → SSE stream is closed with an `error` event, HTTP layer surfaces `5xx` only when no bytes have been sent yet.
- **ERR-2** Parse known error strings: "Quota exceeded", "Please login", "401", "403" → translate to `429` / `401` envelopes for the client.
- **ERR-3** Port conflict → server refuses to start; UI gets the error inline with a suggested alternate port.
- **ERR-4** Zombie reaper runs in three places: explicit Stop button, app quit (`NSApp` termination notification), and SIGTERM/SIGINT of the app itself.

## Out-of-scope for Phase 1 (documented so we don't pretend)

- TLS / HTTPS (LAN-only daemon; users can put a reverse proxy in front)
- mTLS / device-pinned auth
- Rate limiting per client IP (single user, single LAN — too early to optimize)
- Detailed audit log file (write to console for now)

## Reverse map to tests

Every rule above has an XCTest in [[../03-Tests/Security-Tests]]:

| Rule | Test |
|---|---|
| AUTH-1 / AUTH-2 | `AuthTests.testNoBearer401` |
| AUTH-3 | `AuthTests.testConstantTimeCompare` |
| AUTH-4 / LOG-2 | `LoggingTests.testRedactAuthorization` |
| NET-2 | `ServerLifecycleTests.testPortConflictReports` |
| NET-4 | `ServerLifecycleTests.testBodyTooLarge413` |
| VAL-1 | `RequestValidationTests.testBadModelName400` |
| SPAWN-1 | `SpawnerTests.testPromptViaStdinNotArgv` |
| SPAWN-5 | `SpawnerTests.testChildEnvWhitelisted` |
| SPAWN-7 | `SpawnerTests.testTrackedPidsKilledOnStop` |
| ERR-2 | `ErrorMappingTests.testQuotaExceededTo429` |
