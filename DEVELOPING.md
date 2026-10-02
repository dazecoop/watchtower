# Developing Watchtower

Implementation notes. For installation and usage, see [README.md](README.md).

## Building

```bash
./build.sh            # compiles release, assembles dist/Watchtower.app, signs it
open dist/Watchtower.app
```

Requires a Swift 6 toolchain (ships with Xcode). No third-party dependencies —
everything is SwiftUI and AppKit.

### Layout

| File | Role |
| --- | --- |
| `Fleet.swift` | `FleetEngine` (all filesystem work, on one background queue) and `FleetStore` (the `@MainActor` view model and preferences). |
| `TranscriptTail.swift` | Incremental follower for a session's `.jsonl`. |
| `Usage.swift` / `UsageBar.swift` | Plan-limit parsing and the bottom strip. |
| `Reachability.swift` | The optional connection check. |
| `SleepGuard.swift` | The optional power assertion. |
| `WindowFocuser.swift` | Accessibility-based editor window focusing. |
| `AttentionNotifier.swift` | Working → waiting transition alerts. |
| `Theme.swift` | Themes and the environment keys. |
| `Views.swift` | Grid, tiles, feed lines, thinking indicator, shimmer, the age fade. |
| `Animations.swift` | The looping animations, as Core Animation layers (see Performance). |
| `Overlay.swift` | The notch: edge placement maths, the `NSPanel` that hosts it, dragging, click-to-reveal, and the expand/collapse lifecycle. |
| `OverlayView.swift` | Its contents — the notch outline, the concentric usage gauge, the spinner, and the morphing geometry of the swell. |
| `OverlayExpansion.swift` | What the notch opens into: the summary panel, the whole dashboard, and the sizing the controller measures against. |
| `ClaudeMark.swift` | The Claude logomark as path commands (see below). |

### Generated images

Everything in `docs/` is produced from code, not checked in as hand-made art.

`Resources/Capture.sh` takes the source captures: it runs the app in demo mode
once per theme, parks the window on a Retina screen for 2x detail, and grabs
the window and the notch by window id. Settings are passed as launch arguments
rather than written to disk — macOS gives the argument domain priority over
stored preferences, so a capture run never disturbs your own setup.

```bash
./build.sh                                   # Capture.sh shoots dist/Watchtower.app
./Resources/Capture.sh /tmp/watchtower-shots

swiftc -O Resources/MakeShowcase.swift -o /tmp/makeshowcase && /tmp/makeshowcase /tmp/watchtower-shots
swiftc -O Resources/MakeSocial.swift   -o /tmp/makesocial   && /tmp/makesocial   /tmp/watchtower-shots
swiftc -O Resources/MakeBadge.swift    -o /tmp/makebadge    && /tmp/makebadge docs/download-macos.png
```

`MakeShowcase.swift` builds `docs/screenshot.png`, the README hero: one scene
with the themed dashboards stacked on a desktop and the notch on its edge,
rather than a single window, so the whole app is legible in one image.

`MakeSocial.swift` builds `docs/social-preview.png`, the 1280x640 card GitHub
serves as `og:image`. It takes its artwork from the same captures rather than
from `docs/screenshot.png`, which is light-backed and would sit badly on the
card's dark gradient. Committing it is not enough — GitHub only picks it up
once it is uploaded under **Settings → General → Social preview**, which has no
API or CLI equivalent. Re-upload after regenerating.

`build.sh` regenerates `Resources/AppIcon.png` from `Resources/MakeIcon.swift`
whenever the generator is newer.

### Demo mode

`WT_DEMO=1` swaps the real data source for fabricated sessions in
`DemoData.swift` — invented project names, folders and conversation text,
covering all three states. That is what `Capture.sh` runs, so the README art
never exposes real project names or chat content:

```bash
WT_DEMO=1 dist/Watchtower.app/Contents/MacOS/Watchtower
```

The flag is read once at launch and is unreachable otherwise.

### The notch

A borderless, non-activating `NSPanel` at `.statusBar` level, with
`canJoinAllSpaces` and `fullScreenAuxiliary` so it follows you between Spaces
and stays visible over full-screen apps. It never becomes key or main — taking
focus from whatever you are typing in to show a percentage would be rude.

