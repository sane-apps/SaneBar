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
# Build & Test
./Scripts/SaneMaster.rb verify          # Build + unit tests
./Scripts/SaneMaster.rb test_mode       # Kill -> Build -> Launch -> Logs
./Scripts/SaneMaster.rb logs --follow   # Stream live logs
./Scripts/SaneMaster.rb verify_api X    # Check if API exists in SDK

# Memory Health (MCP Knowledge Graph)
./Scripts/SaneMaster.rb mh              # Check entity/token counts
./Scripts/SaneMaster.rb mcompact        # Compact verbose entities
./Scripts/SaneMaster.rb mcleanup        # Generate MCP cleanup commands

# Circuit Breaker (Failure Tracking)
./Scripts/SaneMaster.rb breaker_status  # Check if breaker is OPEN/CLOSED
./Scripts/SaneMaster.rb breaker_errors  # Show failure messages
./Scripts/SaneMaster.rb reset_breaker   # Reset after investigation

# Session Management
./Scripts/SaneMaster.rb session_end     # End session + memory prompt
./Scripts/SaneMaster.rb compliance      # Show session compliance report
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

## Compliance Engine

SaneBar has automated SOP enforcement via hooks:

**Circuit Breaker** (`.claude/circuit_breaker.json`):
- Trips at: 3x same error OR 5 total failures
- When tripped: Edit/Bash tools blocked until reset
- Reset: `./Scripts/SaneMaster.rb reset_breaker`

**Memory Thresholds** (auto-checked at session start/end):
- Entities: 60 (warn), 80 (critical)
- Tokens: 8,000 (warn), 12,000 (critical)
- Archive: Old entities moved to `.claude/memory_archive.jsonl`

**Hooks Active** (in `.claude/settings.json`):
- `circuit_breaker.rb` - Pre-tool failure tracking
- `edit_validator.rb` - File location/size checks
- `test_quality_checker.rb` - Detects tautology tests
- `audit_logger.rb` - Decision trail to `.claude/audit_log.jsonl`

---

## Distribution Notes

- **Cannot sandbox**: Accessibility API requires unsandboxed app
- **Notarization**: Use hardened runtime + Developer ID signing
- **Entitlements**: No sandbox, but hardened runtime required
