# SaneBar Development Guide (SOP)

**Version 1.1** | Last updated: 2026-01-01

---

## ⚠️ THESE WILL BURN YOU

Real failures from past sessions. Don't repeat them.

| Mistake | What Happened | Prevention |
|---------|---------------|------------|
| **Guessed API** | `await scheduleSegment` blocks forever (waits for playback, not scheduling) | `verify_api` first |
| **Assumed Swift binding** | MTAudioProcessingTap C API ≠ Swift API. Hours wasted. | Check `apple-docs` MCP |
| **Skipped xcodegen** | Created file, "file not found" for 20 minutes | `xcodegen generate` after new files |
| **Deleted "unused" file** | Periphery said unused, but ServiceContainer needed it | Grep before delete |
| **Kept guessing** | Hidden Button + keyboardShortcut = EXC_BAD_ACCESS. 4 attempts. | Stop at 2, investigate |

**The #1 differentiator**: Skimming this SOP = 5/10 sessions. Internalizing it = 8+/10.

---

## Quick Start

```bash
./Scripts/SaneMaster.rb verify     # Build + test
./Scripts/SaneMaster.rb test_mode  # Full cycle: kill → build → launch → logs
```

**System**: macOS 26.2 (Tahoe), Apple Silicon, Ruby 3.4+

---

## The Rules

### #0: SAY THE RULE BEFORE CODING

Before writing code, state which rules apply.

```
🟢 "Uses AXUIElement API → verify_api first"
🟢 "New file → xcodegen after"
🔴 "Let me just code this real quick..."
```

### #1: STAY IN PROJECT

All files inside `/Users/sj/SaneBar/`. No exceptions without asking.

```
🟢 /Users/sj/SaneBar/Core/NewService.swift
🔴 ~/.claude/plans/anything.md
🔴 /tmp/scratch.swift
```

### #2: VERIFY BEFORE USING

**Any unfamiliar or Apple-specific API**: run `verify_api` first.

```bash
./Scripts/SaneMaster.rb verify_api AXUIElementCreateSystemWide Accessibility
```

```
🟢 verify_api → then code
🔴 "I remember this API has..."
🔴 "Stack Overflow says..."
```

**Real example**: `onKeyPress` does NOT have a `modifiers:` parameter. Guessing cost 30 minutes.

### #3: TWO STRIKES = STOP

Failed twice? **Stop coding. Start researching.**

```
🟢 "Failed twice → checking apple-docs MCP"
🔴 "Let me try one more thing..." (attempt #3, #4, #5...)
```

Stopping IS compliance. Guessing a 3rd time is the violation.

### #4: GREEN BEFORE DONE

`verify` must pass before claiming done.

```
🟢 "verify failed → fix → verify again → passes → done"
🔴 "verify failed but it's probably fine"
```

### #5: USE SANEMASTER

All builds through SaneMaster. No raw xcodebuild.

```
🟢 ./Scripts/SaneMaster.rb verify
🔴 xcodebuild -scheme SaneBar build
```

### #6: FULL CYCLE AFTER CHANGES

After completing a **logical unit of work** (not every typo):

```bash
./Scripts/SaneMaster.rb verify
killall -9 SaneBar
./Scripts/SaneMaster.rb launch
./Scripts/SaneMaster.rb logs --follow
```

Or just: `./Scripts/SaneMaster.rb test_mode`

### #7: TESTS FOR FIXES AND FEATURES

Every bug fix AND new feature gets a test. No tautologies.

```
🟢 #expect(error.code == .invalidInput)
🔴 #expect(true)
🔴 #expect(value == true || value == false)
```

### #8: DOCUMENT BUGS

Bug found? TodoWrite immediately. Fix it? Update BUG_TRACKING.md.

```
🟢 TodoWrite: "BUG: Items not appearing"
🔴 "I'll remember this"
```

### #9: NEW FILE = XCODEGEN

Created a file? Run `xcodegen generate`. Every time.

```
🟢 Create file → xcodegen generate
🔴 Create file → wonder why Xcode can't find it
```

### #10: FILE SIZE LIMITS

| Lines | Status |
|-------|--------|
| <500 | Good |
| 500-800 | OK if single responsibility |
| >800 | Must split |

Split by responsibility, not by line count.

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
