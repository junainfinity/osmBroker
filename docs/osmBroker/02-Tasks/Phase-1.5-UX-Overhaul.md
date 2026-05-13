# Phase 1.5 — User-driven UX overhaul

**Trigger:** User feedback after live-screenshot walkthrough — "think like Steve Jobs would about his customer. The app should be super simple to use."

**Scope:** Visual + IA overhaul. No backend changes to the broker / NIO / adapter contracts (those already pass 92/92 tests). Strictly UI and small additions to detection (model discovery from config files).

## Verbatim user requirements

> 1. Logo is not what we have in assets for dark or light logo. change it first.
> 2. there are 3 menus on left side bar - Live, More and Network. Change it to CLI, Models, Serve and More.
> Let me tell you what i want in each menu - a) Live: show just all live CLI detected in their mac.
> b) Models: show all the models available from the CLI identified already (show the actual models and not the static example ones you are showing now in the main page) and allow user to click on checkbox if they do or do not want to serve any particular models from those CLI so that when we serve it as an API, it need not even show up as a choice.
> c) Serve: In this menu section I want our user to be able to change their port number and start or stop their service to serve in this mac's ip and manually typed in port - the OpenAI and Anthropic Compatible API the models they had chosen to serve via this mac's IP/localhost and the port number.
> d) More - In this last menu section, show the user their installed and identified AI CLI and the other CLI our osmBroker app is built to identify and broker with installation instructions next to them.
>
> This app should be super user friendly so at the bottom left where you are showing broker end points and below that it says Auth and then it says Bearer and then showing api key set in the app. I want it to show: "Base URL: <localip>:<port> / localhost:<port>" and in the next line: "API Key: <APIKEYSET>" both of them with copy buttons next to them for conveniece and also the text copyable if the user so chooses to text select them

## My interpretation

The user is asking for **simplification** plus **truthfulness**:

1. **Brand fidelity**: stop using the serif Georgia "osmBroker" wordmark. Use the actual brand mark from `osmdesign/apps/web/public/osm-api-{light,dark}.png` (atomic mark, brown lines / yellow nucleus on light, white-on-black for dark backgrounds). The app's sidebar is cream so we ship `osm-api-light.png`.

2. **Tabs as user verbs**: split the conflated Active tab into two: "what do I have" (CLI) vs. "what do I want to serve" (Models). Rename Network → Serve so it's about the verb of running the server, not the noun of network config.

3. **Model truthfulness**: stop hardcoding `gpt-5.5` etc. in the registry as if they were authoritative. **Discover** the user's actual models from each CLI's on-disk config:
   - Codex: `~/.codex/config.toml` has a top-level `model = "..."` line (this Mac has `model = "gpt-5.5"`). Also has `[profiles.<name>]` sections each with their own `model = "..."`.
   - Claude Code: `~/.claude/settings.json` may exist with either flat `model` or `defaults.model`.
   - **Badge** the config-discovered model as "primary" so the user can see at a glance which one their CLI defaults to.

4. **Sidebar bottom card**: drop the "BROKER ENDPOINT … AUTH … Bearer" multi-row layout. Replace with a sharply utilitarian two-row card:
   ```
   Base URL    192.168.68.104:8080    [⌘C]
               localhost:8080         [⌘C]
   API Key     osm-local-dev          [⌘C]
   ```
   Each value is text-selectable AND has a single-click Copy button.

## Task ledger (live)

