# Self-Critique

The prior pass shipped a pretty UI but failed the PRD on substance. Honest accounting so we don't repeat the mistakes.

## What was wrong before

### 1. Built the picture before the product

The first pass mirrored the HTML prototype's visual structure (Active / Routing / Network) and populated it with the prototype's mock data verbatim. The result *looked* like the PRD's app but had no functional broker behind it.

The HTML was a static prototype — useful for visual language, not for behaviour. I treated it as a spec.

**Correction:** PRD §3.3 explicitly asks for an Active / More / Network tab structure. We had Active / Routing / Network. Routing was a visualization of an engine that doesn't exist; More — the actual discovery surface the PRD calls for — was absent. **Fix:** drop the Routing tab, add the More tab in the same slot.

### 2. Lied with placeholder data

The provider cards showed `pid 48231`, `312 MB`, `2 models enabled` — none of which were tied to real state. The "Base API URL" rendered `http://192.168.1.18:8080` regardless of whether that was a real address on the user's machine.

This is the worst class of UI bug: it doesn't crash, it doesn't error, it just confidently misinforms.

**Correction:** Second pass replaced these with real `getifaddrs` LAN lookup, real `ps -Axc` running scan, real PATH detection. **Carry-over fix for this pass:** memory + user fields are still missing from running pills (PRD §3.1).

### 3. Rendered a URL in serif

The sidebar Base API URL card used Georgia 20pt for `http://192.168.1.18:8080`. Georgia is the display face — fine for headings, wrong for URLs. Numbers and punctuation rendered as awkward proportional glyphs.

**Correction:** Switched to SF Mono in the second pass. Note for the build going forward: URLs, code, JSON, file paths, model IDs → always mono. Names, titles, lede → display serif. Body copy → SF.

### 4. No tests

Zero. Not unit, not integration, not security. Every change required eyeball verification with `swift run`.

**Correction:** This build adds an `osmBrokerCore` library target that's independently testable, and an `osmBrokerCoreTests` XCTest target with coverage for every security rule in [[Security-Requirements]]. UI stays in the executable target where SwiftUI views are notoriously hard to unit-test — that's an honest trade.

### 5. Used PRD example model IDs as if they were specs

The HTML had `gpt-5.5`, `claude-3-7-sonnet`, `gemini-3-pro` — speculative names from the PRD's prose examples. I kept them in the registry initially.

**Correction:** Registry now has actual contemporary model IDs (`claude-sonnet-4-5`, `gpt-5-codex`, `gemini-2.5-pro`, etc.). When real model discovery lands (e.g. `pi --list-models`), the fallback list is just a hint.

### 6. Buttons that don't do anything

`Rescan` / `Start broker` / `Apply routes` / `Save network` / `Test key` / `Open in Terminal` — only the first does something. The rest are visual cargo.

**Correction:** This build wires `Start broker` to a real NIO server, `Test key` to a real outbound `curl`-equivalent, `Open in Terminal` to `Terminal.app`. Buttons we can't deliver get removed, not greyed out.

### 7. Spawned background process named `osmBroker` but didn't bundle as an .app

`swift run` produces a bare executable. The screenshot tool can't see it; macOS treats it as a process, not an app; there's no Dock icon control, no menu-bar item.

**Carry-over:** still a CLT-only environment (no Xcode here), so we can't sign a proper `.app` in this session. Mitigate: keep the executable runnable via `swift run` AND prepare a `Scripts/make-app-bundle.sh` so the user can wrap it in a minimal `.app` when they have Xcode.

### 8. Over-promised in the README-of-the-mind

When asked "is it done?" I said "design done, broker not started." That was honest, but I had earlier said "running PID 99751, take your time poking at it" — implying the app was further along than it was. Need to default to *under-claim, then deliver more*.

**Correction:** This build's Dev Log will record what actually works, with the test that proves it, and what's still placeholder.

## Constraints I'll respect this time

1. **No mock data anywhere.** If a value isn't real, the UI shows empty state, "—", or a calibrated stub message.
2. **No button without an action.** Either wired or removed.
3. **Every security rule has a test.** No "trust me" code.
4. **PRD section IDs cited in code comments.** When a thing exists because of a PRD line, the line lives in a `// PRD §X.Y` comment near the code.
5. **Dev Log updated after every meaningful step**, not in retrospect.
