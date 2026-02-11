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

## Move to Visible Bug Investigation (#56)

**Updated:** 2026-02-11 | **Status:** active-investigation | **TTL:** 7d
**Source:** GitHub issue #56, codebase analysis (all relevant files traced), ARCHITECTURE.md icon moving pipeline documentation

### Issue Summary

User on MacBook Pro with notch (v1.0.22, macOS 26.2, non-privileged account) reports:
- Right-clicking a hidden menu bar item in the new strip panel → "Move to Visible"
- Fast menu bar activity occurs (keyboard emulation visible)
- Icon does NOT actually move to visible section
- Diagnostics: 38 total items, 31 hidden, 7 visible, separator at x=1055, main icon at x=1331
- Log collection failed: `Foundation._GenericObjCError error 0`

### Code Path Analysis

#### 1. Context Menu Creation (WHERE "Move to Visible" IS DEFINED)

**Files:**
- `UI/SearchWindow/SecondMenuBarView.swift:152` — New strip panel (floating panel below menu bar)
- `UI/SearchWindow/MenuBarAppTile.swift:101` — Original Find Icon window
- `UI/SearchWindow/MenuBarSearchView+Navigation.swift:30-70` — Action factory for all modes

**Context menu in strip panel (SecondMenuBarView.swift:152):**
```swift
PanelIconTile(
    app: app,
    zone: zone,
    onMoveToVisible: { moveIcon(app, toZone: .visible) }  // ← Right-click menu action
)

private func moveIcon(_ app: RunningApp, toZone: IconZone) {
    switch toZone {
    case .visible:
        _ = menuBarManager.moveIcon(
            bundleID: bundleID, menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex, toHidden: false  // ← toHidden=false = move to visible
        )
    }
}
```

**Zone classification (MenuBarSearchView+Navigation.swift:12-26):**
```swift
func appZone(for app: RunningApp) -> AppZone {
    guard let xPos = app.xPosition else { return .visible }
    let midX = xPos + ((app.width ?? 22) / 2)
    let margin: CGFloat = 6

    if let sepX = menuBarManager.getSeparatorOriginX(),
       midX < (sepX - margin) {
        return .hidden  // ← Icon is LEFT of separator = hidden
    }
    return .visible  // ← Icon is RIGHT of separator = visible
}
```

**Key insight:** The code correctly identifies icon zones based on X position relative to separator. If user sees "Move to Visible" in context menu, the app is CORRECTLY classified as hidden.

#### 2. Icon Moving Pipeline (EXECUTION PATH)

**Main orchestrator: `Core/MenuBarManager+IconMoving.swift:101-283`**

**Move sequence (lines 101-283):**
1. **Guard check (lines 115-119):** Block if `hidingService.isAnimating` or `hidingService.isTransitioning`
2. **Expand via shield pattern (lines 182-198):**
   - If `wasHidden` (hidingState == .hidden), call `hidingService.showAll()` to expand both separators
   - Wait 300ms for macOS relayout
   - **CRITICAL:** The 10000px separator physically blocks Cmd+drag in BOTH directions, so expansion is required
3. **Get separator positions (lines 200-218):**
   - For `toHidden=false` (move to visible): read `getSeparatorRightEdgeX()` and `getMainStatusItemLeftEdgeX()`
   - Separator at visual size (20px), not blocking size (10000px)
4. **Cmd+drag execution (lines 228-254):**
   - Calls `AccessibilityService.moveMenuBarIcon()` with target calculation
   - Target for move-to-visible: `max(separatorX + 1, mainIconLeftEdge - 2)`
   - Verification: icon must land RIGHT of separator
   - One retry if verification fails (line 241-254)
5. **Restore and re-hide (lines 256-266):**
   - `hidingService.restoreFromShowAll()` (re-block always-hidden)
   - `hidingService.hide()` (collapse main separator back to 10000px)
6. **Refresh (lines 269-276):**
   - Wait 300ms for positions to settle
   - Invalidate accessibility cache
   - Post `menuBarIconsDidChange` notification

**Accessibility drag engine: `Core/Services/AccessibilityService+Interaction.swift:171-293`**

