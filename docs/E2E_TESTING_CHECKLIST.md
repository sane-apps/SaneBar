# SaneBar End-to-End Testing Checklist

Start here for active menu bar regressions:
- `docs/MENU_BAR_RUNTIME_PLAYBOOK.md`
- `docs/RUNTIME_AUDIT_2026-03-18.md`

> **MANDATORY**: Run this checklist before every release. Use tracing tools to verify flows.

Canonical scripted runtime path:
- Use `/Applications/SaneBar.app`.
- Do not launch DerivedData builds, archive exports, or legacy `~/Applications/SaneBar.app` copies directly.
- Before any release-style smoke, dedupe installed/build copies:

```bash
~/SaneApps/infra/SaneProcess/scripts/SaneMaster.rb dedupe_apps --host mini --apps SaneBar
```

- For smoke runs, pin the target explicitly:

```bash
SANEBAR_SMOKE_APP_ID=com.sanebar.app \
SANEBAR_SMOKE_APP_PATH=/Applications/SaneBar.app \
SANEBAR_SMOKE_PROCESS_PATH=/Applications/SaneBar.app/Contents/MacOS/SaneBar \
./Scripts/live_zone_smoke.rb
```

The live smoke now includes a resource watchdog:
- sustained CPU over `120%` fails
- sustained RSS over `1024 MB` fails
- emergency CPU/RSS spikes fail immediately
- a native macOS process sample is written to `/tmp/sanebar_runtime_resource_sample.txt` when the watchdog trips
- launch idle budget: average CPU must settle under `5%`, peak CPU under `15%`, RSS under `128 MB`
- post-smoke idle budget: after an `8s` settle window, average CPU must settle back under `5%`, peak CPU under `20%`, RSS under `128 MB`
- whole-pass stress budget: average CPU must stay under `15%`, average RSS under `192 MB`
- second-menu-bar activation must stay open for both left-click and right-click browse flows
- the script-based browse activation lane must use the same idle-close protection as the real panel UI lane

If the Mini falls back to an unsigned `~/Applications/SaneBar.app` build because headless signing is blocked:
- keep that copy only for current-tree debug checks
- preserve `/Applications/SaneBar.app` as the signed/trusted release baseline
- use the signed `/Applications` app for release-style smoke unless you have a freshly trusted signed current build

## Critical Runtime Regression Matrix

These checks are mandatory for the current startup / browse / move bug class. Do not call this class fixed without them.

The source of truth is `Tests/CustomerUIActions.yml` under `runtime_state_matrix`. This checklist is only the human-readable summary. Release proof must cover the standard rows: `upgrade_update`, `cold_launch_relaunch`, `wake_unlock`, `display_topology`, `fullscreen_maximize_transition`, `basic_pro_mode`, and `support_report_media`.

| Check | Why it exists | Must prove |
|------|------|------|
| Cold-start restore with valid current-width backup and poisoned `main=0 / separator=1` | Catches startup recovery collapse family (`#111/#113/#114/#115`) | backup restore beats ordinal reseed, visible lane stays sane |
| Cold-start with `autoRehide=false` | Catches hidden-after-launch regressions | no initial hide after deferred setup |
| Right-click browse focus integrity | Catches `#116` | failed browse activation never changes frontmost app/window |
| Hidden-visible move under stale geometry | Catches wrong-zone false success | retry or fail cleanly, never report wrong success |
| Shared-bundle exact-ID move | Catches `#117` class drift | requested `unique_id` is what moved, not a sibling |
| Restart/update recovery replay | Catches persistence drift | current-width backup survives relaunch and autosave churn |
| Fullscreen/maximize transition | Catches transient menu-bar repaint/blackout during normal window transitions | appearance suppression ignores transient fullscreen/maximize windows and restores color correctly |
| Basic/Pro action parity | Catches silent gated-action drift | Basic clearly gates Pro-only work; Pro completes and persists the same action |
| Support report media path | Catches bug reports that cannot reach support | oversized media uses the safe file-sharing/manual-upload path instead of an oversized email attachment |

Release rule:
- if smoke says `No movable candidate icon found; skipping move checks`, treat that as incomplete coverage, not a pass
- if browse diagnostics show `workspace activation fallback` during browse-panel right-click, treat that as a failure even if the panel stayed visible
- release preflight on the Mini should now run `scripts/startup_layout_probe.rb` automatically after browse smoke, not as an optional manual step

