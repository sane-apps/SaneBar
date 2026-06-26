# Air UI Testing Runbook (notch / built-in-display verification)

> Why this exists: SaneBar's chronic menu-bar bugs (notch-region moves, the
> Always-Hidden "stuck"/beachball family) **only reproduce on a notched
> built-in display**. The Mac mini has no built-in display and drives
> notchless external monitors, so `NSScreen.auxiliaryTopRightArea` is nil
> there and the entire notch code path is dead. **Notch / built-in-display
> behavior MUST be verified on the MacBook Air**, by driving the real UI with
> real mouse input (computer-use), not AppleScript — the AppleScript move
> command (`runScriptMove`) takes a different code path than a human dragging
> a tile, so it hides the real behavior. See `air-is-users-workstation` and
> `sanebar-notch-beachball-fixes-pending` in memory.

This is the default-OFF exception to Mini-first. Keep Mini-first for
everything else. Each step below was hard-won during the 2026-06-25 AH-move
beachball fix; follow it instead of rediscovering.

## 1. Build + install a testable build on the Air

```bash
ruby ~/SaneApps/infra/SaneProcess/scripts/sane_test.rb SaneBar --local --no-logs
```

- Builds **ProdDebug** with bundle id `com.sanebar.app`, stages to
  `/Applications/SaneBar.app`, kills any existing SaneBar first → **single
  instance** (never run two SaneBar instances — it breaks TCC and the app can
  vanish).
- This replaces the notarized release with a debug build. **Restore afterward**
  via the release pipeline or reinstall.

## 2. Make the build trusted for Accessibility (TCC)

A local debug build is signed with the **Apple Development** cert, not the
**Developer ID** the original Accessibility grant was issued for, so SaneBar
shows "Grant Access" and moves silently fail. Re-sign to match the grant:

```bash
codesign --force --deep --options runtime \
  --sign "Developer ID Application: Stephan Joseph (M78L6FXD48)" \
  /Applications/SaneBar.app
```

Then rebind + relaunch so the running process re-reads the grant:
- System Settings → Privacy & Security → Accessibility → toggle **SaneBar OFF
  then ON** (this rebinds the requirement to the current on-disk signature; no
  password prompt on this machine).
- Quit SaneBar (menu → Quit) and relaunch (`open_application "SaneBar"`).
- The panel's "Grant Access" screen should be gone. Confirm with a move.

## 3. Live logging = code evidence alongside the visual

SaneBar logs richly via `os.Logger` (subsystem `com.sanebar.app`, ~30
categories). Capture it live with `Scripts/sanebar_logwatch.sh`:

```bash
bash ~/SaneApps/apps/SaneBar/Scripts/sanebar_logwatch.sh > /tmp/sanebar_live.log 2>&1 &
# then after each action:
tail -40 /tmp/sanebar_live.log | grep -iE "moveIcon task|Move complete|notch-unsafe|Could not find|separator|classif"
```

GOTCHAS:
- Run `log stream` **from a script file**, never inline — the agent shell
  evals commands and mangles the predicate's nested quotes ("too many
  arguments"). Background `log stream` also fails inline; the script-file form
  works.
- Use `--level info` (the move workflow logs at `.info`). `--level debug` was
  observed to fail; `--level info` works.
- `log show` does NOT reliably surface `.info`/`.debug` (not persisted) — use
  `log stream`.

## 4. Driving the panel (computer-use)

- **Computer-use is blocked on the Air by the Mini-first guard** (`sanetools.rb`
  `check_local_ui_tool_guard`). Sanctioned opt-in: `SANE_APPROVE_LOCAL_UI_ON_AIR`
  in the hook env, or the project bypass file
  (`touch <project>/.claude/bypass_active.json`, remove with `trash` when done).
  Only `sanetools.rb` gates computer-use (not the Bash-only guards).
- `request_access` for **both `SaneBar` and `Finder`** — menu-bar/desktop
  clicks count as desktop interaction and need the Finder grant.
- **Open the panel with the global hotkey ⇧⌘Space**, not by clicking the
  menu-bar icon — the icon's x-position shifts as the visible-zone layout
  changes, so pixel-clicks miss.
- **The panel is highly transient** — it auto-dismisses the moment focus
  shifts between discrete actions. Do an entire interaction (open → All tab →
  filter → right-click tile → click "Move to X") in **one `computer_batch`**
  with no intermediate screenshots; gaps let it close.
- Filter to one icon (type its name in the filter box) so the tile is at a
  known position (~549,258) for right-click.

## 5. Ground-truth zone verification (read-only)

AppleScript is fine for *observing* state (not for performing the move):

```bash
osascript -e 'tell application "SaneBar" to list icon zones' | tr ',' '\n' | grep -i <iconName>
```

Pair this with the live log: log proves the workflow ran + completed; this
proves the icon's final zone.

## 6. Surfaces

- **⇧⌘Space** opens the panel in **findIcon** mode (log: `browse panel show
  (findIcon)`).
- The **Browse Icons** menu item opens **secondMenuBar** mode.
- Same window/code, different mode flag — but verify both, in all 6 zone
  transitions (V↔H, V↔AH, H↔AH).

## 7. Cleanup when done

- Remove the bypass file (`trash <project>/.claude/bypass_active.json`).
- Confirm a single SaneBar instance.
- Restore the notarized release build (it was replaced by the debug build).
