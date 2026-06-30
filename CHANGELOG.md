# Changelog

All notable changes to SaneBar are documented here.

For user-requested features, see [marketing/feature-requests.md](marketing/feature-requests.md).

---

## Unreleased

---

## [2.1.87] - 2026-06-30

More reliable icon-moving during display changes, Space switches, and wake. Some notched and multi-display setups still hit macOS limits this cannot fully fix. I will email all paid users soon about macOS 27 and what it means for SaneBar.

---

## [2.1.86] - 2026-06-30

Improves moving menu-bar icons between Visible, Hidden, and Always Hidden, especially on notched MacBooks. Moving an icon to the visible area now aims for a safe drag point near the notch instead of giving up. Pinning one app no longer pulls its same-named companions into Always Hidden, and move verification double-checks against the live menu bar. Verified with real moves on a notched display.

---

## [2.1.85] - 2026-06-29

Quiets a menu-bar flicker some people see every few minutes. When the hidden-icons separator sits parked off-screen — its normal position while icons are hidden — macOS can momentarily report it as missing, and SaneBar would rebuild its menu-bar items on every Space switch or app change, which shows up as a brief flash. SaneBar now recognizes when its main icon is present and stable and stops rebuilding in that case, so the flicker should settle down. This was confirmed on a real affected machine, where the rebuild churn dropped to zero. If you saw this flicker on a multi-monitor setup, this update is aimed at it. Genuinely missing icons still recover as before.

---

## [2.1.84] - 2026-06-28

Further improves menu-bar divider stability around sleep and wake: closes more of the cases where the divider could drift toward Control Center after waking even when your displays had not changed. Hover reveal is more deliberate too: moving your cursor over SaneBar's own icon no longer reveals hidden icons instantly, it now waits for your Reveal delay like the rest of the menu bar. Also adds a way back in when macOS does not place SaneBar's menu-bar icon at launch: relaunching SaneBar now reliably opens a window so you can reach Settings and the Health screen instead of the app being unreachable.

---

## [2.1.83] - 2026-06-26

Fixes icon moves that still failed after recent updates: moving icons between Hidden/Visible/Always Hidden now works (verified on notched built-in displays), and the right-click move menu now shows the correct options for an icon's actual zone. Adds recovery for the menu-bar separator when macOS parks it off-screen so moves stop silently doing nothing.

---

## [2.1.82] - 2026-06-25

Stops the menu bar revealing on its own: hover and scroll reveal now wait for a deliberate 2-second Reveal delay (adjustable in Settings) instead of popping open the moment your cursor passes by. Also fixes updates not applying cleanly when you are several versions behind: the newest version now always takes over, so you no longer get stuck on an older build.

---

## [2.1.81] - 2026-06-25

Your menu bar divider and icon order now stay put through sleep/wake, Space switches, and display changes — no more snapping back toward Control Center. Also fixes moving icons out of Always Hidden, license-key recognition, and unresponsive icon dragging.

---

## [2.1.80] - 2026-06-23

Improves SaneBar divider/layout stability after app activation, Space changes, wake, and display transitions.

---

## [2.1.79] - 2026-06-23

Pro is now free to try for 14 days. Updated default settings based on customer feedback: hover and scroll reveal are off by default, drag reveal stays on, and auto-hide uses a calmer 5-second delay. Improved license-key paste handling and companion app recommendations.

---

## [2.1.78] - 2026-06-22

Pro is now free to try for 14 days. Basic remains included after the trial.

---

## [2.1.77] - 2026-06-22

Pro is now free to try for 14 days. Basic remains included after the trial.

---

## [2.1.76] - 2026-06-21

### Fixed

- Keeps Custom Appearance out of Mission Control and Spaces control surfaces when macOS leaves another app frontmost.
- Removes unused settings and status-item forwarding code while preserving existing menu bar recovery behavior.

---

## [2.1.75] - 2026-06-20

### Fixed

- Avoids notch-unsafe menu bar drag origins on MacBook displays while preserving normal moves on external displays.
- Improves release smoke testing so notched laptop runs use live geometry from the app before moving menu bar icons.

