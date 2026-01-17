# Changelog

All notable changes to SaneBar are documented here.

See [RELEASE_NOTES_1.0.5.md](RELEASE_NOTES_1.0.5.md) for detailed 1.0.5 notes.
For user-requested features, see [marketing/feature-requests.md](marketing/feature-requests.md).

---

## [1.0.6] - 2026-01-14

### Changed
- Enabled Sparkle auto-update framework
- Updated appcast and Homebrew cask for automatic updates

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
- Tags: https://github.com/stephanjoseph/SaneBar/tags
