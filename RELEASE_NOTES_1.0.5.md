# SaneBar v1.0.5 Release Notes

## 🎉 What's New

### Find Icon Window Enhancements
- **Icon Moving**: Right-click menu options to move icons between Hidden and Visible sections
  - Works for most apps (Pipit, Rectangle, Control Center menu extras, etc.)
  - Known limitation: VibeProxy (VS Code fork) doesn't respond to automated moves
- **Fixed Classification**: Hidden/Visible tabs now correctly show icons based on separator position
  - Icons remain properly categorized even when temporarily expanded

### Technical Improvements
- Simplified coordinate system for icon manipulation (direct use of AX global coordinates)
- Improved separator-based classification logic
- Better handling of Control Center and system menu extras

## 🔧 Fixes

- Fixed Find Icon "Visible" tab showing all icons as collapsed/compressed
- Fixed Hidden tab appearing empty when icons were temporarily expanded
- Corrected coordinate conversion issues that prevented icon movement

## 📝 Known Issues

- VibeProxy icon cannot be moved via Find Icon right-click menu (manual drag still works)

## 🏗️ Technical Details

**Version**: 1.0.5 (Build 5)  
**Minimum macOS**: Sequoia (15.0)  
**Architecture**: Apple Silicon (arm64)  
**Code Signing**: Notarized and stapled

## 📦 Installation

### Purchase ($5)
Download the notarized DMG at [sanebar.com](https://sanebar.com).

### Build from Source (Free)
Clone from [GitHub](https://github.com/sane-apps/SaneBar) and build with Xcode.

### Manual Installation
1. Download `SaneBar-1.0.5.dmg`
2. Open the DMG
3. Drag SaneBar to Applications
4. Launch and grant Accessibility permissions when prompted

## 🔐 Security

This release is:
- ✅ Signed with Developer ID
- ✅ Notarized by Apple
- ✅ Hardened Runtime enabled
- ✅ Gatekeeper compatible

---

**Full Changelog**: https://github.com/sane-apps/SaneBar/compare/v1.0.4...v1.0.5
