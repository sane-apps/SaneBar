# SaneBar Development Guide (SOP)

**Version 1.1** | Last updated: 2026-02-02

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

## ⚠️ THIS HAS BURNED YOU

Real failures from past sessions. Don't repeat them.

| Mistake | What Happened | Prevention |
|---------|---------------|------------|
| **Guessed API** | Assumed `AXUIElement` has `.menuBarItems`. It doesn't. 20 min wasted. | `verify_api` first |
| **Assumed permission flow** | Called AX functions before checking `AXIsProcessTrusted()`. Silent failures. | Check permission state first |
| **Skipped xcodegen** | Created `HidingService.swift`, "file not found" for 20 minutes | `xcodegen generate` after new files |
| **Kept guessing** | Menu bar traversal wrong 4 times. Finally checked apple-docs MCP. | Stop at 2, investigate |
| **Trusted codesign verify** | DMG rejected because an executable was inside a `.zip` resource (Apple inspects it; `codesign --deep` doesn’t). | Follow docs/NOTARIZATION.md + preflight zips |
| **Classified Hidden as "offscreen"** | Find Icon showed **Hidden empty** + **Visible everything** (because SaneBar hides via separator expansion, not by pushing icons off-screen). | Hidden/Visible is **separator-relative**: compare icon X against `separatorItem.window.frame.origin.x` |
| **Deleted "unused" file** | Periphery said unused, but `ServiceContainer` needed it. Broke build. | Grep before delete |
| **Modified icon moving logic** | 6-step stealth drag (100ms settle) is battle-tested since v1.0.12. Baseline commit `3cb6e9b`. | **DO NOT MODIFY** icon moving without reading `docs/DEBUGGING_MENU_BAR_INTERACTIONS.md` |

**The #1 differentiator**: Skimming this SOP = 5/10 sessions. Internalizing it = 8+/10.

**"If you skim you sin."** — The answers are here. Read them.

### Why Catchy Rule Names?

Memorable rules + clear tool names = **human can audit in real-time**.

Names like "SANEMASTER OR DISASTER" aren't just mnemonics—they're a **shared vocabulary**. When I say "Rule #5" you instantly know whether I'm complying or drifting. This lets you catch mistakes as they happen instead of after 20 minutes of debugging.

---

## 🚀 Quick Start for AI Agents

**New to this project? Start here:**

1. **Read Rule #0 first** (Section "The Rules") - It's about HOW to use all other rules
2. **All files stay in project** - NEVER write files outside `/Users/sj/SaneApps/apps/SaneBar/` unless user explicitly requests it
3. **Use SaneMaster.rb for everything** - `./scripts/SaneMaster.rb verify` for build+test, never raw `xcodebuild`
4. **Self-rate after every task** - Rate yourself 1-10 on SOP adherence (see Self-Rating section)

Bootstrap runs automatically via SessionStart hook. If it fails, run `./scripts/SaneMaster.rb doctor`.

**Your first action when user says "check our SOP" or "use our SOP":**
```bash
./scripts/SaneMaster.rb bootstrap  # Verify environment (may already have run)
./scripts/SaneMaster.rb verify     # Build + unit tests
```

**Key Commands:**
```bash
./scripts/SaneMaster.rb verify     # Build + test (~30s)
./scripts/SaneMaster.rb test_mode  # Kill → Build → Launch → Logs (full cycle)
./scripts/SaneMaster.rb logs --follow  # Stream live logs
```

**System**: macOS 26.2 (Tahoe), Apple Silicon, Ruby 3.4+

---

## The Rules

### #0: NAME THE RULE BEFORE YOU CODE

✅ DO: State which rules apply before writing code
❌ DON'T: Start coding without thinking about rules

```
🟢 RIGHT: "Uses AXUIElement API → Rule #2: VERIFY BEFORE YOU TRY"
🟢 RIGHT: "New file → Rule #9: NEW FILE? GEN THAT PILE"
🔴 WRONG: "Let me just code this real quick..."
🔴 WRONG: "I'll figure out which rules apply as I go"
```

### #1: STAY IN YOUR LANE

✅ DO: Save all files inside `/Users/sj/SaneApps/apps/SaneBar/`
❌ DON'T: Create files outside project without asking

```
🟢 RIGHT: /Users/sj/SaneApps/apps/SaneBar/Core/NewService.swift
🟢 RIGHT: /Users/sj/SaneApps/apps/SaneBar/Tests/NewServiceTests.swift
🔴 WRONG: ~/.claude/plans/anything.md
🔴 WRONG: /tmp/scratch.swift
```

### #2: VERIFY BEFORE YOU TRY

✅ DO: Run `verify_api` before using any Apple API
❌ DON'T: Assume an API exists from memory or web search

```bash
./scripts/SaneMaster.rb verify_api AXUIElementCreateSystemWide Accessibility
```

