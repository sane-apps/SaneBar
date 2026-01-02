# SaneBar Development Guide (SOP)

**Version 1.1** | Last updated: 2026-01-01

---

## ⚠️ THIS HAS BURNED YOU

Real failures from past sessions. Don't repeat them.

| Mistake | What Happened | Prevention |
|---------|---------------|------------|
| **Guessed API** | Assumed `AXUIElement` has `.menuBarItems`. It doesn't. 20 min wasted. | `verify_api` first |
| **Assumed permission flow** | Called AX functions before checking `AXIsProcessTrusted()`. Silent failures. | Check permission state first |
| **Skipped xcodegen** | Created `HidingService.swift`, "file not found" for 20 minutes | `xcodegen generate` after new files |
| **Kept guessing** | Menu bar traversal wrong 4 times. Finally checked apple-docs MCP. | Stop at 2, investigate |
| **Deleted "unused" file** | Periphery said unused, but `ServiceContainer` needed it. Broke build. | Grep before delete |

**The #1 differentiator**: Skimming this SOP = 5/10 sessions. Internalizing it = 8+/10.

**"If you skim you sin."** — The answers are here. Read them.

### Why Catchy Rule Names?

Memorable rules + clear tool names = **human can audit in real-time**.

Names like "SANEMASTER OR DISASTER" aren't just mnemonics—they're a **shared vocabulary**. When I say "Rule #5" you instantly know whether I'm complying or drifting. This lets you catch mistakes as they happen instead of after 20 minutes of debugging.

---

## Quick Start

```bash
./Scripts/SaneMaster.rb verify     # Build + test
./Scripts/SaneMaster.rb test_mode  # Full cycle: kill → build → launch → logs
```

**System**: macOS 26.2 (Tahoe), Apple Silicon, Ruby 3.4+

---

## The Rules

### #0: NAME THE RULE BEFORE YOU CODE

Before writing code, state which rules apply.

```
🟢 "Uses AXUIElement API → Rule #2: VERIFY BEFORE YOU TRY"
🟢 "New file → Rule #9: NEW FILE? GEN THAT PILE"
🔴 "Let me just code this real quick..."
```

### #1: STAY IN YOUR LANE

All files inside `/Users/sj/SaneBar/`. No exceptions without asking.

```
🟢 /Users/sj/SaneBar/Core/NewService.swift
🔴 ~/.claude/plans/anything.md
🔴 /tmp/scratch.swift
```

### #2: VERIFY BEFORE YOU TRY

**Any unfamiliar or Apple-specific API**: run `verify_api` first.

```bash
./Scripts/SaneMaster.rb verify_api AXUIElementCreateSystemWide Accessibility
```

```
🟢 verify_api → then code
🔴 "I remember this API has..."
🔴 "Stack Overflow says..."
```

### #3: TWO STRIKES? INVESTIGATE

Failed twice? **Stop coding. Start researching.**

```
🟢 "Failed twice → checking apple-docs MCP"
🔴 "Let me try one more thing..." (attempt #3, #4, #5...)
```

Stopping IS compliance. Guessing a 3rd time is the violation.

### #4: GREEN MEANS GO

`verify` must pass before claiming done.

```
🟢 "verify failed → fix → verify again → passes → done"
🔴 "verify failed but it's probably fine"
```

### #5: SANEMASTER OR DISASTER

All builds through SaneMaster. No raw xcodebuild.

```
🟢 ./Scripts/SaneMaster.rb verify
🔴 xcodebuild -scheme SaneBar build
```

### #6: BUILD, KILL, LAUNCH, LOG

After completing a **logical unit of work** (not every typo):

```bash
./Scripts/SaneMaster.rb verify    # BUILD
killall -9 SaneBar                # KILL
./Scripts/SaneMaster.rb launch    # LAUNCH
./Scripts/SaneMaster.rb logs --follow  # LOG
```

Or just: `./Scripts/SaneMaster.rb test_mode`

### #7: NO TEST? NO REST

Every bug fix AND new feature gets a test. No tautologies.

