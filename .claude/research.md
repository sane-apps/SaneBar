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

## Dropdown Panel UX Research

**Updated:** 2026-02-09 | **Status:** verified | **TTL:** 30d
**Source:** Ice source code, GitHub API, web research, Apple Developer Documentation (NSPanel, NSWindow.Level), competitor app research

### Executive Summary

Menu bar management apps use three approaches for revealing hidden icons:
1. **Dropdown panel below menu bar** (Ice "Ice Bar", Bartender "Bartender Bar") — NSPanel positioned flush below menu bar
2. **In-place expansion** (Hidden Bar, Vanilla, Dozer) — No panel, icons reveal in menu bar itself
3. **System Control Center integration** (macOS native) — Hidden items move to Control Center

### Ice Bar Implementation (Primary Research)

**Source:** Ice repository `Ice/UI/IceBar/IceBar.swift` (commit 11edd39)

#### NSPanel Configuration

```swift
// Panel creation
NSPanel(
    contentRect: .zero,
    styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
    backing: .buffered,
    defer: false
)

// Window properties
panel.level = .mainMenu + 1              // Above menu bar
panel.collectionBehavior = [
    .fullScreenAuxiliary,                // Works in fullscreen
    .ignoresCycle,                       // Not in window cycle
    .moveToActiveSpace                   // Follows active Space
]
panel.animationBehavior = .none          // No system animations
panel.isFloatingPanel = true             // Panel float behavior

// Visual properties
panel.backgroundColor = .clear           // Transparent
panel.hasShadow = false                  // Shadow via SwiftUI instead
panel.titlebarAppearsTransparent = true
panel.isMovableByWindowBackground = true // User can reposition
panel.allowsToolTipsWhenApplicationIsInactive = true
```

**Key insights:**
- `.nonactivatingPanel` prevents stealing focus when shown
- `.mainMenu + 1` ensures panel appears above menu bar but below system alerts
- `.fullScreenAuxiliary` critical for fullscreen app support
- `.borderless` + `.fullSizeContentView` for custom rendering

#### Positioning Logic

```swift
// Position flush below menu bar
let menuBarHeight = screen.getMenuBarHeight() ?? 0
let originY = ((screen.frame.maxY - 1) - menuBarHeight) - frame.height

// Three positioning modes:
// 1. Dynamic: Mouse position if hovering empty space, else Ice icon
// 2. Mouse Pointer: Centered on cursor, clamped to screen bounds
// 3. Ice Icon: Below visible Ice icon in menu bar
```

**Menu bar height calculation:**
```swift
let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
```

Works correctly even when menu bar is auto-hidden.

#### Auto-Dismiss Logic

Panel closes automatically on:
- Active Space change (`NSWorkspace.didActivateApplicationNotification`)
- Screen parameters change (resolution, display arrangement)
- Hidden menu bar section moves offscreen
- `windowDidResignKey` (click outside)

#### Known Issues (from Ice GitHub issues)

**Crashes/Bugs:**
- Issue #786: Panel crashes on macOS Tahoe with certain display configurations
- Issue #711, #665: Rendering corruption on macOS Sequoia/Tahoe
- Issue #517: Multi-monitor positioning broken (shows on wrong screen)
- Issue #677: "Endless loading" when Screen Recording permission denied

