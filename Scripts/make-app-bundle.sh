#!/bin/sh
set -e
APP=osmBroker.app
BIN_SRC=.build/release/osmBroker
if [ ! -f "$BIN_SRC" ]; then
  echo "release binary missing; run: swift build -c release" >&2
  exit 1
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Info.plist
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>osmBroker</string>
  <key>CFBundleDisplayName</key><string>osmBroker</string>
  <key>CFBundleIdentifier</key><string>app.osmbroker.osmBroker</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleExecutable</key><string>osmBroker</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

# PkgInfo
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Copy binary
cp "$BIN_SRC" "$APP/Contents/MacOS/osmBroker"
chmod +x "$APP/Contents/MacOS/osmBroker"

# Copy SwiftPM-generated resource bundle into the .app at TWO locations so the
# BrandRow image loader (Sidebar.swift) finds it regardless of which lookup it
# tries:
#   1) Contents/MacOS/osmBroker_osmBroker.bundle/  — the sidecar SPM expects
#   2) Contents/Resources/<file>.png               — loose, so Bundle.main.url(forResource:) hits
RES_BUNDLE_SRC=".build/release/osmBroker_osmBroker.bundle"
if [ -d "$RES_BUNDLE_SRC" ]; then
  cp -R "$RES_BUNDLE_SRC" "$APP/Contents/MacOS/"
  # Also extract the PNGs as loose files in Contents/Resources/. macOS' standard
  # bundle lookup (`Bundle.main.url(forResource:)`) walks this directory.
  for f in "$RES_BUNDLE_SRC"/*.png; do
    [ -f "$f" ] && cp "$f" "$APP/Contents/Resources/"
  done
else
  echo "warning: $RES_BUNDLE_SRC missing — logo + resources won't load" >&2
fi

# Ad-hoc codesign (after every file is in place, so the signature covers the bundle too)
codesign --force --deep --sign - "$APP" 2>&1 | head -5

echo "OK: $APP"
