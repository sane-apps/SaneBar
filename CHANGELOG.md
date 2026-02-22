# Changelog

All notable changes to SaneBar are documented here.

For user-requested features, see [marketing/feature-requests.md](marketing/feature-requests.md).

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

> **Note:** Homebrew distribution discontinued as of Jan 2026. See GitHub #26.

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
