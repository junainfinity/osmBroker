# osmBroker

A native macOS app that **detects local AI CLIs** (Claude Code, Codex CLI, and 14 others) and **exposes them as OpenAI- and Anthropic-compatible HTTP endpoints** over your LAN.

Point AnythingLLM / OpenAI SDK / curl at `http://<your-mac>:8080/v1` with a bearer token, and they can chat with whatever AI CLI is installed on this machine — no cloud API keys for every client.

## Status

**v0.3** — Phase 1.5 UX overhaul shipped. End-to-end through the broker against real claude + real codex CLIs has been verified with 21 live inference calls.

## Quick start

```sh
# Requires Xcode 15 (or Command Line Tools + a working Xcode toolchain via
# DEVELOPER_DIR for tests).
swift build -c release          # builds the SwiftUI app + osmBrokerCore
Scripts/make-app-bundle.sh      # wraps the binary in a hand-rolled .app
open osmBroker.app              # launches with a real LAN IP, real detection
```

In the running app:
1. **CLI** tab — see which AI CLIs were auto-detected (`claude`, `codex`, etc.)
2. **Models** tab — tick which models each CLI should serve
3. **Serve** tab — pick a port, click **Start broker**
4. From anywhere on your LAN:
   ```sh
   curl -N http://<your-mac>:8080/v1/chat/completions \
     -H "Authorization: Bearer osm-local-dev" \
     -H "Content-Type: application/json" \
     -d '{"model":"sonnet","stream":true,
          "messages":[{"role":"user","content":"hi"}]}'
   ```

## Architecture

- **`Sources/osmBrokerCore/`** — pure library, no SwiftUI. Contains:
  - `Broker/` — SwiftNIO HTTP server, OpenAI + Anthropic SSE encoders, bearer-auth (constant-time), error mapping
  - `Adapters/` — `ClaudeAdapter`, `CodexAdapter`, the `Adapter` protocol
  - `Process/` — subprocess spawn + lifecycle (SIGTERM → SIGKILL escalation, signal-safe PID mirror)
  - `Detection/` — PATH search, `--version` probe, `getifaddrs` LAN IP, `~/.codex/config.toml` parser
- **`Sources/osmBroker/`** — SwiftUI app: 4 panes (CLI / Models / Serve / More), sidebar with brand mark + endpoint card, system / light / dark theme toggle.
- **`Tests/osmBrokerCoreTests/`** — XCTest. 101 fast tests plus live-network tests (`LiveCodexBrokerTests`, `LiveClaudeBrokerTests`, `QuizTests`) that exercise real claude + codex through the broker.
- **`docs/osmBroker/`** — the full design + dev log, viewable as an Obsidian vault. Start at `00-Index.md`. Every architecture decision, every bug-find-fix chain, every screenshot tour.
- **`Scripts/make-app-bundle.sh`** — wraps the SPM exec in an ad-hoc-signed `.app` with the right Info.plist and resource-bundle layout.

## Live tests

The free path (no network, no LLM cost):

```sh
swift test --skip Live --skip QuizTests --skip testLiveCodex
```

The full path (live inference, ~$1, ~3 minutes):

```sh
swift test
```

## Reading the design notes

The `docs/osmBroker/` folder is an Obsidian vault. Open it in Obsidian for [[wiki-style]] navigation, or read the files in any markdown viewer.

Highlights:
- `01-Planning/PRD-Analysis.md` — every PRD requirement mapped to delivery state
- `01-Planning/Security-Requirements.md` — AUTH-1..5, NET-1..6, SPAWN-1..7, etc., each linked to a test
- `05-Architecture/Claude-Model-Discovery.md` — why we use `sonnet`/`opus`/`haiku` aliases instead of versioned model IDs
- `05-Architecture/AppState-Discovered-Models.md` — how `~/.codex/config.toml` discovery drives the Models tab defaults
- `04-Logs/Dev-Log.md` — chronological build diary, every entry citing the change + the verification

## License

(TBD.)