---

## [2.1.74] - 2026-06-20

### Fixed

- Stops a recovery loop that could make Settings reopen unexpectedly or disturb saved layouts when the menu bar was already hidden correctly; postponed wake repairs now appear in Settings > Health for manual repair.
- Improves moving icons out of Always Hidden after restart, wake, or display changes, including wide menu bars.
- Reduces repeated background retries after Always Hidden moves, lowering CPU/memory churn and avoiding extra layout disturbance.
- Gives AppleScript users clearer next steps when an icon cannot be found or moved.

### Changed

- Icon-moving AppleScript automation now requires Pro consistently. Basic still supports browse, click, and list commands.

---

## [2.1.73] - 2026-06-19

Improves Always Hidden icon moves after wake/display changes.
Restores hidden menu bar layouts more reliably after display sleep, Spaces, and off-screen window recovery.
Keeps Health repair consistent with Touch ID protection for hidden icons.

---

## [2.1.72] - 2026-06-17

Improves Browse Icons reliability when moving items between Visible, Hidden, and Always Hidden. Reduces background menu-bar scanning work and strengthens resource checks so idle memory growth is caught before release.

---

## [2.1.71] - 2026-06-17

Fixed Always Hidden icon move reliability after restart, display wake, and recovery. Improved menu bar geometry handling for multi-display setups. Added clearer Health guidance when macOS hides SaneBar from the menu bar.

---

## [2.1.70] - 2026-06-16

Improves macOS 27 Spaces and Mission Control handling for Custom Appearance, including active-Space refresh and hidden-state recovery after Space changes.

---

## [2.1.69] - 2026-06-15

Improves restart and recovery when macOS attaches SaneBar's menu bar items off-screen after reboot. SaneBar now waits for live status-item anchors before replaying hidden-state layout, clears poisoned status-item autosave state more reliably, and keeps recovery passive while the menu bar rebuilds.

---

## [2.1.68] - 2026-06-12

Adds AppleScript target-relative menu bar icon reordering within the same section: `move icon before` and `move icon after`.

---

## [2.1.67] - 2026-06-11

