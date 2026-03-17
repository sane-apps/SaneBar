# Menu Bar Runtime Playbook

Start here when SaneBar has a persistent menu bar regression.

This file is the single debugging entry point for:
- hide/show state bugs
- Browse Icons / second menu bar regressions
- icon move / zone classification failures
- display-change / update / restart resets
- menu-extra discovery gaps

Use this together with:
- `docs/DEBUGGING_MENU_BAR_INTERACTIONS.md` for lower-level positioning notes
- `docs/state-machines.md` for the older full-system diagrams
- `docs/E2E_TESTING_CHECKLIST.md` for broader release coverage

Current Mini performance guardrails for runtime smoke:
- fresh launch idle should settle near `0-2%` CPU and about `55-60 MB` RSS
- post-smoke idle is measured only after an `8s` settle window, because scripted browse/move cleanup can stay busy for a couple of seconds without indicating a real loop
- whole-pass stress average is allowed up to `15%` CPU during the aggressive smoke, but the app must still return to near-zero CPU afterward

## Canonical Runtime Path

For scripted launches and live smoke on development machines and on Mini:
- runtime app path: `/Applications/SaneBar.app`
- runtime process path: `/Applications/SaneBar.app/Contents/MacOS/SaneBar`
- runtime bundle id for smoke: `com.sanebar.app`

Everything else is a build artifact, not a launch target:
- `DerivedData/.../SaneBar.app`
- `codex-runs/.../SaneBar.app`
- archive export bundles
- stray `/Applications/SaneBar.app` copies from older sessions

`sane_test.rb` is expected to:
- stage the newest build into `/Applications/SaneBar.app`
- trash non-canonical copies before verification
- launch only that canonical bundle

As of March 6, 2026, `./scripts/SaneMaster.rb test_mode --release` is also expected to:
- prefer the real `Release` configuration
- preserve any signed `/Applications/SaneBar.app` install if headless signing forces an unsigned fallback build
- stage unsigned fallback builds into `~/Applications/SaneBar.app`
- verify that the launched process path matches the bundle it just staged

Do not validate runtime behavior with raw `ssh mini 'cd ... && xcodebuild ...'` or raw `ssh mini '... ./scripts/SaneMaster.rb ...'` from a stale remote repo checkout.
Run `./scripts/SaneMaster.rb ...` from the local workspace root so Mini-first routing syncs the current local tree first.

`Scripts/live_zone_smoke.rb` should be run with explicit target env vars so it does not fall back to Finder / Launch Services name resolution.

## Canonical Regression Buckets

Treat repeated bug reports as one of these runtime families, not as isolated issues.

### R1. Move / classification drift

Symptoms:
- move icon returns success but lands in the wrong zone
- hidden <-> always hidden moves fail intermittently
- separator geometry looks inverted or stale

Primary code:
- `Core/MenuBarManager+IconMoving.swift`
- `Core/Services/SearchService.swift`
- `Core/Services/AppleScriptCommands.swift`
- `Core/Services/LayoutSnapshotGeometry.swift`

### R2. Browse panel / rehide race

Symptoms:
- Browse Icons opens and immediately becomes unusable
- ghost cursor reports during browse interactions
- second menu bar or icon panel fights with auto-rehide
- app activation while opening the panel schedules a hide

Primary code:
- `UI/SearchWindow/SearchWindowController.swift`
- `Core/MenuBarManager+Visibility.swift`
- `Core/MenuBarManager.swift`

### R3. Display reset / persistence drift

Symptoms:
- layout resets after update, restart, or monitor change
- visible icons go back to defaults
- stale pixel positions survive after moving to a new display width

Primary code:
- `Core/Controllers/StatusBarController.swift`

### R4. Settings / expectation mismatch

Symptoms:
- user expects one browse mode but another is active
- auto-rehide behavior surprises the user
- Always Hidden behavior is interpreted as a move bug

Primary code:
- settings UI
- diagnostics output
- onboarding / import behavior

This bucket is real, but do not let it hide R1-R3.

### R5. Detection / host-model gaps

Symptoms:
- app never appears in Find Icons or owner/config lists
- app is missing from scan output even though its menu presence is visible on-screen
- logs show `AXExtrasMenuBar` unavailable and no usable fallback item model

Primary code:
- `Core/Services/AccessibilityService+Scanning.swift`
- `Core/Services/AccessibilityService+MenuExtras.swift`
- `Core/Services/AccessibilityService+Cache.swift`
- `Core/Services/BartenderImportService.swift`

Known examples:
- Little Snitch
- Time Machine
- older “disappearing icons / not in Find Icons” reports where the app had no standard AX extras bar

### R6. Startup scene / status-item bootstrap failure

Symptoms:
- process is alive but no SaneBar icon or separator ever appears
- launch preferences exist, but the status items never render
- shortcuts or other startup interaction surfaces appear dead
- Console shows disconnected status-bar scene errors on Tahoe-class systems

