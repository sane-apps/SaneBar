# SaneBar Research Cache

## Off-Screen Menu Bar Icon After Cmd-Drag (Machine-Specific)

**Updated:** 2026-02-17 | **Status:** verified | **TTL:** 30d
**Source:** Local reproduction + ByHost prefs inspection + script launch path verification

- Repro context: command-dragging SaneBar out of the menu bar during failure-mode testing left machine in persistent bad state.
- Old ByHost keys remained poisoned:
  - `NSStatusItem Preferred Position SaneBar_main_v6 = 1310`
  - `NSStatusItem Preferred Position SaneBar_separator_v6 = 1286`
- Key finding: installer-like signed launches worked, while local script default `Debug` launch path could stay invisible on this machine.
- Root cause in tooling: shared SaneMaster launch path always launched `Debug` from DerivedData.
- Fixes applied:
  1. `StatusBarController` autosave namespace moved to `v7` (`SaneBar_Main_v7`, etc.) so old poisoned key namespace is ignored.
  2. SaneMaster launch updated to support `--proddebug` / `--release`.
  3. SaneBar default launch locked to signed mode (`ProdDebug`) to avoid regression to broken `Debug` behavior.
- Validation:
  - `./scripts/SaneMaster.rb launch --proddebug` launches `.../Build/Products/ProdDebug/SaneBar.app`.
  - Active keys show healthy values in new namespace:
    - `SaneBar_main_v7_v6 = 0`
    - `SaneBar_separator_v7_v6 = 1`

## Ice Competitor Analysis

**Updated:** 2026-02-02 | **Status:** verified | **TTL:** 30d
**Source:** GitHub API analysis of jordanbaird/Ice repository