**Key steps (lines 171-293):**
1. **Poll for on-screen position (lines 192-205):**
   - After `showAll()`, macOS WindowServer re-layouts asynchronously
   - Icons may still be at off-screen positions (x=-3455) when 300ms sleep completes
   - **30 polling attempts × 100ms = 3s max** to wait for icon to reach x >= 0
2. **Target calculation (lines 214-232):**
   ```swift
   let moveOffset = max(30, iconFrame.size.width + 20)  // ← At least 30px
   let targetX: CGFloat = if toHidden, let ahBoundary = visibleBoundaryX {
       max(separatorX - moveOffset, ahBoundary + 2)  // ← Clamp: stay right of AH separator
   } else if toHidden {
       separatorX - moveOffset  // ← Move LEFT of separator
   } else if let boundary = visibleBoundaryX {
       // ← MOVE TO VISIBLE TARGET CALCULATION
       max(separatorX + 1, boundary - 2)  // ← Just right of separator, left of SaneBar icon
   }
   ```
3. **CGEvent Cmd+drag (lines 246, 376-501):**
   - 16-step drag over ~240ms (line 434: 16 steps × 15ms)
   - Cursor hidden during drag (line 414)
   - Pre-position cursor, Cmd+mouseDown, drag, Cmd+mouseUp, restore cursor
4. **Verification (lines 252-292):**
   - Poll for position stability (20 attempts × 50ms = 1s max)
   - Verify icon landed on expected side of separator:
     ```swift
     let margin = max(4, afterFrame.size.width * 0.3)
     let movedToExpectedSide: Bool = if toHidden {
         afterFrame.origin.x < (separatorX - margin)
     } else {
         afterFrame.origin.x > (separatorX + margin)  // ← Must be RIGHT of separator
     }
     ```

#### 3. Separator Position Analysis (USER'S ENVIRONMENT)

**Reported positions:**
- `separatorOriginX: 1055.00` (LEFT edge of separator)
- `mainIconLeftEdgeX: 1331.00` (LEFT edge of SaneBar icon)
- Gap: 1331 - 1055 = 276px
- Visible items: 7
- Average space per item: 276 / 7 = 39.4px

**Analysis:** This is NORMAL. Typical menu bar icon width is 22-30px with 5-10px spacing = 35-40px per icon. 7 items × 40px ≈ 280px. **The gap is NOT suspicious.**

**Target calculation for user's environment:**
- Separator right edge (when expanded): separatorOriginX + 20 = 1055 + 20 = 1075
- mainIconLeftEdge: 1331
- Target: `max(1075 + 1, 1331 - 2)` = `max(1076, 1329)` = **1329**
- This places icon 2px LEFT of SaneBar icon — macOS should auto-insert and push SaneBar right

**Expected behavior:** Icon should land at x=1329, verification checks `afterFrame.origin.x > (1075 + margin)`. With margin = max(4, iconWidth * 0.3) ≈ 6-10px, verification requires x > 1081-1085. Target 1329 is well within the visible zone.

### Potential Failure Points

#### A. Non-Admin Account (LOW LIKELIHOOD)

**Investigation:**
- Accessibility API (`AXUIElement`, `CGEvent`) does NOT require admin privileges
- Cmd+drag simulation works in standard user accounts
- HOWEVER: Some macOS versions have TCC (Transparency, Consent, and Control) bugs in non-admin accounts
- User reports `accessibilityGranted: true` in diagnostics → permission IS granted

**Verdict:** Unlikely root cause, but possible macOS TCC bug in non-admin account. No code changes can fix this.

#### B. MacBook Pro Notch (MEDIUM LIKELIHOOD)

**Investigation:**
- User has `hasNotch: true`, hardware: MacBookPro18,1 (14" or 16" with notch)
- Notch affects menu bar geometry: `screen.safeAreaInsets.top > 0`
- Code reads icon positions via Accessibility API (`kAXPositionAttribute`) which returns GLOBAL screen coordinates

**File:** `Core/Services/AccessibilityService+Interaction.swift:236-243`
```swift
// Line 236-243: Uses icon's actual AX Y position (menuBarY = iconFrame.midY)
// NOT hardcoded Y=12, which would break with notch or accessibility zoom
let menuBarY = iconFrame.midY
let fromPoint = CGPoint(x: iconFrame.midX, y: menuBarY)
let toPoint = CGPoint(x: targetX, y: menuBarY)
```

