<img width="1280" height="640" alt="social-preview" src="https://github.com/user-attachments/assets/9047f111-087e-43f4-ad94-98f538686f5a" />

[![Build](https://github.com/dazecoop/watchtower/actions/workflows/build.yml/badge.svg)](https://github.com/dazecoop/watchtower/actions/workflows/build.yml)
![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-0A0A0C)
![Swift](https://img.shields.io/badge/swift-6-F05138)
![Licence](https://img.shields.io/badge/licence-MIT-2F7DD1)

A read-only macOS dashboard that tiles every running Claude session into a
single window, so you can see what each project is doing at a glance.

If you keep several VS Code windows open with Claude Code working in each, you
normally have to cycle through windows and Spaces to find out where things
stand. Watchtower puts them all side by side: what each session is working on,
what it just said, whether it is still running or waiting on you, and how much
of your plan you have used.

It only ever reads. There is no way to send a message to a session from here.

When you don't need the whole dashboard, there is the **notch**: a small black
readout that sits flush against a screen edge, showing plan usage and whether
anything is running. Click it to bring the dashboard back — or have it swell
open in place, Dynamic Island style, into either a summary of the fleet or the
entire dashboard, without a window ever coming forward. With the notch on,
Watchtower can run without a Dock icon at all.

<img width="1830" height="1200" alt="screenshot" src="https://github.com/user-attachments/assets/70c7b0fb-d5ea-45ba-80ea-87c9fe1c2a4d" />

---

## Requirements

- macOS 14 (Sonoma) or later — Apple silicon or Intel
- Claude Code, in VS Code or the CLI

Watchtower reads the files Claude Code already writes to `~/.claude`. If you
have never run Claude Code, there will be nothing to show.

## Install

<a href="https://github.com/dazecoop/watchtower/releases/latest">
  <img src="docs/download-macos.png" alt="Download for macOS" width="236">
</a>

1. Download `Watchtower-1.3.0.dmg` from the
   [latest release](https://github.com/dazecoop/watchtower/releases/latest).
2. Open it and drag **Watchtower** into **Applications**.
3. Launch it.

### First launch

macOS will block it the first time and say it *"could not verify Watchtower is
free of malware"*. That is expected, nothing was detected, and you only need to
clear it once — see [the FAQ below](#macos-says-it-could-not-verify-watchtower-is-free-of-malware-is-something-wrong)
for what the message actually means.

1. Try to open Watchtower. macOS blocks it.
2. Open **System Settings → Privacy & Security** and scroll to **Security**.
3. Click **Open Anyway**, then confirm.

<img src="docs/gatekeeper.png" alt="Open Anyway in System Settings" width="500">

On older versions of macOS you could right-click the app and choose **Open**
instead. That shortcut no longer works for this kind of block, so use System
Settings.

### Giving it Accessibility access (optional)

Only needed for the **reveal** button that jumps to a session's editor window.
Everything else works without it. A banner appears in the app with a button
that takes you to the right place, or:

**System Settings → Privacy & Security → Accessibility** → add Watchtower.

If Watchtower is already listed but the banner persists, remove the entry with
the **–** button and add it again. An old entry made against a previous build
no longer matches.

---

## Reading the dashboard

Each session gets a tile:

- **Name and status.** Green *Working* means Claude is mid-turn. Amber *Your
  turn* means it has finished and is waiting on you. Grey *Idle* means nothing
  has happened for half an hour — and an idle tile keeps fading the longer it
  stays quiet, so an hour's silence and a day's don't look alike.
- **Title** is the summary Claude Code generates for the session, with the
  project folder and git branch beneath it.
- **Thinking indicator** appears while a turn is running, counting from the
  last thing the session did.
- **The highlighted block** is Claude's most recent prose — the same thing you
  would read in the chat panel. While the turn is still running it shimmers and
  is labelled *so far*, because it is the latest line rather than the last one.
- **Below that** is a live feed of recent steps: tool calls, their output, and
  anything you sent.
- **The footer** shows the model, context tokens in flight, and how many tools
  the session has run.

### Usage

The strip along the bottom shows your plan limits — session, weekly, and any
model-specific weekly limit — with a meter, a percentage and a reset countdown.
Each limit keeps its own colour, the same one it has in the notch. The
percentage turns amber past 75% and red past 90%.

These figures come from the cache Claude Code keeps locally. Watchtower never
contacts Anthropic itself, so the numbers refresh when Claude Code refreshes
them. If nothing has updated them for half an hour the strip dims rather than
presenting stale numbers as current.

### Jumping to a session

The **⬀** button on each tile focuses the editor window running that session,
switching Spaces if the window is on another desktop. It never opens a new
window or file.

Window titles are the only handle macOS gives for this, so matching is by
folder name. When it cannot tell which window you mean, the button becomes a
picker — choose once and it is remembered for that project. Right-click a
resolved button to re-link it.

One wrinkle: a VS Code window with **no folder open** names itself after
whichever file is in front, so its title changes as you switch tabs and a saved
link to it will stop resolving. Windows opened on a folder or workspace are
stable.

### The notch

Turn it on in Settings and a small black readout sits flush against a screen
edge of your choosing, above other windows and on every Space.

It shows one ring per plan limit — each in the same colour it has in the usage
bar — the most pressing percentage underneath, and the Claude mark in the
middle. A green ring circles the mark while any session is mid-turn. Hover for
the full breakdown: counts, every limit, and what the busiest session is doing.

Click it to bring Watchtower forward. Drag it to slide it along its edge.

It sweeps out of the screen edge and back again, MacBook-notch style, and you
set how far. Slide it into a screen corner and it picks up a second sweep into
the edge it has just met, so it sits in the corner rather than curving away
from it. The sweep can be turned off entirely.

#### Expanding in place

Rather than bringing the window forward, the notch can swell open where it
sits. It grows out of whichever edge it is docked to, about the point it is
parked at, and slides back onto the screen instead of off it when it is sitting
in a corner. It closes again when the pointer leaves.

Set it to open on a **click**, or on **hover** with a delay you choose from
instant up to a second. And choose what it opens into:

- **Summary** — a line per session with what it is doing and how long ago, plus
  your plan limits. Click a session to jump to its editor window, *Open* for
  the full window, or click anywhere to close.
- **Full app** — the entire dashboard, tiles and all, inside the notch, with a
  cog for Settings in place of any way back to the window. In this mode the
  notch *is* the app: clicks inside go to the dashboard, so it closes by moving
  away. It always draws on the notch's black rather than your chosen theme,
  since anything lighter reads as a window sitting in the bezel.

**Credit where it's due.** The idea came from
[Codenotch](https://github.com/vinzdg/codenotch), which pins a usage readout to
a screen edge and covers several coding assistants at once — Claude, Cursor,
Codex and others. I used it, liked it, and wanted something that went deeper on
one of them rather than wider across all of them: Watchtower follows individual
Claude Code sessions, so the notch is a way back into a dashboard of what each
session is actually doing. This is a separate implementation written against
that goal, not a port of theirs. If you want one widget covering several
assistants' usage side by side, Codenotch is the better tool.

---

## Settings (⌘,)

Four pages down the left.

### Appearance

| | |
| --- | --- |
| **Theme** | Six themes. *System*, *Light* and *Dark* use macOS vibrancy, so your wallpaper shows faintly through. *Slate*, *Midnight* and *Nocturne* are opaque — nothing bleeds through. |
| **Columns** | Dynamic, or a fixed 1–4. Dynamic fits as many tiles as the window allows. |
| **Render markdown** | Show `**bold**` and backticks as formatting rather than raw syntax. |
| **Thinking indicator** | Turn the animated status off if you prefer it still. |

### Notch

| | |
| --- | --- |
| **Show the notch** | On or off. |
| **Position** | Which screen edge it sits on, and where along that edge. You can also just drag it. |
| **Size** | How big it sits on the bezel. This sizes the notch itself, not what it opens into — an expanded panel is always at a readable size. |
| **Rounding** | How far it sweeps out of the screen edge, and how much its inner corners are rounded. Both move together; the sweep can also be switched off. |

### Expanding

| | |
| --- | --- |
| **Expand the notch in place** | Swell it open where it sits instead of bringing the window forward. |
| **Opens on** | Click, or hover with a delay from instant to a second. |
| **Opens into** | *Summary* or *Full app* — see [above](#expanding-in-place). |

### Behaviour

| | |
| --- | --- |
| **Notify when a session needs you** | A notification the moment a session stops working and starts waiting on your reply. The most useful setting here when several are running. |
| **Menu bar status** | Off by default. Adds a working/waiting count to the menu bar with a jump-to menu. |
| **Hide Dock icon** | Runs Watchtower in the background with no Dock icon and no app menu. Needs the notch or the menu bar status on first, since one of them has to be able to open the window again — otherwise the setting is greyed out, and turning both off later puts the Dock icon back. |

The toolbar also has a filter field for narrowing by name, project or title,
and a sort control: by status, most recent, or project.

### Keyboard

| | |
| --- | --- |
| `⌘R` | Refresh now |
| `⌘P` | Pause / resume live updates |
| `⌘L` | Show active sessions only |
| `⇧⌘O` | Show / hide the notch |
| `⌘,` | Settings |

---

## A note on tile order

Tiles hold their position while work is happening. If they re-sorted on every
update, active sessions would swap places constantly and the grid would be
unreadable. The order is only rewritten once nothing has moved for 30 seconds,
or immediately when you change the sort or filter yourself. New sessions are
added at the end rather than pushed into the middle.

## Privacy

Everything stays on your machine: Watchtower reads local files under
`~/.claude` and makes no network requests of any kind. See the FAQ for
[what it does and does not touch](#does-it-send-my-code-or-conversations-anywhere),
and how to verify that yourself.

## FAQ

### macOS says it could not verify Watchtower is free of malware. Is something wrong?

No, and nothing was found. That message does not mean macOS scanned the app and
detected something — it means the opposite. It has **not** been scanned, so
macOS cannot vouch for it and says so in strong terms.

The check it failed is **notarisation**: uploading the app to Apple to be
scanned and stamped. That requires a paid Apple Developer account, which this
project does not have. Every app distributed outside the App Store without one
produces this same warning, regardless of what it does.

If you would rather not take that on trust, you do not have to:

- **Read the source.** It is all here, and it is small — around 5,000 lines of
  Swift with no third-party dependencies.
- **Check it cannot phone home.** There are no networking APIs anywhere in
  `Sources/`, and the compiled binary links zero networking symbols. You can
  confirm that yourself:
  ```bash
  nm -u /Applications/Watchtower.app/Contents/MacOS/Watchtower | grep -ci "CFNetwork\|NSURLSession"
  # 0
  ```
- **Build it yourself** and skip the download entirely — `./build.sh`, then the
  warning never appears, because an app you built locally is not quarantined.

### Why does it need Accessibility access?

Only for the reveal button that jumps to a session's editor window. macOS
treats controlling another app's windows as an accessibility action, so there
is no way to offer it without the permission. Decline it and everything else
works; the button simply turns into a lock.

### Does it send my code or conversations anywhere?

No. It reads files under `~/.claude` that Claude Code has already written, and
that is all. Nothing is uploaded, and there is no telemetry or analytics. Plan
usage figures come from a cache Claude Code keeps on disk, not from a request
to Anthropic.

### Can it interfere with my sessions?

No. Every file is opened read-only, and the app has no way to send input to a
session. The worst it can do is show you something out of date.

## Troubleshooting

**No sessions appear.** Watchtower only lists sessions whose process is still
running. Check that Claude Code is actually open in a project.

**The reveal button is a lock icon.** Accessibility access has not been granted
— see above.

**The reveal button opens a picker every time.** The window it was linked to
has changed its title. Pick it again, or open that VS Code window on a folder
so its title stays put.

**Usage strip is dim or missing.** No Claude Code session has refreshed the
usage cache recently. It fills in once one does.

## Building from source

See [DEVELOPING.md](DEVELOPING.md).

## Licence

MIT
