---
name: codebase-explorer
description: Explore SaneBar codebase efficiently using Explore subagent. Use when searching for code, understanding architecture, finding patterns, or locating implementations. Keywords: find, search, where is, how does, explore, understand, architecture, codebase
allowed-tools: Read, Grep, Glob, Bash(git:*), Bash(ls:*)
---

# Codebase Explorer

## When This Skill Activates

Claude uses this when you ask:
- "Where is [class/function] defined?"
- "How does [feature] work?"
- "Find all uses of [pattern]"
- "Show me the [component] architecture"
- "Search for [keyword] in the codebase"

## IMPORTANT: Use Explore Subagent

For large searches, **delegate to Explore subagent** (Haiku-powered, saves tokens):

```
Task tool with subagent_type: Explore
```

This is more efficient than direct Grep/Glob for open-ended exploration.

## SaneBar Codebase Map

```
/Users/sj/SaneBar/
├── Core/                    # Foundation
│   ├── Services/            # AccessibilityService, PermissionService
│   ├── Models/              # StatusItemModel, AppModel
│   └── Managers/            # State management
├── UI/                      # SwiftUI
│   ├── Onboarding/          # Permission flow
│   ├── Settings/            # SettingsView + tabs
│   └── Components/          # Reusable components
├── Tests/                   # Swift Testing (@Test, #expect)
├── scripts/                 # Ruby automation
│   ├── SaneMaster.rb        # Main CLI
│   └── hooks/               # Claude Code hooks
└── .claude/                 # Configuration
    ├── rules/               # Code style rules
    ├── skills/              # This directory
    └── CLAUDE.md            # Project SOP
```

## Common Searches

### Find Definitions
```bash
# Where is a class defined?
grep -r "class StatusBarController" --include="*.swift"

# Where is a protocol?
grep -r "protocol.*Service" --include="*.swift"
```

### Find Usage
```bash
# All uses of a type
grep -r "StatusItemModel" --include="*.swift"

# All accessibility API calls
grep -r "AXUIElement" --include="*.swift"
```

### Find by Pattern
```bash
# All views
glob UI/**/*View.swift

# All services
glob Core/Services/*.swift

# All tests
glob Tests/**/*Tests.swift
```

## Code Style Rules

Reference `.claude/rules/` before making changes:

| Rule File | Key Points |
|-----------|------------|
| `views.md` | Extract if body > 50 lines, use @Observable |
| `services.md` | Use actors, protocol-first, dependency injection |
| `models.md` | Structs preferred, Codable/Equatable/Sendable |
| `tests.md` | Swift Testing only (not XCTest), no tautologies |

## Key Patterns in SaneBar

- **Accessibility**: All menu bar scanning uses `AXUIElement` APIs
- **Permissions**: `PermissionService` handles AX permission flow
- **Status Items**: `StatusBarController` manages NSStatusItem positioning
- **State**: `@Observable` for UI, actors for concurrent services
