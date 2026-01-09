# SaneBar Feature Plan

> Implementation plan for SaneBar features

---

## Research Findings

### 1. Menu Bar Search

**Source**: apple-docs MCP - NSWindow.Level, NSPanel
**Finding**: Use floating NSPanel with `.floating` window level positioned near menu bar. NSSearchField for input. Filter icons by name/bundle ID.
**Applies to**: New `UI/SearchWindow/` directory
**Confidence**: High (standard macOS pattern)

**APIs Verified**:
- `NSWindow.Level.floating` - positions window above normal windows
- `NSMenu.menuBarHeight` - get menu bar height for positioning
- `NSScreen.main?.frame` - screen dimensions

---

### 2. Always Show List

**Source**: apple-docs MCP - NSStatusItem
**Finding**: Already have `NSStatusItem.isVisible` property. Store list of bundle IDs that should remain visible. Create additional NSStatusItems for "pinned" icons that stay visible when others hide.
**Applies to**: `Core/Services/PersistenceService.swift`, `Core/MenuBarManager.swift`
**Confidence**: High (extends existing pattern)

**Implementation**:
- Add `alwaysVisibleApps: [String]` to SaneBarSettings
- Create separate NSStatusItem array for pinned icons
- These items stay at fixed length (don't expand to hide)

---

### 3. Per-Icon Hotkeys

**Source**: context7 MCP - KeyboardShortcuts library
**Finding**: KeyboardShortcuts library supports dynamic shortcut names via `KeyboardShortcuts.Name("dynamic-\(id)")`. Can register/unregister at runtime.
**Applies to**: `Core/Services/KeyboardShortcutsService.swift`
**Confidence**: High (already using this library)

**Pattern**:
```swift
// Dynamic shortcut registration
let name = KeyboardShortcuts.Name("icon-\(bundleID)")
KeyboardShortcuts.onKeyUp(for: name) { /* show specific icon */ }
```

---

### 4. Show on Hover

**Source**: apple-docs MCP - NSEvent.addGlobalMonitorForEvents
**Finding**: Use `addGlobalMonitorForEvents(matching: .mouseMoved)` to track cursor position globally. Check if cursor Y is within menu bar height. **CAUTION**: We had BUG-009-CursorHijack with CGEvent mouse simulation - avoid that approach.
**Applies to**: New `Core/Services/HoverService.swift`
**Confidence**: Medium (need careful implementation to avoid cursor issues)

**Safe Implementation**:
```swift
NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { event in
    let menuBarHeight = NSMenu.main?.menuBarHeight ?? 24
    if event.locationInWindow.y >= NSScreen.main!.frame.height - menuBarHeight {
        // Cursor in menu bar area - show hidden items
    }
}
```

**Risk**: Previous hover implementation caused cursor hijacking. Must NOT use CGEvent simulation.

---

### 5. Presets/Profiles

**Source**: Existing PersistenceService pattern
**Finding**: Store multiple SaneBarSettings instances keyed by profile name. Use Codable with dictionary storage.
**Applies to**: `Core/Services/PersistenceService.swift`, `Core/Models/`
**Confidence**: High (standard persistence pattern)

**Data Model**:
```swift
struct SaneBarProfile: Codable {
    var name: String
    var settings: SaneBarSettings
    var iconVisibility: [String: Bool]  // bundleID -> visible
}
```

---

### 6. Icon Click-Through

**Source**: apple-docs MCP - NSStatusItem, CGEvent
**Finding**: This requires intercepting clicks on hidden icons and forwarding them. Would need Accessibility API to identify which icon was clicked, then simulate click. **Complex and risky** - similar to what caused BUG-009.
**Applies to**: Would need new service
**Confidence**: Low (high complexity, potential for bugs)

**Recommendation**: SKIP - Too complex, high risk of cursor/input issues.

---

### 7. Menu Bar Spacing

**Source**: apple-docs MCP - NSStatusItem.length
**Finding**: Already using `.length` property for hiding. Can use same property to add visual spacing. Create "spacer" status items with configurable widths.
**Applies to**: Already implemented in `Core/MenuBarManager.swift`
**Confidence**: High (already working)

**Status**: DONE - We have spacers (0-3 configurable)

---

## Feature Priority Recommendation

| Feature | Difficulty | Value | Risk | Recommend |
|---------|------------|-------|------|-----------|
| Always Show List | Easy | High | Low | **YES - Do First** |
| Menu Bar Search | Medium | High | Low | **YES** |
| Per-Icon Hotkeys | Medium | Medium | Low | **YES** |
| Show on Hover | Medium | High | Medium | **MAYBE - Careful** |
| Presets/Profiles | Medium | Medium | Low | **YES** |
| Icon Click-Through | Hard | Low | High | **NO - Skip** |
| Menu Bar Spacing | Done | - | - | Already done |

---

## Implementation Plan

### Phase 1: Always Show List
**[Rule #2: VERIFY BEFORE YOU TRY]** - APIs verified above

1. Add to `SaneBarSettings`:
   - `alwaysVisibleApps: [String]` - bundle IDs to keep visible

2. Modify `MenuBarManager.swift`:
   - Filter always-visible apps when hiding
   - Create separate status items for pinned icons

3. Add UI in `SettingsView.swift`:
   - New section in Advanced tab
   - List of pinned apps with add/remove

4. **[Rule #7: NO TEST? NO REST]** - Add test:
   - `testAlwaysVisibleAppsRemainVisibleWhenHidden`

5. **[Rule #6: BUILD, KILL, LAUNCH, LOG]** - Verify

---

### Phase 2: Menu Bar Search
**[Rule #2: VERIFY BEFORE YOU TRY]** - APIs verified above

1. Create `UI/SearchWindow/`:
   - `SearchWindowController.swift` - NSWindowController subclass
   - `MenuBarSearchView.swift` - SwiftUI search interface

2. Configure window:
   - `.floating` level
   - Position below menu bar
   - Dismiss on focus loss

3. Add keyboard shortcut:
   - Register `searchMenuBar` in KeyboardShortcutsService
   - Default: Cmd+Shift+Space (or similar)

4. Search logic:
   - Filter by icon name/bundle ID
   - Show matching icons temporarily

5. **[Rule #7: NO TEST? NO REST]** - Add tests

6. **[Rule #6: BUILD, KILL, LAUNCH, LOG]** - Verify

---

### Phase 3: Per-Icon Hotkeys
**[Rule #2: VERIFY BEFORE YOU TRY]** - APIs verified above

1. Add to `SaneBarSettings`:
   - `iconHotkeys: [String: KeyboardShortcuts.Name]`

2. Create UI:
   - Per-icon shortcut recorder in Settings
   - List known menu bar apps

3. Dynamic registration:
   - Register shortcuts on app launch
   - Update when settings change

4. **[Rule #7: NO TEST? NO REST]** - Add tests

5. **[Rule #6: BUILD, KILL, LAUNCH, LOG]** - Verify

---

### Phase 4: Presets/Profiles
**[Rule #2: VERIFY BEFORE YOU TRY]** - Standard persistence

1. Create `Core/Models/SaneBarProfile.swift`

2. Update `PersistenceService`:
   - `saveProfile(_:)`, `loadProfile(_:)`, `listProfiles()`
   - Store in `~/Library/Application Support/SaneBar/profiles/`

3. Add UI:
   - Profile picker in Settings
   - Save/Load/Delete buttons
   - Import/Export for sharing

4. **[Rule #7: NO TEST? NO REST]** - Add tests

5. **[Rule #6: BUILD, KILL, LAUNCH, LOG]** - Verify

---

### Phase 5: Show on Hover (Optional/Careful)
**[Rule #3: TWO STRIKES? INVESTIGATE]** - Previous hover had BUG-009

1. Create `Core/Services/HoverDetectionService.swift`:
   - Use NSEvent.addGlobalMonitorForEvents ONLY
   - NO CGEvent simulation
   - NO cursor manipulation

2. Add settings:
   - `showOnHover: Bool` (default: false)
   - `hoverEdge: Edge` (top, right)
   - `hoverDelay: TimeInterval`

3. Safe implementation:
   - Just call existing `showHiddenItems()` method
   - No mouse event posting

4. **[Rule #7: NO TEST? NO REST]** - Add tests

5. **[Rule #6: BUILD, KILL, LAUNCH, LOG]** - Verify carefully

---

## Verification Protocol

After each phase:
```bash
./Scripts/SaneMaster.rb verify        # Build + tests pass
killall -9 SaneBar                     # Kill old instance
./Scripts/SaneMaster.rb launch         # Start fresh
./Scripts/SaneMaster.rb logs --follow  # Watch for errors
```

---

## User Decisions (2026-01-07)

**Features to implement:**
- [ ] Always Show List - NOT IMPLEMENTED (icons left of delimiter are always visible by design, but no separate `alwaysVisibleApps` setting exists)
- [x] Menu Bar Search (Enhanced with Virtual Click)
- [x] Presets/Profiles
- [x] Per-Icon Hotkeys
- [x] Show on Hover (Implemented safely with NSEvent)
- [ ] ~~Icon Click-Through~~ - SKIPPED (too complex/unsafe)

**Scope:** Core features completed. Always Show List deferred.

**Implementation Order:**
1. Always Show List (easiest, foundations for others)
2. Menu Bar Search (high user value)
3. Per-Icon Hotkeys (extends shortcuts system)
4. Presets/Profiles (builds on all above)
5. Show on Hover (Safe implementation)