## Pre-Test Setup

```bash
# 1. Build and launch fresh
./scripts/SaneMaster.rb test_mode

# 2. Generate button map (see all UI controls)
./scripts/button_map.rb

# 3. Trace specific function (if debugging)
./scripts/trace_flow.rb <function_name>
```

---

## 🖱️ CORE INTERACTIONS

### 1. Left-Click on SaneBar Icon
**Flow**: `statusItemClicked → toggleHiddenItems → [auth check] → hidingService.toggle()`

| Test | Expected | ✓ |
|------|----------|---|
| Click icon when hidden → icons reveal | Hidden icons appear to LEFT of separator | |
| Click icon when expanded → icons hide | Hidden icons disappear | |
| With auth enabled → prompts for password | Touch ID / password dialog appears | |

### 2. Right-Click Menu
**Flow**: `statusItemClicked → showStatusMenu`

| Test | Expected | ✓ |
|------|----------|---|
| Right-click shows menu | Menu with Find Icon, Settings, Quit appears | |
| "Find Icon..." opens search | Search window opens | |
| "Settings..." opens settings | Settings window opens | |
| "Check for Updates..." works | Sparkle update check runs | |
| "Quit SaneBar" quits | App terminates | |

### 3. Option-Click
| Test | Expected | ✓ |
|------|----------|---|
| Option+click opens settings | Settings window opens directly | |

---

## ⚙️ SETTINGS - GENERAL TAB

### Show Dock Icon
**Binding**: `menuBarManager.settings.showDockIcon`

| Test | Expected | ✓ |
|------|----------|---|
| Toggle ON → dock icon appears | SaneBar icon visible in Dock | |
| Toggle OFF → dock icon hidden | No SaneBar in Dock | |

### Require Password
**Binding**: `menuBarManager.settings.requireAuthToShowHiddenIcons`

| Test | Expected | ✓ |
|------|----------|---|
| Toggle ON → auth required to reveal | Left-click prompts for Touch ID | |
| Toggle OFF → no auth needed | Left-click reveals immediately | |
| Does NOT auto-reveal when toggled | Icons stay hidden after toggle | |

### Auto-Check for Updates
**Binding**: `menuBarManager.settings.checkForUpdatesAutomatically`

| Test | Expected | ✓ |
|------|----------|---|
| Toggle ON → Sparkle checks at launch | Update check on next launch | |
| Toggle OFF → no auto-check | Must manually check | |

---

## ⚙️ SETTINGS - RULES TAB

### Auto-Rehide After Reveal
**Binding**: `menuBarManager.settings.autoRehide`

| Test | Expected | ✓ |
|------|----------|---|
| Toggle ON → icons hide after delay | Icons auto-hide after set seconds | |
| Toggle OFF → icons stay revealed | Must manually click to hide | |
| Delay slider changes timing | Verify 1s, 3s, 5s delays work | |

### Show on Hover
**Binding**: `menuBarManager.settings.showOnHover`
**Flow**: `HoverService.onTrigger → showHiddenItemsNow`

| Test | Expected | ✓ |
|------|----------|---|
| Toggle ON → hover reveals icons | Mouse near separator reveals | |
| Toggle OFF → hover does nothing | Must click to reveal | |
| Delay slider works | Verify hover delay timing | |

### Show on Scroll
**Binding**: `menuBarManager.settings.showOnScroll`

| Test | Expected | ✓ |
|------|----------|---|
| Toggle ON → scroll in menu bar reveals | Scroll gesture reveals icons | |
| Toggle OFF → scroll does nothing | Scroll has no effect | |

### Show on Low Battery
**Binding**: `menuBarManager.settings.showOnLowBattery`
**Flow**: `TriggerService.checkBatteryLevel → showHiddenItems`

| Test | Expected | ✓ |
|------|----------|---|
| Toggle ON → reveals at 20% battery | Test with battery simulation | |
| Toggle OFF → no battery trigger | Battery level ignored | |

### Show on App Launch
**Binding**: `menuBarManager.settings.showOnAppLaunch`
**Flow**: `TriggerService.handleAppLaunch → showHiddenItems`

