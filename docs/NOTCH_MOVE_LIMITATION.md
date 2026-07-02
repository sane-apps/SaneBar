# Why SaneBar can't move icons stuck at/behind the notch (macOS 26)

**Status: platform limitation, proven live on notched hardware (2026-07-01).**
This documents the final engineering attempt at issues #170, #155, and #156 —
the family of reports where an icon stranded left of (or behind) the camera
notch cannot be moved to Visible. The result is a negative one, and I'm
publishing it so no contributor burns a week rediscovering it.

TL;DR: **a fix is likely possible — but only by requesting Screen Recording
permission, and I promised users SaneBar would never ask for that.** I'm not
willing to break that promise, even for this. Privacy or nothing.

## The three walls

Probed on a notched MacBook Air (1470×956, notch gap x∈[646, 825]), macOS 26,
with a 22-item overflow fixture and a dev build off branch
`fix/170-cross-notch-teleport`.

**1. A synthetic cmd-drag across the notch is silently dropped.**
SaneBar moves icons by posting a cmd-drag (`performCmdDrag`,
`Core/Services/AccessibilityMenuBarDragService.swift`). Any drag whose
interpolated path enters the notch dead zone posts without error but never
lands: `deltaMidX=0.000000` on every attempt, deterministic, reproduced across
two sessions. WindowServer drops the reorder when the pointer path crosses the
gap.

**2. The working alternative primitive needs a window ID I cannot get.**
Ice (MIT) and its active fork Thaw move items *without any drag path*: a
cmd-mouseDown/mouseUp pair whose CGEvent fields carry the item's CGWindowID
(`.mouseEventWindowUnderMousePointer`, private field `0x33`) so WindowServer
teleports the item — no pointer ever crosses the notch. I implemented exactly
that (see `Core/Services/AccessibilityMenuBarTeleportMove.swift` on the spike
branch). It dead-ends at window-ID resolution:

- `_AXUIElementGetWindow()` returns **-25201 (not supported)** for menu bar
  status items, so the Accessibility permission SaneBar already holds cannot
  produce a window ID.
- `CGWindowListCopyWindowInfo` returns **zero** windows owned by the item's
  app — even in a process **with Screen Recording granted** — because macOS 26
  Tahoe reparents every third-party status-item window to Control Center's
  PID (root-caused independently in Ice PR #911).
- macOS doesn't even render a status-item window left of the notch: live
  enumeration showed all 12 on-screen layer-25 windows packed right of the
  notch (x ≥ 935); the items Accessibility reports at left-of-notch positions
  have no grabbable CGWindow at all.

**3. The permission trade-off.**
Ice and Thaw work because they **require Screen Recording permission** to
enumerate menu bar item windows (and handle the Control Center reparenting by
resolving the item's true source PID). With that permission, the teleport
primitive is field-proven on notched hardware — so this is probably fixable.
But I sold SaneBar on *no screen recording, on-device, privacy first*, and I'm
not willing to trade that away for this edge case. It's privacy or nothing.
Note that even Ice and Thaw document notch-adjacent items as unreliable (Ice
#715: items pushed into the notch disappear; Thaw's layout planner avoids
anchors near the notch), so the permission buys "mostly", not "fixed" anyway.

## What this means in practice

- Moves whose path would cross the notch are refused/fail verification and
  report an error — SaneBar will not pretend they worked.
- The shipping mitigations for crowded notched menu bars are **Settings →
  Appearance → "Reduce space between icons"** (fits more icons before the
  notch) and **Find Icon (⌘⇧Space)**, which can search and activate any icon
  even when it is physically invisible behind the notch.

## For contributors

The full spike — gate fix, dead-zone detection, the teleport primitive, unit
tests, and probe scripts — lives on branch `fix/170-cross-notch-teleport`
(commit message has the complete play-by-play). I'm not going to build a
Screen Recording–gated version myself — it's privacy or nothing for the app I
ship. But SaneBar is MIT now: if you want this feature badly enough to accept
that trade-off, fork it and build your own version with Screen Recording
wired in. I genuinely mean that as an option, not a brush-off.

If you'd rather stay privacy-first and still take a run at it, the other
honest path is waiting for macOS 27 "Golden Gate", which replaces the
per-item-window model entirely (all items become one window; Bartender's
27-era builds already move items "without touching your mouse" via new,
still-undocumented MenuBarAgent API) — any fix built on the macOS 26 model
dies there anyway.

Pull requests are reviewed and merged. Receipts beat vibes: any claimed fix
needs a real zone-delta on notched hardware, not a green unit suite.
