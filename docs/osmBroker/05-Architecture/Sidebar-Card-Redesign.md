# Sidebar bottom card — redesign

## The user's exact request

> at the bottom left where you are showing broker end points and below that it says Auth and then it says Bearer and then showing api key set in the app. I want it to show: "Base URL: <localip>:<port> / localhost:<port>" and in the next line: "API Key: <APIKEYSET>" both of them with copy buttons next to them for conveniece and also the text copyable if the user so chooses to text select them

## What's there today (to be replaced)

```
┌──────────────────────────────┐
│ BROKER ENDPOINT              │
│ http://                      │   ← two-line wrap of URL
│ 192.168.68.104:8080          │
│ also http://localhost:8080   │   ← muted second URL
│ ─────────                    │
│ AUTH                         │
│ Bearer osm-local-dev         │
└──────────────────────────────┘
```

Problems:
- Two URLs, but only one is selectable as a unit, and neither has a Copy button.
- "AUTH" + "Bearer" is jargon — the user just wants the key.
- The leading `http://` on its own line looks like a parse error.

## What the new card will look like

```
┌──────────────────────────────┐
│ BASE URL                     │
│ 192.168.68.104:8080    [⌘]   │
│ localhost:8080         [⌘]   │
│ ─────────                    │
│ API KEY                      │
│ osm-local-dev          [⌘]   │
└──────────────────────────────┘
```

Three copy buttons (LAN base URL, localhost base URL, API key). Each value is also a `.textSelection(.enabled)` text node so Cmd-A → Cmd-C still works.

Drops the `http://` prefix from display because every copy button writes the full scheme-included URL to the clipboard — what's *displayed* should be quick to glance at; what's *copied* should be paste-ready.

## Implementation sketch

```swift
private struct EndpointCard: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label("BASE URL")
            CopyRow(display: "\(state.reachableHost):\(state.port)",
                    copyValue: state.baseURL)
            CopyRow(display: "localhost:\(state.port)",
                    copyValue: state.localhostURL)
            DarkDivider()
            Label("API KEY")
            CopyRow(display: state.apiKey, copyValue: state.apiKey)
        }
        .padding(14)
        .background(Theme.Palette.dark)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, ...))
    }
}

private struct CopyRow: View {
    let display: String
    let copyValue: String
    @State private var copied = false
    var body: some View {
        HStack(spacing: 8) {
            Text(display)
                .font(Theme.Typeface.mono(11))
                .foregroundStyle(Theme.Palette.darkText)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            Button { copy() } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.Palette.silver)
                    .frame(width: 22, height: 22)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }
    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(copyValue, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            copied = false
        }
    }
}
```

## Pasteboard details

We've already used `NSPasteboard` from `MorePane`'s Copy button so the pattern is known. Each copy clears contents first (avoiding the macOS multi-flavor stack issue where `setString` doesn't overwrite an earlier image entry).

## What gets copied vs. what gets shown

| Row | Displayed | Copied |
|---|---|---|
| LAN base URL | `192.168.68.104:8080` | `http://192.168.68.104:8080` |
| Localhost base URL | `localhost:8080` | `http://localhost:8080` |
| API key | `osm-local-dev` | `osm-local-dev` |

The scheme prefix in the copied value is what curl / AnythingLLM / OpenAI SDK actually want. The displayed version trims it because the user already knows it's HTTP and the prefix wastes precious sidebar width.

## When base URL changes

If the user edits `state.port` in the Serve tab, both `CopyRow`s reflect the new value the same frame (they read from `state.reachableHost`, `state.port`). Similarly if `host` flips from `0.0.0.0` to `127.0.0.1` (no LAN), the LAN row shows whatever `reachableHost` becomes, which falls back to "localhost" when no `lanIP` is known.

## Accessibility

- The button has an `accessibilityLabel("Copy \(display)")` so VoiceOver speaks the right thing.
- The text node uses `.textSelection(.enabled)` which gives full-keyboard selection + Cmd-C even without the button — meeting the user's "also the text copyable if the user so chooses to text select them" requirement.

## What this card no longer does

- Doesn't say the word "Bearer" — the API key is what callers paste; they know to wrap it. (Future polish: a small "Use as: `Authorization: Bearer <key>`" hint on hover.)
- Doesn't redact the API key. The whole point is the user *wants* to see and copy it. We never log this value (LOG-2) but display in the user's own sidebar is fine.
