# Menu Bar Interactions & Positioning

## Quick Reference

### Click Behavior
- **Left-click** on main SaneBar icon → Toggle hide/show
- **Right-click** on main icon → Context menu (Find Icon, Settings, Quit)
- **Separator ("/")** → Visual-only, not interactive

### Position Pre-Seeding Pattern

SaneBar seeds ordinal positions in UserDefaults (and ByHost) before creating NSStatusItems.
Seeding only happens when BOTH the app-domain AND ByHost values are missing or non-numeric.

```swift
// 1. SEED positions BEFORE creating items (checks both domains)
private static func seedPositionsIfNeeded() {
    let mainValues = preferredPositionValues(forAutosaveName: mainAutosaveName)
    let seedMain = shouldSeedPreferredPosition(
        appValue: mainValues.appValue, byHostValue: mainValues.byHostValue)
    if seedMain {
        setPreferredPosition(0, forAutosaveName: mainAutosaveName)  // 0 = rightmost
    }
    // ... same for separator (ordinal 1)
}

// 2. CREATE items AFTER seeding
init() {
    Self.clearPersistedVisibilityOverrides()
    Self.migrateCorruptedPositionsIfNeeded()
    Self.seedPositionsIfNeeded()

    mainItem = NSStatusBar.system.statusItem(withLength: .variableLength)
    mainItem.autosaveName = Self.mainAutosaveName
    mainItem.isVisible = true  // Force visible after Cmd+drag cleanup
    // ...
}
```

### Hiding Mechanism

NSStatusItem.length controls visibility:

| State | Separator Length | Effect |
|-------|------------------|--------|
| Expanded | 12–14px (style-dependent) | Normal divider appearance |
| Collapsed | 10,000px | Pushes items left of the separator off-screen |

Items aren't removed, just pushed off the left edge of the screen (x < 0).

---

## Key Rules

### Rule 1: Ordinal Positions, Not Pixel Coordinates

macOS interprets position values as ordering hints (0 = rightmost, 1 = second, etc.), not pixel coordinates.

### Rule 2: Seed BEFORE Create

macOS reads the position from UserDefaults when the item is created. Seeding after creation has no effect.

### Rule 3: Recovery Logic Exists for Edge Cases

macOS handles placement well for normal usage, but SaneBar has recovery paths for:
- **Corrupted positions** (negative values, legacy AH too small): `migrateCorruptedPositionsIfNeeded()`
- **Display changes** (Migration Assistant, monitor swap): `positionsNeedDisplayReset()`
- **Runtime invariant failures**: `recoverStartupPositions()`

These run on launch BEFORE item creation. Don't add new recovery paths without understanding these.

### Rule 4: Cache Positions Before Removal

macOS deletes position data when removing an NSStatusItem or setting `isVisible = false`.
When removing items (e.g. disabling AH separator), clear the stale position key so it
re-seeds cleanly on re-enable. See `ensureAlwaysHiddenSeparator(enabled: false)` for the pattern.

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

## Display-Aware Position Validation

macOS converts ordinal seeds (0, 1) to pixel offsets after first launch. If the app later runs on a different display (Migration Assistant, different Mac, monitor change), those stale pixel positions are meaningless but would pass normal validation.

### How It Works

On launch, `StatusBarController` checks:
1. **Stored screen width** (`SaneBar_CalibratedScreenWidth` in UserDefaults)
2. If no stored width (first launch after update): stamps current width, accepts positions as-is
3. If width changed >10% AND positions are pixel values (>10, <9000): resets to ordinals
4. After position cache warming, stamps the current screen width

### Detection Logic

| Position Value | Classification |
|---------------|----------------|
| 0, 1, 2 | Ordinal seed — not pixel-like |
| 10000 | AH sentinel — not pixel-like |
| 207, 800, 2400 | Pixel offset — pixel-like |

### When Reset Triggers

| Scenario | Reset? | Why |
|----------|--------|-----|
| Same Mac, same display | No | Width matches |
| First launch after update | No | No stored width — stamps and accepts |
| Migration Assistant to new Mac | Yes | Different width + pixel positions |
| External monitor swap | Yes | Different width + pixel positions |

---

## ByHost Visibility Override Cleanup (GitHub #86)

### The Problem

When a user **Cmd+drags** a status item off the menu bar, macOS writes a key like
`NSStatusItem Visible <autosaveName> = false` to the **ByHost global preferences**
domain (`.GlobalPreferences.<UUID>.plist` in `~/Library/Preferences/ByHost/`).

This key persists across launches and overrides `isVisible = true` at runtime,
causing the trigger icon to vanish permanently with no UI to recover it.

### Why Previous Cleanup Failed

The original implementation (`removeByHostVisibilityOverrides`) tried to reverse-engineer
macOS's autosaveName→ByHost key transform. It covered 4 hardcoded variants:

| Autosave Name | Hardcoded ByHost Key |
|---|---|
| `SaneBar_Main_v7` | `SaneBar_main_v7_v6` (lowercased first char) |
| `SaneBar_Main_v7` | `SaneBar_main_v7_v6` (fully lowercased) |
| `SaneBar_Separator_v7` | `SaneBar_separator_v7_v6` |
| `SaneBar_AlwaysHiddenSeparator_v7` | `SaneBar_alwayshiddenseparator_v7_v6` |

