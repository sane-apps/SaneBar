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
🟢 RIGHT: "Uses AXUIElement API → Rule #2: VERIFY BEFORE YOU TRY"
🟢 RIGHT: "New file → Rule #9: NEW FILE? GEN THAT PILE"
🔴 WRONG: "Let me just code this real quick..."
🔴 WRONG: "I'll figure out which rules apply as I go"
```

### #1: STAY IN YOUR LANE

All files inside `/Users/sj/SaneBar/`. No exceptions without asking.

```
🟢 RIGHT: /Users/sj/SaneBar/Core/NewService.swift
🟢 RIGHT: /Users/sj/SaneBar/Tests/NewServiceTests.swift
🔴 WRONG: ~/.claude/plans/anything.md
🔴 WRONG: /tmp/scratch.swift
```

### #2: VERIFY BEFORE YOU TRY

**Any unfamiliar or Apple-specific API**: run `verify_api` first.

```bash
./Scripts/SaneMaster.rb verify_api AXUIElementCreateSystemWide Accessibility
```

```
🟢 RIGHT: verify_api → then code
🟢 RIGHT: "Unfamiliar API → check apple-docs MCP first"
🔴 WRONG: "I remember this API has..."
🔴 WRONG: "Stack Overflow says..."
```

### #3: TWO STRIKES? INVESTIGATE

Failed twice? **Stop coding. Start researching.**

```
🟢 RIGHT: "Failed twice → checking apple-docs MCP"
🟢 RIGHT: "Second attempt failed → reading SDK .swiftinterface"
🔴 WRONG: "Let me try one more thing..." (attempt #3, #4, #5...)
🔴 WRONG: "Third time's a charm..."
```

Stopping IS compliance. Guessing a 3rd time is the violation.

### #4: GREEN MEANS GO

`verify` must pass before claiming done.

```
🟢 RIGHT: "verify failed → fix → verify again → passes → done"
🟢 RIGHT: "Tests red → not done, period"
🔴 WRONG: "verify failed but it's probably fine"
🔴 WRONG: "I'll fix the tests later"
```

### #5: SANEMASTER OR DISASTER

All builds through SaneMaster. No raw xcodebuild.

```
🟢 RIGHT: ./Scripts/SaneMaster.rb verify
🟢 RIGHT: ./Scripts/SaneMaster.rb test_mode
🔴 WRONG: xcodebuild -scheme SaneBar build
🔴 WRONG: swift build (bypassing project tools)
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

```
🟢 RIGHT: "Feature done → verify → kill → launch → check logs"
🟢 RIGHT: "Bug fixed → full cycle before claiming done"
🔴 WRONG: "Built successfully, shipping it" (skipped kill/launch/log)
🔴 WRONG: "Logs? I'll check if something breaks"
```

### #7: NO TEST? NO REST

Every bug fix AND new feature gets a test. No tautologies.

```
🟢 RIGHT: #expect(error.code == .invalidInput)
🟢 RIGHT: #expect(items.count == 3)
🔴 WRONG: #expect(true)
🔴 WRONG: #expect(value == true || value == false)
```

### #8: BUG FOUND? WRITE IT DOWN

Bug found? TodoWrite immediately. Fix it? Update BUG_TRACKING.md.

```
🟢 RIGHT: TodoWrite: "BUG: Items not appearing"
🟢 RIGHT: "Bug fixed → update BUG_TRACKING.md with root cause"
🔴 WRONG: "I'll remember this"
🔴 WRONG: "Fixed it, no need to document"
```

### #9: NEW FILE? GEN THAT PILE

Created a file? Run `xcodegen generate`. Every time.

```
🟢 RIGHT: Create file → xcodegen generate
🟢 RIGHT: "New test file → xcodegen generate immediately"
🔴 WRONG: Create file → wonder why Xcode can't find it
🔴 WRONG: "I'll run xcodegen later when I'm done"
```

### #10: FIVE HUNDRED'S FINE, EIGHT'S THE LINE

| Lines | Status |
|-------|--------|
| <500 | Good |
| 500-800 | OK if single responsibility |
| >800 | Must split |

Split by responsibility, not by line count.

```
🟢 RIGHT: "File at 600 lines, single responsibility → OK"
🟢 RIGHT: "File at 850 lines → split by protocol conformance"
🔴 WRONG: "File at 1200 lines but it works"
🔴 WRONG: "Split into 20 tiny files for no reason"
```

### #11: TOOL BROKE? FIX THE YOKE

If SaneMaster fails, **fix SaneMaster**. Never work around it.

```
🟢 RIGHT: "Nuclear clean doesn't clear cache → fix verify.rb"
🟢 RIGHT: "Logs path wrong → fix test_mode.rb"
🔴 WRONG: "Nuclear clean doesn't work → run raw xcodebuild"
🔴 WRONG: "Logs broken → just skip checking logs"
```

Working around broken tools creates invisible debt. Fix once, benefit forever.

### #12: TALK WHILE I WALK

Use subagents for heavy lifting. Main agent stays responsive to user.

```
🟢 RIGHT: "User asked question → answer while subagent keeps working"
🟢 RIGHT: "Long task → spawn subagent, stay responsive"
🔴 WRONG: "Hold on, let me finish this first..."
🔴 WRONG: "Running verify... (blocks for 2 minutes)"
```

User talks, you listen, work continues uninterrupted.

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