```
🟢 RIGHT: verify_api → then code
🟢 RIGHT: "Unfamiliar API → check apple-docs MCP first"
🔴 WRONG: "I remember this API has..."
🔴 WRONG: "Stack Overflow says..."
```

### #3: TWO STRIKES? INVESTIGATE

✅ DO: After 2 failures → stop, follow **Research Protocol** (see section below)
❌ DON'T: Guess a third time without researching

```
🟢 RIGHT: "Failed twice → Research Protocol → present plan"
🟢 RIGHT: "Second attempt failed → using all research tools"
🔴 WRONG: "Let me try one more thing..." (attempt #3, #4, #5...)
🔴 WRONG: "Third time's a charm..."
```

Stopping IS compliance. Guessing a 3rd time is the violation. See **Research Protocol** section for exactly which tools to use.

### #4: GREEN MEANS GO

✅ DO: Fix all verify failures before claiming done
❌ DON'T: Ship with failing tests

```
🟢 RIGHT: "verify failed → fix → verify again → passes → done"
🟢 RIGHT: "Tests red → not done, period"
🔴 WRONG: "verify failed but it's probably fine"
🔴 WRONG: "I'll fix the tests later"
```

### #5: SANEMASTER OR DISASTER

✅ DO: Use `./scripts/SaneMaster.rb` for all build/test operations
❌ DON'T: Use raw xcodebuild or swift commands

```
🟢 RIGHT: ./scripts/SaneMaster.rb verify
🟢 RIGHT: ./scripts/SaneMaster.rb test_mode
🔴 WRONG: xcodebuild -scheme SaneBar build
🔴 WRONG: swift build (bypassing project tools)
```

### #6: BUILD, KILL, LAUNCH, LOG

✅ DO: Run full sequence after every code change
❌ DON'T: Skip steps or assume it works

```bash
./scripts/SaneMaster.rb verify    # BUILD
killall -9 SaneBar                # KILL
./scripts/SaneMaster.rb launch    # LAUNCH
./scripts/SaneMaster.rb logs --follow  # LOG
```

Or just: `./scripts/SaneMaster.rb test_mode`

```
🟢 RIGHT: "Feature done → verify → kill → launch → check logs"
🟢 RIGHT: "Bug fixed → full cycle before claiming done"
🔴 WRONG: "Built successfully, shipping it" (skipped kill/launch/log)
🔴 WRONG: "Logs? I'll check if something breaks"
```

### #7: NO TEST? NO REST

✅ DO: Every bug fix gets a test that verifies the fix
❌ DON'T: Use placeholder or tautology assertions

```
🟢 RIGHT: #expect(error.code == .invalidInput)
🟢 RIGHT: #expect(items.count == 3)
🔴 WRONG: #expect(true)
🔴 WRONG: #expect(value == true || value == false)
```

### #8: BUG FOUND? WRITE IT DOWN

✅ DO: Document bugs in TodoWrite immediately, GitHub Issues for tracking
❌ DON'T: Try to remember bugs or skip documentation

```
🟢 RIGHT: TodoWrite: "BUG: Items not appearing"
🟢 RIGHT: "Bug fixed → close GitHub issue with root cause"
🔴 WRONG: "I'll remember this"
🔴 WRONG: "Fixed it, no need to document"
```

### #9: NEW FILE? GEN THAT PILE

✅ DO: Run `xcodegen generate` after creating any new file
❌ DON'T: Create files without updating project

```
🟢 RIGHT: Create file → xcodegen generate
🟢 RIGHT: "New test file → xcodegen generate immediately"
🔴 WRONG: Create file → wonder why Xcode can't find it
🔴 WRONG: "I'll run xcodegen later when I'm done"
```

### #10: FIVE HUNDRED'S FINE, EIGHT'S THE LINE

✅ DO: Keep files under 500 lines, split by responsibility
❌ DON'T: Exceed 800 lines or split arbitrarily

| Lines | Status |
|-------|--------|
| <500 | Good |
| 500-800 | OK if single responsibility |
| >800 | Must split |

```
🟢 RIGHT: "File at 600 lines, single responsibility → OK"
🟢 RIGHT: "File at 850 lines → split by protocol conformance"
🔴 WRONG: "File at 1200 lines but it works"
🔴 WRONG: "Split into 20 tiny files for no reason"
```

### #11: TOOL BROKE? FIX THE YOKE

✅ DO: If SaneMaster fails, fix the tool itself
❌ DON'T: Work around broken tools

```
🟢 RIGHT: "Nuclear clean doesn't clear cache → fix verify.rb"
🟢 RIGHT: "Logs path wrong → fix test_mode.rb"
🔴 WRONG: "Nuclear clean doesn't work → run raw xcodebuild"
🔴 WRONG: "Logs broken → just skip checking logs"
```

