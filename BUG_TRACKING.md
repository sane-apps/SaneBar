# SaneBar Bug Tracking

## Active Bugs

*None currently*

---

## Resolved Bugs

### BUG-001: Nuclear clean missing asset cache

**Status**: RESOLVED (2026-01-01)

**Symptom**: Custom MenuBarIcon not loading after asset catalog changes. SF Symbol "menubar.dock.rectangle" still displayed instead of custom icon.

**Root Cause**: `./Scripts/SaneMaster.rb clean --nuclear` did not clear Xcode's asset catalog cache at `~/Library/Caches/com.apple.dt.Xcode/`.

**Fix**: Updated `Scripts/sanemaster/verify.rb:63-97` to include asset cache clearing:
```ruby
system('rm -rf ~/Library/Caches/com.apple.dt.Xcode/')
system('rm -rf ~/Library/Developer/Xcode/DerivedData/ModuleCache.noindex')
```

**Regression Test**: `Tests/MenuBarIconTests.swift:testCustomIconLoadsFromAssetCatalog()`

---

### BUG-002: URL scheme opens browser instead of System Settings

**Status**: RESOLVED (2026-01-01)

**Symptom**: Clicking "Grant Access" opened Brave browser (default browser) instead of System Settings Accessibility panel.

**Root Cause**:
1. First fix attempt (AppleScript `reveal anchor`) failed - syntax broken since macOS Ventura (13+)
2. `NSWorkspace.shared.open(URL)` with `x-apple.systempreferences:` scheme gets hijacked by browsers

**Fix**: Use `open -b` shell command with explicit bundle ID in `Core/Services/PermissionService.swift:67-80`:
```swift
let url = "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility"
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
process.arguments = ["-b", "com.apple.systempreferences", url]
try process.run()
```

**Regression Test**: `Tests/PermissionServiceTests.swift:testPermissionInstructionsNotEmpty()`

**Lesson Learned**: AppleScript `reveal anchor` broken since Ventura. Always verify API compatibility with current macOS version (Tahoe 26.2).

---

### BUG-003: Timer polling not on main RunLoop

**Status**: RESOLVED (2026-01-01)

**Symptom**: Permission polling timer could fire on wrong thread, causing UI state inconsistencies.

**Root Cause**: Timer scheduled via `Timer.scheduledTimer()` without explicit RunLoop specification in an async context.

**Fix**: Ensured `PermissionService` is `@MainActor` isolated and timer uses `RunLoop.main`:
```swift
Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
    // Already on MainActor via class isolation
    self?.checkPermission()
}
```

**Regression Test**: `Tests/PermissionServiceTests.swift:testStartPollingCreatesTimer()`

---

### BUG-004: MenuBarIcon too large to render

**Status**: RESOLVED (2026-01-01)

**Symptom**: Custom MenuBarIcon not visible in menu bar despite code reporting "✅ Using custom MenuBarIcon".

**Root Cause**: Original icon was 2048x2048 pixels. Menu bar icons must be 18x18 (1x) / 36x36 (2x) to render properly.

**Fix**: Resized icons using `sips`:
```bash
sips -z 18 18 MenuBarIcon.png --out MenuBarIcon_1x.png
sips -z 36 36 MenuBarIcon.png --out MenuBarIcon_2x.png
```

Updated `Resources/Assets.xcassets/MenuBarIcon.imageset/Contents.json` to reference correctly sized files.

**Regression Test**: `Tests/MenuBarIconTests.swift:testCustomIconHasAppropriateDimensions()`

**Lesson Learned**: Verify image dimensions BEFORE assuming asset catalog is working. SDK docs specify menu bar icons should be 18pt (template images).

---

### BUG-005: Menu items greyed out / disabled

**Status**: RESOLVED (2026-01-01)

**Symptom**: All menu items (Toggle Hidden Items, Scan Menu Bar, Settings, Quit) appear greyed out and cannot be clicked.

**Root Cause**: `NSMenuItem` objects created without setting `target`. Without explicit target, actions route through responder chain. `MenuBarManager` is not an `NSResponder` subclass, so it's not in the chain → items disabled.

**Fix**: Set `target = self` on each menu item in `MenuBarManager.swift:69-78`:
```swift
let item = NSMenuItem(title: "...", action: #selector(...), keyEquivalent: "...")
item.target = self
menu.addItem(item)
```

**Regression Test**: `Tests/MenuBarManagerTests.swift:testMenuItemsHaveTargetSet()`

**Lesson Learned**: AppKit menu items need explicit `target` when the action handler is not in the responder chain. Verify API behavior before assuming.

---

## Bug Report Template

```markdown
### BUG-XXX: Short description

**Status**: ACTIVE | INVESTIGATING | RESOLVED (date)

**Symptom**: What the user sees

**Root Cause**: Technical explanation

**Fix**: Code changes with file:line references

**Regression Test**: Test file and function name
```
