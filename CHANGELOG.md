# Changelog

All notable changes to SaneBar are documented here.

See [RELEASE_NOTES_1.0.5.md](RELEASE_NOTES_1.0.5.md) for detailed 1.0.5 notes.
For user-requested features, see [marketing/feature-requests.md](marketing/feature-requests.md).

---

## [1.0.8] - 2026-01-17

### Added
- **Focus Mode Trigger**: Auto-show hidden icons when macOS Focus Mode changes (Work, Personal, Do Not Disturb, etc.)
- **Code Tracing Tools**: `button_map.rb` and `trace_flow.rb` scripts for debugging UI flows
- **Class Diagram**: PlantUML visualization of codebase architecture

### Changed
- **Ice Pattern**: Simplified NSStatusItem positioning (removed 880 lines of cruft)
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
