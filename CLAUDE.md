# SaneBar Project Configuration

> Project-specific settings that override/extend the global ~/CLAUDE.md
---

## PRIME DIRECTIVE (from ~/CLAUDE.md)

> When hooks fire: **READ THE MESSAGE FIRST**. The answer is in the prompt/hook/memory/SOP.
> Stop guessing. Start reading.



## Project Structure

| Path | Purpose |
|------|---------|
| `scripts/SaneMaster.rb` | Build tool - use instead of raw xcodebuild |
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
./scripts/SaneMaster.rb verify          # Build + unit tests
./scripts/SaneMaster.rb test_mode       # Kill -> Build -> Launch -> Logs
./scripts/SaneMaster.rb logs --follow   # Stream live logs
./scripts/SaneMaster.rb verify_api X    # Check if API exists in SDK

# Memory Health (MCP Knowledge Graph)
./scripts/SaneMaster.rb mh              # Check entity/token counts
./scripts/SaneMaster.rb mcompact        # Compact verbose entities
./scripts/SaneMaster.rb mcleanup        # Generate MCP cleanup commands

# Circuit Breaker (Failure Tracking)
./scripts/SaneMaster.rb breaker_status  # Check if breaker is OPEN/CLOSED
./scripts/SaneMaster.rb breaker_errors  # Show failure messages
./scripts/SaneMaster.rb reset_breaker   # Reset after investigation

# Session Management
./scripts/SaneMaster.rb session_end     # End session + memory prompt
./scripts/SaneMaster.rb compliance      # Show session compliance report
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
./scripts/SaneMaster.rb verify_api AXUIElementCreateSystemWide Accessibility
./scripts/SaneMaster.rb verify_api kAXExtrasMenuBarAttribute Accessibility
./scripts/SaneMaster.rb verify_api AXUIElementCopyAttributeValue Accessibility
./scripts/SaneMaster.rb verify_api SMAppService ServiceManagement
```

---

## Compliance Engine

SaneBar has automated SOP enforcement via hooks:

**Circuit Breaker** (`.claude/circuit_breaker.json`):
- Trips at: 3x same error OR 5 total failures
- When tripped: Edit/Bash tools blocked until reset
- Reset: `./scripts/SaneMaster.rb reset_breaker`

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