**Root causes:**
- Screen Recording permission required for icon capture (`CGWindowListCreateImage`)
- Multi-monitor math assumes `NSScreen.main` (doesn't track mouse screen)
- Notch handling incomplete (doesn't check `safeAreaInsets` on MacBook Pro)

### Bartender Bar Implementation

**Source:** Web research, Bartender website, user reviews

**Approach:** Secondary dropdown bar below menu bar (similar to Ice Bar)

**Trigger methods:**
- Swipe/scroll in menu bar
- Click menu bar
- Hover over menu bar (configurable)
- Keyboard shortcut
- Quick reveal trigger

**Panel features:**
- Persistent bar that stays open until dismissed
- Full interactivity with menu bar items (click, right-click work normally)
- Search functionality within hidden items
- Drag-to-reorder within Bartender Bar

**Known limitations:**
- Requires both Accessibility AND Screen Recording permissions
- macOS permission bugs on Ventura/Sonoma require manual removal/re-grant
- Complex settings UI overwhelming for new users
- $16 premium price point

### Hidden Bar / Vanilla / Dozer Approach

**Source:** GitHub repos, web research, App Store reviews

**Implementation:** No panel — simple divider-based in-place reveal

**Hidden Bar:**
- Vertical divider (|) in menu bar
- Arrow (>) icon to reveal/hide
- Auto-collapse after 10 seconds (configurable)
- ⌘+drag to reposition icons
- **Zero permissions required**
- Free, open source

**Vanilla:**
- Single divider dot, everything left of it hidden
- Click arrow to toggle visibility
- Hold ⌘ and drag dot to reposition
- MacBook notch support documented
- Free tier + $10 pro

**Dozer:**
- Three dots: two toggles + one interaction point
- Primary toggle (click), secondary toggle (Option+click)
- ⌘+drag to move icons between dots
- **Zero permissions required**
- Free, open source

**Key advantage:** Instant utility, no onboarding friction, no permissions, no bugs

### macOS Control Center Pattern

**Source:** Apple HIG, web research

macOS Tahoe allows menu bar items to move into Control Center for "once in a blue moon" access.

**Design patterns:**
- Overflow items grouped in dropdown from Control Center icon
- System-controlled ordering
- No third-party API to programmatically add items to Control Center
- Users manually configure via System Settings > Control Center

### NSPanel Best Practices (Apple Documentation)

**Source:** Apple Developer Documentation — NSPanel, NSWindow.Level, floating panels

#### Core Characteristics

1. **NSPanel subclass of NSWindow:**
   - Auxiliary function to main window
   - Doesn't show in Window menu
   - Disappears when app inactive (default `hidesOnDeactivate = true`)
   - Shows in responder chain before main window

2. **Key advantages:**
   - Can be key window without becoming main window (receives keyboard input without stealing focus)
   - Floats over fullscreen apps with `.fullScreenAuxiliary`

#### Window Level Hierarchy

**From `NSWindow.Level` documentation:**

Levels stack with precedence — even bottom window in level obscures top window of next level down.

**Common levels (low to high):**
- `.normal` (0) — Standard windows
- `.floating` (3) — Floating panels, palettes
- `.submenu` (5) — Submenu windows
- `.mainMenu` (24) — Menu bar itself
- `.statusBar` (25) — Status items (menu bar icons)
- `.popUpMenu` (101) — Pop-up menus
- `.screenSaver` (1000) — Screen saver

**For menu bar dropdown panel:**
- Use `.mainMenu + 1` (level 25) to sit between menu bar and status items
- Ice uses this exact approach

#### Collection Behavior

```swift
collectionBehavior = [
    .fullScreenAuxiliary,  // Appears in fullscreen space
    .ignoresCycle,         // Not in Cmd+` window cycle
    .moveToActiveSpace     // Follows user to active Space
]
```

#### Style Mask

```swift
styleMask = [
    .nonactivatingPanel,   // CRITICAL: prevents app activation
    .borderless,           // No system chrome
    .fullSizeContentView   // Custom rendering control
]
```

#### Auto-Dismiss Options

**Built-in:**
- `hidesOnDeactivate = true` — Hide when app loses focus (default for NSPanel)
- `windowDidResignKey` delegate method — Detect when window no longer key

**Manual:**
- Click outside detection via event monitor
- Escape key handler
- Timer-based auto-hide (e.g., 10 seconds like Hidden Bar)

#### Positioning for Menu Bar Companion

```swift
// Menu bar height
let menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY

// Position flush below menu bar
let panelY = (screen.frame.maxY - menuBarHeight) - panelHeight

// Account for notch on MacBook Pro (macOS 12+)
if #available(macOS 12.0, *) {
    let safeTop = screen.safeAreaInsets.top
    // Adjust if needed
}