Primary code:
- `Core/MenuBarManager.swift`
- `Core/Controllers/StatusBarController.swift`

Key rule:
- a missing status-item window is not a healthy startup state; it must trigger recovery instead of being treated as “not ready yet”

Current root cause note:
- if `MenuBarManager` eagerly constructs the default `StatusBarController` during init, the `NSStatusItem`s are created before the deferred startup delay and before the headless guard actually matters
- the runtime-safe path is: defer default `StatusBarController` creation until `setupStatusItem()`, validate both main + separator window attachment, and allow a bounded second recovery pass for Tahoe-class disconnected scenes

### R7. Dock policy drift / activation churn

Symptoms:
- Dock icon appears even though `showDockIcon` is off
- issue often follows inline reveal or temporary app-menu suppression
- Console can show `NSApplication._react(to:) dock`

Primary code:
- `Core/MenuBarManager+Visibility.swift`
- `Core/Services/UpdateService.swift`

Key rule:
- when `showDockIcon` is off, activation side effects must not be allowed to leave SaneBar visible in the Dock

## Live GitHub Issue Map

Use this table before replying, closing, or opening another issue. Keep one primary bucket per issue even if the logs show secondary symptoms.

| Issue | State | Primary bucket | Why it belongs there | Notes |
|------|------|------|------|------|
| `#106` | open | `R1` | Browse Icons move path fails; logs show unresolved on-screen frame and bad hardware-fallback coordinates on an external monitor | Treat as current canonical browse-move issue for external-monitor style repros |
| `#110` | open | `R7` | `showDockIcon=false`, yet Console shows `NSApplication._react(to:) dock` shortly after inline app-menu suppression fires | Treat as a Dock-policy drift regression in the inline reveal / app-menu suppression path |
| `#109` | open | `R1` | Fresh 2.1.24 reporter diagnostics show repeated move-to-visible verification failures; same report also exposed browse undercount | Mixed thread: primary bucket stays `R1`, but it also carries `R5` evidence |
| `#108` | open | `R5` | Screenshot plus diagnostics prove Browse undercount: SaneBar found 32 menu bar items while the Second Menu Bar rendered only visible=4 hidden=7 | Real detection/data-pipeline bug, not just customer confusion |
| `#105` | closed | `R2` | Duplicate of `#101` from the same reporter/machine after the later second-menu-bar follow-up landed | Historical duplicate; keep `#101` as the canonical public thread |
| `#102` | closed | `R4` | Report is mostly screenshots plus configuration confusion; no fresh diagnostics ever arrived on a current build | Closed as settings-mismatch / stale-diagnostics, not as a verified runtime regression |
| `#101` | open | `R2` | Reporter supplied fresh 2.1.22 diagnostics showing second-menu-bar activation mismatch and unstable relayout | Historical evidence for the same family as `#105` |
| `#95` | closed | `R1` | Click/move and ghost-cursor family; later reports in `#94` / `#106` have the fresher builds and follow-up | Historical superseded thread; do not use as the current public reference |
| `#94` | open | `R5` | Latest 2.1.23 feedback says generic app opening/movement is mainly fixed, but specific apps (Little Snitch, Solver 3, Carrot Weather) still fail | Treat current `#94` as the residual host-model / no-AX activation thread, not the whole-system move bug anymore |
| `#93` | closed | `R1` | Original ghost-cursor move-to-visible issue | Historical superseded thread; keep for evidence, not as a live blocker |
| `#107` | open | `R6` | Tahoe 26.3.1 report: process alive, no icon/separator render, disconnected scene console errors | New startup bucket; not a move, browse, or persistence regression |
| `#103` | closed | `R4` | Crowded-menu-bar feature request / expectation mismatch | Behavior exists; explicit toggle is implemented on main and queued for next release |
| `#92` | closed | `R3` | Update reset / persistence drift | Same family as `#79` |
| `#79` | closed | `R3` | Visible layout reset after update | Same family as `#92` |
| `#73` | closed | `R3` | Visible icons no longer persist | Earlier persistence-reset thread |
| `#72` | closed | `R3` | Layout does not survive quit/logout/reboot | Earlier persistence-reset thread |
| `#71` | closed | `R5` | Little Snitch never appears in discovery/import | Keep as the original public R5 reporter thread |

Practical rule:
- `#101` and `#106` are the current live open reference threads for second-menu-bar and browse-move regressions.
- `#110` is the current live public reference for Dock icon drift while `showDockIcon=false`.
- `#108` is the live public reference for the Browse undercount / detection mismatch class.
- `#109` is currently the best public mixed thread when a report combines browse mismatch with move failure on the same machine.
- `#94` and `#93` no longer mean the same thing: `#93` remains historical move/click evidence, while current `#94` is now the best public thread for app-specific host-model fallout after the broader move fixes.
- `#71` remains the public reference for the no-AX-host detection class.
- `#107` is the public reference for startup scene/bootstrap failures on Tahoe-class systems.
- Do not tell users to open a brand-new issue if the symptom clearly matches one of these buckets.

