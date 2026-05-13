# osmBroker — Build Vault

Live build notes, decisions, tasks, tests, and dev log for the osmBroker macOS app.

## How to read this vault

Start here, then follow the links. Notes are written **before** the work, then updated as it lands. The Dev Log is the running diary; the Test Log records every test run.

## Planning

- [[01-Planning/PRD-Analysis|PRD Analysis]] — every requirement extracted as a checklist
- [[01-Planning/Security-Requirements|Security Requirements]] — synthesized from PRD §3.5/§7 + handover doc + macOS app safety
- [[01-Planning/Self-Critique|Self-Critique]] — honest accounting of mistakes in the prior build
- [[01-Planning/Architecture-Decisions|Architecture Decisions]] — ADRs (SwiftNIO, core/exec split, adapter pattern, etc.)
- [[01-Planning/Task-Hierarchy|Task Hierarchy]] — major / mini / micro / atomic / nano breakdown

## Tasks (per phase)

- [[02-Tasks/Phase-1-HTTP-Broker|Phase 1 — HTTP Broker]] (done)
- [[02-Tasks/Phase-1.5-UX-Overhaul|Phase 1.5 — UX Overhaul]] (active)
- [[02-Tasks/Phase-2-Adapters-and-More-Tab|Phase 2 — Adapters & More Tab]]
- [[02-Tasks/Phase-3-Polish-and-Marketplace|Phase 3 — Polish & Marketplace]]
- [[02-Tasks/Phase-4-Advanced-Protocols|Phase 4 — MCP / ACP (later)]]

## Tests

- [[03-Tests/Test-Strategy|Test Strategy]]
- [[03-Tests/Unit-Tests|Unit Test Catalogue]]
- [[03-Tests/Integration-Tests|Integration Test Catalogue]]
- [[03-Tests/Security-Tests|Security Test Catalogue]]

## Architecture deep-dives

- [[05-Architecture/HTTP-Server|HTTP Server (SwiftNIO)]]
- [[05-Architecture/Adapter-Pattern|Adapter Pattern]]
- [[05-Architecture/Process-Lifecycle|Process Lifecycle]]
- [[05-Architecture/SSE-Normalization|SSE Normalization]]
- [[05-Architecture/Logo-Branding|Logo & Branding]] *(v0.2 brand mark wiring)*
- [[05-Architecture/Model-Discovery|Model Discovery]] *(per-CLI config readers)*
- [[05-Architecture/Tab-Structure-v2|Tab Structure v2]] *(CLI / Models / Serve / More)*
- [[05-Architecture/Sidebar-Card-Redesign|Sidebar Card Redesign]]
- [[05-Architecture/AppState-Discovered-Models|AppState — Discovered Models]]
- [[05-Architecture/Claude-Model-Discovery|Claude Model Discovery]] *(why we use `sonnet`/`opus`/`haiku` aliases)*
- [[05-Architecture/Top-Bar-Tightening|Top Bar Tightening]] *(v0.2.1)*
- [[05-Architecture/Bundle-Resources-Gotcha|Bundle Resources Gotcha]]

## Running logs

- [[04-Logs/Dev-Log|Dev Log]] — chronological diary of what I'm doing right now
- [[04-Logs/Test-Log|Test Log]] — every test run, every failure, every fix

## Source pointers

- [`Sources/osmBroker/`](../../Sources/osmBroker/) — SwiftUI executable (UI only)
- `Sources/osmBrokerCore/` — broker logic (HTTP, adapters, detection) — *to be created*
- `Tests/osmBrokerCoreTests/` — XCTest target — *to be created*
- [`Package.swift`](../../Package.swift)
- [`cli-agent-broker-handover.md`](../../cli-agent-broker-handover.md) — port reference from `nexu-io/open-design`
- [`osmBroker PRD.pdf`](../../osmBroker%20PRD.pdf) — the spec we're building to