// Set panel origin
panel.setFrameOrigin(NSPoint(x: panelX, y: panelY))
```

**Multi-monitor:** Track mouse screen, not `NSScreen.main`:
```swift
let mouseLocation = NSEvent.mouseLocation
let screen = NSScreen.screens.first {
    NSMouseInRect(mouseLocation, $0.frame, false)
} ?? NSScreen.main
```

### Interaction Patterns

#### Click Handling in Dropdown Panel

**Ice approach:**
1. User clicks icon in Ice Bar panel
2. Panel closes immediately
3. Simulate click on actual menu bar item via Accessibility API
4. Menu appears at menu bar position (not panel position)

**Challenge:** Menu bar items expect clicks at their actual location, not panel location.

**Alternative:** Use `NSWorkspace.shared.open(bundleURL)` to trigger app directly (simpler, no Accessibility needed)

#### Drag-to-Reorder

**Not in panel** — Ice/Bartender handle reordering in settings UI, not in dropdown panel itself.

**Reason:** Drag events on menu bar items require Accessibility API, complex state management.

#### Search/Filter

**Bartender:** Search field in panel filters visible icons by name.

**Implementation:** Filter `AccessibilityService.menuBarOwnersCache` by app name, update grid.

### Icon Rendering in Panel

**Ice approach (requires Screen Recording):**
```swift
CGWindowListCreateImage(
    rect,
    .optionIncludingWindow,
    windowID,
    [.boundsIgnoreFraming, .nominalResolution]
)
```

**Alternative (no permissions):**
```swift
// Bundle icon from app
NSWorkspace.shared.icon(forFile: bundlePath)