## Live Email Thread Map

This is the same cross-reference for inbox threads. These are problem threads only, not receipts, license questions, or DMCA mail.

| Email thread | IDs | Primary bucket | Why it belongs there |
|------|------|------|------|
| `Sanebar installer problem v2.1.11` | `#121 #128 #167 #168 #187 #190 #207 #212 #223` | `R1` | Michael Sydenham thread; repeated reports of drag/drop and hidden/visible failures, with reset-on-update spillover |
| `Issue with Sanebar` | `#131 #135 #145` | `R3` | Restart causes previously visible apps to hide again |
| `Adding items to visible fails` | `#164` | `R1` | Ghost-cursor move failure into Visible |
| `Browse Icons Second Menu Bar Extremely Buggy` | `#102 #114` | `R2` | Judson second-menu-bar browse/activation thread before the later follow-up |
| `bug?` | `#274` | `R4` | Kyle Lamy screenshot thread; Browse Icons was set to Second Menu Bar while left-click was still configured as Toggle Hidden |
| `(no subject)` | `#279` | `unknown severe` | Ivan Bolgov thread; Activity Monitor screenshot proves 100% CPU, ~14 GB memory, and crashes, but no logs or repro steps arrived |
| `More bugs - second menu bar unusable` | `#199 #200` | `R2` | Same Judson second-menu-bar family with fresh logs/video |
| `[Issue #94] ... move them to visible` | `#216` | `R1` | Email mirror of the live GitHub `#94` move/click thread |
| `SaneBar after 2.1.11` | `#133` | `R2` | Hidden apps still do not open from the second menu bar |
| `SaneBar after 2.1.16` | `#171` | `R2` | Follow-up with video showing apps still not opening |
| `SaneBar after 2.1.17` | `#179 #193` | `R2` | Same follow-up family after another release |
| `SaneBar - Possible issue` | `#31 #39` | `R5` | Little Snitch and Time Machine missing from discovery lists |
| `SaneBar 1.0.20 and 1.0.22` | `#29 #36 #38` | `R4` | Early second-menu-bar option/configuration mismatch thread |
| `Problems in sanebar 1.0.23 (following)` | `#40 #53 #54 #56` | `R2` | Second menu bar shows visible and hidden items together / duplicate rendering |
| `SaneBar suggestion after starting using it` | `#63` | `R1` | No drag/drop between hidden and visible plus second-line problems |
| `SaneBar suggestion after 2.1.7` | `#77` | `R5` | Mixed thread, but Little Snitch and undiscoverable icons are the clearest lead |

Practical rule:
- If an email thread clearly mirrors a live GitHub thread, add that relation to the knowledge graph instead of treating it as a new problem.
- If the email is a new symptom string but matches one of these rows, reply in-thread and map it to the existing bucket first.
- Only create a new bucket if the report does not fit `R1-R6`.

## The Actual Runtime Model

The persistent bugs were not one bug. They came from 6 state machines drifting out of sync.

### 1. Visibility state

```mermaid
stateDiagram-v2
    [*] --> hidden
    hidden --> expanded: show / reveal
    expanded --> hidden: hide / rehide fires
    expanded --> expanded: rehide cancelled
```

Source of truth:
- `MenuBarManager.hidingService.state`

Key rule:
- A rehide timer is only valid if no browse session is active and no move is in progress.

### 2. Browse session state

```mermaid
stateDiagram-v2
    [*] --> idle
    idle --> opening: show(mode:)
    opening --> open: window visible
    open --> closing: close / resign
    closing --> idle: dismissal finished
```

Source of truth:
- `SearchWindowController.shared.isBrowseSessionActive`
- `SearchWindowController.shared.isVisible`
- `SearchWindowController.shared.isMoveInProgress`

Key rule:
- `isBrowseSessionActive` is earlier and more reliable than `isVisible` during open/close transitions.

### 3. Geometry confidence state

```mermaid
stateDiagram-v2
    [*] --> reliable
    reliable --> unreliable: hidden AH geometry stale / inverted
    unreliable --> reliable: live separator refresh / valid ordering restored
```

Important distinction:
- raw separator values are not always trustworthy
- hidden-state Always Hidden geometry is intentionally treated as unreliable

Key rule:
- never force a move or smoke invariant from raw AH geometry when the bar is hidden

### 4. Persistence / display-width state

```mermaid
stateDiagram-v2
    [*] --> first_run
    first_run --> stamped: width stored
    stamped --> same_display: width change insignificant
    stamped --> restore_backup: matching width bucket backup exists
    stamped --> reset_required: width changed significantly and only stale pixel positions exist
```

Key rule:
- pixel-like positions from a different display width must not be treated as trustworthy layout state

### 5. Move pipeline state