`OverlayPlacement` anchors it to the *physical* screen edge rather than
`visibleFrame`, so showing or hiding the Dock does not shunt it sideways. The
one exception is the top, which sits under the menu bar instead of over it.
Position along the edge is a single 0…1 number, set by the slider in Settings
or by dragging the notch itself.

Dragging reads `NSEvent.mouseLocation` rather than the gesture's own
translation: the panel moves as you drag, so a view-relative translation would
feed back on itself. One `DragGesture` covers both jobs — a press that never
travels opens the app, anything further moves it.

`NotchShape` is built once with the edge along the top and then rotated into
place, so the four edges cannot drift apart. The profile is the MacBook notch:
flush along the screen edge, swelling out of it through a concave fillet at
each end, rounded on the two corners facing into the screen. One `turn` helper
draws every curve — convex corners and concave fillets differ only in which
side of the curve the pivot sits on.

When an end reaches a screen corner it is touching a *second* screen edge, so
it stops sweeping back into the docked edge and sweeps out of the perpendicular
one instead. That sweep needs depth rather than length, so the content reserves
a strip on its inward side and hands the shape the same figure as `cornerSweep`
— if the two disagreed, the shape would clamp while the padding kept growing
and leave dead space. With the sweep switched off the construction degenerates
to a square end on its own, with no special case.

Size is a plain multiplier rather than a set of presets, and every measurement
in `OverlayMetrics` derives from it — nothing is drawn at a fixed size and then
scaled, which would resample the text and leave it soft. An existing
small/medium/large choice is carried over to the slider on first run rather
than being reset.

The multiplier stops at the bezel. Nothing in `OverlayExpansion` scales with
it: the slider sets how big the notch sits on the edge, and once it is open it
is a panel you are reading, where a small notch has no business shipping
eight-point type.

`OverlayController` decides when an end counts as cornered, with two thresholds
rather than one: squaring an end shortens the panel, which nudges the very
measurement the decision was made from, and a single threshold would let it
flip back and forth every frame.

### Expanding the notch

The notch and the open panel are the same black shape at two sizes. Resizing
the window through the animation stutters and clips whatever is mid-flight, so
the panel takes the open frame *first*, with the content still drawn at the
collapsed size and sitting exactly where the notch already was — nothing jumps
— and the shape then springs between the two inside a window already big enough
to hold it. On the way closed the panel outlasts the spring by `settle`, so the
shape has somewhere to shrink *into* rather than being clipped by a window that
has already given the space back. `expanded` is the target state; `inflated` is
whether the panel is still holding the open size.

`OverlayView` expresses the whole thing along the edge and into the screen, and
maps onto x and y at the very end, so one set of rules covers all four edges.
The panel grows out of whichever edge the notch is docked to, symmetrically
about the point it is parked at, and `OverlayPlacement.frame(anchoredAt:)`
slides it back onto the screen when an end would overhang — so a notch in a
corner opens *along* the screen rather than off it. `anchorAlong` is what keeps
the collapsed shape in the right place inside an off-centre panel.

Three things the layout has to respect, all of which showed up as clipping:

- The size must be imposed on the stack *before* the background, or the shape
  fits itself to the fixed-size gauge and the swell leaves a notch-sized bezel
  floating in an open panel.
- The content is pinned to the size it will settle at and clipped by the shape
  on the way there. Left to fit the shape as it springs, it re-wraps every
  frame and the panel arrives through a blur of truncating text.
- The fillets at each end, and the strip a corner sweep reserves, belong to the
  shape rather than the content — the open panel sets aside exactly what the
  collapsed one does.

Hover is driven by polling `NSEvent.mouseLocation`, not by `onHover`. The panel
never becomes key, and swapping the collapsed body for the open one re-enters
the hover state without the mouse having moved, which shut the panel the
instant it opened. The same timer closes it once the pointer has been away for
a moment. It ticks at 20Hz because the open delay can be set to zero, and a
coarse timer would make "instant" feel like a quarter second.

