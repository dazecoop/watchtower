#!/bin/bash
# Captures the window art used by MakeShowcase.swift and MakeSocial.swift.
#
# Runs the app in demo mode with its settings supplied as launch arguments, so
# the capture never reads or writes your real preferences: macOS gives the
# argument domain priority over everything stored on disk.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-/tmp/watchtower-shots}"
APP="dist/Watchtower.app/Contents/MacOS/Watchtower"
THEMES=(nocturne slate midnight light)

[ -x "$APP" ] || { echo "Build first: ./build.sh"; exit 1; }
mkdir -p "$OUT"

HELP=$(mktemp -d)
trap 'rm -rf "$HELP"' EXIT

# Where to park the window: a Retina screen if there is one, so the art is
# captured at 2x. Printed in the top-left space the accessibility API uses.
cat > "$HELP/spot.swift" <<'SWIFT'
import AppKit
let best = NSScreen.screens.max { $0.backingScaleFactor < $1.backingScaleFactor }!
let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? best
let top = primary.frame.maxY - best.frame.maxY
print(Int(best.frame.minX + 40), Int(top + 70))
SWIFT

# The notch is the one above the normal window layer. It is captured at twice
# its normal size, since it lives on whichever screen is "main" rather than the
# Retina one the window is parked on, and would otherwise come out at 1x.
cat > "$HELP/winid.swift" <<'SWIFT'
import AppKit
let wantNotch = CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "notch"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Watchtower" {
    if ((w[kCGWindowLayer as String] as? Int ?? 0) != 0) == wantNotch {
        print(w[kCGWindowNumber as String] as? Int ?? 0)
        break
    }
}
SWIFT

read -r SX SY < <(swift "$HELP/spot.swift")

for theme in "${THEMES[@]}"; do
  echo "==> $theme"
  pkill -f 'MacOS/Watchtower' 2>/dev/null || true
  sleep 1

  WT_DEMO=1 "$APP" \
    -theme "$theme" -columnCount 3 \
    -showOverlay YES -overlayEdge left -overlayOffset 0.4 \
    -overlayRounding 22 -overlayScale 2 -overlaySweep YES \
    >/dev/null 2>&1 &
  sleep 7

  osascript >/dev/null <<OSA
tell application "System Events" to tell process "Watchtower"
  set w to first window whose subrole is "AXStandardWindow"
  set position of w to {$SX, $SY}
  set size of w to {1160, 760}
end tell
OSA
  sleep 2

  screencapture -x -o -l "$(swift "$HELP/winid.swift" window)" "$OUT/$theme.png"
  # Overwritten each pass rather than written once: skipping it left a stale
  # capture behind whenever the overlay's settings changed between runs.
  screencapture -x -o -l "$(swift "$HELP/winid.swift" notch)" "$OUT/notch.png"
done

pkill -f 'MacOS/Watchtower' 2>/dev/null || true
echo "==> Wrote to $OUT:"; ls -la "$OUT"