**Gaps that caused #86:**
- macOS sometimes writes the key **without lowercasing** (e.g. `SaneBar_Main_v7_v6`)
- Spacer items (`SaneBar_spacer_0` through `SaneBar_spacer_11`) were never cleaned
- macOS 26 introduces `NSStatusItem VisibleCC` keys (found in Thaw/Ice fork)
- Any future `_vN` suffix change would re-break cleanup

### The Fix: Wildcard Enumeration via CFPreferencesCopyKeyList

Instead of guessing key names, enumerate ALL keys in the ByHost global domain and
filter by prefix:

```swift
private static func removeAllByHostVisibilityOverrides() -> Bool {
    let globalDomain = ".GlobalPreferences" as CFString
    guard let allKeys = CFPreferencesCopyKeyList(
        globalDomain,
        kCFPreferencesCurrentUser,
        kCFPreferencesCurrentHost
    ) as? [String] else { return false }

    let prefixes = [
        "NSStatusItem Visible SaneBar_",
        "NSStatusItem VisibleCC SaneBar_"
    ]
    let keysToRemove = allKeys.filter { key in
        prefixes.contains(where: { key.hasPrefix($0) })
    }
    guard !keysToRemove.isEmpty else { return false }

    for key in keysToRemove {
        CFPreferencesSetValue(key as CFString, nil, globalDomain,
                              kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }
    CFPreferencesSynchronize(globalDomain, kCFPreferencesCurrentUser,
                             kCFPreferencesCurrentHost)
    return true
}
```

**Why this is bulletproof:**
- `CFPreferencesCopyKeyList` is public API since macOS 10.0, not deprecated
- Prefix matching catches ANY key variant macOS writes — past, present, or future
- Covers `Visible` and `VisibleCC` (macOS 26)
- Covers all spacer items automatically
- No reverse-engineering of naming transforms needed

### What Gets Cleaned (Full Scope)

| Domain | What | How |
|--------|------|-----|
| App (UserDefaults) | `NSStatusItem Visible SaneBar_Main_v7` etc. | Explicit loop over named items |
| App (UserDefaults) | `NSStatusItem Visible SaneBar_spacer_*` | Prefix sweep via `dictionaryRepresentation()` |
| ByHost (CFPreferences) | ALL `NSStatusItem Visible SaneBar_*` | Wildcard via `CFPreferencesCopyKeyList` |
| ByHost (CFPreferences) | ALL `NSStatusItem VisibleCC SaneBar_*` | Same wildcard (macOS 26 future-proofing) |

### Debugging Commands

```bash
# Check ByHost keys on this machine
defaults -currentHost read -globalDomain | grep -i "SaneBar.*[Vv]isible"

# Check app-domain keys
defaults read com.sanebar.app | grep -i "Visible"
defaults read com.sanebar.dev | grep -i "Visible"

# Nuclear option: manually clear all ByHost SaneBar visibility keys
defaults -currentHost delete -globalDomain "NSStatusItem Visible SaneBar_Main_v7_v6" 2>/dev/null
# (Use the wildcard approach in code — manual cleanup is a stopgap only)
```

### Regression Test Coverage

`StatusBarControllerTests.initClearsPersistedVisibilityOverrides` plants these keys
before init and verifies ALL are nil after:

| Key | What It Tests |
|-----|---------------|
| `NSStatusItem Visible SaneBar_Main_v7` | Standard app-domain |
| `NSStatusItem Visible SaneBar_main_v7_v6` | Known ByHost casing |
| `NSStatusItem Visible SaneBar_alwayshiddenseparator_v7_v6` | Legacy fully-lowercased |
| `NSStatusItem Visible SaneBar_Main_v7_v6` | **Unknown variant — no lowercasing (#86)** |
| `NSStatusItem VisibleCC SaneBar_main_v7_v6` | **macOS 26 VisibleCC** |
| `NSStatusItem Visible SaneBar_spacer_0_v6` | **Spacer ByHost key** |
| `NSStatusItem Visible SaneBar_spacer_0` | **Spacer app-domain key** |

### Timeline

- **v2.0**: First cleanup attempt — 2 hardcoded ByHost key variants
- **v2.1.x**: Added legacy lowercased variant — 4 hardcoded keys
- **v2.1.10 (#86 fix)**: Wildcard enumeration — catches ALL variants permanently

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

Key implementation files in SaneBar:

- **StatusBarController.swift**: Position seeding + item creation
- **HidingService.swift**: Length-toggle hide/show
- **MenuBarManager.swift**: Central coordination

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

The global hook `SaneProcess/scripts/hooks/sane_launch_guard.rb` (registered in `~/.claude/settings.json`)
blocks manual `open SaneBar.app` and direct binary execution. Use `sane_test.rb` for all testing.

| Allowed | Blocked |
|---------|---------|
| `sane_test.rb SaneBar` | `open SaneBar.app` |
| `xcodebuild build` | Direct binary execution |
| `xcodebuild test` | `open -a SaneBar` |
| `SaneMaster.rb test_mode` | Manual launch commands |

### Root Cause (Unknown)

The exact cause is unclear. Theories include:
- Different code signing between Xcode GUI and CLI builds
- DerivedData path affecting bundle metadata
- Saved window state incompatibility between build configurations

If you discover the root cause, please document it here.