```mermaid
stateDiagram-v2
    [*] --> idle
    idle --> reveal_if_needed: user/script move
    reveal_if_needed --> wait_for_relayout: hidden icons shown
    wait_for_relayout --> resolve_target: fresh identity lookup
    resolve_target --> drag_move: separator targets resolved
    drag_move --> verify_zone: AX/classified zone check
    verify_zone --> rehide_if_needed: browse/search flow
    rehide_if_needed --> idle
    verify_zone --> idle: no rehide
```

Key rule:
- move verification must escalate from cached zones to a refreshed classification snapshot before declaring failure

### 6. Startup scene readiness state

```mermaid
stateDiagram-v2
    [*] --> deferred_setup
    deferred_setup --> items_created: status items instantiated
    items_created --> window_ready: button windows attach to the menu bar scene
    items_created --> scene_disconnected: button window stays nil / disconnected scene logs
    scene_disconnected --> autosave_recovery: recreate items with bumped autosave namespace
    autosave_recovery --> window_ready: recovered same launch
    autosave_recovery --> failed_launch: still no window after bounded retry
```

Key rule:
- startup validation must treat a missing status-item window as broken state, not just “not ready yet”

## Official Apple API Ground Truth

Verified against Apple documentation on March 5, 2026.

- `NSStatusItem.autosaveName` is only a unique identifier for saving and restoring a status item. Apple does not document pixel semantics or conflict resolution. Use it as identity, not as proof that a stored position is still valid.
- `NSWorkspace.didActivateApplicationNotification` includes the activated `NSRunningApplication` in `userInfo[applicationUserInfoKey]`. Filtering SaneBar self-activation is therefore the correct way to avoid false app-change rehide.
- `NSScreen.auxiliaryTopRightArea` is the unobscured top-right portion of the screen outside the safe area on obscured displays. It is the right reference point for notch/control-center drift checks.
- `UserDefaults.persistentDomain(forName:)` returns only the app domain, not merged defaults. Use app-domain snapshots for forensics and replay instead of reasoning from mixed defaults output.

## Root Causes Fixed In This Cycle

### Fixed: separator normalization for move targeting

What was wrong:
- move verification could trust stale separator boundaries

What changed:
- live main separator right edge is normalized before cache/verification
- Always Hidden separator boundaries are normalized against the main separator before move targeting

Proof:
- Mini smoke passed
- direct AppleScript move round-trip passed

### Fixed: hidden-state Always Hidden snapshot mismatch

What was wrong:
- snapshot logic treated raw Always Hidden coordinates as authoritative while hidden
- runtime classification already knew that geometry was unreliable in that state

What changed:
- layout snapshot now normalizes AH geometry and marks reliability explicitly

Proof:
- Mini smoke no longer fails on false layout-invariant checks

### Fixed: Browse Icons self-activation rehide race

What was wrong:
- `NSApp.activate(ignoringOtherApps: true)` during browse opening could trip app-change rehide logic
- fire-time rehide checks also trusted `isVisible` too early

What changed:
- app-change rehide now skips SaneBar self-activation
- app-change rehide now skips active browse sessions
- fire-time rehide now blocks on `isBrowseSessionActive` before `isVisible`
- search-triggered rehide defers while the browse session is active or visible

Proof:
- Mini browse script kept the panel open with:
  - `rehideOnAppChange = true`
  - `isBrowseSessionActive = true`
  - `isBrowseVisible = true`
  - `hidingState = expanded`

### Fixed: display backup restore path locked down

What was wrong:
- stale pixel positions after width changes were easy to regress

What changed:
- restore-vs-reset behavior is now covered by initialization tests

Proof:
- full Mini verify includes the restore path coverage

## Current Open Lead

What was closed during the March 6, 2026 Mini pass:
- the old `click succeeded` false-positive lead was real
- browse-origin activation can now verify a real post-click effect instead of trusting the posted click alone
- multi-item bundles were also mis-targeted when a stale `statusItemIndex` overrode a correct live X-position

What changed:
- new AppleScript browse commands can force `.browsePanel` origin directly
- click verification now requires an observable post-click reaction
- status-item resolution now falls back from a stale `statusItemIndex` to nearest-center matching when the live coordinates disagree
- when a precise system-wide menu extra replaces a coarse bundle fallback, positional status-item resolution now survives an identifier miss instead of failing closed
- precise system-wide menu extras now replace coarse same-bundle fallbacks instead of rendering duplicate rows like `Spotlight` + `com.apple.menuextra.spotlight`

Mini proof after the fix:
- `Stats::statusItem:2` was the failing browse-origin case before the patch
- the same live matrix now succeeds for:
  - `Stats::statusItem:0`
  - `Stats::statusItem:1`
  - `Stats::statusItem:2`
  - `Stats::statusItem:3`
  - `Wi-Fi`
  - `Spotlight`

What is still open:
- external confirmation is still needed from the GitHub `#101` class of reporter machines
- R5 detection/host-model gaps remain open for apps that never expose a usable AX menu-extra item at all

