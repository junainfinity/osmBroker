# CLI tab toggle — audit + simplification

## What the user asked

> In the first menu CLI's content section screen does turning the toggle corresponding to each CLI do anything at all? if it doesn't remove the toggle.

## Audit

Each `CLICard` in `CLIPane.swift` renders:

```swift
ToggleSwitch(isOn: state.binding(forAgent: agent.id),
             label: "Expose \(agent.def.name)")
```

That toggle writes to `state.agentExposed[agent.id]`, which is read in `AppState.currentCatalog()`:

```swift
for agent in installedAgents where agentExposed[agent.id] ?? false {
    …
    for model in modelsFor(agent) where modelExposed[model] ?? false {
        entries.append(.init(modelID: model, adapter: adapter))
    }
}
```

So: **yes, it does something** — flipping it off excludes the whole CLI from `/v1/models`. But:

1. It has **zero visible feedback** on the card itself. The pills, the metadata, "Open in Terminal" — everything stays the same when the toggle goes off. Looks broken from the user's POV.
2. The Models tab already lets the user toggle individual models. Disabling every model under a CLI is functionally equivalent to disabling the CLI. **Two doors to the same room.**

## Decision: remove the per-CLI toggle

Single source of truth for "what does the broker serve" → the Models tab. The CLI tab becomes purely **informational** — a glance at what's installed, what's running, where the binary lives. Toggling at the CLI level (e.g. "I have Claude installed but never want to serve it") is rare and easily achieved by un-toggling that CLI's models in the Models tab.

### Code changes

1. **`Sources/osmBroker/CLIPane.swift`** — drop the `ToggleSwitch` from `CLICard`. Card now reads as a clean info row: monogram + name + subtitle + pills + Open in Terminal button.
2. **`Sources/osmBroker/AppState.swift`** — `currentCatalog()` no longer guards on `agentExposed`. Iterate every installed agent; `modelExposed` is the only filter.
3. **Keep `agentExposed`** stored in `AppState` for now — harmless and might be useful for a future advanced mode. Just not consulted by `currentCatalog()`.
4. **Tests** — none of the existing tests directly assert `agentExposed` behaviour, so no test updates.

### Before / after

| Before | After |
|---|---|
| CLI card has toggle that silently changes broker behaviour | CLI card is informational; no toggle |
| Two ways to disable a CLI (CLI tab toggle + Models tab) | One way (Models tab) |
| User sees "toggle off doesn't change anything visible" | User sees "to stop serving model X, untoggle it on Models tab" |

### Counter-argument I considered

Keep the toggle but add visual feedback (dim the card, "disabled" pill, hide the agent's models in Models tab). More code, more conditional rendering, and *more for the user to learn*. Steve-Jobs simplicity wins: one place to make the choice.

## Cross-refs

- [[Tab-Structure-v2]] — CLI vs Models tab split
- [[AppState-Discovered-Models]] — `currentCatalog` filtering logic