Ice (12.7k stars) is the primary open-source competitor. Key pain points from 158 open issues:
Sequoia display corruption (#722, #711), CPU spikes 30-80% (#713, #704), item reordering broken (#684),
settings not persisting (#676), menu bar flashing (#668), multi-monitor bugs (#630, #517).

SaneBar wins on: stability, CPU (<0.1%), multi-monitor, password lock, per-app rules, import (Bartender+Ice).
Ice wins on: visual layout editor (when it works), Ice Bar dropdown.

---

## Stale Position / Duplicate Icons Bug

**Updated:** 2026-02-13 | **Status:** active-investigation | **TTL:** 7d
**Source:** Codebase analysis (Second Menu Bar, SearchService, AccessibilityService, MenuBarManager+AlwaysHidden)

### Problem Summary

The "Second Menu Bar" (floating panel showing hidden icons) sometimes displays **duplicate entries** on startup:
- The same app appears in BOTH "hidden" and "always hidden" sections simultaneously
- Moving an app (right-click → move to section) fixes the duplicates
- The stale data is visible BEFORE user interaction

### Code Path Analysis

#### 1. Second Menu Bar Data Flow (Where the Bug Manifests)

**UI Component:** `UI/SearchWindow/SecondMenuBarView.swift`

The panel displays three sections (lines 116-134):
```swift
if !movableVisible.isEmpty {
    zoneRow(label: "Visible", icon: "eye", apps: movableVisible, zone: .visible)
}
if !movableHidden.isEmpty {
    zoneRow(label: "Hidden", icon: "eye.slash", apps: movableHidden, zone: .hidden)
}
if !movableAlwaysHidden.isEmpty {
    zoneRow(label: "Always Hidden", icon: "lock", apps: movableAlwaysHidden, zone: .alwaysHidden)
}
```

**Data Source:** `UI/SearchWindow/MenuBarSearchView.swift` lines 250-262
```swift
SecondMenuBarView(
    visibleApps: visibleApps,           // ← Cached data
    apps: filteredApps,                 // ← "Hidden" section (menuBarApps filtered)
    alwaysHiddenApps: alwaysHiddenApps, // ← Cached data
    // ...
)
```

**Cache Loading:** Lines 283-309
```swift
private func loadCachedApps() {
    hasAccessibility = AccessibilityService.shared.isGranted
    guard hasAccessibility else { /* ... */ return }

    // Load "hidden" apps (middle section)
    menuBarApps = service.cachedHiddenMenuBarApps()

    // Load all zones for second menu bar
    if isSecondMenuBar {
        visibleApps = service.cachedVisibleMenuBarApps()
        alwaysHiddenApps = service.cachedAlwaysHiddenMenuBarApps()
    }
}
```

**Key Insight:** The panel uses THREE separate cached data sources. If any cache is stale or uses inconsistent classification logic, duplicates can occur.

#### 2. Zone Classification Logic (Where Duplicates Originate)

**Service:** `Core/Services/SearchService.swift`

All three cache methods use the SAME classification function `classifyZone()` (lines 126-147):

```swift
private func classifyZone(
    itemX: CGFloat,
    itemWidth: CGFloat?,
    separatorX: CGFloat,
    alwaysHiddenSeparatorX: CGFloat?
) -> VisibilityZone {
    let width = max(1, itemWidth ?? 22)
    let midX = itemX + (width / 2)
    let margin: CGFloat = 6

    if let alwaysHiddenSeparatorX {
        if midX < (alwaysHiddenSeparatorX - margin) {
            return .alwaysHidden
        }
        if midX < (separatorX - margin) {
            return .hidden
        }
        return .visible
    }

    return midX < (separatorX - margin) ? .hidden : .visible
}
```

**Separator Position Retrieval (CRITICAL):** Lines 82-105
```swift
private func separatorOriginsForClassification() -> (separatorX: CGFloat, alwaysHiddenSeparatorX: CGFloat?)? {
    guard let separatorX = separatorOriginXForClassification() else { return nil }

    guard MenuBarManager.shared.alwaysHiddenSeparatorItem != nil else {
        return (separatorX, nil)
    }

    let alwaysHiddenSeparatorX = MenuBarManager.shared.getAlwaysHiddenSeparatorOriginX()

    // ← VALIDATION: Ensure AH separator is LEFT of main separator
    if let alwaysHiddenSeparatorX, alwaysHiddenSeparatorX >= separatorX {
        logger.warning("Always-hidden separator is not left of main separator; ignoring always-hidden zone")
        return (separatorX, nil)
    }

    // ← FALLBACK: If AH separator position unavailable (at 10,000px blocking mode)
    if alwaysHiddenSeparatorX == nil {
        let screenMinX = menuBarScreenFrame()?.minX ?? 0
        return (separatorX, screenMinX)  // ← Uses screen edge as boundary
    }

    return (separatorX, alwaysHiddenSeparatorX)
}
```

#### 3. The Fallback Mechanism (Where Stale Data Persists)

**Always-Hidden Fallback:** Lines 217-241 in `SearchService.swift`

When separator positions are unavailable (items off-screen, separators at blocking mode):
```swift
func cachedAlwaysHiddenMenuBarApps() -> [RunningApp] {
    guard MenuBarManager.shared.alwaysHiddenSeparatorItem != nil else { return [] }
    let items = AccessibilityService.shared.cachedMenuBarItemsWithPositions()

    if let positions = separatorOriginsForClassification(), positions.alwaysHiddenSeparatorX != nil {
        // ← POSITION-BASED classification (primary)
        let apps = items.filter { /* classifyZone() */ }
        return apps
    }

    // ← FALLBACK: Match against persisted pinned IDs
    return appsMatchingPinnedIds(from: items.map(\.app))
}
```

**Pinned IDs Matching:** Lines 107-118
```swift
private func appsMatchingPinnedIds(from apps: [RunningApp]) -> [RunningApp] {
    let pinnedIds = Set(MenuBarManager.shared.settings.alwaysHiddenPinnedItemIds)
    guard !pinnedIds.isEmpty else { return [] }
    let matched = apps.filter { app in
        pinnedIds.contains(app.uniqueId) || pinnedIds.contains(app.bundleId)
    }
    logger.debug("alwaysHidden fallback: matched \(matched.count) apps from \(pinnedIds.count) pinned IDs")
    return matched
}
```

**Key Issue:** The fallback uses `alwaysHiddenPinnedItemIds` (persisted in UserDefaults) which may be STALE if:
1. App moved but pinned IDs not updated
2. Separator positions changed but cache not invalidated
3. Startup reads cache before positions are available

#### 4. Persisted Pin Management (Where Stale Data Is Written)

**Service:** `Core/MenuBarManager+AlwaysHidden.swift`

**Pin Addition:** Lines 18-30
```swift
func pinAlwaysHidden(app: RunningApp) {
    let id = app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValidPinId(id) else { return }

    var newIds = Set(settings.alwaysHiddenPinnedItemIds)
    let inserted = newIds.insert(id).inserted
    guard inserted else { return }

    settings.alwaysHiddenPinnedItemIds = Array(newIds).sorted()
    // ← NO cache invalidation here
}
```

**Pin Removal:** Lines 32-40
```swift
func unpinAlwaysHidden(app: RunningApp) {
    let id = app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return }

    let newIds = settings.alwaysHiddenPinnedItemIds.filter { $0 != id }
    guard newIds.count != settings.alwaysHiddenPinnedItemIds.count else { return }
    settings.alwaysHiddenPinnedItemIds = newIds
    // ← NO cache invalidation here
}
```

**CRITICAL FINDING:** Neither `pinAlwaysHidden()` nor `unpinAlwaysHidden()` calls `AccessibilityService.shared.invalidateMenuBarItemCache()`. This means:
1. User moves app from "hidden" to "always hidden" → pin is added
2. `SearchService` caches remain unchanged (still have old zone assignments)
3. Next panel open: `cachedAlwaysHiddenMenuBarApps()` uses NEW pinned IDs, `cachedHiddenMenuBarApps()` uses OLD cached positions
4. Result: App appears in BOTH sections

#### 5. Move Operations (Where Cache Gets Stale)

**UI Handler:** `UI/SearchWindow/SecondMenuBarView.swift` lines 189-230

```swift
private func moveIcon(_ app: RunningApp, from source: IconZone, to target: IconZone) {
    // ... determine operation based on source/target zones

    switch (source, target) {
    case (_, .visible):
        if source == .alwaysHidden { menuBarManager.unpinAlwaysHidden(app: app) }
        _ = menuBarManager.moveIcon(/* ... */, toHidden: false)

    case (.visible, .hidden):
        _ = menuBarManager.moveIcon(/* ... */, toHidden: true)

    case (.alwaysHidden, .hidden):
        menuBarManager.unpinAlwaysHidden(app: app)  // ← Removes from pinned IDs
        _ = menuBarManager.moveIconFromAlwaysHiddenToHidden(/* ... */)

    case (_, .alwaysHidden):
        menuBarManager.pinAlwaysHidden(app: app)    // ← Adds to pinned IDs
        _ = menuBarManager.moveIconToAlwaysHidden(/* ... */)
    }

    // ← REFRESH: Scheduled AFTER the move completes
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        onIconMoved?()  // ← Calls loadCachedApps() + refreshApps(force: true)
    }
}
```

**The 300ms Gap:** Between pin update and cache refresh, there's a 300ms window where:
- Pinned IDs are updated (new data)
- Accessibility cache is stale (old positions)
- If user closes panel or system queries cache during this window → duplicates appear

#### 6. Startup Sequence (Where Initial Stale Data Appears)

**Panel Opens:** `UI/SearchWindow/MenuBarSearchView.swift` lines 142-153

```swift
.onAppear {
    loadCachedApps()     // ← Uses cached data (may be empty/stale on first launch)
    refreshApps()        // ← Triggers async refresh (takes time)
    startPermissionMonitoring()
    // ...
}
```

**Cache Loading Flow:**
1. `loadCachedApps()` runs immediately (line 143) → reads `AccessibilityService.shared.cachedMenuBarItemsWithPositions()`
2. If cache is empty (first run) → all arrays are empty
3. If cache exists but positions are stale → classification uses OLD separator positions + NEW pinned IDs
4. `refreshApps()` runs async (line 144) → triggers fresh AX scan
5. **GAP:** Between `loadCachedApps()` and `refreshApps()` completing, panel shows stale data

**Why Moving Fixes It:** Lines 258-261 in SecondMenuBarView
```swift
onIconMoved: {
    loadCachedApps()           // ← Re-loads from cache
    refreshApps(force: true)   // ← Forces fresh AX scan + invalidates cache
}
```

The `force: true` parameter (line 324 in MenuBarSearchView) calls `AccessibilityService.shared.invalidateMenuBarItemCache()` BEFORE scanning.

### Root Cause Summary

**PRIMARY ISSUE: Cache invalidation missing on pin update**

1. **Inconsistent Data Sources:** Three separate caches (visible, hidden, always-hidden) + one persisted data source (pinned IDs)
2. **No Invalidation on Pin Change:** `pinAlwaysHidden()` and `unpinAlwaysHidden()` update persisted IDs but don't invalidate AX cache
3. **Fallback Mismatch:** `cachedAlwaysHiddenMenuBarApps()` uses NEW pinned IDs (fallback), `cachedHiddenMenuBarApps()` uses OLD cached positions (primary)
4. **Startup Race:** Panel opens before AX cache is populated → falls back to pinned IDs for AH, empty for hidden → inconsistent state
5. **Async Refresh Gap:** 300ms+ between panel open and fresh data → user sees stale duplicates

**Why Moving Fixes It:**
- Move operation calls `refreshApps(force: true)`
- `force: true` → `invalidateMenuBarItemCache()` → all caches cleared
- Fresh AX scan → all zones use SAME current separator positions → duplicates resolved

### Validation Missing

**No Duplicate Detection:** The code has identity health logging (SearchService.swift:381-407) but it only logs duplicates, doesn't PREVENT them from being rendered.

```swift
if !duplicateIds.isEmpty {
    let sample = duplicateIds.prefix(10).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    logger.error("Find Icon \(context): DUPLICATE ids detected: \(sample)")
}
```

This logs the issue but doesn't deduplicate before passing to UI.

### Recommended Fixes

#### Fix 1: Invalidate Cache on Pin Update (CRITICAL)

**File:** `Core/MenuBarManager+AlwaysHidden.swift` (lines 18-40)

Add cache invalidation to both pin methods:

```swift
func pinAlwaysHidden(app: RunningApp) {
    let id = app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValidPinId(id) else { return }

    var newIds = Set(settings.alwaysHiddenPinnedItemIds)
    let inserted = newIds.insert(id).inserted
    guard inserted else { return }

    settings.alwaysHiddenPinnedItemIds = Array(newIds).sorted()

    // ← ADD: Invalidate cache so next query uses fresh positions + new pins
    AccessibilityService.shared.invalidateMenuBarItemCache()
}

func unpinAlwaysHidden(app: RunningApp) {
    let id = app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return }

    let newIds = settings.alwaysHiddenPinnedItemIds.filter { $0 != id }
    guard newIds.count != settings.alwaysHiddenPinnedItemIds.count else { return }
    settings.alwaysHiddenPinnedItemIds = newIds

    // ← ADD: Invalidate cache so next query uses fresh positions + new pins
    AccessibilityService.shared.invalidateMenuBarItemCache()
}
```

**Rationale:** Ensures that after pinned IDs change, the next cache read triggers a fresh AX scan with consistent data.

#### Fix 2: Deduplicate Before Rendering (MEDIUM PRIORITY)

**File:** `Core/Services/SearchService.swift` (lines 184-215, 244-268, 217-241)

Add deduplication to the three cache methods:

```swift
@MainActor
func cachedHiddenMenuBarApps() -> [RunningApp] {
    let items = AccessibilityService.shared.cachedMenuBarItemsWithPositions()
    // ... existing classification logic ...

    // ← ADD: Deduplicate by uniqueId before returning
    var seen = Set<String>()
    let deduplicated = apps.filter { app in
        seen.insert(app.uniqueId).inserted
    }

    if apps.count != deduplicated.count {
        logger.warning("cachedHidden: Deduped \(apps.count - deduplicated.count) duplicate entries")
    }

    return deduplicated
}
```

Apply same pattern to `cachedVisibleMenuBarApps()` and `cachedAlwaysHiddenMenuBarApps()`.

**Rationale:** Defensive programming — even if cache invalidation fails, UI won't show duplicates.

#### Fix 3: Startup Cache Validation (LOW PRIORITY)

**File:** `UI/SearchWindow/MenuBarSearchView.swift` (lines 283-309)

Add validation on startup to detect stale cache:

```swift
private func loadCachedApps() {
    hasAccessibility = AccessibilityService.shared.isGranted
    guard hasAccessibility else { /* ... */ return }

    // ← ADD: Check if cache is stale (timestamp check)
    let cacheAge = Date().timeIntervalSince(AccessibilityService.shared.menuBarItemCacheTime)
    let isStale = cacheAge > 5.0  // 5 seconds

    if isStale {
        logger.debug("Cache is stale (\(cacheAge)s old) — skipping loadCachedApps")
        refreshApps(force: true)
        return
    }

    // ... existing cache loading logic ...
}
```

**Rationale:** On panel open, if cache is old (>5s), skip it and go straight to fresh scan.

#### Fix 4: Unified Zone Classification (ARCHITECTURAL, LOW PRIORITY)

**Create:** `Core/Services/MenuBarZoneClassifier.swift`

Centralize all zone classification logic in ONE place:

```swift
actor MenuBarZoneClassifier {
    // Single source of truth for separator positions
    // Single classification method used by ALL cache queries
    // Guarantees consistency across visible/hidden/always-hidden
}
```

**Rationale:** Current design has classification logic duplicated across SearchService, move operations, and verification. Centralizing prevents drift.

### Test Plan

**Reproduce:**
1. Launch SaneBar fresh install
2. Move an app to "always hidden" via context menu
3. Close Second Menu Bar panel
4. Wait 1 second (let cache partially settle)
5. Open Second Menu Bar panel again
6. **Expected Bug:** App appears in BOTH "hidden" AND "always hidden" sections

**Verify Fix 1:**
1. Apply cache invalidation to `pinAlwaysHidden()`
2. Repeat steps 1-5
3. **Expected:** App appears ONLY in "always hidden" section (no duplicates)

**Verify Fix 2:**
1. Inject duplicate into cache manually (for testing)
2. Open panel
3. **Expected:** Deduplication removes duplicate before rendering

**Check Logs:**
```
[DEBUG] cachedAlwaysHidden: found X always hidden apps
[DEBUG] cachedHidden: found Y hidden apps
[DEBUG] Find Icon sample: id=... bundleId=... (verify no duplicates)
```

### Related Files

- `UI/SearchWindow/SecondMenuBarView.swift` — Panel rendering (where duplicates appear)
- `UI/SearchWindow/MenuBarSearchView.swift` — Data loading (loadCachedApps, refreshApps)
- `Core/Services/SearchService.swift` — Zone classification + caching (root logic)
- `Core/MenuBarManager+AlwaysHidden.swift` — Pin management (missing invalidation)
- `Core/Services/AccessibilityService+Cache.swift` — Cache invalidation mechanism
- `Core/Services/AccessibilityService+Scanning.swift` — Menu bar item scanning
- `Core/Models/RunningApp.swift` — uniqueId generation (used for deduplication)

---

## Icon Sizing in Squircle - Root Cause

**Updated:** 2026-02-13 | **Status:** verified | **TTL:** 7d
**Source:** SecondMenuBarView.swift, MenuBarAppTile.swift, RunningApp.swift, AccessibilityService+Scanning.swift

### Problem

Icons inside translucent squircle containers appear TINY — not filling 80-90% of the container as intended. The code sets `tileSize: CGFloat = 32` and `iconSize: CGFloat { tileSize * 0.85 }` (= 27.2), using `.frame(width: iconSize, height: iconSize)` with `.resizable()` and `.aspectRatio(contentMode: .fit)`.

### Root Cause: NSImage Source Size

**Menu bar status item icons are small by design:**
- System menu bar icons are typically 16x16 or 18x18 points (template images)
- Third-party app icons come from `NSRunningApplication.icon` which is 32x32 or 64x64 points
- Control Center/SystemUIServer icons are SF Symbols at 16pt configured size (line 235 in RunningApp.swift)

**How icons are captured:**
1. **Regular apps:** `RunningApp(app: app)` → `icon = app.icon` (line 325 in RunningApp.swift) — uses `NSRunningApplication.icon`
2. **System menu extras:** `menuExtraItem()` → `NSImage(systemSymbolName:)` with `pointSize: 16` (line 235 in RunningApp.swift)
3. **No upscaling applied during capture** — icons are stored at their native size

**Why they appear tiny in the squircle:**

**PanelIconTile (SecondMenuBarView.swift lines 316-327):**
```swift
private let tileSize: CGFloat = 32
private var iconSize: CGFloat { tileSize * 0.85 }  // = 27.2

iconImage
    .frame(width: iconSize, height: iconSize)  // 27.2 × 27.2 frame
```

**The icon image rendering (lines 350-363):**
```swift
if let icon = app.iconThumbnail ?? app.icon {
    Image(nsImage: icon)
        .resizable()                           // Makes it resizable
        .renderingMode(...)
        .foregroundStyle(.primary)
        .aspectRatio(contentMode: .fit)        // Fit within frame
}
```

**The problem:**
- `.resizable()` + `.aspectRatio(contentMode: .fit)` does NOT upscale — it only ensures the image fits within the frame while preserving aspect ratio
- An 18x18 NSImage inside a 27.2x27.2 frame renders at 18x18 (native size) — it does NOT scale up to fill the frame
- SwiftUI respects the NSImage's intrinsic size and won't upscale unless forced

### How Find Icon Handles This (MenuBarAppTile.swift)

**MenuBarAppTile uses a SMALLER percentage:**

Lines 54-55:
```swift
.aspectRatio(contentMode: .fit)
.frame(width: iconSize * 0.7, height: iconSize * 0.7)  // 70% of tile, not 85%
```

**Why this works better:**
- The icon frame is intentionally SMALLER than the icon's native size
- `.fit` scales DOWN (which SwiftUI does reliably) rather than expecting upscaling
- Result: Icons appear appropriately sized within the larger tile

**Find Icon also has a squircle background (line 39):**
```swift
RoundedRectangle(cornerRadius: max(8, iconSize * 0.18))
    .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
```

But the icon itself is only 70% of the tile size, creating visual breathing room.

### The Fix: Scale DOWN, Not UP

**Option 1: Match Find Icon pattern (RECOMMENDED)**

Change PanelIconTile icon frame to 70% instead of 85%:

```swift
private var iconSize: CGFloat { tileSize * 0.7 }  // 22.4 instead of 27.2
```

**Rationale:**
- Makes icons appear proportionally similar to Find Icon
- Relies on scaling down (which SwiftUI handles correctly)
- Provides visual breathing room inside the squircle

**Option 2: Force upscaling with interpolation**

Keep 85% frame but force high-quality upscaling:

```swift
iconImage
    .resizable()
    .interpolation(.high)                      // ← ADD: Explicit interpolation
    .renderingMode(...)
    .foregroundStyle(.primary)
    .aspectRatio(contentMode: .fill)           // ← CHANGE: .fill instead of .fit
    .frame(width: iconSize, height: iconSize)
```

**Rationale:**
- `.fill` forces the image to fill the frame (may crop if aspect ratio doesn't match)
- `.interpolation(.high)` ensures upscaling uses high-quality filtering
- Risk: Template icons may look blurry when upscaled 1.5x (18 → 27)

**Option 3: Pre-render thumbnails at target size**

Generate thumbnails at 27x27 when creating RunningApp:

```swift
// In AccessibilityService+Scanning.swift line 283
let appModel = RunningApp(app: app, ...).withThumbnail(size: 27)
```

**Rationale:**
- `withThumbnail()` already exists (RunningApp.swift line 176)
- Pre-rendered thumbnails are sharp and sized correctly
- Cost: Adds thumbnail generation overhead during scanning
- Current code skips thumbnail generation intentionally (comment on line 284: "Skip thumbnail pre-calculation — let UI render lazily")

### Recommended Solution

**Use Option 1:** Change `iconSize` to `tileSize * 0.7`

**Why:**
- Simplest fix (one line change)
- Consistent with Find Icon (proven pattern)
- No upscaling quality concerns
- No performance overhead

**Code change:**

File: `UI/SearchWindow/SecondMenuBarView.swift` line 318

```swift
private var iconSize: CGFloat { tileSize * 0.7 }  // Was 0.85
```

### Related Code

- **Icon capture:** Core/Models/RunningApp.swift lines 234-240 (SF Symbols at 16pt), line 325 (NSRunningApplication.icon)
- **Thumbnail generation:** Core/Models/RunningApp.swift lines 154-173 (`thumbnail(size:)` method)
- **Squircle rendering:** UI/SearchWindow/SecondMenuBarView.swift lines 306-363 (PanelIconTile)
- **Find Icon comparison:** UI/SearchWindow/MenuBarAppTile.swift lines 34-75 (uses 70% sizing)

---

## Tooltip Not Showing - Root Cause

**Updated:** 2026-02-13 | **Status:** verified | **TTL:** 7d
**Source:** Web research, GitHub code search (Claude Island NSPanel implementation), SaneBar codebase analysis

### Problem

SwiftUI `.help("text")` tooltips on PanelIconTile views are NOT appearing at all. The Second Menu Bar panel is a borderless NSPanel (KeyablePanel) at window level `.statusBar`, and `NSInitialToolTipDelay` is set to 100ms in `applicationDidFinishLaunching`.

### Investigation Summary

1. **NSInitialToolTipDelay Usage:** CORRECT
   - Set in `SaneBarApp.swift:19`: `UserDefaults.standard.set(100, forKey: "NSInitialToolTipDelay")`
   - This is the correct key name and usage (verified via [Componentix blog](https://componentix.com/blog/20/change-tooltip-display-delay-in-cocoa-application/))
   - Default macOS delay is 1000ms; setting 100ms is valid and should work

2. **SwiftUI .help() Modifier:** CORRECTLY APPLIED
   - Applied in `SecondMenuBarView.swift:334`: `.help(app.name)`
   - This is on a Button with `.buttonStyle(.plain)`
   - SwiftUI .help() maps to native NSView.toolTip on macOS

3. **NSPanel Configuration:** MISSING MOUSE EVENT TRACKING
   - Panel created in `SearchWindowController.swift:211-253` (createSecondMenuBarWindow)
   - Panel is borderless: `styleMask: [.borderless, .resizable]` (line 226)
   - Panel level: `.statusBar` (line 234)
   - **CRITICAL MISSING:** Panel does NOT set `acceptsMouseMovedEvents = true`

4. **Root Cause:** NSPanel doesn't track mouse-moved events by default
   - Tooltips require mouse tracking to detect hover
   - Without `acceptsMouseMovedEvents = true`, the panel never receives mouseEntered/mouseMoved events
   - SwiftUI `.help()` modifier relies on underlying AppKit mouse tracking
   - Even though buttons can be clicked (click events work), **hover tracking is separate**

5. **Reference Implementation:** Claude Island NSPanel (verified working)
   - Found in GitHub search: [ClaudeIsland/NotchWindow.swift](https://github.com/farouqaldori/claude-island/blob/0c92dfccf0c3d7356aff0f5cbd8b02a5ff613fcf/ClaudeIsland/UI/Window/NotchWindow.swift)
   - That panel sets: `acceptsMouseMovedEvents = false` BUT uses `ignoresMouseEvents = true` (different use case — transparent overlay)
   - For interactive panels like Second Menu Bar, need `acceptsMouseMovedEvents = true` for tooltips

### The Fix

**File:** `/Users/sj/SaneApps/apps/SaneBar/UI/SearchWindow/SearchWindowController.swift`

**Location:** Line 253 (after `panel.maxSize = NSSize(...)`)

**Add:**
```swift
panel.acceptsMouseMovedEvents = true
```

**Full context (lines 240-254 after fix):**
```swift
panel.isMovableByWindowBackground = true
panel.animationBehavior = .utilityWindow
panel.minSize = NSSize(width: 180, height: 80)
panel.maxSize = NSSize(width: 800, height: 500)

// Enable mouse tracking for tooltips
panel.acceptsMouseMovedEvents = true

// Shadow for depth
if let contentView = panel.contentView {
    contentView.wantsLayer = true
    contentView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
    contentView.layer?.shadowOpacity = 1
    contentView.layer?.shadowRadius = 12
    contentView.layer?.shadowOffset = CGSize(width: 0, height: -4)
}
```

### Why This Works

1. **Mouse Tracking Enabled:** Panel now receives `mouseEntered`, `mouseMoved`, `mouseExited` events
2. **SwiftUI .help() Activation:** SwiftUI's `.help()` modifier uses AppKit's tooltip system, which requires mouse tracking
3. **NSInitialToolTipDelay Honored:** Once tracking is enabled, the 100ms delay setting applies
4. **No Side Effects:** This only affects hover tracking; click events, keyboard events, and window behavior are unchanged

### Verification Steps

After applying fix:
1. Build and launch SaneBar
2. Open Second Menu Bar panel (icon in menu bar → click or hover)
3. Hover over any app icon tile for ~100ms
4. **Expected:** Yellow tooltip appears with app name

### Related References

- [How to make tooltip in SwiftUI for macOS](https://onmyway133.com/posts/how-to-make-tooltip-in-swiftui-for-macos/)
- [SwiftUI for Mac - Part 2 (TrozWare)](https://troz.net/post/2019/swiftui-for-mac-2/)
- [NSPanel and SwiftUI view with mouse events - Hacking with Swift](https://www.hackingwithswift.com/forums/swiftui/nspanel-and-swiftui-view-with-mouse-events/29593)
- [acceptsMouseMovedEvents | Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nswindow/acceptsmousemovedevents)

---

## Move to Visible Bug Investigation (#56)

**Updated:** 2026-02-11 | **Status:** active-investigation | **TTL:** 7d
**Source:** GitHub issue #56, codebase analysis (all relevant files traced), ARCHITECTURE.md icon moving pipeline documentation

(... rest of the existing research content continues unchanged ...)