Separate live detection lead on March 6, 2026:
- installed Little Snitch 6.3.3 on Mini
- `at.obdev.littlesnitch.networkmonitor` is a top-bar host candidate
- SaneBar now detects that host and attempts third-party `AXMenuBar` fallback
- current live result is still `items=0`, so Little Snitch remains unresolved in item-position scanning
- quitting `/Applications/SaneBar.app` and sweeping the raw system-wide menu bar still does not surface a Little Snitch AX item
- `defaults read at.obdev.littlesnitch menuBarExtraIsShown` is `1` on Mini, so this is not just a hidden-state preference mismatch
- launching `/Applications/Little Snitch.app/Contents/Components/Little Snitch Network Monitor.app` directly still produces:
  - no `AXExtrasMenuBar`
  - no `AXMenuBar`
  - no system-wide AX hit-test samples for any `littlesnitch` bundle at the menu-bar y-coordinate
- `at.obdev.littlesnitch.networkmonitor` does own multiple full-width top-bar windows, so the remaining gap is host modeling / OS exposure, not app launch state
- latest mitigation is owner-only fallback in `SearchService.refreshMenuBarApps()`, which keeps this class visible in broad discovery even when macOS will not provide coordinates
- as of March 7, 2026, zoned views now filter out coarse bundle-only fallback entries and only render precise menu-extra identities
- that means second-menu-bar rows and Hidden/Visible/Always Hidden flows no longer present owner/window fallback entries as if they were safely movable/openable
- broad discovery still keeps those apps visible in Find Icon `All`, where app-level activation remains possible even when menu-extra coordinates are unavailable

What that means:
- owner-list coverage and item-position coverage are different problems
- do not close Little Snitch/Time Machine style reports as “same as second menu bar click bug”
- if a report says the app is visible in `Find Icon > All` but not in second-menu-bar rows anymore, that is the intentional capability split, not a regression
- if logs show `Top-bar host AXMenuBar fallback ... items=0`, the remaining problem is deeper than stale targets or rehide timing
- if system-wide hit-testing still finds nothing with SaneBar quit, the remaining problem is outside SaneBar's hide/show state machine

## Known Tricky App Matrix

Keep at least one live or synthetic check for each of these before calling detection fixed:
- Little Snitch: helper/top-bar host with no normal `AXExtrasMenuBar`
- Time Machine: system-hosted special-case detection
- one app with multiple status items under one bundle (`Stats`)
- one Apple menu extra with unstable AX identity (`Spotlight` or `Wi-Fi`)
- one notch-hidden item that only becomes reachable after reveal

Important interpretation rule:
- repeated identical-looking icons in Hidden are not automatically a duplication bug
- `Stats` legitimately exposes multiple menu extras under one bundle, so one hidden row can contain several nearly identical `Stats` icons
- on March 6, 2026 the Mini screenshot that looked like "Little Snitch 6-7 times" was actually four `Stats` items plus other normal hidden icons
- the duplicate-looking `Spotlight` entry was a real merge bug and should now collapse to the precise `com.apple.menuextra.spotlight` entry when the second menu bar is open

March 16, 2026 Mini recheck:
- direct AX probing on the Mini now confirms both `at.obdev.littlesnitch` and `at.obdev.littlesnitch.networkmonitor` return no `AXExtrasMenuBar` and no `AXMenuBar`
- raw WindowServer inspection still shows both processes owning multiple full-width `1920x30` top-bar windows
- signed `/Applications/SaneBar.app` now proves the capability split cleanly:
  - `list icons` returns coarse owner entries for both Little Snitch processes
  - `list icon zones` still does not surface a usable zoned/menu-extra identity for them
- this means the remaining Little Snitch problem is not stale helper IDs anymore; it is that macOS is exposing the app only as top-bar hosts without a normal actionable AX menu-extra
- low-risk posture: keep Little Snitch in `R5` as a known compatibility edge case unless a future fix can prove a precise, stable menu-extra identity without broad host/window heuristics
- do not risk SaneBar startup or generic menu-extra handling just to make Little Snitch fully operable

Do not mark R5 fully closed until this is explained or fixed.

## Current Hotspots To Audit First

If a new regression appears, read these in this order:

1. `Core/MenuBarManager+Visibility.swift`
2. `UI/SearchWindow/SearchWindowController.swift`
3. `Core/MenuBarManager.swift`
4. `Core/MenuBarManager+IconMoving.swift`
5. `Core/Services/SearchService.swift`
6. `Core/Controllers/StatusBarController.swift`
7. `Core/Services/AppleScriptCommands.swift`
8. `Core/Services/LayoutSnapshotGeometry.swift`

## Signed Build Trust Matrix

Treat these runtime targets differently.

