# Bartender Parity Plan

> SOP-compliant implementation plan for making SaneBar a genuine paid competitor to Bartender.

**Created:** 2026-01-02
**Research Sources:** Reddit, MacRumors, GitHub (Ice, Dozer, Hidden Bar), Apple Developer Forums

---

## Executive Summary

Based on forum research, Bartender users complain about:
1. **Trust issues** - Silent ownership change, added telemetry (v5.0.52+)
2. **Stability** - Crashes, freezes, cursor hijacking on macOS Tahoe
3. **Complexity** - 7000+ lines, accessibility API dependencies

**SaneBar's competitive advantage:**
- Zero telemetry, zero network requests
- Simple architecture (300 lines, NSStatusItem.length toggle)
- No accessibility permissions required
- Already macOS Tahoe compatible

**Gap to close:** Edge case handling and polish.

---

## SOP Rules Applied

| Rule | Application |
|------|-------------|
| **#0: NAME THE RULE** | Each task lists which rules apply |
| **#2: VERIFY BEFORE YOU TRY** | Check APIs exist before using |
| **#3: TWO STRIKES? INVESTIGATE** | Stop after 2 failures, research |
| **#5: THEIR HOUSE, THEIR RULES** | Use `./Scripts/SaneMaster.rb` only |
| **#6: BUILD, KILL, LAUNCH, LOG** | Full cycle after every change |
| **#7: NO TEST? NO REST** | Regression test for each fix |
| **#9: NEW FILE? GEN THAT PILE** | Run xcodegen if new files created |

---

## Phase 1: Stability Fixes (HIGH PRIORITY)

### 1.1 Verify Icon Position Persistence

**Problem:** Ice #344 - Menu bar items move to hidden section on restart (45+ comments, 37 upvotes)

**Current State:** SaneBar uses `autosaveName` (MenuBarManager.swift:87,100)

**Investigation:**
```bash
# Check if autosaveName actually persists
defaults read com.sanebar.app | grep -i statusitem
```