In full-app mode the notch replaces the window, so the header carries a cog
rather than a way back. Opening Settings from there is more delicate than it
looks. Sending `showSettingsWindow:` down the responder chain goes nowhere,
because nothing here is key; driving the menu item by hand fares no better.
`SettingsLink` works, but brings two problems of its own. It opens the window
wherever it was last left — another Space, behind what you are looking at, or
on a display since unplugged — so `raiseSettings` watches for it, moves it to
the active Space, and orders it front at a floating level before dropping back
to normal, since asking to be activated is refused when the click arrived at a
panel that will not activate the app. And the gesture that collapses the notch
runs *alongside* the link rather than after it, so it waits one turn of the run
loop — collapsing synchronously tears the link out of the view tree before its
own action has run, and Settings never opens at all.

### The Claude logomark

`ClaudeMark.swift` is generated from the official SVG, converted to absolute
move / line / cubic commands normalised into a 0…1 square — elliptical arcs
flattened to cubics on the way. That keeps the app drawing everything in code
with no image resources, matching how the app icon is produced.

### Five traps worth knowing

All five cost real debugging time and are commented in place:

1. **Scene generics.** Inlining the `commands` builder and a ViewBuilder
   `MenuBarExtra` label into `App.body` nested the opaque types deeply enough
   that the Swift runtime blew its stack resolving type metadata — a segfault
   on launch, not a compile error. `WatchtowerCommands` and `MenuBarContent`
   are separate types to keep that nesting shallow.

2. **`MenuBarExtra(isInserted:)` writes back to its binding** while updating.
   Backed by an `@Published` store property that becomes an endless
   publish/render loop which pins the main thread. It is `@AppStorage`.

3. **A `NSViewRepresentable` that configures its window** must do it from
   `viewDidMoveToWindow`, not from an async hop in `updateNSView`.
   `WindowSurface` did the latter: setting `styleMask` and `backgroundColor`
   invalidates the window, which brings on another render, which schedules
   another hop. The window kept laying out with nothing changed.

4. **`NSHostingView.sizingOptions = [.intrinsicContentSize]`** is what measures
   the notch's content so the panel can be sized to fit it — but it also leaves
   the hosting view laying out against its own constraints rather than the
   panel it now fills. The window renders completely empty. Its frame is
   pinned explicitly after every `setFrame`.

5. **Re-framing a panel on every publish makes it crawl.** The store publishes
   once a second; comparing against `panel.frame` does not settle, because
   AppKit may hand back an adjusted frame and that difference never resolves.
   The controller compares against the frame it last *asked* for, and only
   re-measures the content when a signature of the size-affecting values
   changes — never for the cycling gerund or its timer.

## How it detects sessions

It never scrapes windows or screenshots anything. Claude Code already writes
everything needed to disk:

| Source | What it gives |
| --- | --- |
| `~/.claude/sessions/<pid>.json` | the live registry: session id, name, cwd, `status` (busy/idle), entrypoint. A session counts as live only if its pid is still running. |
| `~/.claude/projects/<slug>/<session-id>.jsonl` | the transcript: `ai-title`, `last-prompt`, assistant prose, thinking, tool calls, tool results, token usage, git branch. |

Transcripts are followed incrementally — only bytes appended since the last
poll are read (1s interval). On first open it walks backwards from EOF until it
has ~160 complete lines, so opening a 50 MB transcript is still instant.

## Jumping to a session's editor window

Each tile has a **reveal** button that focuses the VS Code window running that
session, switching Spaces if the window is on another desktop. It never opens
a new window or file.

This needs **Accessibility** permission (System Settings → Privacy & Security →
Accessibility). The banner in the app will prompt you.

Why the Window menu rather than raising the window directly: the Accessibility
API only reports windows on the *currently active* Space, so an `AXRaise` can't
reach a window on another desktop. An app's Window menu lists every window
regardless of Space, and pressing one of those items makes macOS switch Spaces
and focus it.

Bindings are stored against the window *title*, which is all the Window menu
exposes. A VS Code window with no folder open titles itself after the active
editor ("Untitled-1", "Bash tool output…"), so its title changes as you switch
tabs and a saved link to it will stop resolving — the button simply falls back
to the picker. Windows opened on a folder or workspace have stable titles.

