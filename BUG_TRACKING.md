# SaneBar Bug Tracking

> **Navigation**
> | Session | Features | How to Work | Releases | Testimonials |
> |---------|----------|-------------|----------|--------------|
> | [SESSION_HANDOFF.md](SESSION_HANDOFF.md) | [marketing/feature-requests.md](marketing/feature-requests.md) | [DEVELOPMENT.md](DEVELOPMENT.md) | [CHANGELOG.md](CHANGELOG.md) | [marketing/testimonials.md](marketing/testimonials.md) |

**Single source of truth for all bugs.** GitHub issues link here, not vice versa.

---

## GitHub Issues Cross-Reference

| GitHub | Title | Status | Internal Ref |
|--------|-------|--------|--------------|
| [#21](https://github.com/sane-apps/SaneBar/issues/21) | Icons hidden behind notch | Open | See BUG-021 below |
| [#20](https://github.com/sane-apps/SaneBar/issues/20) | M4 tint not working | Open | See BUG-020 below |
| [#18](https://github.com/sane-apps/SaneBar/issues/18) | Hiding icons not working | Open | See BUG-022 below |
| [#16](https://github.com/sane-apps/SaneBar/issues/16) | Design improvements | Open | UI suggestions, not bugs |
| [#12](https://github.com/sane-apps/SaneBar/issues/12) | Hide SaneBar icon | Reopened | Feature request |

---

## ⚠️ WORKING BASELINE - Commit 3cb6e9b (2026-01-13)

**Icon Moving**: Functional for all apps except VibeProxy (BUG-018)
**Classification**: Hidden/Visible tabs working correctly
**Coordinate System**: Direct AX global coords, separatorX ± 50 targeting

**DO NOT MODIFY** icon moving logic without consulting SESSION_HANDOFF.md

---

## Active Bugs (GitHub-Tracked)

### BUG-020: Menu bar tint not working on M4 Macs
**GitHub**: [#20](https://github.com/sane-apps/SaneBar/issues/20)
**Status**: INVESTIGATING
**Priority**: HIGH

**Symptom**: Menu bar tint flashes briefly on boot/shutdown but doesn't persist during normal use on M4 Macs.

**Environment**: M4 MacBook Air, dark mode, macOS Sequoia/Tahoe

**Related Issues** (from legacy tracking):
- Liquid Glass effect hides menu bar content
- Liquid Glass tint color not applied (grey only)
- Rounded corners toggle has no visible effect

**Root Cause (suspected)**: SwiftUI compositor blending vs AppKit Core Graphics direct drawing. Ice uses different approach that works.

**Research (Jan 17, 2026)**:
- SaneBar: SwiftUI `Rectangle().fill(Color.opacity())` - relies on compositor
- Ice: AppKit `NSView.draw()` with `NSColor.setFill(); rect.fill()` - direct drawing
- Ice also uses `.fullSizeContentView, .nonactivatingPanel` styleMask

**Action Items**:
- [ ] Test adding `.fullSizeContentView, .nonactivatingPanel` to window styleMask
- [ ] Consider rewriting `MenuBarOverlayView` as `NSView` subclass if quick fix fails

---

### BUG-021: Icons hidden behind notch on internal display
**GitHub**: [#21](https://github.com/sane-apps/SaneBar/issues/21)
**Status**: KNOWN LIMITATION
**Priority**: MEDIUM

**Symptom**: Switching from external monitor to internal MacBook display causes icons to get hidden by notch.

**Environment**: M4 MacBook Air, external + internal display setup

**Root Cause**: SaneBar doesn't auto-detect or rescue notch-hidden icons. Same behavior as other menu bar managers.

**Workaround**: Settings → Advanced → Enable "Tighter menu bar icons" (spacing 4). Requires logout.

**Decision**: Document as known limitation. Future feature: notch-aware overflow menu.

---

### BUG-022: Hiding icons not working for some users
**GitHub**: [#18](https://github.com/sane-apps/SaneBar/issues/18)
**Status**: INVESTIGATING
**Priority**: HIGH

**Symptom**: User drags icons to left of SaneBar icon but clicking SaneBar icon does nothing.

**Environment**: macOS Sequoia 15.7.2, v1.0.5

**Root Cause**: Unknown - may be separator position issue or accessibility permission problem.

**Action Items**:
- [ ] Request more details from user (screenshot of Console logs)
- [ ] Check if this relates to BUG-016 (separator misplaced on screen switch)

---

## Active Bugs (Internal)

### BUG-023: Dock icon appears on startup even when disabled
**Status**: FIXED - PENDING VERIFICATION (2026-01-23)
**Priority**: HIGH
**Reported**: 2026-01-10

**Symptom**: App shows in the Dock on startup even when "Show in Dock" is OFF. Toggling the setting on/off fixes it.

**Root Cause**: `ActivationPolicyManager.applyInitialPolicy()` used `DispatchQueue.main.async` which deferred policy application, allowing the dock icon to flash briefly on startup.

**Fix**: Apply dock visibility immediately in `MenuBarManager.loadSettings()` by calling `ActivationPolicyManager.applyPolicy(showDockIcon:)` synchronously right after loading settings from persistence.

**File**: `Core/MenuBarManager.swift:492-494`

---

### BUG-024: Reveal All should toggle + override auto-hide
**Status**: OPEN
**Priority**: MEDIUM
**Reported**: 2026-01-10

**Symptom**: "Reveal All" should become a two-way toggle (Reveal All → Hide All). When manually revealed, it should trump auto-hide logic.

**Action Items**:
- [ ] Add toggle state to Reveal All button
- [ ] Override auto-hide timer when manually revealed

---

### BUG-025: Support/Donate view blocks settings tabs
**Status**: FIXED - PENDING VERIFICATION (2026-01-23)
**Priority**: MEDIUM
**Reported**: 2026-01-11

**Symptom**: Opening the Support/Donate UI prevents switching between Settings tabs; user must close Settings to exit.

**Root Cause**: SwiftUI `.sheet()` modifiers are modal and block interaction with parent view, including the tab bar.

**Fix**: Changed from `.sheet()` to `.popover()` presentation for Licenses, Support, and Feedback views. Popovers are non-modal and allow interaction with the parent view.

**File**: `UI/Settings/AboutSettingsView.swift:90-100`

---

## Improvements from SaneClip (Port These)

> These patterns were developed in SaneClip and should be ported to SaneBar.

### IMP-001: Security-by-Default (Implemented in v1.0.12)
**Status**: RESOLVED (2026-01-22)
**Action Items**:
- [x] Sparkle Signature Fix (v1.0.12)
- [x] Find Icon Performance Fix (v1.0.12) (See GH #29)


**Pattern**: Reducing any security setting requires system authentication (Touch ID or password). No master toggle needed - it's automatic.

**Behavior**:
- Turning ON protections → no auth needed
- Turning OFF protections → always requires auth
- Removing items from exclusion lists → always requires auth

**Implementation**:
```swift
private func authenticateForSecurityChange(reason: String, onSuccess: @escaping () -> Void) {
    let context = LAContext()
    var error: NSError?
    let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        ? .deviceOwnerAuthenticationWithBiometrics
        : .deviceOwnerAuthentication

    context.evaluatePolicy(policy, localizedReason: reason) { success, _ in
        DispatchQueue.main.async {
            if success { onSuccess() }
        }
    }
}
```

**Action Items**:
- [ ] Add `authenticateForSecurityChange()` to SettingsView
- [ ] Wrap all "reduce security" actions with auth call

---

### IMP-002: Dock Visibility on Launch (Fixes BUG-023)
**Status**: FIXED - PENDING VERIFICATION (2026-01-23)
**Priority**: HIGH
**Source**: SaneClip `SettingsModel.swift`

**Pattern**: Apply dock visibility setting immediately in `SettingsModel.init()`, not just when toggled.

**Implementation**: Added `ActivationPolicyManager.applyPolicy(showDockIcon:)` call in `MenuBarManager.loadSettings()` immediately after loading settings from persistence. This ensures the dock policy is applied synchronously before any UI is shown.

**File**: `Core/MenuBarManager.swift:492-494`

---

### IMP-003: Settings UI Aesthetics
**Priority**: MEDIUM
**Source**: SaneClip `UI/Settings/SettingsView.swift`

**Components to port**:
- `SettingsGradientBackground` - Glass effect with gradient
- `CompactSection` - Row-based sections with rounded corners
- `CompactRow`, `CompactToggle`, `CompactDivider` - Consistent padding/alignment
- `VisualEffectBlur` - NSVisualEffectView wrapper for dark mode

**Action Items**:
- [ ] Review SaneClip SettingsView.swift for component implementations
- [ ] Decide which aesthetic elements to adopt

---

### IMP-004: Row-Based Exclusion List UI
**Priority**: MEDIUM
**Source**: SaneClip `UI/Settings/SettingsView.swift`

**Pattern**: Clean row layout instead of chips/tags for exclusion lists:
- Each item on its own row
- X button right-aligned
- "Add..." button (not dropdown menu)
- File picker opens directly to relevant folder

**Action Items**:
- [ ] Review current SaneBar exclusion UI
- [ ] Implement row-based pattern if applicable

---

### BUG-018: VibeProxy icon cannot be moved via Find Icon

**Status**: KNOWN LIMITATION (2026-01-13)

**Symptom**: In Find Icon, right-click "Move to Hidden/Visible" works for all apps EXCEPT VibeProxy (VS Code fork). Icon position remains unchanged after Cmd+drag attempt.

**Reporter**: Internal (sj)

**Root Cause**: Unknown - VibeProxy may handle AXUIElement interactions or Cmd+drag differently than standard apps. All other tested apps (Pipit, standard menu bar apps) move successfully with the simplified coordinate approach.

**Workaround**: None - users must manually drag VibeProxy icon in the actual menu bar.

**Decision**: Not investigating further. Edge case accepted.

---
### BUG-017: Find Icon “Visible” collapses into one tile

**Status**: RESOLVED (2026-01-13)

**Symptom**: In Find Icon, the “Visible” mode shows everything compressed/collapsed into a single (often black) tile with a numeric-looking label, instead of one tile per visible menu bar icon.

**Reporter**: Internal (sj)

**Context**:
- Recent work expanded system-owned menu extras (SystemUIServer / Control Center) into individual virtual items.
- SwiftUI identity collisions were fixed by splitting `RunningApp.bundleId` (owner) from `RunningApp.id` (unique per tile), but the user still reports Visible is collapsed.

**Most Likely Root Causes**:
- `MenuBarManager.getSeparatorOriginX()` returning an incorrect `separatorX`, causing `SearchService.refreshVisibleMenuBarApps()` to filter almost everything out.
- AX `xPosition` values for many items landing on the wrong side of `separatorX` (coordinate mismatch).
- Over-filtering during scanning of menu extras (items being rejected due to missing/odd `AXIdentifier`/labels).

**Files / Areas**:
- `Core/Services/SearchService.swift` (Visible/Hidden filtering by `separatorX`)
- `Core/Services/AccessibilityService+Scanning.swift` (menu extra enumeration + filtering)
- `Core/MenuBarManager.swift` (separator position / `getSeparatorOriginX()`)
- `UI/SearchWindow/MenuBarSearchView.swift` (mode switching + refresh path)

**Action Items**:
- [ ] Add logging: separatorX + min/max item x + visible/hidden counts
- [ ] Log accepted/rejected SystemUIServer menu extras (identifier/label/x/width)
- [ ] Confirm whether “All” mode is correct; if yes, focus on separatorX

---

### BUG-012: Crash on Mac Mini M4 with Sequoia

**Status**: INVESTIGATING

**Symptom**: SaneBar immediately crashes upon start on Mac Mini M4 with Sequoia.

**Reporter**: u/MaxGaav (Reddit)

**Root Cause**: Unknown - awaiting crash report

**Action Items**:
- [ ] Request crash report from user
- [ ] Check if Accessibility permission dialog is causing issue
- [ ] Test on Apple Silicon Mac Mini if available

---

### BUG-013: Menu bar icon unclear on 2K monitors

**Status**: RESOLVED (2026-01-12)

**Symptom**: "On my 2k monitor display the icon doesn't look completely well. Maybe the lines inside are too small..."

**Reporter**: u/nxnayx (Reddit)

**Root Cause**: PNG-based menu bar icon with rasterization artifacts at various DPIs.

**Fix**: Replaced PNG asset with SVG-based menu bar icon (vector graphics scale cleanly at any DPI).

**File**: `docs/images/menubar-icon.svg`

**Regression Test**: Visual verification on 2K/4K displays

---

### BUG-014: Find Icon window slow to respond

**Status**: INVESTIGATING

**Symptom**: "The Find Icon function is slow to respond. My main purpose of using this type of app is to search and click on hidden icons, so this feature needs to be polished."

**Reporter**: u/Elegant_Mobile4311 (Reddit)

**Root Cause**: Unknown - may be related to icon scanning/caching or UI rendering

**Action Items**:
- [ ] Profile Find Icon window open time
- [ ] Check if initial scan is blocking UI thread
- [ ] Verify cache-first loading is working correctly

---

### BUG-015: Keyboard shortcuts reset to defaults after restart

**Status**: INVESTIGATING

**Symptom**: "I tried to disable all the shortcuts by leaving them empty, but I found that after a computer restart, all the default shortcuts are reloaded and applied."

**Reporter**: u/Kin_KC (Reddit)

**Root Cause**: Likely persistence issue - cleared shortcuts may not be saving correctly, or defaults are being re-applied on launch.

**Action Items**:
- [ ] Check KeyboardShortcutsService initialization logic
- [ ] Verify empty shortcut state is being persisted
- [ ] Test clearing shortcuts and restarting

---

### BUG-016: "Separator Misplaced" popup when switching screens

**Status**: INVESTIGATING

**Symptom**: "Switch between screens, I get a 'Separator Misplaced' pop-up (most times). If I hide again, it is fine until I swap screens again."

**Reporter**: u/LOUNITY (Reddit)

**Root Cause**: Multi-display handling issue - separator position validation may be failing when screen configuration changes.

**Action Items**:
- [ ] Review separator position validation logic
- [ ] Check NSScreen.screens change notification handling
- [ ] Test with external monitor connect/disconnect

---

## UX Audit Fixes (2026-01-02)

> **Note**: These are historical records. File references may be outdated due to refactoring.

External auditor identified 5 usability issues. Status varies:

### UI-001: Three Confusing Eye Icons

**Root Cause**: Three similar SF Symbols (eye, eye.slash, eye.trianglebadge.exclamationmark) were indistinguishable.

**Fix**: Replaced with SwiftUI segmented Picker using clear text labels: "Show", "Hide", "Bury"

**File**: *(Historical - file was refactored)*

---

### UI-002: Manual Refresh Button

**Root Cause**: No auto-detection of menu bar changes; users had to manually click Refresh.

**Fix**:
- Removed Refresh button from header
- Auto-refresh now handled by settings window lifecycle

**Files**: *(Historical - implementation changed)*

---

### UI-003: Keyboard Shortcut Conflict

**Root Cause**: ⌘B conflicts with "Bold" in text editors globally.

**Fix**: Changed default to ⌘\ (backslash). User can still customize in Shortcuts tab.

**File**: `Core/Services/KeyboardShortcutsService.swift:120-123`

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

**File**: *(Historical - file was refactored)*

---

### INFRA-001: Stale Diagnostics Logs

**Root Cause**: `find_app_log()` searched entire `@diagnostics_dir` (all historical exports) instead of the current export path.

**Fix**:
- Changed to accept `export_path` parameter and scope search to current export only
- Added `cleanup_old_exports()` to keep only last 3 diagnostic exports
- Made diagnostics.rb project-aware using `project_name` method

**Files**: `scripts/sanemaster/diagnostics.rb:38-47, 159-164`

---

### INFRA-002: Stale Build Detection

**Root Cause**: Could launch old app binary after source changes without rebuilding.

**Fix**: Added stale build detection to `launch_app()`:
- Compares binary mtime vs newest source file mtime
- Auto-rebuilds if stale (unless `--force` flag)
- Made test_mode.rb project-aware using `project_name` method

**Files**: `scripts/sanemaster/test_mode.rb:17-47`

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

### BUG-011: Ralph-Wiggum (SaneLoop) Plugin Parsing Errors

**Status**: PARTIALLY RESOLVED (2026-01-03)

**Symptom**: `/ralph-loop` and `/cancel-ralph` commands fail with parse errors like `command not found: PHASES:` or `parse error near ')'`. Special characters in prompts break shell parsing.

**Root Cause**:
1. `ralph-loop.md` passes `$ARGUMENTS` unquoted - newlines cause each line to execute as command
2. `ralph-loop.md` - even with quotes, parentheses `)` still cause `parse error near ')'`
3. `cancel-ralph.md` uses multiline `[[ -f` conditional which fails in the ` ```! ` execution context

**Fix Attempt 1** (2026-01-02) - Partial:
```bash
# Added eval wrapper:
eval "\"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh\" $ARGUMENTS"
```

**Fix Attempt 2** (2026-01-03) - Partial:
```bash
# Added quotes around $ARGUMENTS to handle newlines:
eval "\"${CLAUDE_PLUGIN_ROOT}/scripts/setup-ralph-loop.sh\" \"$ARGUMENTS\""
```
This fixes multi-line prompts but NOT prompts containing `()` or other shell metacharacters.

For `cancel-ralph.md`:
```bash
# Changed to single-line:
if test -f .claude/ralph-loop.local.md; then ITERATION=$(...); echo "..."; else echo "..."; fi
```

**Files Fixed** (3 locations x 2 commands = 6 files in `~/.claude/plugins/`):
- `cache/claude-plugins-official/ralph-wiggum/6d3752c000e2/commands/`
- `cache/claude-plugins-official/ralph-wiggum/unknown/commands/`
- `marketplaces/claude-plugins-official/plugins/ralph-wiggum/commands/`

**Workaround**: Use simple prompts without parentheses, brackets, or colons in SaneLoop commands.

**Proper Fix Needed**: Plugin should write $ARGUMENTS to a temp file and have the script read from it, avoiding shell parsing entirely.

**Note**: Claude Code caches plugins at session start. Fixes require session restart to take effect.

**Regression Test**: None (external plugin, not project code)

---

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

**Root Cause**: `./scripts/SaneMaster.rb clean --nuclear` did not clear Xcode's asset catalog cache at `~/Library/Caches/com.apple.dt.Xcode/`.

**Fix**: Updated `scripts/sanemaster/verify.rb:63-97` to include asset cache clearing:
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