Major reliability release for menu bar layout and recovery. Fixes the missing-icon recovery dead end (Repair always acts and points to System Settings when macOS hides SaneBar's icons). Cached geometry is bound to the display arrangement it was observed under, so recovery can no longer replay coordinates from a different monitor setup. Displays arranged left of the primary work correctly. Moving icons to visible is far more reliable (drags target the middle of the visible lane). Automatic layout restores only run with verified geometry and never move the cursor during wake; postponed restores appear in Health for one-click apply. Drift detection respects where you placed the SaneBar toggle. If macOS rapidly flaps icon visibility, SaneBar stands down instead of fighting it. Clearer Layout Mode wording.

---

## [2.1.66] - 2026-06-06

Improves wake and display recovery for Hidden and hide-all-other layouts, including helper-owned menu extras.

---

## [2.1.65] - 2026-06-06

Improves reliability for Browse Icons moves out of Always Hidden and reduces background recovery cursor movement risk. Strengthens startup, wake, and exact-ID menu-bar verification.

---

## [2.1.64] - 2026-06-05

Fixes menu bar recovery after wake and display changes; prevents stale geometry from moving visible or always-hidden items when live anchors are missing; keeps hide-all-other boundaries consistent.

---

## [2.1.63] - 2026-06-01

Fixes dynamic menu bar item arrangement after wake, display changes, and Spotlight/helper recovery. Improves recovery replay and auto-hide reliability after wake.

---

### Earlier 2.1.63 notes - 2026-05-29

Fixes dynamic menu bar item jumps on wake, arrange, and Spotlight for 3rd-party helpers (SwiftBar, Fantastical, Lungo, etc.). Broadens shouldResetPersistentStateForStatusItemRecovery to force hard reset to live left-edge anchor on any bad-data reason (missing coordinates, invalid items/geometry) during .wakeResume / .screenParametersChanged / .manualLayoutRestore. Updates recovery policy tests. (Addresses #147, #142, #150)

---

## [2.1.62] - 2026-05-27

Improves wake recovery for dynamic menu bar items, strengthens Hide All Other and Always Hidden replay, and adds release-blocking checks for activation tint, exact-ID moves, auto-rehide, and display wake behavior.

---

## [2.1.61] - 2026-05-26

Improves Selective Profile reliability after wake and display changes so saved Visible and Hidden items stay in their chosen sections. Also improves profile loading from Settings and adds stricter release checks for saved visibility layouts.

---

## [2.1.60] - 2026-05-25

Improves fullscreen tint handling so the tint stays out of fullscreen apps, and improves wake and display layout recovery so Visible items stay where expected.

---

## [2.1.59] - 2026-05-21

Improves menu bar tint behavior in fullscreen apps, including Claude Desktop, and helps Hidden and Visible menu bar items keep their layout after wake or display changes.

---

## [2.1.58] - 2026-05-20

Keeps Custom Appearance tint stable through fullscreen, maximize, and app-switch transitions. Removes stale release-tool dependencies that triggered the Ruby JWT security alert.

---

## [2.1.57] - 2026-05-19

Fixes license-key paste reliability in activation and settings.

---

## [2.1.56] - 2026-05-18

Improves license key entry in Settings, onboarding, and Pro upgrade prompts. Keeps menu bar appearance steadier during fullscreen and maximize transitions. Improves wake, restart, and display-change layout handling so icons stay where expected. Improves Browse Icons and Second Menu Bar reliability for custom groups and moves between Visible, Hidden, and Always Hidden.

---

## [2.1.55] - 2026-05-16

Keeps custom menu bar colors more stable during fullscreen and window changes, improves SaneBar after wake and display changes, and makes moving items in Browse Icons smoother.

---

## [2.1.54] - 2026-05-15

Keeps Custom Appearance tint stable when launching or switching to large desktop apps. Improves Hidden and Always Hidden icon moves so icons stay in the section you choose after SaneBar verifies the physical menu bar position.

---

## [2.1.53] - 2026-05-13

Improves Browse Icons and menu bar recovery reliability, fixes Custom group creation in the Icon Panel, restores usable Settings window sizing, and adds stricter customer UI click-through release checks.

---

## [2.1.52] - 2026-05-11

Improves restart and Dock-launch recovery so Custom Appearance tint and the SaneBar menu bar item stay stable after status items are recreated.

---

## [2.1.51] - 2026-05-11

Keeps Custom Appearance tint stable after restart and Dock launches, and improves menu bar recovery after startup so the SaneBar icon stays fully configured.

---

## [2.1.50] - 2026-05-09

Improves Browse Icons drag reliability in Icon Panel and Second Menu Bar, keeps Always Hidden moves responsive, and includes the recent tint/full-screen compatibility and settings/menu polish fixes.

---

## [2.1.49] - 2026-05-09

Improves menu bar tint behavior around fullscreen browser windows, fixes hover reveal reliability, and makes menu bar layout checks smoother during updates.

---

## [2.1.48] - 2026-05-04

Improves Basic and Pro menu bar controls, makes Browse Icons and Second Menu Bar more reliable with Always Hidden items, keeps appearance changes smooth, and lowers background memory use.

---

## [2.1.47] - 2026-04-30

Adds a first-run Health wizard and layout rescue tools, improves Bartender import with preview, makes Basic and Pro settings clearer, and improves menu bar layout recovery after launch, wake, display changes, and upgrades.

---

## [2.1.46] - 2026-04-28

Makes SaneBar more reliable when moving hidden icons, waking your Mac, or switching displays. Improves hidden-to-visible drag reliability on multi-display setups, improves recovery when menu bar items attach slowly or saved positions drift, and adds clearer diagnostics for macOS menu bar visibility edge cases.

---

## [2.1.45] - 2026-04-23

Keeps the SaneBar icon and hidden layout stable after wake and display changes.
Improves layout checks so SaneBar waits for fresh menu bar positions before adjusting items.

---

## [2.1.44] - 2026-04-23

Improves recovery when menu bar items drift or disappear after dragging, restart, wake, or display changes. Tightens browse and move stability on busy menu bars.

---

## [2.1.43] - 2026-04-21

Harden menu bar recovery and reduce browse scan churn.

---

## [2.1.42] - 2026-04-17

Browse Icons now re-hides more reliably after you close it.
Auto-hide is more consistent when you reveal hidden icons from the menu bar.

---

## [2.1.41] - 2026-04-14

Browse Icons and the second menu bar now feel lighter and use less CPU on busy menu bars. Improves layout recovery after restart and wake so your icon setup stays where you put it. Full-screen video now hides Custom Appearance correctly, and turning it off stays off.

---

## [2.1.40] - 2026-04-09

Fixes recovery when SaneBar was already stuck in a missing-icon state after an upgrade, reinstall, or reset. Improves startup recovery when saved menu bar geometry is invalid. Fixes the Advanced Workflow setup screen so all controls fit cleanly in the window.

---

## [2.1.39] - 2026-04-02

Improves menu bar layout reliability, makes hidden items behave more consistently, and keeps Basic and Pro features behaving as expected.

---

## [2.1.38] - 2026-04-01

Improves startup, wake, and display-change layout recovery so menu bar icons stay more stable and easier to recover.

---

## [2.1.37] - 2026-03-27

Keeps the SaneBar icon and hidden layout in place more reliably after login, wake, and display changes.
Reduces cases where the menu bar layout resets itself or the SaneBar icon disappears.
Improves recovery on crowded and notched menu bars so hidden apps stay easier to reach.

---

## [2.1.36] - 2026-03-26

Fixes missing menu bar icon recovery after drag-out and reset, makes Reset to Defaults rebuild the menu bar items safely, improves uninstall cleanup for stale status-item state, and updates the Ruby JSON dependency for security.

---

## [2.1.35] - 2026-03-25

Fixed wake and display recovery so hidden icons stay hidden. Improved status-item recovery when menu bar layout drifts. Better Always Hidden reliability and stronger visual QA for browse and settings.

---

## [2.1.34] - 2026-03-24

Improved layout recovery after sleep, wake, and display changes. Fixed the dark tint turning black. Better reliability for hidden, visible, and Always Hidden icon moves. Standardized shared chrome so browse and settings surfaces stay consistent.

---

## [2.1.33] - 2026-03-19

Fixes focus jumps after hover reveal by separating passive hover reveal from inline app-menu suppression. Adds wake-aware position validation with stale-task cancellation, improves restart, sleep, display-change, notch Mac, and external monitor recovery, and tightens release proof against the staged Release app.

---

## [2.1.32] - 2026-03-18

Fixes startup and layout resets after launch and display changes by restoring poisoned relaunch state from current-width backups instead of collapsing Visible items into Hidden. Serializes launch-time validation behind startup hide/recovery, tightens shared-bundle identity so Browse Icons and moves fail safely instead of targeting the wrong sibling, and adds a Mini startup relaunch probe to release preflight.

---

## [2.1.30] - 2026-03-17

Fix common Apple menu extra moves. Fix multi display hover screen detection. Add compatibility FAQ for unusual custom host menu bar apps.

---

## [2.1.29] - 2026-03-16

Improves startup and layout recovery after display and profile changes so icons are less likely to restore in the wrong place after restart.
Improves crowded menu bar guidance when Visible gets tight and the Second Menu Bar is a better fit.
Improves runtime validation and release smoke stability for icon movement and Browse Icons activation.
Improves Menu Bar Appearance so the overlay is less likely to stay visible over full-width apps like World of Warcraft.

---

## [2.1.28] - 2026-03-13

Improves startup placement and layout recovery, especially on Tahoe and external displays. Also improves Browse Icons clarity and general stability.

---

## [2.1.27] - 2026-03-13

Improved launch reliability so visible icons stay where you expect.
Improved saved profile and layout restore behavior.
Improved Browse Icons clarity with cleaner controls and clearer drag targets.
Improved menu bar icon settings and overall settings polish.

---

## [2.1.26] - 2026-03-11

- Fix unexpected Dock icon surfacing when the Dock icon setting is off
- Fix Browse Icons drag failures on multi-display setups
- Improve Second Menu Bar interaction stability and reduce premature close behavior

---

## [2.1.25] - 2026-03-10

Critical stability update for Browse Icons, Second Menu Bar, startup positioning, and inline reveal reliability.

---

## [2.1.24] - 2026-03-07

Improved Tahoe startup reliability, filtered non-operable ghost entries from zoned menu views, and hardened browse activation stability.

---

## [Unreleased]

- Added a new **Rules → Revealing** toggle: **Hide app menus during inline reveal**
- Defaulted the new toggle to on for crowded menu bars
- Import from Ice now preserves that preference instead of dropping it

---

## [2.1.23] - 2026-03-06

Critical update: fixed Second Menu Bar clicks, browse panel and icon panel reliability, icon movement between Visible Hidden and Always Hidden, launch positioning next to Control Center, and stale menu bar state recovery.

---

## [2.1.22] - 2026-03-05

Critical stability update: improves icon movement between Visible, Hidden, and Always Hidden, fixes second menu bar refresh and click behavior, and strengthens launch-time diagnostics and layout recovery.

---

## [2.1.21] - 2026-03-05

Critical stability update: improves icon movement between Visible, Hidden, and Always Hidden, fixes second menu bar refresh and click behavior, and strengthens launch-time diagnostics and layout recovery.

---

## [2.1.20] - 2026-03-03

Fix panel refresh sync, harden launch/runtime behavior, and improve menu handling stability.

---

## [2.1.19] - 2026-03-03

- Fix icon panel refresh latency after moving icons between zones. - Harden launch/test path to prevent duplicate installs and Accessibility permission loops. - Improve stability when switching between Second Menu Bar and Icon Panel.

---

## [2.1.18] - 2026-03-02

This update fixes a download/install problem that could make macOS block SaneBar after some unzip methods. It also improves icon moving and click behavior in Browse Icons and the second menu bar.

---

## [2.1.17] - 2026-03-01

This update improves auto rehide behavior around Browse Icons and makes moving icons between Hidden and Visible more reliable.

---

## [2.1.16] - 2026-02-28

Improved auto-hide reliability when closing Icon Panel and switching browse views.
Made icon movement refresh faster and more consistent across Hidden, Visible, and Always Hidden tabs.
Improved launch stability to avoid duplicate-instance and permission confusion during testing and daily use.

---

## [2.1.13] - 2026-02-28

Critical hotfix: recovers from corrupted WindowServer status-item position cache that could cause menu bar icons to disappear or fail to restore. Automatically self-heals autosave namespace and rebuilds status items.

---

## [2.1.12] - 2026-02-27

SaneUI polish + onboarding clarity update\n\n- Premium navy/teal visual pass across onboarding and settings\n- Clearer zone movement and browse mode explanations\n- Improved accessibility permission UX and icon readability\n- Reliability fixes for rehide/hover behavior\n- Added sanebar:// automation commands and copy icon ID actions\n- Updated website screenshots and notch explainer copy

---

## [2.1.11] - 2026-02-25

Improved icon movement and ordering in both Browse Icons views.\nFixed startup placement and recovery for menu bar icons.\nMade left-click and right-click actions more reliable and responsive.\nReduced unexpected auto-close behavior while managing icons.

---

## [2.1.10] - 2026-02-21

Dark mode consistency improvements, purchase flow clarity updates, and stability fixes.

---

## [2.1.9] - 2026-02-20

Maintenance release: closes open issue backlog (including #79), reconciles Air/mini release state, and hardens release automation.

---

## [2.1.7] - 2026-02-19

Fixes second-menu-bar regression where visible icons could collapse into hidden after install; improves move reliability and adds regression coverage.

---

## [2.1.6] - 2026-02-19

- Fixed a persistent corrupted-state bug where Cmd-dragging SaneBar out of the menu bar could keep it hidden across relaunches.
- Added launch-time self-healing for both current and legacy ByHost visibility keys so previously affected installs recover automatically.
- Fixed second-menu-bar drag/drop routing for Always Hidden and Hidden transitions (including previously no-op move paths).
- Improved Accessibility grant flow in Browse Icons and onboarding by centralizing "Grant" behavior and forcing a fresh permission re-check on retry.
- Preserved the "Require authentication to show hidden icons" setting for upgrade users by migrating legacy keychain-backed values into settings JSON.
- Added regression coverage for corrupted visibility recovery, zone-transition exhaustiveness, and auth-setting migration.

---

## [2.1.5] - 2026-02-18

### Fixed
- **External Monitor Toggle**: Manual show/hide toggle now works correctly on external monitors
- **Apple Menu-Extra Detection**: Improved canonicalization for missing or ambiguous system identifiers

---

## [2.1.4] - 2026-02-18

### Fixed
- **Zone Move Reliability**: Fixed regressions in moving icons between visible/hidden zones
- **Visible/Hidden Persistence**: Icon section assignments now persist correctly across restarts
- **Helper-Hosted Extras**: Improved detection for apps like Little Snitch that host menu extras via helper processes
- **Separator Fallback**: Better target resolution and fallback classification for separator items

---

## [2.1.3] - 2026-02-18

### Fixed
- **Status Item Recovery**: Fixed machine-specific icon recovery after Cmd-drag removal
- **Icon Movement Coordinates**: Hardened coordinate calculations for icon moves
- **External Monitor Policy**: Improved handling of external monitor show/hide policy
- **Second Menu Bar Drag-and-Drop**: Improved drag between Hidden, Always Hidden, and Visible zones

---

## [2.1.2] - 2026-02-16

### Fixed
- **High Energy Usage**: Resolved animated background causing excessive CPU/energy drain
- **Mouse Event Throttle**: Added throttling to reduce unnecessary event processing
- **Stage Manager**: Fixed compatibility with macOS Stage Manager

---

## [2.1.1] - 2026-02-16

### Fixed
- **Rounded Corners Truncation**: Removed horizontal inset causing clipped corners (#64)
- **Website Download Links**: Updated stale v1.5.0 links to current version

---

## [2.1.0] - 2026-02-15

### Fixed
- **Always-Hidden Separator Position**: Fixed toggle stability and positioning
- **Pro Mode Debugging**: Debug builds now skip test host correctly

---

## [2.0.0] - 2026-02-15

### Added
- **Second Menu Bar**: Browse hidden icons in a dedicated panel (left-click or right-click trigger, configurable in Settings)
- **Freemium Model**: Free users get full Browse Icons; Pro unlocks icon moving, advanced triggers, and customization
- **Killer Onboarding**: Animated setup wizard with presets, import detection, and progress bar
- **Schedule Triggers**: Auto-show/hide icons on a time-based schedule
- **Battery Threshold Trigger**: Auto-reveal icons when battery drops below a set level
- **Icon Reorder**: Drag-and-drop icon reordering in Second Menu Bar
- **Move to Applications Prompt**: Guides users to move app from Downloads to Applications
- **Script Triggers**: Per-icon AppleScript commands for automation

### Changed
- **Renamed "Floating Panel" to "Second Menu Bar"**: Clearer naming with segmented picker UI (#58)
- **Second Menu Bar Layout**: 3-row layout with frosted glass and animated gradient
- **Onboarding Overhaul**: Streamlined permissions, one-click setup, accessibility prompt improvements
- **Website Overhaul**: Basic/Pro feature cards, hero pricing, golden ratio spacing, mobile-optimized

### Fixed
- **Reduce Transparency**: Tint renders at full opacity, Liquid Glass skipped when enabled (#34)
- **Keyboard Shortcuts**: No longer reset after user clears them (#46)
- **Find Icon**: Window stays open during icon interactions
- **Click-Through**: Fixed click-through behavior on hidden icons
- **Always-Hidden Enforcement**: Improved reliability of always-hidden icon persistence
- **Hotkey Display Sync**: Fixed display not updating after hotkey changes (#57)
- **Move to Visible Race Condition**: Fixed timing issue when promoting icons (#56)
- **Build from Source**: External contributors can build without signing certificate (#44)

---

## [1.0.18] - 2026-02-02

### Changed
- **License**: Switched to PolyForm Shield 1.0.0 (previously MIT → GPL v3)
- **App Icon Style**: Updated to 2D cross-app design language

### Added
- **Import from Ice**: Migrate behavioral settings from Ice menu bar manager (Settings → General → Migration)
- **Import from Bartender**: Migrate icon layout and behavioral settings from Bartender plist (Settings → General → Migration)
- **Custom Menu Bar Icon**: Upload your own image as the SaneBar menu bar icon (Settings → Appearance)
- **Standalone Build**: External contributors can now build without internal infrastructure (#39)

### Fixed
- **About View**: Button layout no longer truncates on smaller windows
- **Dark Mode Tint**: Dual light/dark tint controls with sensible defaults (#34)
- **Security Email**: Corrected contact email across all documentation (#37)

---

## [1.0.17] - 2026-01-29

### Security
- **Third-Party Audit Response**: Addressed findings from Jan 2026 audit
- **Touch ID Hardening**: AppleScript commands now enforce Touch ID requirements
- **Auth Rate Limiting**: Added 30s lockout after 5 failed authentication attempts

### Changed
- **New App Icon**: Polished 3D squircle design for better macOS integration
- **Cleaned Up**: Removed unused "Click to Show" setting that conflicted with visible items
- **Website**: Unified messaging and added trust badges linking to audit

### Fixed
- **Stability**: Replaced force casts in Accessibility code for better crash resilience
- **Dock Icon**: Respects user preference immediately on first launch

---

## [1.0.16] - 2026-01-24

### Added
- **Hover Tooltips**: 43+ hover explanations across all Settings tabs - hover over any control to see what it does
- **Smart Triggers in Comparison**: Website now highlights Smart Triggers (battery, Wi-Fi, Focus, app-based auto-reveal)

### Changed
- **User-Friendly Labels**: Replaced technical jargon with plain English
  - Corner radius: "14pt" → "Round" (Subtle/Soft/Round/Pill/Circle)
  - Spacing: "6pt" → "Normal" (Tight/Normal/Roomy/Wide)
  - Delays: "200ms" → "Quick" (Instant/Quick/Normal/Patient)
- **Settings Sidebar**: Wider for better readability (180px min, 200px ideal)
- **Gesture Picker**: Simplified to "Show only" / "Show and hide" options
- **Experimental Tab**: Friendlier messaging ("Hey Sane crew!")
- **Comparison Table**: Reordered for impact - unique features first, table-stakes last

### Fixed
- **Check Now Button**: Added debounce to prevent rapid-fire update checks

---

## [1.0.15] - 2026-01-23

### Added
- **Experimental Tab**: New Settings tab for beta features and easy bug reporting
- **Directional Scroll**: Scroll up to show icons, scroll down to hide (optional)
- **Show When Rearranging**: All icons revealed while ⌘+dragging to reorganize
- **Hide on App Change**: Auto-hide when switching to a different app (optional)
- **Gesture Toggle**: Scroll/click can now toggle visibility (show if hidden, hide if visible)
- **External Monitor Detection**: Option to keep icons visible on external monitors (plenty of space there)

### Changed
- Settings → Rules reorganized with new gesture options
- Settings sidebar now includes Experimental tab
- HoverService now detects scroll direction and ⌘+drag gestures

---

## [1.0.13] - 2026-01-23

### Fixed
- **Positioning Reset Bug**: Removed faulty recovery logic that was resetting user icon positions

---

## [1.0.12] - 2026-01-22

### Fixed
- **Electron App Compatibility**: Implemented "6-step stealth move" logic that finally fixes the "Sticky Icon" issue for Electron apps (Claude, Slack, VibeProxy, etc.). They now respond perfectly to automated moves in Find Icon.
- **Update Reliability**: Fixed a critical issue where auto-updates would fail due to signature verification errors. Updates are now reliable again.
- **Find Icon Performance**: Fixed "beach ball" hanging and 2-second delays when switching tabs in the "Find Icon" window. Thumbnail loading is now lazy and cached.
- **Sparkle Signatures**: Corrected EdDSA signatures for previous releases (v1.0.8-v1.0.11) in the appcast feed to allow them to update successfully.

---



### Added
- **Focus Mode Trigger**: Auto-show hidden icons when macOS Focus Mode changes (Work, Personal, Do Not Disturb, etc.)
- **Code Tracing Tools**: `button_map.rb` and `trace_flow.rb` scripts for debugging UI flows
- **Class Diagram**: PlantUML visualization of codebase architecture

### Changed
- **Position Pre-Seeding**: Simplified NSStatusItem positioning (removed 880 lines of cruft)
- **Session Management**: Improved hooks for development workflow

### Fixed
- Test suite references to removed StatusBarController constants

---

## [1.0.7] - 2026-01-17

### Added
- **Hide SaneBar Icon**: Option to completely hide the main icon (separator handles clicks)
- **In-App Issue Reporting**: Report bugs directly from the app
- **Keyboard Navigation**: Arrow keys work in Find Icon search results
- **Open Source Community Files**: CONTRIBUTING, SECURITY, CODE_OF_CONDUCT guides

### Changed
- **Settings Redesign**: New sidebar architecture for easier navigation
- **Plain English Terminology**: Clearer labels throughout settings
- **Compact Settings Layout**: More efficient use of space
- **Divider Styles**: Improved visual options for section dividers

### Fixed
- Separator now handles left-click when main icon is hidden
- Context menu anchors correctly when main icon is hidden
- Default menu bar positions reset properly
- Status item placement validation improved

---

## [1.0.6] - 2026-01-14

### Changed
- Enabled Sparkle auto-update framework
- Updated appcast for automatic updates

> **Note:** Homebrew distribution was restored in March 2026. Use `brew install --cask sane-apps/tap/sanebar`.

---

## [1.0.5] - 2026-01-14

### Added
- **Find Icon**: Right-click menu to move icons between Hidden/Visible sections
- Improved Control Center and system menu extra handling

### Fixed
- Find Icon "Visible" tab showing icons collapsed/compressed
- Hidden tab appearing empty when icons were temporarily expanded
- Coordinate conversion issues preventing icon movement

### Known Issues
- VibeProxy icon cannot be moved via Find Icon (manual drag still works)

---

## [1.0.3] - 2026-01-09

### Added
- Pre-compiled DMG releases for easier installation
- Menu bar spacing control (Settings → Advanced → System Icon Spacing)
- Visual zones with custom dividers (line, dot styles)
- Find Icon search with cache-first loading

### Changed
- Find Icon shortcut changed from `⌘Space` to `⌘⇧Space` (avoid Spotlight conflict)
- Menu bar icon updated to bolder design

---

## [1.0.2] - 2026-01-09

### Changed
- Menu bar icon redesigned (removed circle, use line.3.horizontal.decrease)
- Website and documentation updates

---

## [1.0.0] - 2026-01-05

### Added
- Initial public release
- Hide/show menu bar icons with click or keyboard shortcut
- AppleScript support for automation
- Per-icon keyboard shortcuts
- Profiles for different configurations
- Show on hover option
- Menu bar appearance customization (tint, shadow)
- Privacy-focused: 100% on-device, no analytics

### Technical
- Requires macOS Sequoia (15.0) or later
- Apple Silicon only (arm64)
- Signed and notarized

---

## Version Numbering

- v1.0.1 and v1.0.4 were skipped due to build/release pipeline issues
- Tags: https://github.com/sane-apps/SaneBar/tags
