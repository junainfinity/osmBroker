# AppState — wiring discovered models per agent

## Goal of this step

Make `ConfigDiscovery`'s output reachable from the UI without breaking the existing toggle / broker-catalogue plumbing.

## Two new `@Published` fields

```swift
/// Per-agent models the user actually has, in priority order.
/// Built from `ConfigDiscovery` ∪ `def.fallbackModels` (config first).
@Published var discoveredModels: [String: [String]] = [:]

/// Agent → its config-discovered "primary" model. Nil if the CLI has no
/// config or no model setting. Used to badge "primary" in the Models pane.
@Published var primaryModel: [String: String] = [:]
```

These are populated inside `applyDetection(_:)` once per scan. They're the **source of truth** for which models exist; `agent.models` (the registry fallback) becomes purely a default-for-display when no config exists.

## Why merge ∪ instead of *replace*

If a user's `~/.codex/config.toml` only mentions `gpt-5.5`, we don't want to lose `gpt-5-codex` from the visible list — they might want to opt in to it. So:

```
discoveredModels[codex] = uniq(configModels ++ registryModels)
```

`configModels` first → it sorts higher in the UI → user sees their actual setting at the top. The registry models follow as discoverable alternatives.

## Where `agent.models` still matters

`AdapterRequest` validation already checks `model` against `RequestValidation.sanitizedModel(_:)` for shape. Whether a model is actually *served* depends on `currentCatalog()` which consults `modelExposed[modelID]`. The registry's `fallbackModels` continue to define which adapters answer to which model strings at the broker level — they're not deleted, just demoted from "what's on screen" to "what the adapter declares it can route."

## `currentCatalog` change

```swift
for agent in installedAgents where agentExposed[agent.id] ?? false {
    guard let adapter = adapterFor(agent.id) else { continue }
    // Iterate the *union*, not just registry models.
    for model in (discoveredModels[agent.id] ?? agent.models)
        where modelExposed[model] ?? false {
        entries.append(.init(modelID: model, adapter: adapter))
    }
}
```

If `discoveredModels` is empty (no config files yet), fall back to `agent.models` as before — preserves existing behaviour for users without config files.

## `applyDetection` change

Same loop, two new lines:

```swift
private func applyDetection(_ agents: [DetectedAgent]) {
    detectedAgents = agents

    for agent in agents where agentExposed[agent.id] == nil {
        agentExposed[agent.id] = agent.isInstalled
    }

    // NEW: layer ConfigDiscovery results on top.
    for agent in agents where agent.isInstalled {
        let cfg = configDiscoveryResult(for: agent.id)
        let union = uniqueOrdered(cfg.discovered + agent.models)
        discoveredModels[agent.id] = union
        if let p = cfg.primary { primaryModel[agent.id] = p }
        for model in union where modelExposed[model] == nil {
            modelExposed[model] = true
        }
    }

    // …existing selection-default logic unchanged…
}

private func configDiscoveryResult(for id: String) -> ConfigDiscovery.Result {
    switch id {
    case "codex":  return ConfigDiscovery.codex()
    case "claude": return ConfigDiscovery.claude()
    default:       return .init(discovered: [], primary: nil)
    }
}

private func uniqueOrdered(_ xs: [String]) -> [String] {
    var seen = Set<String>(); var out: [String] = []
    for x in xs where seen.insert(x).inserted { out.append(x) }
    return out
}
```

## Reactive surface for the UI

`ModelsPane` will iterate:

```swift
ForEach(state.installedAgents, id: \.id) { agent in
    AgentModelsCard(
        agent: agent,
        models: state.discoveredModels[agent.id] ?? agent.models,
        primary: state.primaryModel[agent.id]
    )
}
```

`AgentModelsCard` reads `state.modelExposed[modelID]` for each checkbox and writes through `state.binding(forModel: modelID)`. Existing pattern; no new bindings required.

## Tests

ConfigDiscovery has unit tests at the parser level already. The AppState wiring is harder to unit-test because it's `@MainActor` SwiftUI state. Manual verification through the running app:

1. Launch, observe Codex section shows `gpt-5.5` first, badged "primary".
2. Edit `~/.codex/config.toml` to `model = "gpt-5-codex"`, click Rescan, observe primary badge moves.
3. Delete `~/.codex/config.toml`, click Rescan, observe registry models remain but no primary badge.

Codified as steps in [[../03-Tests/Test-Strategy]] under "UI smoke".

## Edge cases

- **Symlinked $HOME**: `NSHomeDirectory()` resolves through symlinks; ConfigDiscovery sees the real path. Tested implicitly by macOS itself in setUp / tearDown.
- **TOML with multiple `model =` lines at top level**: scanner returns the *first*. Users with override-style configs may be confused, but TOML semantics say first wins for a duplicate key in the same scope.
- **Comments containing `model =`**: parser is comment-aware (test #4).

## Auto-enable rules

> Why does `gpt-5.5` default ON but `gpt-5-codex` default OFF on this Mac?

Pre-fix behavior: every model in the registry's union was auto-enabled on first detection. That meant on a ChatGPT-account install of Codex (where only `gpt-5.5` actually works), our `/v1/models` would advertise `gpt-5`, `gpt-5-codex`, and `gpt-5-mini` — every one of which the upstream codex CLI rejects with `"not supported when using Codex with a ChatGPT account"`. The user's first call to any of those models 404'd.

[[../04-Logs/Dev-Log#2026-05-13-t260m-3-questions-per-model-live-quiz]] captured this when the live quiz ran 21 calls and 9 of them — all Codex non-discovered models — returned upstream 400s.

Post-fix rule, in `AppState.applyDetection`:

```swift
let onlyDiscovered = !cfg.discovered.isEmpty
for model in union where modelExposed[model] == nil {
    modelExposed[model] = onlyDiscovered ? cfg.discovered.contains(model) : true
}
```

In English:
- **If `ConfigDiscovery` surfaced any models from the user's own config** → trust that as the account-tier truth. Only auto-enable models in the discovered set; registry-fallback entries default OFF.
- **If discovery found nothing** (e.g. claude — there's no standard `model` config to read) → auto-enable everything in the union. Aliases like `sonnet`/`opus`/`haiku` are stable and Anthropic's tier-gating is per-message, not per-model-string.

On this Mac, that means:
- **Codex**: `gpt-5.5` defaults ON (it's in `~/.codex/config.toml`). `gpt-5-codex`, `gpt-5`, `gpt-5-mini` all default OFF.
- **Claude**: `sonnet`, `opus`, `haiku` all default ON (no `~/.claude/settings.json#model`).

User can flip the speculative ones ON manually in the Models tab if they have a different account tier — defaults just stop *advertising* models the user's account can't reach.

## Cross-refs

- [[Model-Discovery]] — the parser this rule consumes
- [[Claude-Model-Discovery]] — why claude has no config-discovered models (aliases instead)
- [[../04-Logs/Dev-Log]] — the quiz evidence that drove this rule
