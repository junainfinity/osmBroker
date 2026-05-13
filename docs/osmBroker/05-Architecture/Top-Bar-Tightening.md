# Top bar tightening (v0.2.1)

## What the user observed

> there is lot of free space at the title bar of the app, correct it be appropriate width.

The custom top bar inside the window was:
- **44 pt tall** (chunky for what's a Mac chrome strip)
- Had a centered "osmBroker · Local AI routing server" string flanked by two `Spacer(minLength: 0)`s
- Combined with the 1200 pt default window width, the title floated in a big empty trough — half a centimetre of cream on either side on most displays

## What I changed

`Sources/osmBroker/ContentView.swift` — `TopBar`:

```swift
HStack(spacing: 10) {
    Color.clear.frame(width: 70, height: 1)   // traffic-light clearance (unchanged)
    Text("Local AI routing server")           // shorter tagline, left-aligned right past the lights
        .font(Theme.Typeface.body(12))        // was 13
        .foregroundStyle(Theme.Palette.muted)
    Spacer(minLength: 8)
    StatusPill()                              // floats right edge
}
.padding(.horizontal, 12)                     // was 16
.frame(height: 36)                            // was 44
```

Key moves:
1. **Dropped the "osmBroker · " prefix** from the title. The sidebar already has the brand mark + wordmark; the top bar text was redundant.
2. **Left-aligned the tagline** instead of centering it. The tagline now sits flush against the traffic-light clearance; the status pill takes the right edge. No more yawning gap.
3. **Bar height 44 → 36**. The previous 44 matched the OS standard for tabbed Safari-style toolbars; for a single-line tagline + pill, 36 reads as the "compact toolbar" you see in apps like Sketch or Things.

`Sources/osmBroker/App.swift` — window defaults:

```swift
.frame(minWidth: 960, minHeight: 640)   // was 980 × 680
.defaultSize(width: 1080, height: 720)  // was 1200 × 780
```

The smaller default plus the tighter top bar makes the layout feel deliberate on a 13" MacBook screen instead of like a stretched-out web page.

## What survived intact

- Traffic-light clearance (70 pt). macOS draws the close/min/max buttons absolutely; removing the clearance would let content slip under them.
- The status pill — still the right-edge anchor showing `Live · …:8080` or `Idle · …`. The pulse dot animates green when the broker is up.
- The blur background (`.ultraThinMaterial` over `Theme.Palette.surface.opacity(0.94)`) — same vibranced look, just shorter.

## Visual diff (pending screenshot)

When Screen Recording permission is restored:
- 44 pt → 36 pt: 8 pt fewer above the content area = slightly more headroom for the pane.
- Tagline left-of-center instead of dead-center: less floating whitespace on wide windows.

## Cross-refs

- [[Logo-Branding]] — sidebar already has the brand; top bar doesn't need to repeat it
- [[Sidebar-Card-Redesign]] — the status info that *does* belong at-a-glance lives in the pinned bottom card (BASE URL / API KEY)