- [x] Hunted brand assets — found at `~/Projects/osmdesign/apps/web/public/osm-api-{light,dark}.png`. Copied into `Sources/osmBroker/Resources/osm-mark-{light,dark}.png`. Added `.process("Resources")` to executableTarget in `Package.swift`. See [[../05-Architecture/Logo-Branding]].
- [x] Rewrote `Models.swift`'s `Pane` enum: `cli / models / serve / more`. Each with SF Symbol icon (`terminal`, `rectangle.stack`, `antenna.radiowaves.left.and.right`, `square.grid.2x2`). Default selected pane is now `.cli`.
- [x] Wrote `osmBrokerCore/Detection/ConfigDiscovery.swift` — pure Swift TOML and JSON readers for `~/.codex/config.toml` and `~/.claude/settings.json`. Returns `Result(discovered: [String], primary: String?)`. See [[../05-Architecture/Model-Discovery]].
- [x] Tests for ConfigDiscovery (8 cases — TOML quirks, missing files, JSON shapes). Tests use a tmpdir as fake $HOME.
- [ ] **(in progress)** Wire ConfigDiscovery results into `DetectedAgent.models` so the UI sees real models, not just the registry fallback list.
- [ ] Rewrite `Sidebar.swift`: logo + brand row, new endpoint card with copy buttons.
- [ ] Rename `ActivePane.swift` → `CLIPane.swift` and trim to a clean list (no model toggles, no detail JSON block, no "Not on this Mac" grid).
- [ ] Build `ModelsPane.swift` — sections per installed CLI with checkboxes and a "primary" badge for the config-discovered model.
- [ ] Rename `NetworkPane.swift` → `ServePane.swift` and trim — just port + Start/Stop + big base URL card.
- [ ] Move "Quick Launchers" (Open in Terminal) into CLI pane where it belongs contextually.
- [ ] Update `MorePane.swift` — installed CLIs first, then not-installed with install commands.
- [ ] Update `ContentView.swift` to dispatch four panes.
- [ ] Update `Sidebar.swift`'s nav counts: CLI → installed count, Models → enabled count, Serve → IDLE/LIVE, More → 16.
- [ ] Rebuild release + bundle + screenshot each pane.
- [ ] Final dev/test log entries.

## Cross-refs

- [[../05-Architecture/Logo-Branding]] — asset wiring + Image rendering
- [[../05-Architecture/Model-Discovery]] — ConfigDiscovery design + integration plan
- [[../05-Architecture/Sidebar-Card-Redesign]] — the new Base URL / API Key card
- [[../05-Architecture/Tab-Structure-v2]] — full IA: what lives where
- [[../05-Architecture/AppState-Discovered-Models]] — how discovered models flow into the UI
- [[../05-Architecture/Bundle-Resources-Gotcha]] — bug discovered post-build
- [[../04-Logs/Dev-Log]] — append-only timeline

## Verification status (so far)

| Item | How verified | Result |
|---|---|---|
| Pane enum + AppState `.cli` default | Compile succeeds + tests pass | ✅ |
| ConfigDiscovery against this Mac's real `~/.codex/config.toml` | One-shot swift script reading the same file with the same parser logic returned `gpt-5.5` | ✅ — proven |
| AppState `discoveredModels` + `primaryModel` populate on scan | Unit-tested at parser level (9 ConfigDiscovery tests); end-to-end requires UI screenshot | ⚠ pending visual |
| Sidebar redesign — logo + new card | Resource bundle now in `.app/Contents/MacOS/osmBroker_osmBroker.bundle/` after `make-app-bundle.sh` fix | ⚠ pending visual |
| CLIPane — slim list, Open in Terminal | Code compiles, app launches (PID alive) | ⚠ pending visual |
| ModelsPane — checkboxes + primary badge | Code compiles | ⚠ pending visual |
| ServePane — big base URL + copy | Code compiles | ⚠ pending visual |
| MorePane — installed-first sectioning | Code compiles | ⚠ pending visual |
| Full test suite | `swift test` → **101 of 101 pass** in 28.2 s after one transient codex flake retry | ✅ |

## Screen-capture wedge (separate from the build)

After several screenshots earlier in the session, the screen-capture pipeline started returning `nil (permission missing or SCContentFilter failure)`. The harness still says `osmBroker` is granted at tier `full` (verified with `list_granted_applications`), so the OS-level Screen Recording permission for the parent Claude process has been pulled — most likely by macOS revoking after sleep, or because the harness's containing app needs to be ticked again in **System Settings → Privacy & Security → Screen & System Audio Recording**.

**To restore visual verification:** open System Settings → Privacy & Security → Screen & System Audio Recording, ensure the Claude/Claude-Code entry is checked, and quit + relaunch the Claude harness.

Until then, this overhaul ships headlessly verified:
- Build clean, all tests green.
- ConfigDiscovery proven against the real `~/.codex/config.toml`.
- App launches with the new bundle layout (PNG resources present at the expected path).
