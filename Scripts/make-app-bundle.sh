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

# Copy SwiftPM-generated resource bundle into Contents/Resources/.
#
# Why NOT Contents/MacOS/ (the previous home): codesign --deep walks every
# subdir of Contents/MacOS/ and tries to sign each as a separate component.
# SwiftPM's <module>_<module>.bundle has no Info.plist, no Contents/MacOS, no
# Mach-O — just raw resource files. codesign --deep fails with "bundle format
# unrecognized" and leaves the parent .app's signature seal in an inconsistent
# half-resealed state, which the kernel then rejects at launch with a
# CODESIGNING / Invalid Page exception (SIGKILL during dyld init, before any
# of our code runs).
#
# Moving the SwiftPM bundle to Contents/Resources/ — where its raw-resource
# shape is expected — fixes this. SwiftPM's `Bundle.module` lookup also still
# resolves there because Swift's runtime searches Resources/<module>.bundle.
RES_BUNDLE_SRC=".build/release/osmBroker_osmBroker.bundle"
if [ -d "$RES_BUNDLE_SRC" ]; then
  cp -R "$RES_BUNDLE_SRC" "$APP/Contents/Resources/"
  # Also extract the PNGs as loose files in Contents/Resources/ so
  # Bundle.main.url(forResource:) hits them too — belt + suspenders.
  for f in "$RES_BUNDLE_SRC"/*.png; do
    [ -f "$f" ] && cp "$f" "$APP/Contents/Resources/"
  done
else
  echo "warning: $RES_BUNDLE_SRC missing — logo + resources won't load" >&2
fi

# Ad-hoc codesign WITHOUT --deep. Two-pass:
#   1. Sign the main exec on its own.
#   2. Sign the parent bundle, which seals the now-stable Contents/Resources/
#      tree by hashing each file into _CodeSignature/CodeResources.
# We intentionally skip --deep because it would recurse into the SwiftPM
# resource bundle and choke on its non-conformant format.
codesign --force --sign - "$APP/Contents/MacOS/osmBroker"
codesign --force --sign - "$APP"

# Hard-fail if the result isn't actually valid — the previous version of this
# script silently produced bundles that crashed on launch.
if ! codesign --verify --strict "$APP" 2>/dev/null; then
  echo "ERROR: $APP failed codesign verification" >&2
  codesign --verify --strict "$APP" 2>&1 | sed 's/^/  /' >&2
  exit 1
fi

echo "OK: $APP (codesign verified)"