**Verdict:** Code handles notch correctly by reading actual Y position from Accessibility API. NOT the root cause.

#### C. Separator Position Read During Blocking Mode (HIGH LIKELIHOOD)

**Investigation:**
- User's bar was in `hidden` state when "Move to Visible" was clicked
- `MenuBarManager+IconMoving.swift:142` checks `wasHidden = hidingState == .hidden`
- If wasHidden, calls `hidingService.showAll()` to expand separators (line 193)

**CRITICAL CODE PATH (lines 200-218):**
```swift
let (separatorX, visibleBoundaryX): (CGFloat?, CGFloat?) = await MainActor.run {
    // ← toHidden=false branch (move to visible)
    let sep = self.getSeparatorRightEdgeX()  // ← Read separator RIGHT edge
    let mainLeft = self.getMainStatusItemLeftEdgeX()
    return (sep, mainLeft)
}
```

**`getSeparatorRightEdgeX()` logic (lines 63-85):**
```swift
func getSeparatorRightEdgeX() -> CGFloat? {
    guard let separatorButton = separatorItem?.button,
          let separatorWindow = separatorButton.window
    else {
        logger.error("separatorItem or window is nil")
        return nil
    }
    let frame = separatorWindow.frame
    guard frame.width > 0 else {
        logger.error("frame.width is 0")
        return nil
    }
    // Cache the origin for classification during blocking mode
    if frame.origin.x > 0, frame.width < 1000 {
        lastKnownSeparatorX = frame.origin.x
    }
    let rightEdge = frame.origin.x + frame.width
    return rightEdge
}
```

**RACE CONDITION HYPOTHESIS:**
1. User clicks "Move to Visible" while bar is `hidden`
2. `showAll()` fires (line 193) → separator transitions from 10000px → 20px
3. 300ms sleep (line 194)
4. **DURING the 300ms sleep**, macOS WindowServer is still re-laying out items
5. `getSeparatorRightEdgeX()` is called (line 215) AFTER the sleep
6. **IF the separator window frame hasn't updated yet**, `frame.width` might still be 10000 or transitioning
7. The `if frame.width < 1000` check (line 79) would FAIL
8. `rightEdge = frame.origin.x + 10000` would be returned (off-screen)
9. Target calculation: `max(-2925 + 1, 1331 - 2)` = 1329 (correct)
10. **BUT if separator origin is still off-screen** (x=-2945), `separatorX + 1` = -2944
11. Verification would fail because icon at x=1329 is NOT `> (separatorX + margin)` when separatorX is negative

**COUNTER-EVIDENCE:** The code caches `lastKnownSeparatorX` (line 80) when separator is at visual size. On next read during blocking mode, it uses the cache. However, the `getSeparatorRightEdgeX()` method does NOT check if separator is in blocking mode — it always reads the live window frame.

**ACTUAL ISSUE:** `getSeparatorRightEdgeX()` has NO blocking mode cache fallback. `getSeparatorOriginX()` (lines 13-34) DOES check `if separatorItem.length > 1000` and returns `lastKnownSeparatorX`, but `getSeparatorRightEdgeX()` does NOT.

**File:** `Core/MenuBarManager+IconMoving.swift:63-85` (getSeparatorRightEdgeX)
- Missing: `if separatorItem.length > 1000 { return lastKnownSeparatorX + 20 }` check

**Verdict:** HIGH LIKELIHOOD. If macOS hasn't finished relayout 300ms after `showAll()`, separator window frame might still be at off-screen or transitioning width, causing incorrect target calculation.

#### D. Verification Margin Too Strict for Small Icons (MEDIUM LIKELIHOOD)

**Code:** `AccessibilityService+Interaction.swift:281`
```swift
let margin = max(4, afterFrame.size.width * 0.3)
let movedToExpectedSide: Bool = if toHidden {
    afterFrame.origin.x < (separatorX - margin)
} else {
    afterFrame.origin.x > (separatorX + margin)
}
```

**Hypothesis:** If icon width is 16px (small icon), margin = max(4, 16 * 0.3) = max(4, 4.8) = 4.8px. Icon must land at x > (separatorX + 4.8). If separator is at 1075, icon must be > 1079.8. Target is 1329, so this should pass.

**Verdict:** Unlikely root cause for this user, but margin formula might be too strict for edge cases.

