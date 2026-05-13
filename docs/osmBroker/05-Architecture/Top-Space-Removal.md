# Top space removal (v0.2.2)

## The remaining gap

After [[Top-Bar-Tightening]] reduced the toolbar from 44 → 36 pt, the user pointed out there's *still* an obvious empty strip between the traffic-light row and where the first piece of content (the eyebrow + display title) starts. Measured from a v0.2.1 screenshot:

- Window top → traffic-light row: ~22 pt (macOS chrome, transparent)
- TopBar (`"Local AI routing server" + status pill`): 36 pt
- Divider: 1 pt
- Pane top padding: 28 pt
- *= 87 pt before any real content*

That's a lot of vertical pixels for a single line of muted-tone tagline + a status pill.

## What I'm doing

Drop the TopBar entirely. The "Local AI routing server" tagline was redundant the moment the sidebar gained the brand mark + wordmark + `Local AI router` line. The status pill (Idle / Live + URL) was *also* duplicated by the sidebar `Serve` nav badge (IDLE / LIVE) and the `BROKER STATUS` line we're about to add to the endpoint card.

New layout:

```
window {
  HStack(spacing: 0) {
    Sidebar()       // top-padded so brand row clears the traffic lights
    Divider()
    MainPane()      // 28 pt internal top padding stays; lights don't overlap it horizontally
  }
}
```

No more VStack-of-TopBar-then-content wrapper.

## What replaces the lost status pill

In the sidebar endpoint card, prepend a `STATUS` row:

```
STATUS
● Live · 192.168.68.104:8080            [or]    ○ Idle
─────
BASE URL
192.168.68.104:8080            [copy]
localhost:8080                 [copy]
─────
API KEY
osm-local-dev                  [copy]
```

The pulse dot animates green when the broker is live (same `PulseDot` view used previously). Now you read your broker state in the same card you read the URL, instead of glancing up to a separate strip.

## Traffic-light clearance now lives in the sidebar

With no TopBar, the lights overlay the *top-left of the window*, which is the sidebar's top-left. The sidebar's `BrandRow` would draw under them. So the sidebar's outer `.padding(.vertical, 18)` becomes `.padding(.top, 32).padding(.bottom, 18)`. Brand row now sits cleanly below the lights at ~32 pt.

The main pane doesn't need extra top padding — the lights are to the left of where the main pane starts, so its existing `.padding(28)` is enough breathing room.

## Vertical-space savings

Before: 87 pt of chrome/empty before first content.
After: 32 pt sidebar top inset (to clear lights), no separate bar, content starts at the same `~28 pt` it always did in the main pane.

The main pane's content effectively rises by 37 pt. Visually significant on a 720 pt window — the page feels almost like content sits *immediately* under the traffic lights.

## Cross-refs

- [[Top-Bar-Tightening]] — the prior iteration that got us to 36 pt; this note supersedes it
- [[Sidebar-Card-Redesign]] — the endpoint card design; now gains the STATUS row at the top
- [[Tab-Structure-v2]] — sidebar nav badges (IDLE / LIVE) remain the secondary status indicator
