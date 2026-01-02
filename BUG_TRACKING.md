# SaneBar Bug Tracking

## Active Bugs

*None currently*

---

## UX Audit Fixes (2026-01-02)

External auditor identified 5 usability issues. All resolved:

### UI-001: Three Confusing Eye Icons

**Root Cause**: Three similar SF Symbols (eye, eye.slash, eye.trianglebadge.exclamationmark) were indistinguishable.

**Fix**: Replaced with SwiftUI segmented Picker using clear text labels: "Show", "Hide", "Bury"

**File**: `UI/Components/StatusItemRow.swift:84-103`

---

### UI-002: Manual Refresh Button

**Root Cause**: No auto-detection of menu bar changes; users had to manually click Refresh.

**Fix**:
- Removed Refresh button from header
- Added 5-second auto-refresh timer in `MenuBarManager.startAutoRefresh()`
- Timer starts/stops with settings window lifecycle

**Files**: `Core/MenuBarManager.swift:317-333`, `UI/SettingsView.swift:118-123`

---

### UI-003: Keyboard Shortcut Conflict

**Root Cause**: ⌘B conflicts with "Bold" in text editors globally.

**Fix**: Changed to Option+S (user-implemented)

---

### UI-004: Privacy Badge Placement

**Root Cause**: Prominent "100% On-Device" badge above tabs competed with functional UI.

**Fix**: Moved CompactPrivacyBadge to footer - always visible for peace of mind but not intrusive.

**File**: `UI/SettingsView.swift:456-458`

---

### UI-005: Usage Tab Vanity Metrics

**Root Cause**: Raw click counts ("Total Clicks: 0") are not actionable.

**Fix**:
- Smart Suggestions now primary content
- Usage stats moved to collapsible DisclosureGroup

**File**: `UI/UsageStatsView.swift:24-48`

---

### INFRA-001: Stale Diagnostics Logs

**Root Cause**: `find_app_log()` searched entire `@diagnostics_dir` (all historical exports) instead of the current export path.

**Fix**:
- Changed to accept `export_path` parameter and scope search to current export only
- Added `cleanup_old_exports()` to keep only last 3 diagnostic exports
- Made diagnostics.rb project-aware using `project_name` method

**Files**: `Scripts/sanemaster/diagnostics.rb:38-47, 159-164`

---

### INFRA-002: Stale Build Detection

**Root Cause**: Could launch old app binary after source changes without rebuilding.

**Fix**: Added stale build detection to `launch_app()`:
- Compares binary mtime vs newest source file mtime
- Auto-rebuilds if stale (unless `--force` flag)
- Made test_mode.rb project-aware using `project_name` method

**Files**: `Scripts/sanemaster/test_mode.rb:17-47`

---

### INFRA-003: Project-Aware Tooling

**Root Cause**: Hardcoded "SaneBar"/"SaneVideo" strings required maintaining separate file versions.

**Fix**: Added `project_name` method that detects from current directory (`File.basename(Dir.pwd)`):
- Diagnostics directory: `#{project_name}_Diagnostics`
- Crash file globs: `#{project_name}-*.ips`
- DerivedData paths: `#{project_name}-*/...`
- Process names for `log` command: `process == "#{project_name}"`

**Result**: Both `diagnostics.rb` and `test_mode.rb` are now identical in both projects.

---

## Resolved Bugs

### BUG-007: Permission alert never displays

**Status**: RESOLVED (2026-01-01)

**Symptom**: When user clicks "Scan Menu Bar" without permission, `showPermissionRequest()` is called but no alert appears. The `showingPermissionAlert` property was set but never bound to UI.

**Root Cause**: `PermissionService.showingPermissionAlert` was a `@Published` property but no SwiftUI view was observing it with an `.alert()` modifier.

**Fix**:
1. Added `Notification.Name.showPermissionAlert` in `Core/Services/PermissionService.swift:7-10`
2. Updated `showPermissionRequest()` to post notification in `Core/Services/PermissionService.swift:140-141`
3. Added `.onReceive()` and `.alert()` modifiers in `UI/SettingsView.swift:19-30`

**Regression Test**: `Tests/MenuBarManagerTests.swift:testShowPermissionRequestPostsNotification()`

---

### BUG-006: Scan provides no visible feedback

**Status**: RESOLVED (2026-01-01)

**Symptom**: Clicking "Scan Menu Bar" or "Refresh" button provides no feedback. The `print()` statements in `scan()` went to stdout, invisible to users.

**Root Cause**: `MenuBarManager.scan()` used `print()` for logging which goes to Console.app, not the UI. The `isScanning` state was set but no success feedback was shown.

**Fix**:
1. Added `lastScanMessage` published property in `Core/MenuBarManager.swift:19`
2. Set success message after scan in `Core/MenuBarManager.swift:118`
3. Added 3-second auto-clear in `Core/MenuBarManager.swift:126-131`
4. Updated `SettingsView.headerView` to display the message with checkmark icon in `UI/SettingsView.swift:63-86`

**Regression Test**: `Tests/MenuBarManagerTests.swift:testScanSetsLastScanMessageOnSuccess()`, `testScanClearsLastScanMessageOnError()`

---

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