Window matching is by folder name against the window title. Titles don't always
contain the folder name (a multi-root workspace might be `Untitled (Workspace)`),
so when the match is ambiguous the button becomes a picker — choose the window
once and it is remembered per project folder. Right-click a resolved button to
re-link or forget it.

## Reading a tile

- **Green dot / Working** — Claude is mid-turn.
- **Amber / Your turn** — the turn finished; it's waiting on you.
- **Grey / Idle** — alive but nothing for 30+ minutes.

While a session is working the thinking indicator sits at the top, since that
is the most current thing happening. Below it, the highlighted box is the newest
recorded event, followed by the preceding few.

Tiles are display-only — there is no detail view and clicking one does nothing.

Footer shows model, context tokens in flight, and tool calls this session.

## Usage bar

A slim strip along the bottom of the window shows your plan limits: session
(5hr), weekly, and any model-scoped weekly limit such as Fable. Each shows a
meter, the percentage, and how long until it resets. Hover for the exact reset
time.

The figures come from `~/.claude.json` → `cachedUsageUtilization`, which Claude
Code writes after polling your account limits. The `limits` array it stores is
the same list Claude's own usage panel renders, so new limit kinds appear here
without a code change. Nothing is fetched from the network — Watchtower only
reads what Claude Code has already cached.

That cache is the whole supply, and it only moves when Claude Code moves it:
while a session runs, and when you run `/usage`. With nothing open it freezes,
which is why the reader is built to notice two things that change without the
file changing at all. The JSON is still re-parsed only on an mtime change, but
the *snapshot* is rebuilt from the cached rows on every poll, so both of these
flip on their own:

- **Staleness.** `fetchedAt` older than `UsageSnapshot.staleAfter` (30 minutes)
  sets `stale`, which fades the strip, the notch's arcs and its headline.
- **Expiry.** A limit whose `resets_at` has passed carries a percentage for a
  window that has already rolled over. What has been used in the *new* window
  is unknown until Claude Code reports it, so `expired` is set: the figure
  renders as a dash, the arc is not drawn, and the limit is skipped when
  picking the notch's headline number. Inventing a 0 would be a different lie.

Because expiry is stamped into `UsageLimit` rather than computed in the views,
the snapshot genuinely differs the moment a window rolls over, so `FleetStore`
republishes and everything redraws — which a purely computed property would not
have done, since nothing else need change while the fleet sits idle.

Each limit has a fixed colour from `Color.forLimit(_:)`, shared with the notch
rings so a limit reads the same in both places. Severity rides on the
percentage text instead — amber past 75%, red past 90%, or earlier if the API
marks a limit as warning/critical — which leaves the meter colours stable. An
expired limit reports no severity at all: the old window's is no longer about
anything.

## What a tile spotlights

The highlighted block shows Claude's most recent **prose**, not whatever record
is newest. That distinction matters: the newest record is very often a raw tool
result, so a tile would show something like the first line of a `gh pr checks`
dump while the editor's chat panel showed Claude's actual sentence. They were
both current, just different things — the tile now matches what you read in the
editor.

While the turn is still running the block carries a slow shimmer and its label
reads "so far" rather than "says", because a static "says" block looks like a
finished statement when it is really just the latest line.

## Thinking indicator

While a session is working, its tile shows a pulsing marker, one of Claude
Code's gerunds ("Pondering…", "Synthesizing…") and a timer counting from its
last recorded step. Without it a busy tile that has only your prompt on it
looks stalled.

The word is picked from the elapsed time and a per-session seed, so tiles don't
cycle in lockstep. It is cosmetic — it reflects that the session is mid-turn,
not what Claude is literally thinking.

## Grid stability

Tiles keep their position while work is happening — otherwise active sessions
swap places constantly and the grid is unreadable. The order is only rewritten
when no session has had activity for 30 seconds, or when you change the sort
mode or the active-only filter yourself. New sessions are appended rather than
inserted.

## Cleaning up idle sessions

`FleetStore.dismissed` maps a session id to the `lastActivity` it carried when
it was cleaned up. `listed` is the fleet less those, and every surface draws
from it: the grid through `recomputeOrder`, the notch's summary through
`OverlayExpansion.rows`.