| Test | Expected | ✓ |
|------|----------|---|
| Toggle ON + add app → launch reveals | Start selected app, icons reveal | |
| Toggle OFF → app launch ignored | Apps don't trigger reveal | |
| App picker adds/removes apps | Apps appear in list correctly | |

### Show on Network Change
**Binding**: `menuBarManager.settings.showOnNetworkChange`
**Flow**: `NetworkTriggerService.handleNetworkChange → showHiddenItems`

| Test | Expected | ✓ |
|------|----------|---|
| Toggle ON + add network → reveals | Connect to listed WiFi, icons reveal | |
| Toggle OFF → network changes ignored | WiFi changes don't trigger | |
| Network picker adds/removes SSIDs | SSIDs appear in list | |

---

## ⚙️ SETTINGS - APPEARANCE TAB

### Divider Style
**Binding**: `menuBarManager.settings.dividerStyle`

| Test | Expected | ✓ |
|------|----------|---|
| Slash (/) selected | Separator shows "/" | |
| Backslash (\) selected | Separator shows "\" | |
| Pipe (|) selected | Separator shows "|" | |
| Thin Pipe selected | Separator shows thin "❘" | |
| Dot selected | Separator shows dot | |

### Spacer Count (0-12)
**Binding**: `menuBarManager.settings.spacerCount`

| Test | Expected | ✓ |
|------|----------|---|
| Set to 0 → no extra spacers | Only main + separator visible | |
| Set to 3 → three spacers appear | Three "│" or "•" in menu bar | |
| Set to 12 (max) → twelve spacers | All 12 visible in menu bar | |

### Spacer Style (when count > 0)
**Binding**: `menuBarManager.settings.spacerStyle`

| Test | Expected | ✓ |
|------|----------|---|
| Line style → "│" characters | Vertical line spacers | |
| Dot style → "•" characters | Dot spacers | |

### Spacer Width
**Binding**: `menuBarManager.settings.spacerWidth`

| Test | Expected | ✓ |
|------|----------|---|
| Compact → narrow spacing | 8px wide spacers | |
| Normal → medium spacing | 12px wide spacers | |
| Wide → wide spacing | 20px wide spacers | |

### Menu Bar Appearance (Visual Zones)
**Binding**: `menuBarManager.settings.menuBarAppearance.*`

| Test | Expected | ✓ |
|------|----------|---|
| Enable appearance → overlay visible | Tinted background on menu bar | |
| Disable → no overlay | Standard menu bar | |
| Liquid Glass toggle | Blur effect on/off | |
| Shadow toggle | Drop shadow on/off | |
| Border toggle | Border line on/off | |
| Rounded corners toggle | Rounded vs square corners | |

---

## 🔍 FIND ICON (Search Window)

| Test | Expected | ✓ |
|------|----------|---|
| Cmd+Shift+Space opens window | Search window appears | |
| Typing filters results | App list filters in real-time | |
| Arrow keys navigate | Selection moves up/down | |
| Enter/click activates | Selected app comes to front | |
| Escape closes | Window closes | |

---

## 🔧 TRACING TOOLS REFERENCE

### button_map.rb
Shows ALL UI controls and their bindings:
```bash
./scripts/button_map.rb
```

### trace_flow.rb
Search for specific functions:
```bash
./scripts/trace_flow.rb toggleHiddenItems
./scripts/trace_flow.rb showOnHover
```

### Class Diagram
Visual architecture: `docs/class_diagram.png`

---

## 🐛 COMMON FAILURE MODES

| Symptom | Likely Cause | Check |
|---------|--------------|-------|
| Toggle doesn't persist | Settings not saving | Check `saveSettings()` call |
| Toggle reveals icons unexpectedly | Settings observer side effect | Check `$settings` sink |
| Spacers not visible | Count is 0 or positions wrong | Check `spacerCount` value |
| Auth bypassed | Trigger path skips auth | Trace flow to `authenticate()` |
| Menu bar overlay missing | Appearance disabled | Check `isEnabled` flag |

---

## Post-Test

```bash
# Verify no crashes in logs
./scripts/SaneMaster.rb logs --tail 50

# Check for warnings
log show --predicate 'subsystem == "com.sanebar.app"' --last 5m --style compact
```

**Sign-off**: All tests passing? Ship it! 🚀
