#!/bin/bash
# Builds Watchtower.app into ./dist
set -euo pipefail
cd "$(dirname "$0")"

APP="dist/Watchtower.app"
echo "==> Compiling (release)"
swift build -c release

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/release/Watchtower" "$APP/Contents/MacOS/Watchtower"

# Icon: regenerate the PNG only if the generator is newer than the output.
if [ ! -f Resources/AppIcon.png ] || [ Resources/MakeIcon.swift -nt Resources/AppIcon.png ]; then
  swiftc -O Resources/MakeIcon.swift -o /tmp/wt-makeicon
  /tmp/wt-makeicon Resources/AppIcon.png
fi

ICONSET=$(mktemp -d)/AppIcon.iconset
mkdir -p "$ICONSET"
for s in 16 32 64 128 256 512; do
  sips -z $s $s Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Watchtower</string>
  <key>CFBundleDisplayName</key><string>Watchtower</string>
  <key>CFBundleIdentifier</key><string>com.daze.watchtower</string>
  <key>CFBundleExecutable</key><string>Watchtower</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.5.0</string>
  <key>CFBundleVersion</key><string>6</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# Sign with a stable identity when one exists. This matters: an ad-hoc
# signature pins the Accessibility grant to the exact binary hash, so the
# permission is lost on every rebuild. A real identity keeps it across builds.
IDENTITY=$(security find-identity -v -p codesigning 2>/dev/null \
  | awk '/Developer ID Application|Apple Development/ { print $2; exit }')

if [ -n "$IDENTITY" ]; then
  echo "==> Signing with stable identity ${IDENTITY:0:12}…"
  codesign --force --options runtime --sign "$IDENTITY" "$APP"
else
  echo "==> No signing identity found; falling back to ad-hoc"
  echo "    (Accessibility permission will need re-granting after each rebuild)"
  codesign --force --sign - "$APP" 2>/dev/null || true
fi

echo "==> Done: $APP"
