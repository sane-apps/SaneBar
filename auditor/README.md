# SaneBar Audit Package

> Complete state machine documentation and source files for code review.

## Contents

| File | Description |
|------|-------------|
| `state-machines.md` | **START HERE** - Full 13-section audit documentation with Mermaid diagrams |
| `HidingService.swift` | Core hide/show state machine (2 states) |
| `AccessibilityService.swift` | Permission monitoring + cache management |
| `MenuBarManager.swift` | Main orchestrator (ties all services together) |
| `SearchWindowController.swift` | Find Icon window lifecycle |
| `PersistenceService.swift` | Settings storage |

## Reading Order

1. **state-machines.md** - Comprehensive documentation covering:
   - State diagrams (Mermaid format)
   - All transitions with guards
   - Concurrency model & thread safety
   - Error handling matrix
   - External API dependencies
   - Security considerations
   - Test coverage checklist

2. **HidingService.swift** - Start here for core logic (simplest, ~180 lines)

3. **MenuBarManager.swift** - Main coordinator (~840 lines, references all other services)

4. **AccessibilityService.swift** - AX API interactions (~775 lines)

## Key Architecture Points

- **All UI code is `@MainActor`** - Thread-safe by design
- **No singletons in business logic** - Dependency injection for testability
- **Hiding via NSStatusItem.length** - No CGEvent cursor hijacking
- **Permission monitoring** - Reactive via `DistributedNotificationCenter`

## Questions?

Contact: [your contact info here]
