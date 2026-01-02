# SaneBar Project Configuration

> Project-specific settings that override/extend the global ~/CLAUDE.md

---

## Project Structure

| Path | Purpose |
|------|---------|
| `Scripts/SaneMaster.rb` | Build tool - use instead of raw xcodebuild |
| `Core/` | Foundation types, Managers, Services |
| `Core/Services/` | Accessibility API wrappers, permission handling |
| `Core/Models/` | Data models (StatusItemModel, etc.) |
| `UI/` | SwiftUI views |
| `UI/Onboarding/` | Permission request flow |
| `Tests/` | Unit tests (regression tests go here) |
| `project.yml` | XcodeGen configuration |

---

## Quick Commands

```bash
./Scripts/SaneMaster.rb verify          # Build + unit tests
./Scripts/SaneMaster.rb test_mode       # Kill -> Build -> Launch -> Logs
./Scripts/SaneMaster.rb logs --follow   # Stream live logs
./Scripts/SaneMaster.rb verify_api X    # Check if API exists in SDK
```

---

## SaneBar-Specific Patterns

- **Accessibility API**: All menu bar scanning uses `AXUIElement` APIs
- **Verify APIs**: Always run `verify_api` before using Apple Accessibility APIs
- **Permission Flow**: `UI/Onboarding/PermissionRequestView.swift` handles AX permission
- **Services**: Located in `Core/Services/` (AccessibilityService, PermissionService, etc.)
- **State**: `@Observable` classes for UI state, actors for concurrent services

---

## Key APIs (Verify Before Using)

```bash
# Always verify these exist before coding:
./Scripts/SaneMaster.rb verify_api AXUIElementCreateSystemWide Accessibility
./Scripts/SaneMaster.rb verify_api kAXExtrasMenuBarAttribute Accessibility
./Scripts/SaneMaster.rb verify_api AXUIElementCopyAttributeValue Accessibility
./Scripts/SaneMaster.rb verify_api SMAppService ServiceManagement
```

---

## Distribution Notes

- **Cannot sandbox**: Accessibility API requires unsandboxed app
- **Notarization**: Use hardened runtime + Developer ID signing
- **Entitlements**: No sandbox, but hardened runtime required
