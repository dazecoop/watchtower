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
| `WindowFocuser.swift` | Accessibility-based editor window focusing. |
| `AttentionNotifier.swift` | Working → waiting transition alerts. |
| `Theme.swift` | Themes and the environment keys. |
| `Views.swift` | Grid, tiles, feed lines, thinking indicator, shimmer. |

### Generated images

`docs/download-macos.png` and the app icon are drawn in code, not checked in as
hand-made assets:

```bash
swiftc -O Resources/MakeBadge.swift  -o /tmp/makebadge  && /tmp/makebadge docs/download-macos.png
swiftc -O Resources/MakeSocial.swift -o /tmp/makesocial && /tmp/makesocial
```

`MakeSocial.swift` builds `docs/social-preview.png`, the 1280x640 card GitHub
serves as `og:image`. Committing it is not enough — GitHub only picks it up
once it is uploaded under **Settings → General → Social preview**, which has no
API or CLI equivalent. Re-upload after regenerating.

`build.sh` regenerates `Resources/AppIcon.png` from `Resources/MakeIcon.swift`
whenever the generator is newer.

### Demo mode

`WT_DEMO=1` swaps the real data source for fabricated sessions in
`DemoData.swift` — invented project names, folders and conversation text,
covering all three states. That is how `docs/screenshot.png` is produced, so
the README never exposes real project names or chat content:

```bash
WT_DEMO=1 dist/Watchtower.app/Contents/MacOS/Watchtower
```

The flag is read once at launch and is unreachable otherwise.

### Two SwiftUI traps worth knowing

Both cost real debugging time and are commented in place:

1. **Scene generics.** Inlining the `commands` builder and a ViewBuilder
   `MenuBarExtra` label into `App.body` nested the opaque types deeply enough
   that the Swift runtime blew its stack resolving type metadata — a segfault
   on launch, not a compile error. `WatchtowerCommands` and `MenuBarContent`
   are separate types to keep that nesting shallow.

2. **`MenuBarExtra(isInserted:)` writes back to its binding** while updating.
   Backed by an `@Published` store property that becomes an endless
   publish/render loop which pins the main thread. It is `@AppStorage`.

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
reads what Claude Code has already cached, and re-parses the file only when its
mtime changes.

Meters turn amber past 75% and red past 90%, or earlier if the API marks a
limit as warning/critical. If the cache hasn't been refreshed in 30 minutes the
whole bar dims, rather than presenting stale numbers as current.

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

`⌘R` refresh · `⌘P` pause/resume · `⌘L` active-only

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
are never re-laid out.

## Caveats

- Strictly read-only; there is no way to send input to a session.
- Sessions are detected from disk, so anything Claude Code doesn't record
  (for example a pending permission prompt) isn't visible.
