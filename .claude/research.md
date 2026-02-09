# SaneBar Research Cache

## Ice Competitor Analysis

**Updated:** 2026-02-02 | **Status:** verified | **TTL:** 30d
**Source:** GitHub API analysis of jordanbaird/Ice repository

Ice (12.7k stars) is the primary open-source competitor. Key pain points from 158 open issues:
Sequoia display corruption (#722, #711), CPU spikes 30-80% (#713, #704), item reordering broken (#684),
settings not persisting (#676), menu bar flashing (#668), multi-monitor bugs (#630, #517).

SaneBar wins on: stability, CPU (<0.1%), multi-monitor, password lock, per-app rules, import (Bartender+Ice).
Ice wins on: visual layout editor (when it works), Ice Bar dropdown.

---

## Secondary Panel / Dropdown Bar — Implementation Plan

**Updated:** 2026-02-07 | **Status:** approved-for-build | **TTL:** 30d
**Source:** 18 adversarial reviews (6 perspectives x 3 models), Ice source analysis, SaneBar architecture review

**Context:** Customer asked for this feature. We told them we'd look into it.

### Background (Condensed from Sections 1-8)

Ice's "Ice Bar" uses `NSPanel` with `.nonactivatingPanel`, `.level = .mainMenu + 1`, `.fullScreenAuxiliary`.
Positions below menu bar via `screen.frame.maxY - menuBarHeight - panelHeight`. Icon images via
`ScreenCapture.captureWindow()` (requires Screen Recording permission). Click handling: close panel, then
simulate click on actual menu bar item. Known bugs: crashes (#786), Tahoe rendering (#711, #665),
multi-monitor positioning (#517), endless loading (#677).

**SaneBar reusable components:** `SearchWindowController` (floating window + hover suspension),
`AccessibilityService.menuBarOwnersCache` (icon data), `MenuBarSearchView` (icon grid).
**Missing:** below-menu-bar positioning, borderless panel style, bundle icon rendering.

**All 18 critic reviews recommend deferring. If forced: Option B (minimal ~150 lines, reuse SearchWindowController).**

### The 5 Critical Issues + Mitigations

| # | Issue | Mitigation | Location |
|---|-------|------------|----------|
| 1 | HidingService vs Panel state fight | When `useDropdownPanel=true`, keep delimiter expanded always. Never call `hide()`. | `MenuBarManager.toggleHiddenItems()` :715 |
| 2 | Screen Recording permission | Use `NSWorkspace.shared.icon(forFile:)` for bundle icons + `AccessibilityService.menuBarOwnersCache` for names. NO `CGWindowListCreateImage`. | New panel view |
| 3 | HoverService races | Already solved: `SearchWindowController.show()` sets `hoverService.isSuspended = true` (:55). Panel reuses this. Add 300ms debounce before re-enabling on close. | `SearchWindowController.swift:55,76` |
| 4 | Auto-rehide fires during panel | On panel `show()`: call `hidingService.cancelRehide()`. Panel mode = no rehide concept. | `SearchWindowController.show()` |
| 5 | Feature redundancy with Find Icon | Different purposes: Find Icon = search by name (keyboard). Panel = quick visual browse (mouse). Option-click = Find Icon. Left-click = Panel. | UX documentation |

### File-by-File Plan (~150 lines total)

**1. `Core/Services/PersistenceService.swift`** (~10 lines)
- Add `var useDropdownPanel: Bool = false` to `SaneBarSettings` (after `alwaysHiddenPinnedItemIds` ~line 228)
- Add to `CodingKeys` and `init(from:)` with `decodeIfPresent`

**2. `UI/SearchWindow/SearchWindowController.swift`** (~60 lines changed)
- Add `SearchWindowMode` enum: `.findIcon` (current) vs `.panel` (below menu bar, borderless)
- Mode read from `settings.useDropdownPanel` on each `show()` call
- Panel mode: `styleMask: [.borderless, .nonactivatingPanel]`, `level: .mainMenu + 1`,
  `collectionBehavior: [.fullScreenAuxiliary, .ignoresCycle]`, position flush below menu bar
- On mode change: nil the window to force recreation via lazy `createWindow()`
- On `show()`: also call `hidingService.cancelRehide()`

**3. `Core/MenuBarManager.swift`** (~20 lines)
- `toggleHiddenItems()` :715 — early return: if `useDropdownPanel`, call `SearchWindowController.shared.toggle()`
- `showHiddenItemsNow()` :758 — early return: if `useDropdownPanel`, call `SearchWindowController.shared.show()`
- `hideHiddenItems()` :796 — early return: if `useDropdownPanel`, no-op
- On setting change (false→true): force `hidingService.show()` + `cancelRehide()`

**4. `UI/Settings/ExperimentalSettingsView.swift`** (~30 lines)
- `CompactToggle("Dropdown panel for hidden icons", isOn: $settings.useDropdownPanel)`
- Help text explaining it replaces expand/collapse; Find Icon still works
- `onChange`: force delimiter expanded, nil search window for recreation

**5. `UI/SearchWindow/MenuBarSearchView.swift`** (~20 lines)
- Add `RenderingMode` enum: `.searchWindow` (full) vs `.dropdownPanel` (compact, no search bar)
- Panel mode: horizontal icon grid, `NSWorkspace.shared.icon(forFile:)` for images
- Click action: close panel + `NSWorkspace.shared.open(bundleURL)`

**No new files.** All reuses existing infrastructure.

### Edge Cases (v1 vs v2)

| Edge Case | v1 | v2 |
|-----------|----|----|
| Multi-monitor | `NSScreen.main` only | Track mouse, show on active screen |
| Notch | Safe — below `visibleFrame.maxY` | Detect `safeAreaInsets` |
| Fullscreen | `.fullScreenAuxiliary` | Already handled |
| Spaces | Auto-dismiss via `windowDidResignKey` | Add `activeSpaceDidChange` observer |
| Sleep/wake | Auto-closes on resign key | Wake notification to revalidate |
| Rapid toggle | 300ms debounce | Already sufficient |

### Rollback Plan

1. **Sparkle kill switch**: Ship build that forces `useDropdownPanel = false`
2. **User fix**: `defaults write com.sanebar.app useDropdownPanel -bool false`
3. **Code removal**: If <5% usage after 30 days, delete the ~150 lines

### Build Sequence

1. Add `useDropdownPanel` to `SaneBarSettings` + `CodingKeys` + `init(from:)`
2. Add UI toggle in `ExperimentalSettingsView`
3. Add `SearchWindowMode` enum + mode-aware positioning in `SearchWindowController`
4. Add panel routing in `MenuBarManager` toggle/show/hide methods
5. Add compact rendering mode in `MenuBarSearchView`
6. Test: toggle ON -> click icon -> panel appears below menu bar
7. Test: toggle OFF -> original delimiter behavior restored
8. Test: Find Icon (Cmd+Shift+Space) still works in both modes

---

## Icon Moving — Graduated to ARCHITECTURE.md

**Graduated:** 2026-02-09 | All icon moving research (APIs, competitors, bug analysis) moved to `ARCHITECTURE.md` § "Icon Moving Pipeline".

Sections graduated:
- Icon Moving Pipeline — Bug Root Cause Analysis (9 bugs, all fixed)
- Competitor Icon Moving Approaches (Ice, Dozer, Bartender)
- Apple APIs — Menu Bar Icon Positioning (comprehensive dead-end analysis)

---

### Graduated Sections

- **Icon Moving Pipeline** (graduated Feb 9): All API research, competitor analysis, 9-bug RCA → `ARCHITECTURE.md` § "Icon Moving Pipeline"
- **Privacy-First Click Tracking** (implemented Feb 6): Cloudflare Web Analytics + go.saneapps.com Worker deployed
- **Ice Import Service** (implemented Feb 5): `BartenderImportService` extended to import Ice settings via `com.jordanbaird.Ice` plist
- **Tint + Reduce Transparency Bug #34** (implemented Feb 6): Skip Liquid Glass when RT enabled, opacity floor 0.5, live observer via `DistributedNotificationCenter`. 4 commits on main, ships in v1.0.19.
