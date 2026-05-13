# Model Discovery

## The problem (in the user's words)

> show the actual models and not the static example ones you are showing now in the main page

Until this pass, `AgentDef.fallbackModels` was a hand-curated list per CLI. For Codex that meant `["gpt-5.5", "gpt-5-codex", "gpt-5", "gpt-5-mini"]`. We discovered the hard way during the live test that **`gpt-5` is rejected** on ChatGPT-account installs of codex:

```
{"type":"error","status":400,"error":{"type":"invalid_request_error",
 "message":"The 'gpt-5' model is not supported when using Codex with a ChatGPT account."}}
```

So the fallback list was *plausible* but not *true*. The user's own machine has exactly one model set: `gpt-5.5`, configured in `~/.codex/config.toml`. That's the ground truth.

## Approach: read the CLI's config files

We can't ask codex "what models do you support?" — there's no `codex models` command. We *can* ask the user's filesystem what models the user has set up. That's `ConfigDiscovery`.

Two adapters get config readers today:
- **Codex** — TOML at `~/.codex/config.toml`
- **Claude** — JSON at `~/.claude/settings.json` (also tries `~/.claude/config.json` and `~/.config/claude/settings.json` in priority order)

Other adapters (Gemini / Kimi / etc.) get `ConfigDiscovery` stubs over time as their config conventions stabilize. For now they fall through to the registry's curated list.

## TOML scanner — why a hand-rolled one

Swift has no TOML parser in the stdlib and bringing in a third-party crate just for one field would balloon the dependency graph. Codex's config grammar is small enough to scan with three rules:

1. Find a line matching `<key> = "<value>"` at column 0 — return value.
2. Tolerate `# comment` at the end of a line, *as long as the `#` is outside any quoted string*.
3. Recognize `[profiles.<name>]` (and `[profile.<name>]`) section headers — values inside those scopes are "alternate" models, useful for badging in the UI.

Implementation lives at `Sources/osmBrokerCore/Detection/ConfigDiscovery.swift`. Two public funcs: `codex(homeDir:)` and `claude(homeDir:)`. Both take an explicit `homeDir` parameter so the test suite can point them at a tmpdir without hitting the real `~`.

The internal helper `parseTOMLString(key:in:)` is also `internal` so the test file can unit-test it directly (Swift's `@testable import` is enough — no need to make it `public`).

## Claude — multiple paths, two shapes

Claude Code's settings file isn't standardized across releases. The function tries three paths in priority order:
1. `~/.claude/settings.json` — newest layout
2. `~/.claude/config.json` — older / alternate
3. `~/.config/claude/settings.json` — XDG-style fallback

Once a file is found, two JSON shapes are tried:
- Flat: `{"model": "claude-sonnet-4-5", …}`
- Nested under `defaults`: `{"defaults": {"model": "claude-opus-4-1"}, …}`

If neither key path resolves, return an empty `Result` and let the registry's curated list take over.

## Return shape

```swift
public struct Result: Sendable, Equatable {
    public let discovered: [String]  // models found on disk (may be empty)
    public let primary: String?      // current default model, if known
}
```

The UI badges `primary` as "**primary** · from `~/.codex/config.toml`" so the user sees both the value and *where it came from*. This is the "truthfulness" requirement.

## Integration plan (next chunk of work)

`AppState.applyDetection(_:)` currently does:

```swift
for agent in agents {
    for model in agent.models where modelExposed[model] == nil {
        modelExposed[model] = true
    }
}
```

About to be replaced by:

```swift
for agent in agents {
    // Merge config-discovered models with the registry's curated list.
    let discovered = configDiscovery(for: agent.id).discovered
    let combined = Array(NSOrderedSet(array: discovered + agent.models)) as! [String]
    discoveredModels[agent.id] = combined
    primaryModel[agent.id] = configDiscovery(for: agent.id).primary
    for model in combined where modelExposed[model] == nil {
        modelExposed[model] = true
    }
}
```

Two new `@Published` fields on AppState:
- `discoveredModels: [String: [String]]` — per-agent ordered union of config + registry
- `primaryModel: [String: String]` — agent → its default model (nil if unknown)

The Models pane keys off these.

## Tests landed

`Tests/osmBrokerCoreTests/ConfigDiscoveryTests.swift` — 8 cases:

| # | Test | What it pins down |
|---|---|---|
| 1 | `testParseTOMLSimpleString` | Basic `key = "value"` extraction |
| 2 | `testParseTOMLTrailingComment` | Inline `# comment` after value is stripped |
| 3 | `testParseTOMLMissingKeyReturnsNil` | Absent key → nil, no fallback magic |
| 4 | `testParseTOMLIgnoresCommentedLine` | A `# model = "x"` line is correctly skipped |
| 5 | `testExtractProfileModels` | `[profiles.fast]` and `[profiles.code]` sections each contribute their `model =` value |
| 6 | `testCodexDiscoveryEndToEnd` | Tmpdir-rooted home with a real config.toml; primary + discovered both correct |
| 7 | `testCodexDiscoveryMissingConfigReturnsEmpty` | Nonexistent dir → `Result(discovered: [], primary: nil)` |
| 8 | `testClaudeDiscoveryFlatModel` / `testClaudeDiscoveryNestedDefaultsModel` | Both JSON shapes tested |

Tests run in `< 5 ms` total — no subprocess, no network.

## What the UI will show

For this Mac, the Codex section of the Models pane will look like:

```
Codex CLI                                /opt/homebrew/bin/codex
─────────────────────────────────────────────────────────────────
☑ gpt-5.5       · primary (from ~/.codex/config.toml)    [Serve]
☑ gpt-5-codex                                            [Serve]
☐ gpt-5         · not supported on ChatGPT accounts      [Serve]
☐ gpt-5-mini                                             [Serve]
```

The "primary" badge is the win. The user knows immediately which model is *real* on their machine.

## What this does NOT do

- Doesn't query the OpenAI / Anthropic public APIs for an authoritative model list. That requires API keys + network and creates an offline-first regression.
- Doesn't try to validate that a configured model actually works (would need a real spawn). The user gets honest reporting of what's configured, not a guarantee that every entry will succeed.
- Doesn't write back to the config files. We're a read-only consumer of the user's choices.
