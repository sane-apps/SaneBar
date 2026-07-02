# SaneBar End-to-End Testing Checklist

This is a manual, per-setting end-to-end pass over the real app: launch a build, exercise each control, and verify the observable result in the menu bar.

- Launch a build for testing with `./Scripts/SaneMaster.rb test_mode`.
- `Scripts/live_zone_smoke.rb` is the automated cousin of this checklist (maintainer tooling for scripted browse/move smoke).
- For active menu bar regressions, start with `docs/MENU_BAR_RUNTIME_PLAYBOOK.md`.

## Pre-Test Setup

```bash
# 1. Build and launch fresh
./Scripts/SaneMaster.rb test_mode

# 2. Generate button map (see all UI controls)
./Scripts/button_map.rb

# 3. Trace specific function (if debugging)
rg "function_name" Core UI Tests
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
./Scripts/button_map.rb
```

### Source Search
Search for specific functions:
```bash
rg "toggleHiddenItems" Core UI Tests
rg "showOnHover" Core UI Tests
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
./Scripts/SaneMaster.rb logs --tail 50

# Check for warnings
log show --predicate 'subsystem == "com.sanebar.app"' --last 5m --style compact
```

**Sign-off**: All tests passing? Ship it! 🚀