**Rules:** [#2: VERIFY], [#7: TEST]

**Files:**
- `Core/MenuBarManager.swift:87` - mainStatusItem autosaveName
- `Core/MenuBarManager.swift:100` - separatorItem autosaveName
- `Core/MenuBarManager.swift:300` - spacer autosaveName

**Test to Add:** `Tests/MenuBarManagerTests.swift`
```swift
@Test func autosaveNamesAreUnique() {
    // Verify each status item has unique autosaveName
    // This ensures macOS can persist positions correctly
}
```

**Acceptance Criteria:**
- [ ] `defaults read` shows saved positions
- [ ] Quit and relaunch preserves icon order
- [ ] Regression test passes

---

### 1.2 Crash Prevention Guards

**Problem:** Ice #821 - Crashes on click (macOS 26.1/26.2)

**Current State:** HidingService.swift has basic guards but no nil checks before toggle

**Rules:** [#6: BUILD, KILL, LAUNCH, LOG], [#7: TEST]

**Files:**
- `Core/Services/HidingService.swift:81-89` - toggle() method
- `Core/Services/HidingService.swift:92-112` - show() method
- `Core/Services/HidingService.swift:114-137` - hide() method

**Fix:** Add defensive guards:
```swift
// HidingService.swift:81
func toggle() async {
    guard delimiterItem != nil else {
        logger.error("toggle() called but delimiterItem is nil - skipping")
        return
    }
    // ... existing code
}
```

**Test to Add:** `Tests/HidingServiceTests.swift`
```swift
@Test func toggleWithNilDelimiterDoesNotCrash() async {
    let service = HidingService()
    // Don't configure - delimiterItem is nil
    await service.toggle()
    // Should not crash, should log error
}
```

**Verification:**
```bash
./Scripts/SaneMaster.rb verify
killall -9 SaneBar
./Scripts/SaneMaster.rb launch
./Scripts/SaneMaster.rb logs --follow
# Click rapidly on SaneBar icon - should not crash
```

**Acceptance Criteria:**
- [ ] No crash when clicking rapidly
- [ ] Error logged if delimiterItem is nil
- [ ] Regression test passes

---

### 1.3 Full Screen Mode Handling

**Problem:** Ice #331 - Hidden icons don't appear when menu bar auto-hides in full screen

**Current State:** No full screen detection in SaneBar

**Rules:** [#2: VERIFY], [#6: BUILD, KILL, LAUNCH, LOG]

**Investigation:**
```bash
./Scripts/SaneMaster.rb verify_api NSScreen.main?.visibleFrame AppKit
./Scripts/SaneMaster.rb verify_api NSApplication.shared.presentationOptions AppKit
```

**Files:**
- `Core/Services/HidingService.swift` - Add full screen detection
- `Core/MenuBarManager.swift` - Adjust behavior when full screen

**Approach:**
1. Detect full screen via `NSApp.presentationOptions.contains(.fullScreen)`
2. When in full screen + auto-hide menu bar, use longer animation delay
3. Or: post notification to user that full screen mode has limitations

**Test:** Manual with AppleScript
```bash
# Enter full screen
osascript -e 'tell app "Safari" to activate' -e 'delay 0.5' -e 'tell app "System Events" to keystroke "f" using {command down, control down}'
# Wait for full screen
sleep 2
# Toggle SaneBar
osascript -e 'tell app "SaneBar" to toggle'
# Verify icons appear (manual check)
```

**Acceptance Criteria:**
- [ ] In full screen, toggle still works (or shows helpful message)
- [ ] No crash in full screen mode
- [ ] Behavior documented in Settings

---

## Phase 2: Multi-Display Support (MEDIUM PRIORITY)

### 2.1 External Monitor Verification

**Problem:** Ice #836 - Doesn't work on external monitor with auto-hide menu bar

**Current State:** Untested on multiple displays

**Rules:** [#2: VERIFY], [#6: BUILD, KILL, LAUNCH, LOG]

**Investigation:**
```swift
// Check how many screens
NSScreen.screens.count
// Check which screen has menu bar
NSScreen.screens.first { $0.frame.contains(NSStatusBar.system.statusItems.first?.button?.window?.frame ?? .zero) }
```

**Files:**
- `Core/MenuBarManager.swift` - May need screen-aware logic
- `Core/Services/HidingService.swift` - Verify length toggle works on all screens

**Test:** Requires physical external monitor or Sidecar
```bash
# Connect external display
# Move SaneBar to external display menu bar
# Toggle - verify it works
```

**Acceptance Criteria:**
- [ ] Toggle works on primary display
- [ ] Toggle works on secondary display
- [ ] No different behavior between displays

---

### 2.2 Notch-Aware Spacing

**Problem:** Icons disappear behind MacBook notch when too many

**Current State:** No notch detection

**Rules:** [#2: VERIFY]

**Investigation:**
```bash
./Scripts/SaneMaster.rb verify_api NSScreen.safeAreaInsets AppKit
```

**Note:** `safeAreaInsets` is iOS. For macOS, check:
```swift
// Notched Macs have auxiliaryTopLeftArea and auxiliaryTopRightArea
NSScreen.main?.auxiliaryTopLeftArea  // Available macOS 12+
```

**Files:**
- `Core/MenuBarManager.swift` - Add notch detection helper
- `UI/SettingsView.swift` - Show warning if many icons + notched Mac

**Approach:**
1. Detect if running on notched Mac
2. Show tip in Settings: "You have X icons. Consider hiding more to avoid notch overflow."
3. Optional: Adjust default spacing

**Acceptance Criteria:**
- [ ] Detects notched Mac correctly
- [ ] Shows helpful tip in Settings
- [ ] No icons lost behind notch (user education)

---

## Phase 3: Additional Triggers (MEDIUM PRIORITY)

### 3.1 Battery Level Trigger

**Problem:** Bartender has automatic triggers based on battery level

**Current State:** Only app launch trigger exists (TriggerService.swift)

**Rules:** [#2: VERIFY], [#9: NEW FILE? GEN THAT PILE]

**Investigation:**
```bash
./Scripts/SaneMaster.rb verify_api IOPSCopyPowerSourcesInfo IOKit
```

**Files:**
- `Core/Services/TriggerService.swift:29-54` - Add battery observer
- `Core/Models/SaneBarSettings.swift` - Add batteryTrigger settings
- `UI/SettingsView.swift` - Add battery trigger UI

**Implementation:**
```swift
// TriggerService.swift - Add battery monitoring
import IOKit.ps

private func setupBatteryObserver() {
    // Use IOPSNotificationCreateRunLoopSource for battery changes
    // Check IOPSCopyPowerSourcesInfo for current level
}
```

**Test:**
```swift
@Test func batteryTriggerShowsIconsWhenLow() {
    // Mock battery level at 15%
    // Verify showHiddenItems() called
}
```

**Acceptance Criteria:**
- [ ] Battery level detected correctly
- [ ] Icons show when battery drops below threshold
- [ ] Setting persists across restart
- [ ] Regression test passes

---

### 3.2 WiFi Network Trigger

**Problem:** Bartender shows different icons at home vs office

**Current State:** No WiFi detection

**Rules:** [#2: VERIFY], [#9: NEW FILE? GEN THAT PILE]

**Investigation:**
```bash
./Scripts/SaneMaster.rb verify_api CWWiFiClient CoreWLAN
```

**Files:**
- `Core/Services/TriggerService.swift` - Add WiFi observer
- `Core/Models/SaneBarSettings.swift` - Add wifiTrigger settings
- `UI/SettingsView.swift` - Add WiFi trigger UI

**Note:** CoreWLAN may require entitlement. Check:
```xml
<!-- SaneBar.entitlements -->
<key>com.apple.developer.networking.wifi-info</key>
<true/>
```

**Acceptance Criteria:**
- [ ] Current SSID detected
- [ ] Icons show when connecting to specified network
- [ ] Works without Location Services (if possible)

---

## Phase 4: UI Polish (LOW PRIORITY)

### 4.1 First-Launch Onboarding

**Problem:** Users don't know how to Cmd+drag icons

**Current State:** Instructions in Settings > General, but no first-launch flow

**Rules:** [#9: NEW FILE? GEN THAT PILE]

**Files:**
- `UI/Onboarding/OnboardingView.swift` (new)
- `Core/Services/PersistenceService.swift` - Add `hasSeenOnboarding` flag
- `SaneBarApp.swift` - Show onboarding on first launch

**Content:**
1. Welcome screen with SaneBar icon
2. Animated GIF/video showing Cmd+drag
3. "Got it" button → dismiss

**Acceptance Criteria:**
- [ ] Shows on first launch only
- [ ] Clear visual showing Cmd+drag
- [ ] Dismisses and doesn't show again

---

### 4.2 Visual Feedback Improvements

**Problem:** No visual feedback during state changes

**Current State:** Icon changes (filled vs outline) but no animation

**Files:**
- `Core/MenuBarManager.swift:253-265` - updateStatusItemAppearance()

**Improvements:**
1. Brief pulse/highlight when expanding
2. Optional: Sound effect (toggleable in settings)

**Acceptance Criteria:**
- [ ] Visual feedback when toggling
- [ ] Feedback is subtle, not distracting
- [ ] Can be disabled in settings

---

## Verification Protocol

After EACH change:

```bash
# [Rule #6: BUILD, KILL, LAUNCH, LOG]
./Scripts/SaneMaster.rb verify        # Build + tests
killall -9 SaneBar                     # Kill old
./Scripts/SaneMaster.rb launch         # Start fresh
./Scripts/SaneMaster.rb logs --follow  # Watch logs
```

---

## Implementation Order

| Order | Task | Est. Complexity | Files Changed |
|-------|------|-----------------|---------------|
| 1 | 1.2 Crash prevention guards | Low | 1 |
| 2 | 1.1 Verify position persistence | Low | 1 + test |
| 3 | 1.3 Full screen handling | Medium | 2 |
| 4 | 2.1 External monitor verification | Low | 0 (testing) |
| 5 | 2.2 Notch-aware spacing | Medium | 2 |
| 6 | 3.1 Battery trigger | Medium | 3 + test |
| 7 | 3.2 WiFi trigger | Medium | 3 + test |
| 8 | 4.1 Onboarding | Medium | 3 (new files) |
| 9 | 4.2 Visual feedback | Low | 1 |

---

## Success Criteria

**Bartender Parity achieved when:**

1. [ ] All Phase 1 (Stability) items complete
2. [ ] All Phase 2 (Multi-Display) items verified
3. [ ] At least 1 Phase 3 trigger implemented
4. [ ] Basic onboarding exists
5. [ ] Zero crashes in 1 hour of testing
6. [ ] All regression tests pass

---

## Research Sources

- [Bartender ownership concerns](https://www.macrumors.com/2024/06/04/bartender-mac-app-new-owner/)
- [Bartender 6 issues](https://www.macbartender.com/Bartender6/blog/)
- [Ice GitHub issues](https://github.com/jordanbaird/Ice/issues)
- [Ice #344 - Items move on restart](https://github.com/jordanbaird/Ice/issues/344)
- [Ice #331 - Full screen mode](https://github.com/jordanbaird/Ice/issues/331)
- [Ice #836 - External monitor](https://github.com/jordanbaird/Ice/issues/836)
- [Notch handling tips](https://www.jessesquires.com/blog/2023/12/16/macbook-notch-and-menu-bar-fixes/)
- [Menu bar spacing Terminal commands](https://mjtsai.com/blog/2023/12/08/mac-menu-bar-icons-and-the-notch/)
