# SaneBar Project Configuration

> Project-specific settings that override/extend the global ~/CLAUDE.md

---

## Project Location

| Path | Description |
|------|-------------|
| **This project** | `~/SaneApps/apps/SaneBar/` |
| **Save outputs** | `~/SaneApps/apps/SaneBar/outputs/` |
| **Screenshots** | `~/Desktop/Screenshots/` (label with project prefix) |
| **Shared UI** | `~/SaneApps/infra/SaneUI/` |
| **Hooks/tooling** | `~/SaneApps/infra/SaneProcess/` |

**Sister apps:** SaneClip, SaneVideo, SaneSync, SaneHosts, SaneAI, SaneClick

---

## Key Documentation

| Document | When to Use |
|----------|-------------|
| [BUG_TRACKING.md](BUG_TRACKING.md) | Report bugs, check GitHub issue status |
| [ROADMAP.md](ROADMAP.md) | Feature status, what's planned |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Full SOP, 12 rules, compliance |
| [.claude/rules/](/.claude/rules/README.md) | Code style rules by file type |
| [docs/DEBUGGING_MENU_BAR_INTERACTIONS.md](docs/DEBUGGING_MENU_BAR_INTERACTIONS.md) | Positioning bugs, coordinate system |

---

## Sane Philosophy

```
┌─────────────────────────────────────────────────────┐
│           BEFORE YOU SHIP, ASK:                     │
│                                                     │
│  1. Does this REDUCE fear or create it?             │
│  2. Power: Does user have control?                  │
│  3. Love: Does this help people?                    │
│  4. Sound Mind: Is this clear and calm?             │
│                                                     │
│  Grandma test: Would her life be better?            │
│                                                     │
│  "Not fear, but power, love, sound mind"            │
│  — 2 Timothy 1:7                                    │
└─────────────────────────────────────────────────────┘
```

→ Full philosophy: `~/SaneApps/meta/Brand/NORTH_STAR.md`

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

## ⚠️ NSStatusItem Positioning - THE ICE PATTERN

**SaneBar uses the Ice pattern for positioning. Do NOT reinvent the wheel.**

→ **Full docs: `docs/DEBUGGING_MENU_BAR_INTERACTIONS.md`**

### The Pattern (10 lines, battle-tested)

```swift
// 1. SEED ordinal positions in UserDefaults BEFORE creating items
private static func seedPositionsIfNeeded() {
    let defaults = UserDefaults.standard
    if defaults.object(forKey: "NSStatusItem Preferred Position \(mainAutosaveName)") == nil {
        defaults.set(0, forKey: "NSStatusItem Preferred Position \(mainAutosaveName)")  // 0 = rightmost
    }
    if defaults.object(forKey: "NSStatusItem Preferred Position \(separatorAutosaveName)") == nil {
        defaults.set(1, forKey: "NSStatusItem Preferred Position \(separatorAutosaveName)")  // 1 = second
    }
}

// 2. CREATE items AFTER seeding, assign autosaveName
init() {
    Self.seedPositionsIfNeeded()
    self.mainItem = NSStatusBar.system.statusItem(withLength: variableLength)
    self.mainItem.autosaveName = Self.mainAutosaveName
    // ...
}
```

### Key Rules