| Target | Bundle ID | Typical trust/TCC state | Use for | Do not use for |
|------|------|------|------|------|
| Fresh Debug build in DerivedData | `com.sanebar.dev` | Usually no Accessibility grant unless manually staged | browse/rehide probes, prefs-restore replay, layout snapshot checks | final click/move smoke unless AX trust is confirmed |
| Trusted dev install in `/Applications/SaneBar.app` | usually `com.sanebar.app` or manually staged dev build | usable for real move smoke when AX trust is already granted | hidden/visible/AH round-trips, live smoke | proving a brand-new signed artifact |
| Fresh `ProdDebug` build | `com.sanebar.app` | should match release behavior, but trust only after codesign is clean | pre-release smoke once Sparkle/framework signing succeeds | assumptions while Sparkle signing is failing |
| Public release artifact after install | `com.sanebar.app` | actual customer path | final release confidence and customer repro confirmation | developer-only probes that depend on extra script commands |

Current blocker:
- Mini `ProdDebug` was still failing Sparkle codesign with `errSecInternalComponent`, so release confidence should stay below "fully proven" until that artifact passes the same smoke.
- Mini Accessibility trust can also fail at the system TCC layer even when the app row is visible in System Settings. On March 5, 2026 both `com.sanebar.app` and `com.sanebar.dev` were present in `/Library/Application Support/com.apple.TCC/TCC.db` with `auth_value=0`, which left AppleScript and live AX probes denied until the row was re-enabled through the password-gated `Modify Settings` sheet.

## Reporter Prefs Forensics

When a customer says "nothing changed" across releases, stop guessing and clone the app domain.

### Capture

1. Export only the app domain:

```bash
defaults export com.sanebar.app - > sanebar-defaults.plist
```

2. Capture immediately after repro:
- in-app bug report
- `layout snapshot`
- `list icon zones`

3. Keep these diagnostics fields:
- `prefsForensics`
- `nsStatusItemPreferredPositions`
- `settings`

### Replay

Use the debug bundle id to avoid touching the production install:

```bash
defaults import com.sanebar.dev sanebar-defaults.plist
open -a ~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/SaneBar.app
```

Then compare:
- current width bucket backups
- stored width bucket backups
- legacy always-hidden key
- whether launch restores a width-matched backup or resets to ordinals

### What To Look For

- `NSStatusItem Preferred Position SaneBar_AlwaysHiddenSeparator` still present with a tiny value
- stale pixel-like main/separator values paired with a different calibrated width
- current-width backup keys present but ignored
- hidden items unexpectedly becoming Always Hidden after first launch

Bartender residue is still only a hypothesis. Prefer proving or disproving SaneBar-domain state first.

## Stale Settings Checklist

Before calling something a "random old settings problem", check these explicitly:

- current `autosaveVersion`
- current main/separator/AH preferred positions
- legacy non-versioned Always Hidden separator key
- calibrated screen width
- current screen width and screen count
- current-width display backup keys
- stored-width display backup keys
- pinned Always Hidden ids count
- whether the first launch after reinstall moves items to Always Hidden before any user action

## Mini Repro Pack

Install these on Mini before chasing menu-bar regressions:

```bash
brew install --cask shottr stats hiddenbar
brew install cliclick mas
```

What each one is for:
- `Shottr`: third-party menu extra with screenshot-style behavior
- `Stats`: multi-item menu extra host
- `Hidden Bar`: another hide/show menu bar implementation to compare against
- `cliclick`: fallback UI automation when AppleScript element targeting is too brittle
- `mas`: App Store CLI for future repro apps that are App Store-only

Current notes:
- `Klack` was not available through Homebrew during this pass, so treat it as manual/App Store install territory.
- `Shottr`, `Stats`, and `Hidden Bar` can install cleanly but still remain background-only until their own onboarding is completed.
- `cliclick` was already present on Mini before this pass.

## Mini Screenshot Path That Actually Works

Direct screenshot tools launched from the SSH shell were not reliable on Mini during the March 6 pass:
- plain `screencapture` from SSH could fail with `could not create image from display`
- ad-hoc `ScreenCaptureKit` helpers were denied by TCC
- Shottr deep links and guessed hotkeys were not reliable enough for repeatable automation

The working path was to ask the active GUI `Terminal` app to run `screencapture`:

```bash
ssh mini 'osascript -e '\''tell application "SaneBar" to show second menu bar'\'' >/dev/null; sleep 1; osascript <<'\''APPLESCRIPT'\'' 
tell application "Terminal"
  do script "screencapture -x $HOME/Desktop/Screenshots/sanebar-open.png"
end tell
APPLESCRIPT
sleep 2
ls -l ~/Desktop/Screenshots/sanebar-open.png'
```

Use this when the test requires proof that the menu bar actually opened and rendered the expected icons.

## Mini Accessibility / TCC Recovery

Do not trust the user-level TCC database alone for Accessibility. On Mini, the meaningful rows for SaneBar were in:

```bash
sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
  "select client,auth_value,auth_reason,auth_version,length(csreq) \
   from access \
   where service='kTCCServiceAccessibility' and client like 'com.sanebar%';"
```