Working around broken tools creates invisible debt. Fix once, benefit forever.

### #12: TALK WHILE I WALK

✅ DO: Use subagents for heavy lifting, stay responsive to user
❌ DON'T: Block on long operations

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
- No bug documentation (violates Rule #8)
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

[Rule #5: USE SANEMASTER] - `./scripts/SaneMaster.rb clean --nuclear`
[Rule #9: NEW FILE = XCODEGEN] - Already ran for asset catalog

[Rule #7: TESTS FOR FIXES] - Create tests:
  - Tests/MenuBarIconTests.swift: `testCustomIconLoads()`
  - Tests/PermissionServiceTests.swift: `testOpenSettingsNotBrowser()`

[Rule #8: DOCUMENT BUGS] - Track in GitHub Issues:
  - BUG-001: Asset cache not cleared by nuclear clean
  - BUG-002: URL scheme opens default browser

[Rule #6: FULL CYCLE] - Verify fixes:
  - `./scripts/SaneMaster.rb verify`
  - `killall -9 SaneBar`
  - `./scripts/SaneMaster.rb launch`
  - Manual: Confirm custom icon visible, Settings opens System Settings

[Rule #4: GREEN BEFORE DONE] - All tests pass before claiming complete

Approve?
```

**Why approved:**
- Every step cites its justifying rule
- Tests specified for each bug fix
- Bug documentation included
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

## Research Protocol (STANDARD)

This is the standard protocol for investigating problems. Used by Rule #3, Circuit Breaker, and any time you're stuck.

### Tools to Use (ALL of them)

| Tool | Purpose | When to Use |
|------|---------|-------------|
| **Task agents** | Explore codebase, analyze patterns | "Where is X used?", "How does Y work?" |
| **apple-docs MCP** | Verify Apple APIs exist and usage | Any Apple framework API |
| **context7 MCP** | Library documentation | Third-party packages (KeyboardShortcuts, etc.) |
| **WebSearch/WebFetch** | Solutions, patterns, best practices | Error messages, architectural questions |
| **Grep/Glob/Read** | Local investigation | Find similar patterns, check implementations |
| **memory MCP** | Past bug patterns, architecture decisions | "Have we seen this before?" |
| **verify_api** | SDK symbol verification | Before using any unfamiliar API |

### Research Output → Plan

After research, present findings in this format:

```
## Research Findings

### What I Found
- [Tool used]: [What it revealed]
- [Tool used]: [What it revealed]

### Root Cause
[Clear explanation of why the problem occurs]

### Proposed Fix

[Rule #X: NAME] - specific action
[Rule #Y: NAME] - specific action
...

### Verification
- [ ] ./scripts/SaneMaster.rb verify passes
- [ ] Manual test: [specific check]
```

### When to Use This Protocol

| Trigger | Action |
|---------|--------|
| **Rule #3**: 2 failures on same problem | STOP → Research Protocol → Plan |
| **Circuit Breaker**: Blocked by 3x same error or 5 total | STOP → Research Protocol → Plan → User approves reset |
| **Unfamiliar API** | Research Protocol (lighter: just verify_api + docs) |
| **Architectural question** | Research Protocol → discuss with user |

---

## Circuit Breaker Protocol

The circuit breaker is an automated safety mechanism that **blocks Edit/Bash/Write tools** after repeated failures. This prevents runaway loops (learned from 700+ iteration failure on 2026-01-02).

### When It Triggers

| Condition | Threshold | Meaning |
|-----------|-----------|---------|
| **Same error 3x** | 3 identical | Stuck in loop, repeating same mistake |
| **Total failures** | 5 any errors | Flailing, time to step back |

Success resets the counter. Normal iterative development (fail → fix → fail → fix → succeed) works fine.

### Commands

```bash
./scripts/SaneMaster.rb breaker_status  # Check if tripped
./scripts/SaneMaster.rb breaker_errors  # See what failed
./scripts/SaneMaster.rb reset_breaker   # Unblock (after plan approved)
```

### Recovery Flow

When blocked, follow the **Research Protocol** (section above). Start with `breaker_errors` to see what failed.

```
🔴 CIRCUIT BREAKER TRIPS
         │
         ▼
┌─────────────────────────────────────────────┐
│  1. READ ERRORS                             │
│     ./scripts/SaneMaster.rb breaker_errors  │
├─────────────────────────────────────────────┤
│  2. RESEARCH (use ALL tools above)          │
│     - What API am I misusing?               │
│     - Has this bug pattern happened before? │
│     - What does the documentation say?      │
├─────────────────────────────────────────────┤
│  3. PRESENT SOP-COMPLIANT PLAN              │
│     - State which rules apply               │
│     - Show what research revealed           │
│     - Propose specific fix steps            │
├─────────────────────────────────────────────┤
│  4. USER APPROVES PLAN                      │
│     User runs: ./scripts/SaneMaster.rb      │
│                reset_breaker                │
└─────────────────────────────────────────────┘
         │
         ▼
    🟢 EXECUTE APPROVED PLAN
```

**Key insight**: Being blocked is not failure—it's the system working. The research phase often reveals the root cause that guessing would never find.

---

## Available Tools

### SaneMaster Commands

```bash
./scripts/SaneMaster.rb verify          # Build + tests
./scripts/SaneMaster.rb verify --clean  # Full clean build
./scripts/SaneMaster.rb test_mode       # Kill → Build → Launch → Logs
./scripts/SaneMaster.rb launch          # Launch app
./scripts/SaneMaster.rb logs --follow   # Stream live logs
./scripts/SaneMaster.rb clean --nuclear # Deep clean (all caches)
./scripts/SaneMaster.rb verify_api X    # Check if API exists in SDK
./scripts/SaneMaster.rb session_end     # End session with memory capture
```

### Tool Decision Matrix

| Situation | Tool to Use | Why |
|-----------|-------------|-----|
| **Need API signature/existence** | `./scripts/SaneMaster.rb verify_api` | SDK is source of truth (Rule #2) |
| **Need API usage examples** | `apple-docs` MCP | Rich examples, WWDC context |
| **Need library docs (KeyboardShortcuts, etc.)** | `context7` MCP | Real-time docs from source |
| **Build/test the project** | `./scripts/SaneMaster.rb verify` | Always use SaneMaster (Rule #5) |
| **Generate mock classes** | `./scripts/SaneMaster.rb gen_mock` (Mockolo) | Fast protocol→mock generation |
| **GitHub issues/PRs** | `github` MCP | Create issues, review PRs |
| **Remember context across sessions** | `memory` MCP | Persistent knowledge graph |

### SaneLoop: SOP Enforcement Loop

**Purpose**: Forces Claude to complete ALL SOP requirements before claiming a task is done.

**How it works**:
1. Run `/sane-loop` with a prompt containing SOP requirements
2. Claude works on the task
3. When Claude tries to exit, a Stop hook intercepts and feeds the prompt back
4. Claude sees previous work and iterates until completion criteria are met
5. Loop exits when `<promise>COMPLETE</promise>` appears or max iterations hit

**MANDATORY Rules** (learned from 700+ iteration failure on 2026-01-02):

| Rule | Requirement | Why |
|------|-------------|-----|
| **Always set `--max-iterations`** | Use 10-20, NEVER 0 or omit | Prevents infinite loops |
| **Always set `--completion-promise`** | Clear, verifiable text | Loop needs exit condition |
| **Promise must be TRUE** | Only output when genuinely complete | Don't lie to escape loop |

✅ DO:
```bash
/sane-loop "Fix bug X" --completion-promise "BUG-FIXED" --max-iterations 15
/sane-loop "Add feature Y" --completion-promise "FEATURE-COMPLETE" --max-iterations 20
```

❌ DON'T:
```bash
/sane-loop "Fix bug X"  # NO! Missing both required flags
/sane-loop "Fix bug X" --max-iterations 0  # NO! Unlimited = infinite loop
```

**Usage for bug fixes**:

```bash
/sane-loop "Fix: [describe bug]

SOP Requirements (verify before completing):
1. ./scripts/SaneMaster.rb verify passes
2. killall -9 SaneBar && ./scripts/SaneMaster.rb launch
3. ./scripts/SaneMaster.rb logs --follow (check for errors)
4. Regression test added in Tests/
5. GitHub issue updated/closed
6. Self-rating 1-10 provided

Output <promise>SOP-COMPLETE</promise> ONLY when ALL verified." --completion-promise "SOP-COMPLETE" --max-iterations 10
```

**Usage for features**:

```bash
/sane-loop "Implement: [describe feature]

Requirements: [list requirements]

SOP: verify passes, logs checked, self-rating provided.

<promise>FEATURE-DONE</promise>" --completion-promise "FEATURE-DONE" --max-iterations 15
```

**Commands**:
- `/sane-loop "<prompt>" --completion-promise "<text>" --max-iterations N` - Start loop
- `/cancel-sane` - Cancel active loop

**When to use**:
- Complex bug fixes requiring multiple verification steps
- Feature implementations with many requirements
- Any task where Claude tends to skip SOP steps

---

## Project Structure

```
SaneBar/
├── Core/           # Managers, Services, Models
├── UI/             # SwiftUI views
├── Tests/          # Unit tests
├── scripts/        # SaneMaster automation
└── SaneBarApp.swift
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Ghost beeps / no launch | `xcodegen generate` |
| Phantom build errors | `./scripts/SaneMaster.rb clean --nuclear` |
