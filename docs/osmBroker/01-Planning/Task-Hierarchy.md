# Task Hierarchy

Five levels: **major → mini → micro → atomic → nano**. Names match what the user asked for. The hierarchy makes scope inspectable: every line item bottoms out at a single function or test case.

## Major (phase) → Mini (component) → Micro (file) → Atomic (function) → Nano (line/test)

```
v1.0 PRD-aligned build
├── M1. HTTP Broker (this milestone)
│   ├── m1.1 Package restructure
│   │   ├── µ Package.swift → Library + Exec + Tests
│   │   ├── µ Move Detection/* to osmBrokerCore
│   │   ├── µ Add swift-nio + swift-log deps
│   │   └── atomic: re-export public types via Core module
│   │
│   ├── m1.2 ANSI stripping
│   │   ├── µ ANSIStripper.swift
│   │   ├── atomic: stripCSI(_:) handles `ESC [ … cmd`
│   │   ├── atomic: stripOSC(_:) handles `ESC ] … BEL/ST`
│   │   ├── atomic: stripCR / progress spinner artefacts
│   │   └── nano: 12 table-driven test cases
│   │
│   ├── m1.3 SSE encoding
│   │   ├── µ SSEEncoder.swift
│   │   ├── atomic: dataFrame(json:) → `data: {…}\n\n`
│   │   ├── atomic: eventFrame(name:, json:) → `event: name\ndata: {…}\n\n`
│   │   ├── atomic: doneFrame() → `data: [DONE]\n\n`
│   │   └── nano: 8 unit tests (empty, multiline, embedded \n)
│   │
│   ├── m1.4 Auth middleware
│   │   ├── µ Auth.swift
│   │   ├── atomic: parseBearer(_ header: String) -> String?
│   │   ├── atomic: constantTimeEquals(_:_:) -> Bool
│   │   ├── atomic: redactAuthorization(_:) -> String   // for logs
│   │   └── nano: tests for missing / wrong / right token + timing-safe path
│   │
│   ├── m1.5 Process spawning
│   │   ├── µ ProcessSpawner.swift  (Foundation Process wrapper)
│   │   ├── µ ProcessRegistry.swift (tracked PIDs + teardown)
│   │   ├── atomic: spawn(adapter, prompt, model) -> ChildHandle
│   │   ├── atomic: ChildHandle.terminate() (SIGTERM → 2s → SIGKILL)
│   │   ├── atomic: ProcessRegistry.killAll()
│   │   ├── atomic: env whitelist construction
│   │   └── nano: SPAWN-1 / SPAWN-5 / SPAWN-7 tests
│   │
│   ├── m1.6 Adapter framework
│   │   ├── µ Adapter.swift  (protocol + AdapterEvent + AdapterOptions)
│   │   ├── µ Adapters/ClaudeAdapter.swift  (claude -p, plain stdout for now)
│   │   ├── µ Adapters/FakeEchoAdapter.swift (test-only fixture)
│   │   ├── atomic: ClaudeAdapter.buildArguments
│   │   ├── atomic: PlainTextStreamHandler (LF-delimited chunks)
│   │   └── nano: adapter unit test using fake-echo fixture
│   │
│   ├── m1.7 NIO HTTP server
│   │   ├── µ Server.swift  (Bootstrap + Channel pipeline)
│   │   ├── µ Routes.swift  (path dispatch)
│   │   ├── µ Handlers/ModelsHandler.swift
│   │   ├── µ Handlers/ChatCompletionsHandler.swift
│   │   ├── µ Handlers/MessagesHandler.swift
│   │   ├── µ Handlers/NotFoundHandler.swift
│   │   ├── atomic: portConflictCheck(host:port:) -> Result
│   │   ├── atomic: bodyAggregator (cap at 1 MiB)
│   │   ├── atomic: error envelope (OpenAI- and Anthropic-shaped)
│   │   └── nano: integration tests on a real loopback port
│   │
│   ├── m1.8 UI wiring (minimal)
│   │   ├── µ AppState.start/stop broker
│   │   ├── µ Active pane: real "Start broker" button
│   │   ├── µ Network pane: port conflict feedback
│   │   ├── µ Sidebar status pill reflects broker state
│   │   └── nano: smoke run + manual UI test
│   │
│   └── m1.9 Lifecycle & teardown
│       ├── µ NSAppTerminationObserver.swift
│       ├── atomic: signal handler for SIGTERM/SIGINT
│       └── nano: teardown test simulating quit
│
├── M2. More tab + multi-CLI adapters
│   ├── m2.1 Replace Routing with More tab (PRD §3.3)
│   ├── m2.2 Curated registry JSON + search
│   ├── m2.3 Install command surfacing
│   ├── m2.4 CodexAdapter (`codex exec --json` from handover doc)
│   ├── m2.5 GeminiAdapter + ReAct filter toggle (PRD §5)
│   └── m2.6 Memory + user columns on running pill (PRD §3.1)
│
├── M3. Polish
│   ├── m3.1 Capability badges from `--help` parse
│   ├── m3.2 Continuous polling
│   ├── m3.3 Error string parsing → 429/401 mapping (PRD §7)
│   ├── m3.4 Open-in-Terminal launcher
│   └── m3.5 README + .app bundle helper script
│
└── M4. Advanced (deferred)
    ├── KimiAdapter via `kimi acp` (PRD §5)
    ├── MCP relay for Claude Code
    └── Per-model metrics
```

## Phase 1 detailed plan

See [[../02-Tasks/Phase-1-HTTP-Broker]].

## Where each major lands

| Major | PRD ref | Mini count | Atomic count (approx) |
|---|---|---|---|
| M1 HTTP Broker | §4, §3.5, §7 | 9 | ~30 |
| M2 More + Multi-CLI | §3.3, §3.1, §5 | 6 | ~18 |
| M3 Polish | §7, §3.2 | 5 | ~12 |
| M4 Advanced | §5 (Kimi), §5 (Claude MCP) | 3 | TBD |
