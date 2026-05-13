# Claude model discovery — what we got wrong + what's right

## The bug the user spotted

> the claude cli broker is broken because those are not the models claude CLI is serving

Until this fix the registry advertised:
- `claude-sonnet-4-5`
- `claude-opus-4-1`
- `claude-haiku-4-5`

The actual names Claude Code resolves to on this Mac (extracted from a live `claude -p --model sonnet --output-format json` response's `modelUsage` block):
- `claude-sonnet-4-6`
- `claude-opus-4-7`
- `claude-haiku-4-5-20251001`

Every. Single. One. Wrong. The broker would 404 if a client sent the registry's literal names to `claude -p --model claude-sonnet-4-5`.

## Why my registry was wrong

I copy-pasted "plausible looking" Claude model names into `AgentDef.fallbackModels` thinking they were forward-looking placeholders. They weren't.

Anthropic's release cadence rolls minor versions of each tier (sonnet 4-5 → 4-6, opus 4-1 → 4-7) without warning. Hardcoding specific names goes stale fast.

## What's actually trustworthy

`claude --help` (version 2.1.140) says:

> `--model <model>` — Model for the current session. Provide an **alias for the latest model** (e.g. 'sonnet' or 'opus') or a model's full name (e.g. 'claude-sonnet-4-6').

So `sonnet`, `opus`, `haiku` are first-class names that auto-resolve to whatever the latest is. **They are the right abstraction for our broker to expose.**

## What I'm changing

1. `AgentRegistry.all` — claude's `fallbackModels` becomes `["sonnet", "opus", "haiku"]`.
2. `ClaudeAdapter.argumentsForRequest` already passes whatever model the client sent to `claude -p --model <X>`. Aliases work as-is.
3. Tests that hardcoded `claude-sonnet-4-5` etc. get updated to `sonnet`.
4. Bumped `~/.local/bin/claude` is at `2.1.140` this turn (was `2.1.138`) — detection still works; the version pill in the UI will reflect the new number on next Rescan.

## What I'm NOT doing (yet)

**Live per-alias probing to surface the resolved name in the UI.** Each `claude -p --model X` call costs real money (haiku ~$0.01, sonnet ~$0.024, opus ~$0.054 per call on this account). Probing all three on every Rescan is $0.09 per click + ~15 s of latency. Not acceptable.

If a future iteration wants "currently: claude-sonnet-4-6" decoration, we'd:
- Cache resolved names per alias in `~/Library/Application Support/osmBroker/claude-resolved.json`
- Probe once per day in the background, or behind a "Probe models" button on the Models tab
- TTL the cache so user sees fresh info after Anthropic's model drops

Tracked in [[../02-Tasks/Phase-3-Polish-and-Marketplace]].

## How clients should send models

After this fix, the broker's `/v1/models` advertises:

```json
{
  "data": [
    {"id": "sonnet",   "owned_by": "claude", "object": "model"},
    {"id": "opus",     "owned_by": "claude", "object": "model"},
    {"id": "haiku",    "owned_by": "claude", "object": "model"},
    {"id": "gpt-5.5",  "owned_by": "codex",  "object": "model"},
    …
  ]
}
```

Clients use the alias. Internally the broker spawns `claude -p --model sonnet …`, Claude resolves to today's `claude-sonnet-4-6`, the right model runs. Tomorrow when Anthropic ships `claude-sonnet-4-7`, the same alias quietly upgrades — zero work on our side.

Claude *also* accepts the full names (`claude-sonnet-4-6`, etc.). If a client sends one directly, our adapter forwards it verbatim and it works — but those names aren't in our advertised catalog because they're stale the day Anthropic releases the next minor.

## Cross-refs

- [[Model-Discovery]] — original (config-file-based) discovery for Codex via `~/.codex/config.toml`. Claude doesn't ship a config readable for this purpose; aliases are the right answer.
- [[../02-Tasks/Phase-1.5-UX-Overhaul#verification-status-so-far]] — verification matrix; Claude model row is now ✅ after this fix.