// Or from running app
NSRunningApplication.icon
```

**Trade-off:**
- Screen Recording: Exact icon as shown in menu bar (includes badges, overlays)
- Bundle icon: Generic app icon, no live state, but zero permissions

### Sizing Recommendations

**Ice Bar:** Dynamic height based on content, typically 60-80pt tall

**Width:** Full screen width minus safe margins (20pt each side)

**Icon grid:**
- 32x32pt icons
- 8-12pt spacing
- Horizontal flow, wraps to multiple rows if needed

### Edge Cases to Handle

| Edge Case | Detection | Solution |
|-----------|-----------|----------|
| **MacBook notch** | `screen.safeAreaInsets.top > 0` | Position below `visibleFrame.maxY`, not `frame.maxY` |
| **Auto-hidden menu bar** | `screen.frame.maxY - screen.visibleFrame.maxY` varies | Recalculate on screen change notification |
| **Multi-monitor** | Mouse screen ≠ `NSScreen.main` | Track mouse location, find containing screen |
| **Fullscreen app** | `NSWorkspace` notifications | `.fullScreenAuxiliary` collection behavior |
| **Space change** | `NSWorkspace.activeSpaceDidChangeNotification` | Close panel, reopen on new Space if needed |
| **Display sleep/wake** | `NSWorkspace.screensDidWakeNotification` | Revalidate screen geometry |
| **Resolution change** | `NSApplication.didChangeScreenParametersNotification` | Recalculate position and size |

### Performance Considerations

**Ice issues:**
- CPU spikes 30-80% reported (issues #713, #704)
- Main thread blocking during icon capture
- Excessive redraws on hover/animation

**Best practices:**
- Icon rendering: Background thread, cache results
- Position calculations: Only on geometry changes, not every frame
- Animations: Use `CALayer` implicit animations, not manual timers
- Screen Recording: Only if user explicitly enables feature (offer bundle icon fallback)

### Recommendations for SaneBar

**Based on research:**

1. **Start simple:** In-place expansion (Hidden Bar style) first — zero friction, zero bugs
2. **Panel as v2:** Dropdown panel is higher complexity, requires:
   - Screen Recording permission (for exact icons) OR bundle icons (less accurate)
   - Multi-monitor edge cases
   - Fullscreen/Space handling
   - Click-outside dismiss logic

3. **Reuse existing infrastructure:**
   - `SearchWindowController` already handles floating window + hover suspension
   - `AccessibilityService.menuBarOwnersCache` provides icon data
   - `MenuBarSearchView` renders icon grid
   - Missing: below-menu-bar positioning, borderless panel style

4. **Avoid Ice bugs:**
   - Don't require Screen Recording unless user opts in
   - Track mouse screen, not `NSScreen.main`
   - Check `safeAreaInsets` for notch
   - Add `.fullScreenAuxiliary` collection behavior
   - Debounce position updates (300ms)

5. **Feature comparison:**
   - Ice wins: Visual panel (when stable)
   - SaneBar wins: Stability, CPU (<0.1%), no permission hell, Find Icon search
   - Panel adds: Visual browsing (mouse-friendly)
   - Panel doesn't replace: Find Icon (keyboard-friendly search)

---

## Competitor Onboarding Analysis

**Updated:** 2026-02-09 | **Status:** verified | **TTL:** 30d
**Source:** Web research, GitHub repos, YouTube reviews, Apple HIG documentation, competitor websites

### Summary Table

| App | Onboarding Steps | Permission Handling | Live Preview/Demo | Settings UI | Standout UX |
|-----|------------------|---------------------|-------------------|-------------|-------------|
| **Bartender 5/6** | Multi-step permission + feature intro | 2 permissions (Accessibility, Screen Recording) with explanation pages, known permission bugs | No interactive demo — manual setup | Three-section layout (Shown/Hidden/Always Hidden), drag-to-arrange | Profiles system, triggers, hotkeys, widgets |
| **Ice** | Minimal — permission prompts only | Screen Recording optional (limited mode without it), improved permission interface in recent versions | No guided demo — users discover by clicking | Layout editor with visual icon arrangement, 3-tier system (Visible/Hidden/Always-Hidden) | Open source, free, very active development |
| **Hidden Bar** | Zero onboarding — drag & click to start | None required | Instant — arrow icon immediately visible | Minimal preferences accessed via dot icon | Ultra-light, zero friction |
| **Vanilla** | Drag divider to position, click arrow | None required | Instant — divider visible in menu bar | Minimal preferences via dot icon, MacBook notch support | Free tier, simple mental model |
| **Dozer** | Three-dot system explained in README | None required | Instant — two dots appear in menu bar | Right-click dots for settings | Minimal, no permissions |

### Bartender 5/6 — Premium Market Leader ($16)

**Onboarding Flow:**
- Download DMG, drag to Applications, launch
- **Permission screens:** Two separate requests with explanation pages
  - **Accessibility:** Required to move menu bar items and detect clicks/swipes/hovers
  - **Screen Recording:** Required to capture menu bar item images for settings UI and styling
  - Both include privacy notes: "Does not capture personal information"
- **Known issue:** macOS Ventura/Sonoma permission bug where apps don't receive permissions despite user granting them. Workaround: manually remove from System Settings and re-grant
- **No interactive tutorial** — users manually configure in settings after permissions granted
- First launch shows empty settings window; user must discover features

**Settings UI:**
- **Three-section layout:** Shown Items, Hidden Items, Always Hidden Items
- Drag-and-drop between sections
- **Advanced features:** Profiles (context-based configs), Triggers (app/battery/location/WiFi/time/scripts), Hotkeys (assign to any menu item), Spacers (grouping with labels/emojis), Widgets (custom menu bar items with actions)
- Rebuilt for macOS 26 (Tahoe) — "smoother, faster, more responsive"

**Standout UX:**
- Power user features: context-aware profiles, automation triggers
- Professional polish but steep learning curve
- 4-week trial to explore features
- Educational resources: ScreenCastsOnline video tutorial

**Sources:** [Bartender Support](https://www.macbartender.com/Bartender5/support/), [Permission Issues](https://www.macbartender.com/Bartender5/PermissionIssues/), [Permission Info](https://www.macbartender.com/Bartender5/PermissionInfo/), [TheSweetBits Review](https://thesweetbits.com/tools/bartender-review/)

---

### Ice — Popular Open Source (Free, 12.7k stars)

**Onboarding Flow:**
- Download Ice.zip from GitHub releases, drag to Applications
- **Recent improvement:** v0.11.x "improved permissions interface for better onboarding"
- **Screen Recording permission:** Optional — app can run in limited mode without it
  - **With permission:** Individual icon images/titles in Ice Bar, desktop background overlay for styling
  - **Without permission:** No Ice Bar, no visual layout editor, limited to basic border/tint/shadow
- GitHub discussions reveal users struggle with permission setup (multiple issues #362, #710, #711, #679)
- **No guided tutorial** — README minimal, users directed to website (icemenubar.app)

**Settings UI:**
- **Visual layout editor:** Drag icons between Visible/Hidden/Always-Hidden sections (when working — multiple bugs)
- **Ice Bar:** Dropdown panel below menu bar showing hidden icons (primary differentiator from competitors)
- Modern SwiftUI interface

**Standout UX:**
- **Ice Bar dropdown** — unique feature showing hidden icons in panel below menu bar
- Active development with frequent releases
- Free and open source
- **Known issues:** Sequoia display corruption, CPU spikes 30-80%, settings not persisting, multi-monitor bugs

**User feedback:** "Powerful" but "buggy" — stability issues prevent mainstream adoption

**Sources:** [Ice GitHub](https://github.com/jordanbaird/Ice), [Ice Website](https://www.icemenubar.app/), [XDA Review](https://www.xda-developers.com/ice-menu-bar-management-tool/), [Podfeet Review](https://www.podfeet.com/blog/2024/06/ice-bartender-replacement/), [Digital Minimalist](https://www.digitalminimalist.com/blog/ice-keep-your-mac-menu-bar-clean-and-organized)

---

### Hidden Bar — Simple Free Option

**Onboarding Flow:**
- Download from GitHub or App Store (notarized)
- **Zero onboarding screens** — arrow icon appears immediately in menu bar
- **No permissions required**
- Drag icon with ⌘+drag to position between other menu items
- Click arrow to hide/show items to the left

**Settings UI:**
- Minimal preferences accessed by clicking the dot
- No complex configuration — intentionally simple

**Standout UX:**
- **Instant gratification:** Works immediately without setup
- **Zero friction:** No permissions, no tutorials, no configuration
- "Does what it says — hides (or quickly brings back) any or all menu bar icons with a click"
- Ultra-light footprint

**User feedback:** "Great experience," "easy to configure and easy to use"

**Sources:** [Hidden Bar GitHub](https://github.com/dwarvesf/hidden), [MacRumors Thread](https://forums.macrumors.com/threads/hidden-bar-free-app-to-hide-menu-bar-icons-m1-supported.2289890/), [MacUpdate](https://hidden-bar.macupdate.com/)

---

### Vanilla — Another Free Option

**Onboarding Flow:**
- Download from website, launch
- **Instant visual feedback:** Divider dot appears in menu bar
- Hold ⌘ and drag dot to position between menu items
- Everything left of dot gets hidden
- Click arrow icon to toggle hidden items

**Settings UI:**
- Minimal preferences accessed via dot
- **MacBook notch support:** Special setup instructions for machines with notch
- **macOS 12.4+ consideration:** Warns about dynamic Date & Time toggle conflicting with Vanilla's spacing

**Standout UX:**
- **Simple mental model:** One divider, click to toggle
- Free tier with limited features, $10 pro version
- Works immediately without tutorial
- Documented edge cases (notch, dynamic menu bar items)

**Sources:** [Vanilla Website](https://matthewpalmer.net/vanilla/), [Vanilla Help](https://matthewpalmer.net/vanilla/help.html), [Vanilla Notch Setup](https://matthewpalmer.net/vanilla/vanilla-macbook-notch.html), [MacMenuBar](https://macmenubar.com/vanilla/)

---

### Dozer — Minimal Free Option

**Onboarding Flow:**
- Install via Homebrew (`brew install --cask dozer`) or download DMG
- **Three dots appear immediately** in menu bar
- **README explains:** Two Dozer icons act as toggles (numbered right to left)
  1. Interaction point (anywhere on menu bar)
  2. Primary toggle — click hides/shows icons to its left
  3. Secondary toggle — Option+click reveals second hidden group
- Move icons between dots with ⌘+drag

**Settings UI:**
- Right-click any Dozer icon for settings
- Minimal configuration

**Standout UX:**
- **Two-tier hiding:** Primary group (left-click) + optional secondary group (Option+click)
- **Zero permissions**
- Clean, minimalist approach
- Requires macOS 10.13+

**Sources:** [Dozer GitHub](https://github.com/Mortennn/Dozer), [Badgeify Comparison](https://badgeify.app/top-3-bartender-free-alternatives-to-manage-your-mac-menu-bar/), [Den's Hub Alternatives](https://denshub.com/en/bartender-macos-alternatives/)

---

## macOS App Onboarding Best Practices

### Apple HIG Guidelines (Official)

**Source:** [Apple HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding)

**Key principles:**
1. **Focus on core actions:** Design tour around 1-2 "must-do" tasks that deliver the most value and will be repeated frequently
2. **User control:** Always include skip, pause, restart options — forcing rigid process causes frustration
3. **Progressive onboarding:** Teach users as they climb — tooltips on hover, contextual hints when first used
4. **Avoid feature dumps:** Don't cover every single feature upfront

**Launch guidance:**
- Onboarding should help people get a quick start
- Keep introductory flows skippable for experienced users
- "All Settings" view should always be accessible

**Sources:** [Apple HIG Onboarding](https://developer.apple.com/design/human-interface-guidelines/onboarding), [ScreenCharm Best Practices](https://screencharm.com/blog/user-onboarding-best-practices)

---

### What Makes Onboarding "Delightful" vs Just Functional

**Delightful examples researched:**

#### Arc Browser — Exceptional Onboarding

**What makes it special:**
- **Intro video on first launch** — reminiscent of Apple's classic "Welcome" videos, sets emotional tone
- **Hand-holding without condescension:** Guides through Sidebar, Spaces, pinned tabs
- **Task-based setup:** Import data, set theme, make default browser, enable ad blocker, add favorite apps
- **Fun factor:** "The onboarding process is so fun you'll wish you could do it again"
- **Multi-profile import:** Can import multiple browser profiles at once during onboarding

**Why it works:**
- Combines visual (intro video) + interactive (guided setup) + practical (import your data)
- Celebrates the uniqueness of the product
- Makes users excited to explore deeper customization

**Sources:** [How to Install Arc](https://thecoderworld.com/how-to-install-and-use-arc-browser-on-macos/), [Arc First Experiences](https://beeps.website/blog/2023-12-10-initial-experiences-using-arc-browser/), [Arc Guide](https://eshop.macsales.com/blog/86505-arc-changed-the-way-i-use-a-mac-the-ultimate-guide-to-an-ingenious-new-browser/), [Page Flows Arc](https://pageflows.com/post/mac-os/onboarding/arc/)

#### Things 3 — Pre-Populated Tutorial Project

**What makes it special:**
- **Sample Project on first launch:** Pre-populated project walks through creating tasks, adding notes, scheduling deadlines
- **Section-by-section introduction:** App introduces itself gradually
- **15-day trial with full features:** No limitations during trial, purchase link preserves existing to-dos

**Why it works:**
- Learning by doing with real examples
- No empty canvas problem — shows what "good" looks like
- Trial without limitations builds trust

**Sources:** [Things Support](https://culturedcode.com/things/support/articles/2803551/), [Things Tutorial Recreation](https://culturedcode.com/things/support/articles/2803553/), [Things First Impressions](https://mariusmasalar.me/things-3-first-impressions-8f0155c60cf2)

#### Raycast — Best Onboarding Award

**What makes it special:**
- **"One of the best onboarding I've seen in an application"** (multiple sources)
- **Most important step:** Setting up keyboard shortcut to launch Raycast
- Walkthrough explains core features with interactive elements

**Why it works:**
- Prioritizes the one critical action (keyboard shortcut) that enables everything else
- Interactive rather than passive reading

**Sources:** [Raycast Introduction](https://medium.com/@b6pzeusbc54tvhw5jgpyw8pwz2x6gs/using-raycast-001-introduction-installation-9dd58eea8836), [Raycast Guide](https://albertosadde.com/blog/raycast)

---

### Key Onboarding Patterns (2026 Best Practices)

**From research across 10+ sources:**

| Pattern | Description | When to Use |
|---------|-------------|-------------|
| **Progressive Disclosure** | Reveal features in carefully sequenced layers | Complex apps with many features (Bartender, Arc) |
| **Interactive Product Tour** | Users perform actions, not just read | Apps with novel interactions (Raycast) |
| **Pre-Populated Samples** | Show "good" examples instead of empty canvas | Productivity apps (Things 3) |
| **Frontload Value** | Remind users why they downloaded on first screen | Apps competing in crowded markets |
| **Personalized Welcome** | Tailor intro based on user role/goals | Apps with multiple use cases |
| **Gallery of Examples** | Show stunning projects by other users | Creative software (Pixelmator Pro) |
| **Zero-Friction Start** | No onboarding — instant utility | Simple utilities (Hidden Bar, Vanilla, Dozer) |
| **Welcome Video** | Emotional connection, show personality | Premium apps building brand (Arc) |

**The spectrum:**
- **Simple utility apps** (Hidden Bar, Dozer): Zero onboarding = feature
- **Medium complexity** (Ice, Vanilla): Minimal text explainers + instant preview
- **Power user tools** (Bartender): Manual setup + extensive docs + video tutorials
- **Novel interactions** (Raycast, Arc): Interactive guided tours + emotional connection

**Sources:** [7 macOS Onboarding Best Practices](https://screencharm.com/blog/user-onboarding-best-practices), [Mobile Onboarding UX](https://www.designstudiouiux.com/blog/mobile-app-onboarding-best-practices/), [VWO Onboarding Guide](https://vwo.com/blog/mobile-app-onboarding-guide/), [Userflow Guide](https://www.userflow.com/blog/onboarding-user-experience-the-ultimate-guide-to-creating-exceptional-first-impressions)

---

## Menu Bar App Settings UI Design Patterns

**From developer resources and HIG:**

**Architecture expectations:**
- Menu bar icons should be **template images** (adapt to light/dark menu bar)
- Preferences in **standard window** (not embedded in menu popover)
- **Keyboard shortcuts** should follow macOS conventions
- **MenuBarExtra** (SwiftUI) or **NSStatusItem** (AppKit) for menu bar presence

**Common patterns:**
- **NSPopover** for quick actions (most common but has issues: delay, unnatural dismissal, "floating app" feel)
- **Dedicated settings window** for complex configuration (Bartender, Ice)
- **Minimal preferences** accessed via icon right-click (Hidden Bar, Vanilla, Dozer)
- **Hybrid approach:** 70% SwiftUI (views/state) + 30% AppKit (system integration)

**Settings window best practices:**
- Build preferences UI **early** — you'll need it sooner than you think
- Keep menu bar functionality **lightweight and efficient**
- Without distractions of full interface, design for **efficiency and straightforwardness**

**Sources:** [Apple HIG Menu Bar](https://developer.apple.com/design/human-interface-guidelines/the-menu-bar), [Building macOS Menu Bar App](https://gaitازis.medium.com/building-a-macos-menu-bar-app-with-swift-d6e293cd48eb), [Native Menu Bar App Lessons](https://medium.com/@p_anhphong/what-i-learned-building-a-native-macos-menu-bar-app-eacbc16c2e14), [SwiftUI MenuBarExtra](https://nilcoalescing.com/blog/BuildAMacOSMenuBarUtilityInSwiftUI/)

---

## Insights for SaneBar Onboarding

### What We're Competing Against

**Free competitors (Hidden Bar, Vanilla, Dozer):**
- **Strength:** Zero onboarding friction — instant utility
- **Weakness:** Limited features, no power user capabilities
- **User expectation:** Should "just work" immediately

**Premium competitors (Bartender):**
- **Strength:** Extensive features, professional polish, educational resources
- **Weakness:** Steep learning curve, permission bugs, manual setup
- **User expectation:** Worth the price if deeply configurable

**Open source (Ice):**
- **Strength:** Active development, free, innovative features (Ice Bar)
- **Weakness:** Stability issues, buggy, sparse documentation
- **User expectation:** Cutting-edge but expect rough edges

### SaneBar's Positioning Opportunity

**Where we can win:**
1. **Stable + Simple:** Ice's features without the bugs
2. **Smart permissions:** Learn from Bartender's permission hell — explain clearly, handle edge cases
3. **Progressive disclosure:** Start simple (Hidden Bar level), reveal power features (Bartender level) as users grow
4. **Instant preview:** Show live demo of the app working during onboarding (not just static screens)
5. **Import competition:** Already supporting Bartender + Ice import — highlight this in onboarding for switchers

### Recommended Onboarding Flow for SaneBar

**Based on research findings:**

**Pre-launch checklist:**
- [ ] Permission explanations ready (Accessibility only — simpler than Bartender)
- [ ] Known edge cases handled (macOS permission bugs, multi-monitor, notch)
- [ ] Import flow tested (Bartender + Ice settings)

**Onboarding steps (2-3 screens max):**

1. **Welcome Screen**
   - Brief intro: "Hide menu bar clutter. Stay focused."
   - **Unique value prop:** "Import from Bartender or Ice" (for switchers)
   - Big "Get Started" button

2. **Permission Screen** (if not granted)
   - Visual diagram showing what Accessibility enables: "Move icons, detect clicks"
   - Privacy note: "SaneBar never captures your screen"
   - "Open System Settings" button with fallback instructions
   - **Learn from Bartender bugs:** Include troubleshooting link for permission issues

3. **Interactive Demo** (UNIQUE — none of the competitors do this well)
   - **Live preview:** Show actual menu bar with delimiter working
   - Animated highlight: "Click here to hide icons" → items animate away
   - **Progressive hints:** "⌘+drag to reposition" appears after first click
   - "Try Import Settings" button for Bartender/Ice users (pre-fill if detected)

4. **Optional: Quick Settings** (skippable)
   - "Do you want SaneBar to start at login?" Toggle
   - "Choose a hiding style: Auto or Manual" (show preview of each)
   - Big "Done — Start Using SaneBar" button

**Post-onboarding:**
- **Contextual tooltips:** First time user hovers over settings icon → "Configure auto-hide, hotkeys, and more"
- **Empty state in Settings:** If no rules configured, show examples: "Hide Slack when not running" with template button
- **Changelog highlights:** On updates, show 1-line "What's New" (learn from Raycast's minimal update notes)

**Comparison to competitors:**

| Feature | Bartender | Ice | Hidden Bar | SaneBar (Proposed) |
|---------|-----------|-----|------------|-------------------|
| Steps | ~5 (permissions + manual setup) | ~2 (minimal) | 0 (instant) | 3 (welcome + permission + demo) |
| Interactive | No | No | Instant (no tutorial) | Yes (live preview) |
| Permission handling | Buggy, complex (2 permissions) | Optional, confusing | None needed | Clear explanation, 1 permission |
| Import competition | No | No | No | **Yes** (Bartender + Ice) |
| Empty canvas problem | Yes | Yes | N/A | No (live demo shows it working) |

**Key differentiator:** **Live interactive demo** showing the app actually working during onboarding — none of the competitors do this effectively.

---

### Additional Notes

**Permission handling lessons:**
- **Bartender's pain:** Two permissions (Accessibility + Screen Recording) with known macOS bugs requiring manual removal/re-grant
- **Ice's confusion:** Screen Recording "optional" but disables key features → users confused about what they're missing
- **SaneBar advantage:** Only needs Accessibility → simpler explanation, fewer edge cases

**Settings UI lessons:**
- **Bartender:** Three-section drag-and-drop (Shown/Hidden/Always Hidden) is intuitive
- **Ice:** Visual layout editor is powerful when it works (stability issues)
- **Simple apps:** Right-click icon for minimal settings (Hidden Bar, Vanilla, Dozer)
- **SaneBar current:** Separate settings window works well, consider adding visual icon arranger in future

**Feature highlight priorities:**
- **Onboarding:** Show core hiding/showing behavior only
- **Post-onboarding:** Progressive reveal of advanced features (per-app rules, auto-rehide, hotkeys, import)
- **Never during onboarding:** Profiles, triggers, widgets (Bartender's mistake — overwhelming)

**Zero-friction principle:**
- Hidden Bar/Vanilla/Dozer win because they work **immediately**
- Arc/Things 3 win because onboarding is **fun and valuable**
- Bartender/Ice lose because onboarding is **confusing and buggy**
- **SaneBar goal:** Combine instant utility (like simple apps) with guided discovery (like Arc) without the bugs (unlike Ice) or complexity (unlike Bartender)