```
🟢 #expect(error.code == .invalidInput)
🔴 #expect(true)
🔴 #expect(value == true || value == false)
```

### #8: BUG FOUND? WRITE IT DOWN

Bug found? TodoWrite immediately. Fix it? Update BUG_TRACKING.md.

```
🟢 TodoWrite: "BUG: Items not appearing"
🔴 "I'll remember this"
```

### #9: NEW FILE? GEN THAT PILE

Created a file? Run `xcodegen generate`. Every time.

```
🟢 Create file → xcodegen generate
🔴 Create file → wonder why Xcode can't find it
```

### #10: FIVE HUNDRED'S FINE, EIGHT'S THE LINE

| Lines | Status |
|-------|--------|
| <500 | Good |
| 500-800 | OK if single responsibility |
| >800 | Must split |

Split by responsibility, not by line count.

---

## Plan Format (MANDATORY)

Every plan must cite which rule justifies each step. No exceptions.

**Format**: `[Rule #X: NAME] - specific action with file:line or command`

### ❌ DISAPPROVED PLAN (Real Example - 2026-01-01)

```
## Plan: Fix Menu Bar Icon Issues

### Issues
1. Menu bar icon shows SF Symbol instead of custom icon
2. Permission URL opens browser instead of System Settings

### Steps
1. Nuclear clean to clear caches
2. Fix URL scheme in PermissionService.swift
3. Rebuild and verify
4. Launch and test manually

Approve?
```

**Why rejected:**
- No `[Rule #X]` citations - can't verify SOP compliance
- No tests specified (violates Rule #7)
- No BUG_TRACKING.md update (violates Rule #8)
- Vague "fix" without file:line references

### ✅ APPROVED PLAN (Same Task, Correct Format)

```
## Plan: Fix Menu Bar Icon & Permission URL

### Bugs to Fix
| Bug | File:Line | Root Cause |
|-----|-----------|------------|
| Icon not loading | MenuBarManager.swift:50 | Asset cache not cleared |
| URL opens browser | PermissionService.swift:68 | URL scheme hijacked |

### Steps

[Rule #5: USE SANEMASTER] - `./Scripts/SaneMaster.rb clean --nuclear`
[Rule #9: NEW FILE = XCODEGEN] - Already ran for asset catalog

[Rule #7: TESTS FOR FIXES] - Create tests:
  - Tests/MenuBarIconTests.swift: `testCustomIconLoads()`
  - Tests/PermissionServiceTests.swift: `testOpenSettingsNotBrowser()`

[Rule #8: DOCUMENT BUGS] - Update BUG_TRACKING.md:
  - BUG-001: Asset cache not cleared by nuclear clean
  - BUG-002: URL scheme opens default browser

[Rule #6: FULL CYCLE] - Verify fixes:
  - `./Scripts/SaneMaster.rb verify`
  - `killall -9 SaneBar`
  - `./Scripts/SaneMaster.rb launch`
  - Manual: Confirm custom icon visible, Settings opens System Settings

[Rule #4: GREEN BEFORE DONE] - All tests pass before claiming complete

Approve?
```

**Why approved:**
- Every step cites its justifying rule
- Tests specified for each bug fix
- BUG_TRACKING.md updates included
- Specific file:line references
- Clear verification criteria

---

## Self-Rating (MANDATORY)

After each task, rate yourself. Format:

```
**Self-rating: 7/10**
✅ Used verify_api, ran full cycle
❌ Forgot to run xcodegen after new file
```

| Score | Meaning |
|-------|---------|
| 9-10 | All rules followed |
| 7-8 | Minor miss |
| 5-6 | Notable gaps |
| 1-4 | Multiple violations |

---

## Project Structure

```
SaneBar/
├── Core/           # Managers, Services, Models
├── UI/             # SwiftUI views
├── Tests/          # Unit tests
├── Scripts/        # SaneMaster automation
└── SaneBarApp.swift
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Ghost beeps / no launch | `xcodegen generate` |
| Phantom build errors | `./Scripts/SaneMaster.rb clean --nuclear` |
