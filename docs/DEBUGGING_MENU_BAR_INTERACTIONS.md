# Menu Bar Interactions & Positioning

## Quick Reference

### Click Behavior
- **Left-click** on main SaneBar icon → Toggle hide/show
- **Right-click** on main icon → Context menu (Find Icon, Settings, Quit)
- **Separator ("/")** → Visual-only, not interactive

### The Ice Pattern

SaneBar uses the same positioning pattern as [Ice](https://github.com/jordanbaird/Ice), a popular open-source menu bar manager.

```swift
// 1. SEED positions in UserDefaults BEFORE creating items
private static func seedPositionsIfNeeded() {
    let defaults = UserDefaults.standard
    let mainKey = "NSStatusItem Preferred Position \(mainAutosaveName)"
    let sepKey = "NSStatusItem Preferred Position \(separatorAutosaveName)"

    if defaults.object(forKey: mainKey) == nil {
        defaults.set(0, forKey: mainKey)  // 0 = rightmost
    }
    if defaults.object(forKey: sepKey) == nil {
        defaults.set(1, forKey: sepKey)   // 1 = second from right
    }
}

// 2. CREATE items AFTER seeding
init() {
    Self.seedPositionsIfNeeded()

    self.mainItem = NSStatusBar.system.statusItem(withLength: variableLength)
    self.mainItem.autosaveName = Self.mainAutosaveName

    self.separatorItem = NSStatusBar.system.statusItem(withLength: 20)
    self.separatorItem.autosaveName = Self.separatorAutosaveName
}
```

### Hiding Mechanism

NSStatusItem.length controls visibility:

| State | Separator Length | Effect |
|-------|------------------|--------|
| Expanded | 20px | Normal divider appearance |
| Collapsed | 10,000px | Pushes hidden items off-screen |

Items aren't removed, just pushed off the right edge of the screen.

---

## Key Rules

### Rule 1: Ordinal Positions, Not Pixel Coordinates

macOS interprets position values as ordering hints (0 = rightmost, 1 = second, etc.), not pixel coordinates.

### Rule 2: Seed BEFORE Create

macOS reads the position from UserDefaults when the item is created. Seeding after creation has no effect.

### Rule 3: Trust macOS

Seed positions once correctly, use autosaveName, and let macOS handle placement. No recovery logic needed.

### Rule 4: Cache Positions Before Removal

macOS deletes position data when removing an NSStatusItem or setting `isVisible = false`. Cache and restore:

```swift
deinit {
    let cached = StatusItemDefaults[.preferredPosition, autosaveName]
    NSStatusBar.system.removeStatusItem(statusItem)
    StatusItemDefaults[.preferredPosition, autosaveName] = cached
}
```

---

## NSStatusItem Position System

### UserDefaults Keys

macOS stores positions with this key format:
```
NSStatusItem Preferred Position <autosaveName>
```

### Ordinal Values

| Value | Meaning |
|-------|---------|
| 0 | Rightmost position (near Control Center) |
| 1 | Second from right |
| 2 | Third from right |

### Position Persistence

- Positions persist across app launches
- Stored in the app's UserDefaults domain
- User can manually reposition with Cmd+drag

---

## Debugging Checklist

### Icons in Wrong Position?

1. **Check stored positions**:
   ```bash
   defaults read com.sanebar.app | grep -i "NSStatusItem"
   ```

2. **Verify seeding happened**:
   - Position 0 should exist for main icon
   - Position 1 should exist for separator

3. **Test with fresh prefs**:
   ```bash
   defaults delete com.sanebar.app
   ```

### Icons Not Appearing?

1. Check if items were created (log in StatusBarController.init)
2. Verify autosaveNames are being set
3. Check window layer (should be 25 for status items)

---

## Anti-Patterns to Avoid

| Approach | Why It Fails |
|----------|--------------|
| Pixel X-coordinates | macOS expects ordinal values (0,1,2) |
| Create before seeding | macOS reads position on creation |
| Recovery/validation logic | Unnecessary if initialization is correct |
| Disabling autosaveName | Loses position persistence |
| Complex coordinate calculations | Simple ordinal values work |
| Continuous position monitoring | Single correct initialization is sufficient |

---

## Reference Implementation

Ice source code provides the authoritative pattern:

- **StatusItemDefaults.swift**: UserDefaults key proxy
- **ControlItem.swift**: Item creation with seeding pattern
- **MigrationManager.swift**: Version upgrades and position migration

Repository: https://github.com/jordanbaird/Ice

---

## Files

| File | Purpose |
|------|---------|
| `Core/Controllers/StatusBarController.swift` | Item creation, position seeding |
| `Core/Services/HidingService.swift` | Length toggle for hide/show |
| `Core/MenuBarManager.swift` | Overall orchestration |

---

## Environment Variables

| Variable | Purpose | Status |
|----------|---------|--------|
| `SANEBAR_UI_TESTING` | Enable UI testing mode | Active |
| `SANEBAR_STATUSITEM_DELAY_MS` | Delay item creation | Active |

---

## ⚠️ Debug Build Offscreen Window Issue

### The Problem

When building and launching SaneBar locally via `xcodebuild` (especially with custom `derivedDataPath`), windows may appear **completely offscreen** and become inaccessible. This is a long-standing issue that was previously considered unfixable.

### Symptoms

- Settings window opens but is invisible (offscreen)
- App launches but no UI appears on any display
- Cannot interact with the app despite it running

### Potential Fix (Discovered Jan 24, 2026)

**NOT FULLY VERIFIED** - Use at your own risk.

Resetting all app defaults and saved window state may fix the issue:

```bash
# Reset defaults for both debug and release bundle IDs
defaults delete com.sanebar.dev
defaults delete com.sanebar.app

# Remove saved application state (window positions)
rm -rf ~/Library/Saved\ Application\ State/com.sanebar.dev.savedState
rm -rf ~/Library/Saved\ Application\ State/com.sanebar.app.savedState
```

After running these commands, the next app launch should recreate fresh window positions.

### Prevention

A Claude Code hook at `.claude/hooks/block-sanebar-launch.rb` can block local app launches to prevent this issue. If hooks are centralized via SaneProcess, make sure the global hook config still invokes this script. Only headless operations should be allowed when the hook is active:

| Allowed | Blocked |
|---------|---------|
| `xcodebuild build` | `open SaneBar.app` |
| `xcodebuild test` | `./scripts/SaneMaster.rb test_mode` |
| Code review (grep/read) | `build_run_macos` |

### Root Cause (Unknown)

The exact cause is unclear. Theories include:
- Different code signing between Xcode GUI and CLI builds
- DerivedData path affecting bundle metadata
- Saved window state incompatibility between build configurations

If you discover the root cause, please document it here.
