#!/bin/bash
# Captures the README's state images: the toolbar with the connection dot and
# the awake cup lit, and the notch opened into its summary and into the full
# app. The toolbar is a crop of one window capture; the two notch captures are
# handed to MakeNotchScenes.swift, which sets each on a desktop under a menu
# bar, so the picture shows the notch where it sits rather than as a cut-out.
#
# Like Capture.sh it runs the app in demo mode with its settings supplied as
# launch arguments, so your real preferences are never read or written.
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="${1:-docs}"
SHOTS="${2:-/tmp/watchtower-states}"
APP="dist/Watchtower.app/Contents/MacOS/Watchtower"
[ -x "$APP" ] || { echo "Build first: ./build.sh"; exit 1; }
mkdir -p "$OUT" "$SHOTS"

HELP=$(mktemp -d)
trap 'rm -rf "$HELP"; pkill -f "MacOS/Watchtower" 2>/dev/null || true' EXIT

# Centre and id of the app's largest window at a given layer: 0 for the
# window, anything else for the notch panel. Largest, because a lingering
# tooltip is also above the normal layer.
cat > "$HELP/win.swift" <<'SWIFT'
import AppKit
let wantNotch = CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "notch"
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
var best: ([String: CGFloat], Int, CGFloat)? = nil
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Watchtower" {
    guard ((w[kCGWindowLayer as String] as? Int ?? 0) != 0) == wantNotch else { continue }
    let b = w[kCGWindowBounds as String] as! [String: CGFloat]
    let area = b["Width"]! * b["Height"]!
    if best == nil || area > best!.2 { best = (b, w[kCGWindowNumber as String] as? Int ?? 0, area) }
}
if let (b, id, _) = best {
    print(Int(b["X"]! + b["Width"]! / 2), Int(b["Y"]! + b["Height"]! / 2), id)
}
SWIFT

cat > "$HELP/warp.swift" <<'SWIFT'
import AppKit
let a = CommandLine.arguments
CGWarpMouseCursorPosition(CGPoint(x: Double(a[1])!, y: Double(a[2])!))
SWIFT

# Crops a capture in place to a region given in points (the captures are 2x).
cat > "$HELP/crop.swift" <<'SWIFT'
import AppKit
let a = CommandLine.arguments
let url = URL(fileURLWithPath: a[1])
let (top, left, height, width) = (Double(a[2])! * 2, Double(a[3])! * 2, Double(a[4])! * 2, Double(a[5])! * 2)
let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
let rect = CGRect(x: left, y: top, width: min(width, Double(image.width) - left), height: min(height, Double(image.height) - top))
let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image.cropping(to: rect)!, nil)
CGImageDestinationFinalize(dest)
SWIFT

# Parks the pointer in the bottom-left corner so no tooltip or hover state
# ends up in a capture.
park() { swift "$HELP/warp.swift" 2 "$(swift -e 'import AppKit; print(Int(NSScreen.screens[0].frame.height) - 2)')"; }

launch() {
  pkill -f 'MacOS/Watchtower' 2>/dev/null || true
  sleep 1
  WT_DEMO=1 "$APP" -theme midnight -columnCount 3 "$@" >/dev/null 2>&1 &
  sleep 6
}

echo "==> window: toolbar with the connection dot and the awake cup"
launch -showOverlay NO -checkInternet YES -keepAwake YES
osascript >/dev/null <<'OSA'
tell application "System Events" to tell process "Watchtower"
  set w to first window whose subrole is "AXStandardWindow"
  set position of w to {40, 70}
  set size of w to {1160, 760}
end tell
OSA
sleep 1.5
park
read -r _ _ WID < <(swift "$HELP/win.swift" window)
screencapture -x -o -l "$WID" "$OUT/toolbar-status.png"
# The title bar plus the top of the first row, from the traffic lights to
# just past the settings cog.
swift "$HELP/crop.swift" "$OUT/toolbar-status.png" 0 0 118 560

for style in summary app; do
  echo "==> notch: $style"
  launch -showOverlay YES -overlayEdge top -overlayOffset 0.5 -overlayRounding 22 \
         -overlayExpands YES -overlayExpandTrigger hover -overlayHoverDelay 0 \
         -overlayExpandStyle "$style" -checkInternet YES -keepAwake YES
  read -r CX CY _ < <(swift "$HELP/win.swift" notch)
  # Resting the pointer on the notch opens it; it then stays, just off any row.
  swift "$HELP/warp.swift" "$CX" "$CY"
  sleep 2.5
  swift "$HELP/warp.swift" "$CX" "$(( CY + 2 ))"
  read -r _ _ WID < <(swift "$HELP/win.swift" notch)
  screencapture -x -o -l "$WID" "$SHOTS/notch-$style.png"
done

echo "==> scenes"
swiftc -O Resources/MakeNotchScenes.swift -o "$HELP/makenotch"
"$HELP/makenotch" "$SHOTS"

echo "==> Wrote to $OUT:"; ls -la "$OUT"/toolbar-status.png "$OUT"/notch-*.png
