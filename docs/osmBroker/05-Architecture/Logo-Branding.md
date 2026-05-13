# Logo & Branding

## What landed

Replaced the Georgia 28-pt serif "osmBroker" wordmark in the sidebar with the **osm atomic mark**.

```
Sources/osmBroker/Resources/
├── osm-mark-light.png   (atom on transparent — for cream sidebar)
└── osm-mark-dark.png    (white-on-black silhouette — kept for future dark mode)
```

## Provenance — where the mark came from

After the user said "Logo is not what we have in assets for dark or light logo. change it first", I searched for brand assets:

```
$ find ~/Projects/osmdesign -iname "*osm*.png" -maxdepth 4
.../docs/screenshots/02-settings-osmapi.png        # screenshot, not a mark
.../apps/web/out/osm-api-light.png                 # build artifact, same as below
.../apps/web/out/osm-api-dark.png                  # build artifact
.../apps/web/public/osm-api-light.png              # canonical
.../apps/web/public/osm-api-dark.png               # canonical
```

The `public/` versions are the canonical artefacts (the `out/` versions are post-build copies). Both PNGs are 31–32 KB. Inspected each visually:

- **light** — brown orbital lines + yellow nucleus on transparent. Reads as a delicate atomic mark on cream/light surfaces. **This is the one for our app**, since the sidebar background is the cream `Theme.Palette.sidebarSurface` (`#EFEDE3`).
- **dark** — black blob silhouette with white orbital outline and yellow nucleus. For use against dark surfaces (later: dark-mode support).

Copied both into the executable target's resources so both ship with the app and we don't have to round-trip back to the design repo when wiring dark mode later:

```sh
cp ~/Projects/osmdesign/apps/web/public/osm-api-light.png Sources/osmBroker/Resources/osm-mark-light.png
cp ~/Projects/osmdesign/apps/web/public/osm-api-dark.png  Sources/osmBroker/Resources/osm-mark-dark.png
```

## Package wiring

`Package.swift` needs the `resources:` array on the `osmBroker` executable target to make those PNGs bundle-loadable at runtime. Added:

```swift
.executableTarget(
    name: "osmBroker",
    dependencies: ["osmBrokerCore"],
    path: "Sources/osmBroker",
    resources: [
        .process("Resources")
    ]
)
```

`.process` runs the PNGs through asset processing (high-res variants, color-space normalization). The alternative, `.copy`, ships them verbatim — fine for fonts/raw data, but `.process` is what you want for images consumed by SwiftUI's `Image(_:bundle:)`.

## SwiftUI rendering plan

Once the resources are wired, the sidebar's brand row reads:

```swift
HStack(spacing: 10) {
    Image("osm-mark-light", bundle: .module)
        .resizable()
        .interpolation(.high)
        .scaledToFit()
        .frame(width: 32, height: 32)
    VStack(alignment: .leading, spacing: 0) {
        Text("osmBroker")
            .font(Theme.Typeface.display(22))
            .tracking(-0.5)
            .foregroundStyle(Theme.Palette.fg)
        Text("Local AI router")
            .font(Theme.Typeface.body(11))
            .foregroundStyle(Theme.Palette.muted)
    }
}
```

`Bundle.module` is auto-synthesized by SPM for any target that declares `resources:`. The "osm-mark-light" name (no extension) matches the file basename.

The wordmark itself drops from 28-pt to 22-pt because the logo now carries half the brand weight. Subtitle drops from 3-line lede to a single tight line.

## Alternatives I considered

1. **Use only the mark, no wordmark.** Cleaner but a fresh user landing on the app wouldn't know its name. Kept the wordmark, just smaller.
2. **Use a vector (SVG).** SwiftUI's PDF-import + `.template` rendering would let us tint the mark with the theme palette. The mark already exists as PNG, and PDF re-render would lose the yellow accent that comes from the brand. Stick with PNG.
3. **Generate a `.icns`** for the `.app` bundle icon. Worth doing later; right now the bundle uses no icon (default macOS app icon). Defer to a polish pass; tracked in [[Phase-1.5-UX-Overhaul]].

## Dark-mode readiness

`osm-mark-dark.png` is shipped but unused. When `@Environment(\.colorScheme) == .dark` we'll switch which image name we pass to `Image(_:bundle:)`. Trivial follow-up; not in scope for this pass.

## Verification (DONE, 2026-05-13 15:33)

Sidebar zoom screenshot shows the atomic mark at 32×32 with the yellow nucleus visible, sitting cleanly left of the Georgia "osmBroker" wordmark; "Local AI router" tagline underneath in muted body sans. No jaggies (`.interpolation(.high)` doing its job).

## Iteration history — the loading bug

First attempt: `Image("osm-mark-light", bundle: .module)`. **Did not render.**

Root cause: SwiftPM's auto-generated `Bundle.module` looks for the resource bundle at `Bundle.main.bundleURL.appendingPathComponent("osmBroker_osmBroker.bundle")`. For a `swift run` execution `Bundle.main` is the binary and `.bundleURL.appendingPathComponent(...)` lands next to the binary where SPM put the sidecar. **For our hand-rolled `.app`, `Bundle.main.bundleURL` resolves to the `.app/` directory itself** — so SPM looks for `osmBroker.app/osmBroker_osmBroker.bundle/`, which doesn't exist in our standard `Contents/MacOS/` layout. The accessor fell through to the hardcoded build-path fallback (`.build/release/osmBroker_osmBroker.bundle/`), which sometimes works (if the .build directory hasn't been touched) but is brittle — and it didn't work for SwiftUI's image lookup for reasons I never fully diagnosed.

Second attempt (shipped): hand-roll a multi-location `NSImage(contentsOf:)` loader on `BrandMark`. Try in order:

1. `Bundle.main.url(forResource: "osm-mark-light", withExtension: "png")` — loose-file lookup inside `Contents/Resources/`.
2. `Bundle.module.url(forResource: …)` — for `swift run` and any future build where the sidecar IS reachable.
3. Explicit URLs for every plausible sidecar layout: `Contents/Resources/…`, `Contents/MacOS/…`, `.app/…`, and one-folder-up.

Plus a UI fallback: if `nil` from all paths, render a serif "o" on the accent-soft background so the brand row never goes blank. Belt and suspenders.

Bundle script (`Scripts/make-app-bundle.sh`) also copies the PNGs into **both**:
- `Contents/Resources/osm-mark-{light,dark}.png` (loose) — satisfies path 1
- `Contents/MacOS/osmBroker_osmBroker.bundle/` (sidecar) — satisfies path 3

This makes the load path robust to any future SPM accessor changes.
