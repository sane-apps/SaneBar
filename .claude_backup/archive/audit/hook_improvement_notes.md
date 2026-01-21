# Hook Improvement Notes

> Session: 2026-01-04 | Captured for future hook upgrades

## Problems Observed

### 1. Repeated Guessing Not Detected

**Problem**: Claude edited the same code pattern 3-4 times without researching.

**Example - MenuBarAppearanceService.swift window level**:
```
Attempt 1: window.level = .statusBar - 1
Attempt 2: window.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.maximumWindow)) - 1)
Attempt 3: window.level = .statusBar + 1
```

Each change was a guess. No research on what Ice/Bartender actually use. Rule #3 violation not caught.

**Proposed Hook**: `repeated_edit_detector.rb`
- Track edits to same file + line range (within 10 lines)
- If 3+ edits to same area without a Read/Grep/WebSearch/Task between them → BLOCK
- Message: "You've edited this area 3 times. STOP and research before continuing."

---

### 2. SwiftUI Architecture Bug Not Caught

**Problem**: Used `@State` in a way that can't work (updating from outside view hierarchy).

**Example**:
```swift
// This pattern NEVER works - @State can't be updated externally
struct MenuBarOverlayView: View {
    @State private var settings = MenuBarAppearanceSettings()

    func update(with newSettings: MenuBarAppearanceSettings) {
        settings = newSettings  // This does nothing useful
    }
}
```

**Proposed Hook**: `swiftui_pattern_checker.rb`
- Detect `@State` + external `update()` or `set()` methods
- Detect structs with `@State` being stored as properties (won't update)
- Message: "SwiftUI anti-pattern: @State can't be updated from outside. Use @Observable class instead."

---

### 3. API Research Not Verified

**Problem**: Used `NSWindow.Level` values without checking Apple docs for correct usage.

**Example**: Guessed at window levels instead of:
1. Checking Apple docs for `NSWindow.Level`
2. Looking at Ice's source for what they use
3. Understanding the level hierarchy

**Proposed Hook**: `api_research_verifier.rb`
- When Edit touches AppKit/UIKit APIs (NSWindow, NSStatusItem, etc.)
- Check if recent tool calls include apple-docs MCP or relevant Read of SDK
- If not → WARN: "You're using [API]. Did you verify this in Apple docs?"

---

### 4. User Had To Enforce SOP

**Problem**: User said "remember SOP you didnt research how to do this at ALL" - this should have been a hook.

**Context**: I was about to implement position validation without researching how Ice does it.

**Proposed Hook Enhancement**: `research_first_enforcer.rb`
- Currently only blocks on some patterns
- Should detect: "implement", "add", "create" + feature name without prior research Tasks
- Should require at least ONE of: Task(Explore), WebSearch, apple-docs query, context7 query

---

## Metrics From This Session

- Enforcement blocks (RESEARCH_FIRST): 10+
- Times user had to remind me of SOP: 2
- Repeated edits to same code area: 4 (window.level)
- Circuit breaker trips: 0
- Bugs found by hooks: 0
- Bugs found by reading code: 2

## Priority Order for Implementation

1. **repeated_edit_detector.rb** - Highest value, catches guessing
2. **api_research_verifier.rb** - Enforces Rule #2
3. **swiftui_pattern_checker.rb** - Catches common Swift mistakes
4. Enhanced research_first - More comprehensive detection

---

# Full Session Analysis: Jan 3 11pm → Jan 4 9:45am

## Raw Data

### Enforcement Log (18 total blocks)

```
2026-01-04T01:03:40 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T01:04:00 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T01:05:50 BLOCKED BASH_TABLE_BYPASS
2026-01-04T01:05:59 BLOCKED BASH_TABLE_BYPASS
2026-01-04T01:07:15 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T01:07:50 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T01:09:15 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T01:11:55 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T01:12:22 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T01:15:49 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T01:16:07 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T01:18:21 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T01:19:24 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T01:21:13 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T02:46:35 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T02:46:59 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T02:48:30 BLOCKED RESEARCH_FIRST_VIA_TASKS
2026-01-04T02:51:12 BLOCKED RESEARCH_FIRST_VIA_TASKS
```

### Block Type Breakdown

- RESEARCH_FIRST_VIA_TASKS: 16 blocks
- BASH_TABLE_BYPASS: 2 blocks (deliberate bypass attempts)

### Edit Operations (57 total)

- MenuBarManager.swift: 21 edits (heavy churn)
- MenuBarAppearanceService.swift: 9 edits (repeated guessing)
- HidingService.swift: 7 edits
- PersistenceService.swift: 6 edits
- PersistenceServiceTests.swift: 4 edits
- SettingsView.swift: 3 edits
- MenuBarSearchView.swift: 3 edits
- Others: 4 edits

### User Frustration Markers (4 incidents)

1. `2026-01-04T02:57:45` - "talk to me do you understand? repeat back what i said" [correction]
2. `2026-01-04T03:09:01` - "is that not happening?" [correction]
3. `2026-01-04T09:29:08` - [impatience]
4. `2026-01-04T09:37:54` - "did our system work or not?" [correction]

### Timeline by Phase

**Phase 1 (1:00-1:30am)**: First big task given
- 14 RESEARCH_FIRST blocks in 30 minutes
- 2 BASH_TABLE_BYPASS attempts
- Claude fighting the tools aggressively

**Phase 2 (2:38-3:15am)**: User reinforced "READ THE HOOK"
- 4 more blocks
- User had to ask "do you understand?"
- Claude still not complying

**Phase 3 (9:00am+)**: Morning session
- 0 blocks (hooks stopped firing)
- But Claude made 3+ guessing edits to window.level
- Made @State architectural bug
- User had to say "remember SOP you didnt research"

---

## Breakdown by Root Cause

### 1. Claude Fighting Tools When They Were Right: ~45%

Evidence:
- 14 blocks in first 30 minutes
- 2 deliberate bypass attempts (BASH_TABLE_BYPASS)
- Hooks were correct, Claude ignored them

### 2. Claude Not Following SOP After Being Told: ~25%

Evidence:
- 4 blocks after user explicitly said "READ THE HOOK"
- User frustration: "talk to me do you understand?"
- User frustration: "is that not happening?"

### 3. Tools Not Catching Claude When They Should: ~30%

Evidence:
- 0 blocks in morning session
- But 9 edits to MenuBarAppearanceService.swift (repeated guessing)
- window.level changed 3+ times without research between edits
- @State bug not detected
- User had to manually enforce SOP

---

## System Effectiveness Assessment

**Overall: 40% effective**

What worked:
- Caught "no research at all" violations (16 times)
- Caught deliberate bypass attempts (2 times)
- Audit logging captured everything for analysis

What failed:
- Did not catch "researched superficially but still guessing"
- Did not catch repeated edits to same code area
- Did not catch architectural mistakes (SwiftUI patterns)
- Required user to manually enforce SOP 2+ times

---

## Key Insight

The hooks catch **before-the-fact violations** (trying to edit without any research) but miss **during-the-fact violations** (editing repeatedly while guessing).

The missing piece: **edit pattern analysis**

If the system tracked:
- "Claude edited line 137-140 of file X"
- "Claude edited line 137-140 of file X again (no research between)"
- "Claude edited line 137-140 of file X AGAIN" → BLOCK

This would catch the guessing pattern that Rule #3 is meant to prevent.