Interpretation:
- `auth_value=2`: granted
- `auth_value=0`: explicitly denied

Observed failure shape on March 5, 2026:
- System Settings showed two `SaneBar` rows in Accessibility
- both checkboxes could be flipped to `1`
- AppleScript still returned `Accessibility permission is required`
- the real blocker was the password-gated sheet with buttons `Modify Settings` and `Cancel`
- until that password sheet is completed, the system TCC row stays denied

Useful Mini checks:

```bash
ssh mini 'open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"'
ssh mini 'osascript -e '\''tell application "System Events" to tell process "System Settings" to get name of every button of every sheet of window "Accessibility"'\'''
ssh mini 'sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db "select client,auth_value from access where service='\''kTCCServiceAccessibility'\'' and client like '\''com.sanebar%'\'';"'
```

What this means for confidence:
- if the system TCC row is denied, Mini cannot be used for honest end-to-end SaneBar click/move proof
- unit tests can still pass, but live confidence must stay capped until the password-gated grant is completed

## Mini Verification Commands

These are the commands that mattered for this fix cycle.

### 1. Full suite

```bash
./scripts/SaneMaster.rb verify
```

What it proves:
- build still works
- unit/integration coverage still passes

### 2. Trusted app live smoke

```bash
SANEBAR_SMOKE_REQUIRE_ALWAYS_HIDDEN=1 ruby ./Scripts/live_zone_smoke.rb
```

What it proves:
- real move actions work end to end on Mini
- hidden/visible/always-hidden transitions still behave

Prerequisite:
- `com.sanebar.app` must already be Accessibility-granted at the system TCC layer

### 2a. Signed canonical release-path smoke

```bash
./scripts/SaneMaster.rb test_mode --release --no-logs
```

What it proves:
- the signed `Release` build is the one staged into `/Applications/SaneBar.app`
- Launch Services and Finder resolve the same canonical bundle that runtime smoke will hit

Prerequisite:
- the local codesign environment must be healthy enough to build and stage the `Release` app

### 2b. Release preflight runtime gate

```bash
./scripts/SaneMaster.rb release_preflight
```

What it now proves before release:
- the normal preflight checks still run
- when Mini can sign, a staged `Release` app is launched on Mini
- when Mini cannot sign, QA falls back to the signed `/Applications/SaneBar.app` install for release-style smoke
- `live_zone_smoke.rb` runs against the chosen release-style target, not whichever bundle happened to launch last
- second-menu-bar browse activation now has to stay alive across both left-click and right-click smoke paths, including the AppleScript browse activation lane
- the live smoke watchdog samples the actual SaneBar process and fails on runaway CPU or memory instead of silently passing functional checks
- the live smoke now also enforces lightweight budgets: the app must settle to a low idle CPU/RSS budget after launch and again after the browse/move pass
- screenshot artifacts are required only for the browse modes that target bundle actually exposes
- the smoke passes twice in one QA run: cold launch, then immediate repeat
- `/tmp/sanebar_runtime_smoke.log` keeps the actual browse activation diagnostics when a pass fails
- `/tmp/sanebar_runtime_resource_sample-passN.txt` is captured automatically if the watchdog sees a CPU or RSS runaway

Why the repeat pass matters:
- a single pass can succeed while pass 2 still exposes second-menu-bar browse activation drift
- the current failure shape is `finalOutcome: workspace activation fallback` plus `verification=failed (no observable menu/panel reaction)` while the browse panel still reports `currentMode: secondMenuBar`, `windowVisible: true`, and `lastRelayoutReason: refit`
- another real failure shape we already hit: the UI path was fixed, but the AppleScript browse path still bypassed `noteBrowseActivationStarted()/Finished()`, so right-click smoke closed the second-menu-bar panel mid-activation until script/UI parity was restored on 2026-03-10

Why the watchdog matters:
- Ivan `#279` proved SaneBar can go pathological with `100%` CPU and about `14 GB` RSS without crashing cleanly
- functional smoke alone would miss that if click/move flows still happened to work
- the watchdog turns that into a release-blocking runtime failure with a native process sample attached

What the performance budgets mean:
- peak CPU during an interaction pass is treated as a clue, not the whole story
- the hard gate is that SaneBar must settle down quickly after launch and after the full smoke run
- current release smoke budgets are:
  - launch idle: avg CPU `<= 5%`, peak CPU `<= 15%`, RSS `<= 128 MB`
  - post-smoke idle: avg CPU `<= 5%`, peak CPU `<= 20%`, RSS `<= 128 MB`
  - whole-pass average: avg CPU `<= 10%`, avg RSS `<= 192 MB`

### 2c. Targeted native-item smoke

Use the existing smoke harness when you need scientific repros for Apple-native items without widening the default release candidate pool:

```bash
SANEBAR_SMOKE_REQUIRED_IDS=com.apple.menuextra.siri,com.apple.menuextra.spotlight,com.apple.menuextra.focusmode \
SANEBAR_SMOKE_REQUIRE_ALL_CANDIDATES=1 \
SANEBAR_SMOKE_CAPTURE_SCREENSHOTS=0 \
ruby ./Scripts/live_zone_smoke.rb
```

What it proves:
- the real hidden -> visible move path still works for the exact native items you named
- the smoke is using the same browse/move tooling as release smoke, not an ad-hoc AppleScript harness
- explicit required IDs can now bypass the normal move denylist for focused investigations, while the default release smoke policy stays conservative
- focused required-ID runs keep browse validation in compatibility mode (open/close only) so unrelated right-click browse flakiness does not block a move-path investigation
- if the default conservative smoke has no movable candidates on an Apple-heavy machine, use this path instead of widening the release fixture pool

When to use it:
- Focus / Siri / Spotlight regressions
- reproducing a customer report on a specific Apple-native item
- verifying a native-item move fix before deciding whether a third-party oddball should stay in the known-edge-case bucket

### 3. Trusted app direct move round-trip

Use path-targeted AppleScript against:
- `/Applications/SaneBar.app`

Round-trip:
- hidden -> visible -> hidden -> always hidden -> hidden

What it proves:
- move commands and classified zones agree

Prerequisite:
- AppleScript commands must no longer return `Accessibility permission is required`

### 4. Debug-build browse rehide probe

Use path-targeted AppleScript against the fresh Debug build:
- `~/Library/Developer/Xcode/DerivedData/.../Build/Products/Debug/SaneBar.app`

Sequence:
- `hide items`
- `show second menu bar`
- wait
- `layout snapshot`
- `close browse panel`
- `layout snapshot`

Expected open snapshot:
- `hidingState = expanded`
- `isBrowseSessionActive = true`
- `isBrowseVisible = true`
- `rehideOnAppChange = true`

This is the proof that the browse panel no longer loses to self-activation rehide.

### 4a. Debug-build browse-origin activation probe

Use the debug or staged canonical app, then run:

```applescript
tell application "SaneBar"
    show second menu bar
    activate browse icon "eu.exelban.Stats::statusItem:2"
end tell
```

Variants:
- `right click browse icon "<id>"`
- use `Wi-Fi`, `Spotlight`, and another `Stats` item in the same matrix

What it proves:
- the browse panel path is using `.browsePanel` activation origin
- multi-item target resolution still works after relayout instead of trusting a stale `statusItemIndex`

### 5. Debug-build prefs restore replay

Use the debug bundle id so the real install stays untouched.

Seed:
- stale main/separator positions
- mismatched stored width
- matching-width backup keys for the current display

Then launch the debug app and confirm:
- main/separator restore to the current-width backup
- calibrated width stamps to the current display

What it proves:
- restore beats ordinal reset on the real launch path

## Known Tooling Trap

Mini `ProdDebug` build can fail before runtime verification with:
- Sparkle framework codesign failure
- `errSecInternalComponent`

That is a signing/toolchain issue, not the menu bar regression itself.

When that happens:
1. keep logic verification on Mini Debug for browse/session checks
2. keep move/smoke verification on the trusted installed app
3. fix signing separately

Also note:
- before March 6, 2026, `test_mode --release` could silently build `Release` and then still launch the `ProdDebug` path
- if old notes say "`test_mode --release` is unreliable", that was true then and no longer should be true after the `sanemaster/test_mode.rb` fix

## Triage Rules

When a new report comes in:

1. Put it in one of `R1-R5`.
2. Apply the matching GitHub root label if the issue is in GitHub:
   - `root:R1 move-classification`
   - `root:R2 browse-rehide`
   - `root:R3 persistence-reset`
   - `root:R4 settings-expectation`
   - `root:R5 detection-host-model`
3. Capture `layout snapshot` and `list icon zones` first.
4. Do not close it until the original reporter confirms on their machine.
5. If the bug mentions:
   - monitor change
   - update
   - restart
   - restore
   start in `StatusBarController.swift`
6. If the bug mentions:
   - browse
   - second menu bar
   - ghost cursor
   - panel opens then closes
   start in `SearchWindowController.swift` and `MenuBarManager+Visibility.swift`
7. If the bug mentions:
   - moved but landed wrong
   - always hidden drift
   - move succeeded but zone is wrong
   start in `MenuBarManager+IconMoving.swift` and `SearchService.swift`
8. If the bug mentions:
   - never appears in Find Icons
   - helper-hosted menu extra
   - Little Snitch
   - Time Machine
   start in `AccessibilityService+Scanning.swift`, `AccessibilityService+SystemWideScanning.swift`, and `SearchService+Diagnostics.swift`

## Exit Criteria

Do not call a persistent regression fixed unless all of these are true:

1. The root cause is named in one of `R1-R5`.
2. The code path is covered by at least one focused test.
3. The Mini full suite passes.
4. At least one Mini runtime check passes on the real interaction path.
5. The verification command is written down here so the next person can rerun it.