The dismissal is deliberately conditional rather than a plain hidden-set. It
holds only while the session is still dormant *and* its activity has not moved
past the timestamp recorded — so anything new in a session's transcript brings
it straight back, with no explicit un-hiding anywhere. `pruneDismissed` then
drops the entry, which matters: without it, a session that woke up and later
went quiet again would be silently re-hidden by a dismissal it had already
escaped.

Nothing about this reaches the sessions themselves; it is as read-only as the
rest of the app. It is also not persisted. A tidy-up is about the fleet in
front of you, not a standing rule, and a hidden-sessions list surviving a
relaunch is a bug report waiting to happen.

Not to be confused with the active-only filter (`⚡`), which hides every idle
session for as long as it is on. Clean up clears the current ones and leaves
the next one alone, so the two are offered separately and the toolbar drops the
clean-up button entirely while the filter is on.

## Connection check

Off by default, and the only code in Watchtower that opens a socket — which is
why it is a setting rather than a feature, and why the README says so plainly.

`NWPathMonitor` gives the link state, and that alone decides red: no satisfied
path means no network, and there is nothing to probe. With a path up, the probe
is an `NWConnection` to port 53 on a public resolver. Reaching `.ready` is the
whole test — nothing is written and nothing is read, so there is no DNS query
to answer and no payload to leak. `.waiting` counts as a failure: it means the
system has nowhere to send this right now, which is what a dead network looks
like, and taking it at face value is what makes a captive portal show up as
amber in four seconds rather than hanging.

Four resolvers rotate (Cloudflare, Google, Quad9, OpenDNS). That is one
connection per operator per minute, which is nothing to any of them, and it
stops one resolver having a bad day from reading as an outage. A failed probe
is retried against the *next* operator before the dot changes, for the same
reason — two different networks failing back to back is a real signal, one is
noise.

The amber state is the point of the whole thing. Offline is something macOS
already tells you about; connected-but-useless is the one it is quietest about,
and the one that wastes the most time.

## Keeping the Mac awake

`IOPMAssertionCreateWithName` with `kIOPMAssertionTypePreventUserIdleSystemSleep`
— the same assertion `caffeinate -i` takes. Not a `caffeinate` subprocess: no
child to supervise, and the kernel drops the assertion if Watchtower dies, so a
crash cannot strand a Mac that will never sleep again. Deliberately not
`PreventUserIdleDisplaySleep`: the display sleeping does not stop a session, and
an app that keeps the screen lit because something is running in the background
is an app people turn off.

One line decides it, in one place:

```swift
sleepGuard.apply(keepAwake && !paused && workingCount > 0)
```

`apply` is idempotent, so `refresh` can hand it the current answer every second
without tracking edges, and the three things that can change the answer — the
setting, the pause, and the fleet — all route through it. The `paused` term is
not decoration: pausing stops `refresh`, so without it the assertion would be
held on the strength of a fleet the app had stopped looking at, and an idle Mac
would stay awake until something happened to resume it.

## Running without a Dock icon

**Hide Dock icon** switches the activation policy to `.accessory`. That also
takes away the app menu, so something else has to be able to summon the window:
the setting is only honoured while the notch or the menu bar item is on, and
`applyActivationPolicy()` re-checks whenever either changes. Enforcing it there
rather than only greying out the toggle matters — turning both off afterwards
would otherwise strand the app with no way back to it.

Clicking the notch brings the window forward, and reopens it if it was closed.
Rebuilding a closed `WindowGroup` window is something only SwiftUI can do:
`applicationShouldHandleReopen` is what a Dock click runs, but calling it does
not bring the scene back, so `RootView` parks its `openWindow` action in
`AppWindow.reopen` for the controller to use. The controller only calls it when
no *visible* window is found — a closed window can linger in `NSApp.windows` as
an off-screen husk, and treating that as the main window was why clicking the
notch quietly did nothing.

## Title bar

The window has no separate title bar surface: `toolbarBackground(.hidden)`
drops the toolbar's material and separator, and `WindowSurface` makes the title
bar transparent and hands the window either the theme's own colour or a clear
background so the content's vibrancy reaches up through `fullSizeContentView`.
The result is one unbroken surface from the traffic lights down.

