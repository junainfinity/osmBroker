# Bundle resources gotcha (post-build discovery)

## What broke

After rebuild + bundle + launch of the Phase-1.5 redesign, a sanity check on the produced `.app` revealed:

```
$ find osmBroker.app -type f
osmBroker.app/Contents/Info.plist
osmBroker.app/Contents/MacOS/osmBroker
osmBroker.app/Contents/PkgInfo
osmBroker.app/Contents/_CodeSignature/CodeResources
```

No PNGs. The osm logo we just spent time wiring in would render as the missing-asset placeholder at runtime.

## Why

SwiftPM compiles resources into a sidecar bundle next to the executable, named `<package>_<target>.bundle`. For us:

```
.build/release/osmBroker_osmBroker.bundle/
├── osm-mark-light.png
└── osm-mark-dark.png
```

`Bundle.module` — which `Image("osm-mark-light", bundle: .module)` keys off — looks for that sidecar in the same directory as the running executable, **not** in `Contents/Resources/` of an app bundle.

The original `Scripts/make-app-bundle.sh` only copied the binary. The sidecar bundle never made it across, so at runtime `Bundle.module` resolved to an effectively empty bundle.

## Fix

`make-app-bundle.sh` updated to also copy the SPM-generated bundle directory into `Contents/MacOS/`:

```sh
RES_BUNDLE_SRC=".build/release/osmBroker_osmBroker.bundle"
if [ -d "$RES_BUNDLE_SRC" ]; then
  cp -R "$RES_BUNDLE_SRC" "$APP/Contents/MacOS/"
else
  echo "warning: $RES_BUNDLE_SRC missing — logo + resources won't load" >&2
fi
```

After the fix, the `.app` tree is:

```
osmBroker.app/
├── Contents/
│   ├── Info.plist
│   ├── PkgInfo
│   └── MacOS/
│       ├── osmBroker                                          (binary)
│       └── osmBroker_osmBroker.bundle/                        (resource bundle)
│           ├── osm-mark-light.png
│           └── osm-mark-dark.png
```

`Bundle.module` now resolves the PNGs successfully.

## codesign warning (cosmetic)

After the fix, ad-hoc `codesign --force --deep --sign -` printed:

```
osmBroker.app: bundle format unrecognized, invalid, or unsuitable
In subcomponent: …/MacOS/osmBroker_osmBroker.bundle
```

Reason: SPM's sidecar bundle is a "loose" resource directory without its own `Info.plist`. `codesign --deep` treats it as a bundle and chokes. For development this is **non-fatal** — the app still launches and the resources still load. Production builds (Phase 3 packaging task) should write a minimal `Info.plist` into the sidecar before signing:

```sh
cat > "$APP/Contents/MacOS/osmBroker_osmBroker.bundle/Info.plist" <<INFO
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>app.osmbroker.osmBroker.resources</string>
  <key>CFBundlePackageType</key><string>BNDL</string>
</dict></plist>
INFO
```

Deferred — not blocking the redesign verification.

## Lesson

For any future `.process("Resources")` additions, the bundle script needs to:
1. Copy the SPM sidecar into `Contents/MacOS/`.
2. Drop a minimal Info.plist into the sidecar before deep-signing.

Adding this to [[Phase-3-Polish-and-Marketplace]] as a pre-release-packaging checklist item.
