# PRD Analysis

Source: `osmBroker PRD.pdf` v1.0.0. Every concrete requirement extracted as a checkbox so we can track delivery. Status reflects state at the start of this build phase.

Legend: [x] done, [~] partial, [ ] not started.

## §1 — Vision

Single-line summary: **native macOS app that auto-detects AI CLIs, wraps them as OpenAI/Anthropic HTTP endpoints, served locally or over LAN with bearer-token auth.**

## §2 — User architecture

- [x] Host = high-RAM Mac running multiple CLIs
- [ ] Local client points to `http://127.0.0.1:8080/v1`
- [ ] Network client points to `http://<lan-ip>:8080/v1`

## §3.1 — Process Detection Engine

- [~] Native process scanning (have: `/bin/ps -Axc` snapshot. PRD wants: libproc / NSTask monitoring.)
- [x] Target binaries: claude, codex, gemini, kimi, deepseek, etc. (16 in registry, covers the PRD's named set)
- [~] Active card shows PID (have PID; missing memory, system user)
- [ ] **Continuous polling** for launch/termination (we only scan on Rescan)

## §3.2 — Active Dashboard

- [x] SwiftUI
- [x] Card per CLI
- [ ] Provider metadata via `--help` / `features list` parsing → capability badges ("Supports MCP", "Agentic ReAct")
- [~] Empty state shown (have: registry pill list. Missing: one-click install commands like `brew install codex` / `npm i -g @anthropic-ai/claude-code`, "initialize terminal session" button)

## §3.3 — "More" Tab (Discovery & Marketplace)

- [ ] Dedicated **More** tab (currently we have a Routing tab that PRD doesn't ask for)
- [ ] Search across curated CLI registry
- [ ] Detail entries for Kimi (ACP, zsh), Perplexity (RAG, SQLite-vec), DeepSeek (inline, context caching)
- [ ] "Add" button → install commands

## §3.4 — Provider & Model Configuration

- [x] Master per-provider toggle
- [x] Per-model toggles
- [ ] Toggled models actually feed `/v1/models` (no server yet)

## §3.5 — Network Configuration & Security

- [x] Host: 127.0.0.1 / 0.0.0.0 (UI field)
- [x] Port: default 8080 (UI field)
- [ ] Common fallback ports suggested: 11434, 5001
- [x] API key field
- [ ] **Bearer auth enforced** — 401 on mismatch (no server)
- [ ] Port-conflict detection + red flag + suggested alternative

## §4 — Translation & Routing Engine

- [ ] HTTP server (PRD suggests SwiftNIO or Vapor → we pick SwiftNIO)
- [ ] `GET /v1/models` → OpenAI-shaped JSON array
- [ ] `POST /v1/chat/completions` → OpenAI-shaped streaming
- [ ] `POST /v1/messages` → Anthropic-shaped streaming
- [ ] Request → lookup model owner → spawn CLI subprocess (IPC bridge)
- [ ] stdin translation: JSON messages → CLI input
- [ ] stdout: strip ANSI, chunk into SSE frames
- [ ] Async non-blocking I/O
- [ ] <10ms per-token overhead target (measure, not assume)

## §5 — Per-CLI Profiles

- [ ] **Codex** — bypass TUI, force stdout, `/model` flag handling
- [ ] **Claude Code** — `claude -p` print mode, optional MCP tool-call relay
- [ ] **Kimi** — `kimi acp` server mode (ACP JSON-RPC)
- [ ] **Gemini** — strip ReAct internal thoughts unless "Reasoning Mode" toggle is on

## §6.1 — Setup workflow (must support end-to-end)

1. [x] Launch app
2. [x] App detects `claude` and `codex` automatically
3. [ ] Install Kimi via More tab → appears in Active list
4. [x] Toggle specific models on
5. [x] Set host=0.0.0.0, port=8080, API key (currently UI-only — no enforcement)

## §6.2 — Execution workflow (must support end-to-end)

1. [ ] Colleague opens AnythingLLM on Windows on same LAN
2. [ ] Selects "OpenAI Compatible Endpoint"
3. [ ] Enters `http://<mac-ip>:8080/v1` + API key
4. [ ] Model dropdown populated from osmBroker `/v1/models`
5. [ ] Chat request → osmBroker spawns matching CLI → streams SSE back

## §7 — Edge cases

- [ ] CLI crash mid-stream → 500 error envelope, "Process Failed" badge
- [ ] Quota / login errors parsed → 429 / 401 to client
- [ ] Port already bound → red input, alternative suggested
- [ ] Zombie processes → clean teardown on app quit

## §8 — Roadmap mapping

- **Phase 1 (v0.1)** — HTTP server + IPC + Claude Code hardcoded → **building now**
- **Phase 2 (v0.5)** — UI + auto-detection + Codex + Gemini → **UI done from prior work; broker side pending**
- **Phase 3 (v1.0)** — 0.0.0.0 + API key + More tab → **partial (UI) → finishing in same milestone**
- **Phase 4 (v1.5)** — MCP / ACP native → **deferred**

## Cross-references

- See [[Security-Requirements]] for the security-side translation of §3.5, §7
- See [[Self-Critique]] for what went wrong against this PRD in the prior pass
- See [[Architecture-Decisions]] for how we satisfy §4 mechanically
- See [[../02-Tasks/Phase-1-HTTP-Broker|Phase-1 task list]] for the day-by-day delivery plan