## Themes

Six themes, in Settings or the moon menu in the toolbar: System, Light, Dark,
Slate, Midnight and Nocturne.

System, Light and Dark use macOS vibrancy, so your wallpaper shows faintly
through. Slate, Midnight and Nocturne paint their own opaque background
instead, which is the point of them — nothing bleeds through.

## Settings (⌘,)

- **Theme** and **Columns** (dynamic, or a fixed 1–4).
- **Render markdown** — shows `**bold**` and backticks as formatting rather
  than raw syntax. On by default.
- **Show thinking indicator**.
- **Notify when a session needs you** — posts a macOS notification the moment a
  session stops working and starts waiting on your reply. This is the one worth
  leaving on when several sessions are running.
- **Show menu bar status** — off by default. Adds a working/waiting count to
  the menu bar with a jump-to-session menu.

The toolbar also has a filter field for narrowing by name, project or title.

## Shortcuts

`⌘R` refresh · `⌘P` pause/resume · `⌘L` active-only · `⇧⌘K` clean up idle

## Signing

`build.sh` signs with a real code-signing identity from your keychain when it
finds one, falling back to ad-hoc otherwise. This matters for permissions: an
ad-hoc signature pins the Accessibility grant to the exact binary hash, so the
permission is silently lost on every rebuild. A stable identity keeps it.

If you previously approved an ad-hoc build, remove the old `Watchtower` row in
System Settings → Privacy & Security → Accessibility with the `–` button, then
add it again — the stale row no longer matches the new signature.

## Performance

The app does no work when you cannot see it. Hiding the window, minimising it
or fully covering it with another window stops the poll timer and freezes every
animation and per-second timer; it all resumes on the way back. Snapshots are
equatable and only republished when something actually changed, so idle tiles
are never re-laid out. The notch is the exception: it is a live readout, so
leaving it on keeps the timer running whatever the window is doing.

### Why the idle animations are Core Animation

`Animations.swift` draws the breathing asterisk, the status-dot pulse, the
shimmer sweep and the notch's spinner as `CALayer`s with `CABasicAnimation`,
not as SwiftUI animations. This is the single most important thing in the app
for CPU, and it is not a micro-optimisation.

A running SwiftUI animation keeps `NSHostingView` needing layout, and AppKit
then runs a **full view-graph render for the whole window on every display
cycle** — 120 times a second on a ProMotion display. The cost has nothing to do
with how small the animating thing is; it scales with how much is on screen.
Isolating the animation in its own leaf view does not help, because the
invalidation is at the hosting view, not the leaf.

Measured on a 1512x950 window, six tiles, two of them working:

| | CPU |
| --- | --- |
| SwiftUI animations | 18.5% |
| the same animations as layers | 4.6% |
| plus the per-second label fixes below | 3.6% |

On a real nine-session fleet with the notch on, the same work took the app from
roughly 53% of a core to under 2%.

If you add another loop — anything with `repeatForever` in it — put it in
`Animations.swift` as a layer. The pattern is small: an `NSView` subclass that
builds one layer, adds one animation, and positions it in `layout()`. Note that
an `NSViewRepresentable` has no size of its own in a SwiftUI stack, so each one
is given an explicit `.frame` at the call site.

### Per-second labels

Every age label used to run its own one-second `TimelineView`. Two changes:

`AgeSchedule` ticks once a second only while the label is still counting
seconds, then on each minute boundary — a tile quiet for five hours was
redrawing 3,600 times an hour to change nothing.

All the remaining per-second schedules start from `wholeSecond(after:)` rather
than their own `.now`, so they tick on the same instant. Scattered phases cost
one window-wide layout pass each; in step they cost one between them.

### Accessibility polling

Walking another app's Window menu is synchronous IPC into that app. It runs on
its own queue, and the result is only published when the list actually differs
— reassigning an identical list re-rendered the whole grid every four seconds.

## Caveats

- Strictly read-only; there is no way to send input to a session.
- Sessions are detected from disk, so anything Claude Code doesn't record
  (for example a pending permission prompt) isn't visible.
