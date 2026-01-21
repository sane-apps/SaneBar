# Control Center Individual Items Fix

> **Branch:** `feature/control-center-items` (archived 2026-01-20)
> **Status:** ⏸️ PAUSED - Branch archived during docs audit. Revisit when prioritized.
> **Created:** 2026-01-12
> **Updated:** 2026-01-12

## Problem

Battery (and other Control Center items) don't appear in Find Icon window because:

1. Control Center (`com.apple.controlcenter`) owns multiple independent menu bar icons:
   - AirDrop
   - Battery
   - Clock
   - Focus
   - Wi-Fi
   - Control Center button

2. Current code groups items by **bundle ID** and keeps only ONE entry per app

3. Result: All Control Center items collapsed into single "Control Center" entry

## Discovery

Running this test script reveals Control Center's structure:

```swift
// Control Center's AXExtrasMenuBar children have:
// - AXDescription: "Battery", "Wi-Fi", "Clock", etc.
// - AXIdentifier: "com.apple.menuextra.battery", etc.
// - AXPosition: x coordinate (negative = hidden, positive = visible)
```

**Test results (2026-01-12):**
```
[0] desc=AirDrop, id=com.apple.menuextra.airdrop, x=-4036 (HIDDEN)
[1] desc=Battery, id=com.apple.menuextra.battery, x=-3947 (HIDDEN)
[2] desc=Clock, id=com.apple.menuextra.clock, x=1326 (VISIBLE)
[3] desc=Focus, id=com.apple.menuextra.focusmode, x=-4074 (HIDDEN)
[4] desc=Wi-Fi, id=com.apple.menuextra.wifi, x=-3985 (HIDDEN)
[5] desc=Control Center, id=com.apple.menuextra.controlcenter, x=1284 (VISIBLE)
[6-13] desc=nil, id=nil, x=0 (unused slots)
```

## Solution Design

### 1. Model Changes (`Core/Models/RunningApp.swift`)

Add support for "virtual" apps representing Control Center items:

```swift
struct RunningApp {
    // Existing fields...

    // New: For Control Center items
    var menuExtraIdentifier: String?  // e.g., "com.apple.menuextra.battery"
    var isControlCenterItem: Bool { menuExtraIdentifier != nil }

    // Unique ID: use menuExtraIdentifier if present, else bundleID
    var uniqueId: String {
        menuExtraIdentifier ?? id
    }
}
```

### 2. AccessibilityService Changes

In `listMenuBarItemOwners()` and `listMenuBarItemsWithPositions()`:

```swift
// Special-case Control Center
if bundleID == "com.apple.controlcenter" {
    // Enumerate children instead of treating as single app
    for item in items {
        if let identifier = getAXIdentifier(item),
           let description = getAXDescription(item),
           !identifier.isEmpty {
            // Create virtual RunningApp for each item
            let virtualApp = RunningApp(
                name: description,  // "Battery", "Wi-Fi", etc.
                bundleId: bundleID,
                menuExtraIdentifier: identifier,
                icon: getIconForMenuExtra(identifier)
            )
            apps.append((app: virtualApp, x: xPos))
        }
    }
} else {
    // Normal handling for other apps
}
```

### 3. Move Operation Changes

Update `moveMenuBarIcon()` to accept either:
- Bundle ID (existing behavior)
- Menu extra identifier (new, for Control Center items)

```swift
func moveMenuBarIcon(
    bundleID: String,
    menuExtraId: String?,  // NEW
    toHidden: Bool,
    separatorX: CGFloat
) -> Bool {
    if let extraId = menuExtraId {
        // Find specific Control Center item by identifier
        return moveControlCenterItem(identifier: extraId, toHidden: toHidden, separatorX: separatorX)
    } else {
        // Existing logic for regular apps
    }
}
```

### 4. Icon Mapping

Map menu extra identifiers to SF Symbols:

```swift
static func iconForMenuExtra(_ identifier: String) -> String {
    switch identifier {
    case "com.apple.menuextra.battery": return "battery.100"
    case "com.apple.menuextra.wifi": return "wifi"
    case "com.apple.menuextra.bluetooth": return "bluetooth"
    case "com.apple.menuextra.clock": return "clock"
    case "com.apple.menuextra.airdrop": return "airdrop"
    case "com.apple.menuextra.focusmode": return "moon.fill"
    case "com.apple.menuextra.controlcenter": return "switch.2"
    default: return "questionmark.circle"
    }
}
```

## Testing Checklist

Before merging to main:

- [ ] Battery appears in Find Icon (Hidden view when hidden)
- [ ] Wi-Fi appears in Find Icon
- [ ] Clock appears in Find Icon (Visible view)
- [ ] Focus appears in Find Icon
- [ ] Moving Battery to Visible works
- [ ] Moving Wi-Fi to Hidden works
- [ ] Other apps (non-Control Center) still work normally
- [ ] Performance: scanning time acceptable
- [ ] No crashes on various macOS versions

## Files Modified

1. ✅ `Core/Models/RunningApp.swift` - Added `menuExtraIdentifier`, `uniqueId`, `isControlCenterItem`, and `controlCenterItem()` factory
2. ✅ `Core/Services/AccessibilityService.swift` - Added `enumerateControlCenterItems()` and updated all scanning methods
3. ⏳ `Core/MenuBarManager.swift` - TODO: Update moveIcon for menu extras
4. ⏳ `UI/SearchWindow/MenuBarSearchView.swift` - TODO: Handle virtual apps in UI (may work automatically)

## Risks

- **Performance**: Enumerating Control Center items adds overhead
- **Stability**: AX API might behave differently across macOS versions
- **Edge cases**: What if user has Control Center items disabled?

## Rollback Plan

If issues found, simply don't merge. Main branch remains stable.