| Rule | Why |
|------|-----|
| Seed BEFORE create | macOS reads position on item creation |
| Use ordinal (0,1,2), not pixels | macOS interprets as ordering hints |
| Trust macOS | No recovery/validation/nudge logic needed |
| Reference: [Ice](https://github.com/jordanbaird/Ice) | The authoritative implementation |

### Reference

- Pattern based on [Ice](https://github.com/jordanbaird/Ice) implementation
- See `docs/DEBUGGING_MENU_BAR_INTERACTIONS.md` for full details

---

## SaneBar-Specific Patterns

- **Accessibility API**: All menu bar scanning uses `AXUIElement` APIs
- **Verify APIs**: Always run `verify_api` before using Apple Accessibility APIs
- **Permission Flow**: `UI/Onboarding/WelcomeView.swift` handles AX permission
- **Services**: Located in `Core/Services/` (AccessibilityService, DiagnosticsService, etc.)
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

**Hooks Active** (via SaneProcess in `.claude/settings.json`):
- `session_start.rb` - Project context, memory health, MCP verification
- `saneprompt.rb` - Prompt intelligence, staging detection
- `sanetools.rb` - Pre-tool checks: MCP verification, circuit breaker, edit validation
- `sanetrack.rb` - Post-tool: failure tracking, feature reminders, tautology detection
- `sanestop.rb` - Session summary, SOP score, weak spot tracking

---

## MCP Tool Optimization (TOKEN SAVERS)

### XcodeBuildMCP Session Setup
At session start, set defaults ONCE to avoid repeating on every build:
```
mcp__XcodeBuildMCP__session-set-defaults:
  projectPath: /Users/sj/SaneApps/apps/SaneBar/SaneBar.xcodeproj
  scheme: SaneBar
  arch: arm64
```
Note: SaneBar is a **macOS app** - no simulator needed. Use `build_macos`, `test_macos`, `build_run_macos`.

### claude-mem 3-Layer Workflow (10x Token Savings)
```
1. search(query, project: "SaneBar") → Get index with IDs (~50-100 tokens/result)
2. timeline(anchor=ID)              → Get context around results
3. get_observations([IDs])          → Fetch ONLY filtered IDs
```
**Always add `project: "SaneBar"` to searches for isolation.**

### apple-docs Optimization
- `compact: true` works on `list_technologies`, `get_sample_code`, `wwdc` (NOT on `search_apple_docs`)
- `analyze_api analysis="all"` for comprehensive API analysis
- `apple_docs` as universal entry point (auto-routes queries)

### context7 for Library Docs
- `resolve-library-id` FIRST, then `query-docs`
- SwiftUI ID: `/websites/developer_apple_swiftui` (13,515 snippets!)

### macos-automator (493 Pre-Built Scripts)
- `get_scripting_tips search_term: "keyword"` to find scripts
- `get_scripting_tips list_categories: true` to browse
- 13 categories including `13_developer` (92 Xcode/dev scripts)

### github MCP
- `search_code` to find patterns in public repos
- `search_repositories` to find reference implementations

---

## Claude Code Features (USE THESE!)

### Key Commands to Remember

| Command | When to Use | Shortcut |
|---------|-------------|----------|
| `/rewind` | Rollback code AND conversation after errors | `Esc+Esc` |
| `/context` | Visualize context window token usage | - |
| `/compact [instructions]` | Optimize memory with focus | - |
| `/stats` | See usage patterns (press `r` for date range) | - |

### Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Esc+Esc` | Rewind to checkpoint |
| `Shift+Tab` | Cycle permission modes (Normal → Auto-Accept → Plan) |
| `Option+T` | Toggle extended thinking |
| `Ctrl+O` | Toggle verbose mode |
| `Ctrl+B` | Background running task |

### Smart /compact Instructions

Don't just run `/compact` - give it focus instructions:
```
/compact keep SaneBar accessibility patterns and bug fixes, archive general Swift tips
```

### Project Skills (Auto-Discovered)

Skills in `.claude/skills/` activate automatically based on context:

| Skill | Triggers When |
|-------|---------------|
| `session-context-manager` | Checking memory health, session state |
| `memory-compactor` | Memory full, tokens high, need to archive |
| `codebase-explorer` | Searching code, finding implementations |
| `feature-reminders` | Claude checks itself for feature suggestions |

### Use Explore Subagent for Searches

For large codebase searches, delegate to Explore subagent (Haiku-powered, saves context):
```
Task tool with subagent_type: Explore
```

### Auto-Reminders Active

Hooks will remind about features at appropriate times:
- `/rewind` suggested after errors
- `/context` suggested every 5 edits
- Explore subagent suggested for complex searches

---

## Distribution Notes

- **Cannot sandbox**: Accessibility API requires unsandboxed app
- **Notarization**: Use hardened runtime + Developer ID signing
- **Entitlements**: No sandbox, but hardened runtime required