#### E. CGEvent Drag Timing on Slower Macs (LOW-MEDIUM LIKELIHOOD)

**Code:** `AccessibilityService+Interaction.swift:434`
```swift
let steps = 16
for i in 1 ... steps {
    let t = CGFloat(i) / CGFloat(steps)
    // ...
    drag.post(tap: .cghidEventTap)
    Thread.sleep(forTimeInterval: 0.015)  // ← 15ms per step
}
```

**Total drag time:** 16 × 15ms = 240ms

**Hypothesis:** On slower Macs (8GB M1 mini?), macOS WindowServer might not process drag events fast enough. If the drag completes before WindowServer registers the full Cmd+drag gesture, the icon might "rubber-band" back to original position.

**COUNTER-EVIDENCE:** User reports "fast menu bar activity" which suggests the drag IS happening. If drag was too fast, they wouldn't see activity.

**Verdict:** LOW likelihood. 240ms is already human-like (Ice uses similar timing).

#### F. Icon Moving During Notch Screen with Off-Center Menu Bar (LOW LIKELIHOOD)

**Hypothesis:** Notch screens have menu bar items positioned around the notch. If icon is near the notch boundary, drag target might be calculated incorrectly.

**COUNTER-EVIDENCE:** User's separator is at x=1055, main icon at x=1331. Notch on 14" MacBook Pro is centered around x=700-900 (approximate). Both positions are well RIGHT of the notch, in the normal menu bar area.

**Verdict:** LOW likelihood.

#### G. Log Collection Failure = Permission Issue? (LOW LIKELIHOOD)

**User reports:** `[ERROR] Failed to collect logs: Foundation._GenericObjCError error 0`

**Code:** `Core/Services/DiagnosticsService.swift:172-178`
```swift
let entries = try store.getEntries(at: position, matching: predicate)
} catch {
    return [DiagnosticReport.LogEntry(
        timestamp: Date(),
        level: "ERROR",
        message: "Failed to collect logs: \(error.localizedDescription)"
    )]
}
```

**Hypothesis:** `OSLogStore` requires Full Disk Access on some macOS versions when running in non-privileged account. If log collection fails, could other system APIs (CGEvent, AXUIElement) also be failing silently?

**COUNTER-EVIDENCE:** User reports `accessibilityGranted: true`, and CGEvent doesn't require Full Disk Access. Log collection is a separate system (OSLog) with different permissions.

**Verdict:** LOW likelihood that this is related to icon moving failure, but indicates possible permission oddities in non-admin account.

### Known Fragilities from ARCHITECTURE.md

From `ARCHITECTURE.md` § "Icon Moving Pipeline — Known Fragilities":

