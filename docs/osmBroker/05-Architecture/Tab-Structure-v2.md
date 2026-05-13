# Tab Structure v2 — CLI / Models / Serve / More

The user's restructure broke the earlier "Active / More / Network" into four verbs that map cleanly to the workflow:

| Tab | User question it answers | What lives here |
|---|---|---|
| **CLI** | "What AI tools are running on this Mac right now?" | List of detected/installed CLIs — name, path, version, running PIDs. No model toggles. No detail panel. Cleanest possible scan-and-go view. |
| **Models** | "Which specific models do I want this Mac to serve?" | For each installed CLI, the union of (config-discovered models) + (registry-curated models) with a checkbox per model. Primary model badged. Disabled models won't appear in `/v1/models` and will 404 on `/v1/chat/completions`. |
| **Serve** | "Turn it on. Where can clients reach it?" | Port field, Start/Stop, prominent base URL display, error/conflict banners. **No** more interfaces card, **no** more Quick Launchers — those were Network-pane clutter. |
| **More** | "What other AI CLIs could I add?" | Two sections: "Installed on this Mac" (Claude/Codex right now), then "Available CLIs" (the 14 not-yet-installed) with install commands + Copy buttons + Install ↗ links. |

## Why split Active into CLI + Models

The old Active pane tried to do three things at once:
1. Show that we detect CLIs ✅
2. Let user enable/disable per-CLI ✅
3. Let user enable/disable per-model 🚫 (conflated with #2)

#1 and #2 happen at the CLI granularity; #3 at the model granularity. Squeezing them into one screen meant the model toggles lived inside a right-side detail panel that was easy to miss. The user's mental model is two separate decisions:

1. *Do I want my broker to know about Claude Code at all?* → CLI tab
2. *Given that I do, which Claude models should it serve?* → Models tab

So we split.

## Why Network → Serve

"Network" is the noun. "Serve" is the verb. The whole pane is about flipping a switch that says "yes, broadcast my CLIs as an HTTP API." The verb name is more truthful.

Stripping out of Serve:
- **Network interfaces card** — discovered IPs are valuable but not actionable on this screen. Moving to a hover/tooltip on the base URL OR to a tiny diagnostic strip if needed.
- **Quick Launchers** — "Open in Terminal" is about *running the CLI directly*, which is a CLI-tab concern, not a server concern. Migrating to CLI tab.

## Why More gets two sections

Previously More showed all 16 adapters in one grid. The installed ones (Claude, Codex) carried an `installed` pill but were otherwise mixed with the unavailable ones. The user has to scan to find what they already have. Reorder:

```
Installed on this Mac     2 of 16
  [Claude Code card]
  [Codex CLI card]

Available CLIs            14 of 16
  [Gemini CLI card with install command]
  [GitHub Copilot CLI card with install command]
  …
```

Same component, different sectioning.

## Default selected tab

Was `.active`. Now `.cli`. Same role: cold-launch lands on "what do you have," because the user has zero state on first run.

## Sidebar counts (right-aligned digits in nav)

| Tab | Count | When it changes |
|---|---|---|
| CLI | `state.installedAgents.count` | After a Rescan |
| Models | `state.enabledModelCount` | When any model toggle flips |
| Serve | `IDLE` / `LIVE` | When Start/Stop broker fires |
| More | `AgentRegistry.all.count` (16) | Static |

## Mapping: which file holds what

```
Sources/osmBroker/
├── CLIPane.swift           (was ActivePane.swift; rename + slim down)
├── ModelsPane.swift        (NEW — section per agent, checkboxes)
├── ServePane.swift         (was NetworkPane.swift; rename + slim down)
├── MorePane.swift          (existing, lightly refactor)
├── Sidebar.swift           (logo + new endpoint card)
├── ContentView.swift       (dispatch four panes instead of three)
└── …
```

## What I'm intentionally NOT building this pass

- Per-model rate limiting / quotas
- Per-tab keyboard shortcuts (Cmd-1 / 2 / 3 / 4) — easy follow-up
- Custom model entry ("type a model ID you want to expose") — solid feature but not requested
- Configurable host (currently hardcoded `0.0.0.0`) — `host` is editable in code, just no UI field in Serve. Add later if asked.

## Cross-refs

- [[Logo-Branding]] — the new visual identity in the sidebar
- [[Model-Discovery]] — where the per-model data on the Models tab comes from
- [[Sidebar-Card-Redesign]] — the redrawn Base URL / API Key card at the sidebar bottom
- [[../02-Tasks/Phase-1.5-UX-Overhaul]] — overall task list