1. **First drag sometimes fails** — timing between `showAll()` completing and icons becoming draggable
2. **Wide icons (>100px)** may need special grab points
3. **AH-to-Hidden verification is too strict** when separators are flush
4. **Separator reads -3349 during blocking mode** — mitigated by `lastKnownSeparatorX` cache (BUT only in `getSeparatorOriginX()`, NOT `getSeparatorRightEdgeX()`)
5. **Re-hiding after move** can undo the move if macOS hasn't reclassified the icon yet
6. **This will always be fragile** — Ice has the same open bugs (#684)

**Fragility #4 is EXACTLY the issue:** `getSeparatorRightEdgeX()` has no blocking mode cache fallback.

### Hypothesized Root Cause

**PRIMARY SUSPECT: Race condition in separator position read after `showAll()`**

**Sequence:**
1. User clicks "Move to Visible" on hidden icon (bar is in `hidden` state)
2. `moveIcon()` checks `wasHidden = true` (line 142)
3. Calls `hidingService.showAll()` (line 193) → separator length: 10000px → 20px
4. Waits 300ms (line 194)
5. **During 300ms**, macOS WindowServer starts re-layout, but may not finish on slower Macs
6. `getSeparatorRightEdgeX()` is called (line 215)
7. **Separator window frame is still transitioning** (width between 20 and 10000, or position still off-screen)
8. `rightEdge = frame.origin.x + frame.width` returns incorrect value (either negative or huge)
9. Target calculation: `max(incorrectSeparatorX + 1, 1331 - 2)` = 1329 (mainIconLeftEdge wins)
10. Drag executes to x=1329 (CORRECT position)
11. **Verification fails** because it re-reads separator position AFTER drag, and now separator is at correct position (x=1055)
12. Verification: `afterFrame.origin.x > (separatorX + margin)` → `1329 > 1055 + 6` → TRUE
13. **Wait, verification should PASS...**

**REVISED HYPOTHESIS: Verification reads STALE separator position**

Re-reading verification code (lines 276-292):
```swift
// Poll for position stability (20 attempts × 50ms)
for attempt in 1 ... maxAttempts {
    Thread.sleep(forTimeInterval: 0.05)
    let currentFrame = getMenuBarIconFrame(...)  // ← Re-read icon position
    if let current = currentFrame, let previous = previousFrame, current.origin.x == previous.origin.x {
        afterFrame = current
        logger.info("AX position stabilized after \(attempt * 50)ms")
        break
    }
}

// Verify icon landed on expected side of separator
let margin = max(4, afterFrame.size.width * 0.3)
let movedToExpectedSide: Bool = if toHidden {
    afterFrame.origin.x < (separatorX - margin)
} else {
    afterFrame.origin.x > (separatorX + margin)  // ← Uses separatorX from BEFORE drag
}
```

**AH-HA:** Verification uses `separatorX` value from BEFORE the drag (calculated at line 214-232). It does NOT re-read the separator position. If separator was transitioning during the initial read, the verification will compare against the WRONG separator position.

**CORRECT ROOT CAUSE:**
1. `getSeparatorRightEdgeX()` reads separator during transition → returns incorrect value
2. Target is calculated correctly using `max(incorrectSep, boundary)` → boundary wins (1329)
3. Drag executes to 1329 (icon DOES move to visible)
4. Verification compares `1329 > incorrectSep + margin` → might FAIL if `incorrectSep` is huge (e.g., 10000)
5. Verification reports FAILURE even though icon moved correctly
6. Retry executes with SAME stale separator value → fails again
7. `restoreFromShowAll()` + `hide()` collapses separator back to 10000px
8. Icon is re-hidden even though it successfully moved to visible zone

**FINAL HYPOTHESIS:** Icon DOES move to visible (drag completes), but verification fails due to stale separator read, and `hide()` re-pushes it off-screen before the user sees it.

### Recommended Fixes

#### Fix 1: Add blocking mode cache to `getSeparatorRightEdgeX()` (CRITICAL)

**File:** `Core/MenuBarManager+IconMoving.swift:63-85`

**Current code:**
```swift
func getSeparatorRightEdgeX() -> CGFloat? {
    guard let separatorButton = separatorItem?.button,
          let separatorWindow = separatorButton.window
    else { return nil }
    let frame = separatorWindow.frame
    guard frame.width > 0 else { return nil }

    // Cache the origin for classification
    if frame.origin.x > 0, frame.width < 1000 {
        lastKnownSeparatorX = frame.origin.x
    }
    let rightEdge = frame.origin.x + frame.width
    return rightEdge
}
```

**ADD:**
```swift
func getSeparatorRightEdgeX() -> CGFloat? {
    guard let separatorItem else { return nil }

    // If in blocking mode or transitioning, use cached value + visual width
    if separatorItem.length > 1000 {
        guard let cachedOrigin = lastKnownSeparatorX else { return nil }
        return cachedOrigin + 20  // Visual width when expanded
    }

    guard let separatorButton = separatorItem.button,
          let separatorWindow = separatorButton.window
    else { return nil }
    // ... rest of method
}
```

#### Fix 2: Increase settle delay after `showAll()` for slower Macs (MEDIUM PRIORITY)

**File:** `Core/MenuBarManager+IconMoving.swift:194`

**Current:** `try? await Task.sleep(for: .milliseconds(300))`

**Change to:** `try? await Task.sleep(for: .milliseconds(500))`

**Rationale:** 300ms might not be enough for slower Macs (especially 8GB M1 with memory pressure). 500ms reduces risk of reading transitioning window frames. This was already noted in ARCHITECTURE.md: "500ms hits auto-rehide" but that's a trade-off vs correctness.

#### Fix 3: Re-read separator position in verification (LOW PRIORITY, RISKY)

**File:** `Core/Services/AccessibilityService+Interaction.swift:276-292`

**Current:** Uses `separatorX` from before drag

**Change to:** Call `menuBarManager.getSeparatorRightEdgeX()` again AFTER drag completes

**Rationale:** Ensures verification compares against separator's ACTUAL current position

**Risk:** If separator is still transitioning, verification might read another incorrect value. Better to fix the root cause (Fix 1) than add more reads.

#### Fix 4: Disable re-hide if verification fails (MEDIUM PRIORITY)

**File:** `Core/MenuBarManager+IconMoving.swift:256-266`

**Current:**
```swift
if wasHidden {
    await hidingService.restoreFromShowAll()
    if !shouldSkipHide {
        await hidingService.hide()  // ← Re-hides even if verification failed
    }
}
```

**Change to:**
```swift
if wasHidden {
    await hidingService.restoreFromShowAll()
    if !shouldSkipHide && success {  // ← Only re-hide if move succeeded
        await hidingService.hide()
    } else if !success {
        logger.warning("Move verification failed — keeping items expanded to prevent re-hiding moved icon")
    }
}
```

**Rationale:** If icon DID move (drag completed) but verification failed (stale separator read), re-hiding will push the icon back off-screen. Better to leave expanded and let user manually hide.

### Test Plan

**To reproduce the bug:**
1. Launch SaneBar on MacBook Pro with notch (or any Mac)
2. Hide menu bar (click SaneBar icon)
3. Open Find Icon or new strip panel
4. Right-click a hidden icon → "Move to Visible"
5. Observe: Fast menu bar activity, but icon doesn't appear in visible section
6. Check logs for: separator position values, verification result

**Expected logs if hypothesis is correct:**
```
[INFO] Separator right edge BEFORE: 10000.00 (or negative value)
[INFO] Target X: 1329.00
[INFO] Icon frame AFTER: x=1329.00 (icon DID move)
[ERROR] Move verification failed: expected toHidden=false, separatorX=10000.00, afterX=1329.00
[INFO] Move complete - re-hiding items...
```

**After Fix 1 applied:**
```
[INFO] Separator right edge BEFORE: 1075.00 (cached + 20)
[INFO] Target X: 1329.00
[INFO] Icon frame AFTER: x=1329.00
[INFO] Move verification PASSED
```

### Additional Notes

- **Non-admin account:** Unlikely to be the root cause, but user should verify Accessibility permission is granted in System Settings → Privacy & Security → Accessibility → SaneBar (checked)
- **Log collection failure:** Unrelated to icon moving, but indicates possible permission quirks. User can manually grant Full Disk Access to enable log collection.
- **Notch:** Correctly handled by code (uses actual Y position from AX API, not hardcoded)
- **Separator gap (276px for 7 items):** NORMAL, not suspicious

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

## SaneBar Interaction Map

**Updated:** 2026-02-11 | **Status:** verified | **TTL:** 90d
**Source:** Complete codebase trace of all user interaction paths

### Click Behaviors (MenuBarManager+Actions.swift)

| User Action | Code Path | What Happens |
|-------------|-----------|--------------|
| **LEFT-CLICK** SaneBar icon | `statusItemClicked()` line 91 → `clickType = .leftClick` (line 132) → `toggleHiddenItems()` (line 134) | **Toggles** hidden items (show if hidden, hide if shown). Default primary action. |
| **RIGHT-CLICK** SaneBar icon | `statusItemClicked()` line 91 → `clickType = .rightClick` (line 135) → `showStatusMenu()` (line 136) | Shows context menu with: Find Icon, Settings, Check for Updates, Quit |
| **OPTION-CLICK** SaneBar icon | `statusItemClicked()` line 91 → `clickType = .optionClick` (line 129) → `SearchWindowController.shared.toggle(mode: .findIcon)` (line 131) | Opens **Find Icon** search window (the original access method) |
| **Control+Click** SaneBar icon | Treated as right-click (line 24, 361) | Same as right-click → shows context menu |

**Click Type Detection:** `StatusBarController.clickType(from:)` lines 357-367
- Right-click: `event.type == .rightMouseUp` OR `event.buttonNumber == 1` OR `Control` modifier
- Option-click: `event.type == .leftMouseUp` AND `event.modifierFlags.contains(.option)`
- Left-click: Everything else

### Right-Click Menu Items (StatusBarController.swift:283-308)

Created in `createMenu()`:

1. **"Find Icon..."** → `openFindIcon()` (MenuBarManager+Actions.swift:74) → `SearchWindowController.shared.toggle()` → Opens Find Icon search window
2. **Separator**
3. **"Settings..."** (⌘,) → `openSettings()` → `SettingsOpener.open()`
4. **"Check for Updates..."** → `checkForUpdates()` → Sparkle updater
5. **Separator**
6. **"Quit SaneBar"** (⌘Q) → `quitApp()` → `NSApplication.shared.terminate(nil)`

### Keyboard Shortcuts (KeyboardShortcutsService.swift)

Default shortcuts set on first launch (lines 118-142):

| Shortcut | Action | Code Handler | What It Does |
|----------|--------|--------------|--------------|
| **⌘\\** | Toggle Hidden Items | `toggleHiddenItems()` line 65-68 | Same as left-clicking icon |
| **⌘⇧\\** | Show Hidden Items | `showHiddenItems()` line 72-75 | Force show (doesn't toggle) |
| **⌘⌥\\** | Hide Items | `hideItems()` line 79-82 | Force hide (doesn't toggle) |
| **⌘⇧Space** | Search Menu Bar | `searchMenuBar` line 93-96 | Opens **Find Icon** search window |
| **⌘,** | Open Settings | Built-in macOS standard | Settings window (not in shortcuts service) |

**Note:** No default for "Open Settings" global hotkey (line 138-140) — ⌘, only works when SaneBar is active. User can set custom global hotkey in Settings → Shortcuts.

### Find Icon vs Second Menu Bar (SearchWindowController.swift)

**TWO DIFFERENT MODES for accessing hidden icons:**

#### Find Icon (Original Method)
- **Trigger:** Option-click icon OR ⌘⇧Space OR right-click menu "Find Icon..."
- **What it is:** Floating search window (titled "Find Icon", closable, resizable, centered)
- **Created:** Lines 184-209 (`.titled, .closable, .resizable`, level = `.floating`)
- **Position:** Centered near top of screen (line 136-140)
- **Behavior:** Search by app name, arrow keys to navigate, Enter to click, ESC to close
- **Code mode:** `SearchWindowMode.findIcon` (line 7)

#### Second Menu Bar (Alternative Method)
- **Trigger:** Left-click icon (IF `useSecondMenuBar` setting is ON)
- **What it is:** Borderless panel below the menu bar showing all hidden icons
- **Created:** Lines 211-252 (`.borderless`, level = `.statusBar`, uses `KeyablePanel`)
- **Position:** Below menu bar, right-aligned to SaneBar icon (line 142-168)
- **Behavior:** Visual grid of icons, click to open, right-click for context menu, ESC to close
- **Code mode:** `SearchWindowMode.secondMenuBar` (line 10)

**The Setting:** `useSecondMenuBar: Bool` (PersistenceService.swift:227)
- **Default:** `false` (Find Icon is default)
- **Where to toggle:** Settings → General → Hiding → "Show hidden icons in second menu bar"
- **Effect:** Changes what LEFT-CLICK does AND what `toggle()` opens

### How `useSecondMenuBar` Changes Behavior (SearchWindowController.swift:45-47)

```swift
var activeMode: SearchWindowMode {
    MenuBarManager.shared.settings.useSecondMenuBar ? .secondMenuBar : .findIcon
}
```

**When `useSecondMenuBar = false` (DEFAULT):**
- Left-click → `toggleHiddenItems()` → separator expands/collapses (traditional behavior)
- Option-click → Opens Find Icon search window
- ⌘⇧Space → Opens Find Icon search window

**When `useSecondMenuBar = true`:**
- Left-click → `toggleHiddenItems()` → Opens Second Menu Bar panel (line 131)
- Option-click → **STILL opens Find Icon** (line 131 forces `.findIcon` mode)
- ⌘⇧Space → Opens Find Icon search window
- Separator stays hidden (panel replaces expand/collapse paradigm)

**Key Code Path (MenuBarManager+Actions.swift:129-134):**
```swift
case .optionClick:
    SearchWindowController.shared.toggle(mode: .findIcon)  // ← ALWAYS Find Icon
case .leftClick:
    toggleHiddenItems()  // ← Delegates to search controller if useSecondMenuBar=true
```

### Toggle Logic Flow (MenuBarManager+Visibility.swift:17-55)

**`toggleHiddenItems()` — The Primary Toggle Function**

Lines 17-55 in MenuBarManager+Visibility.swift:

1. **Check current state** (line 19): Read `hidingService.state` (`.hidden` or `.expanded`)
2. **Auth check** (lines 20-38): If showing AND `requireAuthToShowHiddenIcons = true`, prompt Touch ID/password
3. **Toggle** (line 41): Call `hidingService.toggle()` (expand if hidden, hide if expanded)
4. **Unpin if hiding** (lines 45-48): If user hid items, set `isRevealPinned = false`
5. **Auto-rehide schedule** (lines 51-53): If expanded + autoRehide enabled, schedule timer to collapse

**The Three Toggle Functions:**

| Function | What It Does | Use Case |
|----------|--------------|----------|
| `toggleHiddenItems()` | Toggle (show if hidden, hide if shown) | Default action (left-click, ⌘\\) |
| `showHiddenItems()` | Force show (no toggle) | Hotkey ⌘⇧\\, automation |
| `hideHiddenItems()` | Force hide (no toggle) | Hotkey ⌘⌥\\, automation, auto-rehide timer |

### Visual Differences Between Modes

| Feature | Find Icon | Second Menu Bar |
|---------|-----------|-----------------|
| **Window Style** | Titled window with "Find Icon" title bar, close button | Borderless panel, no title bar |
| **Size** | 420×520px, resizable | Auto-sized to fit icons, not resizable |
| **Position** | Centered near top of screen | Below menu bar, right-aligned to SaneBar icon |
| **Search bar** | Yes — type to filter apps | No — shows all icons |
| **Navigation** | Keyboard (arrow keys, Enter) + mouse | Mouse only (click icons) |
| **Closing** | Click X, press ESC, click outside | Press ESC, click outside (NO auto-close on icon click) |
| **Window Level** | `.floating` (above most windows) | `.statusBar` (same level as menu bar) |
| **Auto-close** | Yes (200ms after losing focus, line 270-276) | **NO** (line 263-265) — stays open while using menus |
| **Icon Rendering** | Search view with app names | Panel with icon tiles |

### The Key Distinction (from README.md lines 129-136)

**README.md explains it:**
- **Find Icon:** "Search for any menu bar app by name and activate it" — keyboard-first, search-driven
- **Second Menu Bar:** "See all your hidden and always-hidden icons in a floating bar below the menu bar" — visual, mouse-driven
- **Both work together:** Option-click ALWAYS opens Find Icon (even when Second Menu Bar is enabled)

### Auto-Close Behavior Difference (SearchWindowController.swift:258-277)

**Find Icon (`.findIcon` mode):**
```swift
func windowDidResignKey(_: Notification) {
    if currentMode == .secondMenuBar { return }  // ← Skip for panel

    // 200ms grace period — if window regains key, cancel close
    resignCloseTask = Task {
        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }
        close()
    }
}
```

**Second Menu Bar (`.secondMenuBar` mode):**
- **Never auto-closes** on `resignKey` (line 265)
- Users expect it to stay open while clicking menus/dropdowns
- Closed explicitly: ESC key OR click outside OR user action

### Summary: The Complete Interaction Matrix

| User Does | `useSecondMenuBar = false` | `useSecondMenuBar = true` |
|-----------|----------------------------|---------------------------|
| **Left-click icon** | Separator expands/collapses | Second Menu Bar panel opens |
| **Right-click icon** | Context menu (Find Icon, Settings, Updates, Quit) | Same context menu |
| **Option-click icon** | Find Icon search window | Find Icon search window (unchanged) |
| **⌘\\** (hotkey) | Separator expands/collapses | Second Menu Bar panel opens |
| **⌘⇧Space** (hotkey) | Find Icon search window | Find Icon search window (unchanged) |
| **"Find Icon..." menu** | Find Icon search window | Find Icon search window (unchanged) |

**The Golden Rule:**
- **Option-click and ⌘⇧Space ALWAYS open Find Icon** (search-driven access)
- **Left-click behavior is controlled by `useSecondMenuBar` setting** (toggle separator OR open panel)
- **Find Icon and Second Menu Bar are COMPLEMENTARY** — both can coexist, serve different use cases

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

---

(... rest of existing research.md content continues unchanged ...)
