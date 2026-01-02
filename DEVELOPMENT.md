# SaneBar Development Guide (SOP)

**Version 1.0** | Last updated: 2026-01-01

> **SINGLE SOURCE OF TRUTH** for all Developers and AI Agents.
>
> **SOP = Standard Operating Procedure = This File (DEVELOPMENT.md)**
>
> When you see "SOP", "use our SOP", or "follow the SOP", this is the document.
>
> **Read this entirely before touching code.**

---

## 🚀 Quick Start for AI Agents

**New to this project? Start here:**

1. **Bootstrap runs automatically** - `./Scripts/SaneMaster.rb bootstrap`
2. **Read Rule #0 first** (Section 1)
3. **Know the Self-Rating requirement**
4. **Use SaneMaster.rb**: All tools are in `./Scripts/SaneMaster.rb`

**Key Commands:**

```bash
./Scripts/SaneMaster.rb bootstrap  # Environment check + auto-update
./Scripts/SaneMaster.rb verify     # Build + unit tests
```

---

## 0. Critical System Context: macOS 26.2 (Tahoe)

- **OS**: macOS 26.2 (Tahoe). APIs differ from older versions.
- **Hardware**: Apple Silicon (M1+) ONLY.
- **Ruby**: Homebrew Ruby 3.4+ required.

---

## 1. The Golden Rules

### Rule #0: MAP RULES BEFORE CODING

✅ DO: State which rules apply before writing code
❌ DON'T: Start coding without thinking about rules

🟢 GOOD: "This uses Accessibility API → verify_api first (Rule #2)"
🟢 GOOD: "New file needed → run xcodegen after (Rule #9)"
🔴 BAD: "Let me just start coding..."
🔴 BAD: "I'll figure out the rules as I go"

---

### Rule #1: FILES STAY IN PROJECT

✅ DO: Save all files inside `/Users/sj/SaneBar/`
❌ DON'T: Create files outside project without asking

🟢 GOOD: `/Users/sj/SaneBar/Core/NewService.swift`
🟢 GOOD: `/Users/sj/SaneBar/Scripts/new_helper.rb`
🔴 BAD: `~/.claude/plans/my-plan.md`
🔴 BAD: `/tmp/scratch.swift`

If file must go elsewhere → ask user where.

---

### Rule #2: SDK IS SOURCE OF TRUTH

✅ DO: Run verify_api before using any Apple API
❌ DON'T: Assume an API exists from memory or web search

🟢 GOOD: `./Scripts/SaneMaster.rb verify_api AXUIElementCreateSystemWide Accessibility`
🟢 GOOD: `./Scripts/SaneMaster.rb verify_api kAXExtrasMenuBarAttribute Accessibility`
🔴 BAD: "I remember AXUIElement has a .menuBarItems property"
🔴 BAD: "Stack Overflow says use .statusItems"

---

### Rule #3: INVESTIGATE-AFTER-TWO

✅ DO: After 2 failures → stop, run verify_api, check docs
❌ DON'T: Guess a third time without researching

🟢 GOOD: "Failed twice. Running verify_api to check if this API exists."
🟢 GOOD: "Two attempts failed. Checking apple-docs MCP for correct usage."
🔴 BAD: "Let me try a slightly different approach..." (attempt #3)
🔴 BAD: "Maybe if I change this one thing..." (attempt #4)

---

### Rule #4: VERIFY BEFORE SHIP

✅ DO: Fix all verify failures before claiming done
❌ DON'T: Ship with failing tests

🟢 GOOD: "verify failed → fixing the error → running verify again"
🟢 GOOD: "Tests pass. Ready to ship."
🔴 BAD: "verify failed but it's probably fine"
🔴 BAD: "I'll fix that test later"

---

### Rule #5: USE SANEMASTER.RB

✅ DO: Use `./Scripts/SaneMaster.rb` for all build/test operations
❌ DON'T: Use raw xcodebuild or xcode commands

🟢 GOOD: `./Scripts/SaneMaster.rb verify`
🟢 GOOD: `./Scripts/SaneMaster.rb verify_api MyAPI`
🔴 BAD: `xcodebuild -scheme SaneBar build`
🔴 BAD: `xcrun xcodebuild test`

---

### Rule #6: BUILD → KILL → LAUNCH → LOGS

✅ DO: Run full sequence after every code change
❌ DON'T: Skip steps or assume it works

🟢 GOOD:
```bash
./Scripts/SaneMaster.rb verify
killall -9 SaneBar
./Scripts/SaneMaster.rb launch
./Scripts/SaneMaster.rb logs --follow
```
🟢 GOOD: `./Scripts/SaneMaster.rb test_mode` (runs all steps)
🔴 BAD: `./Scripts/SaneMaster.rb verify` then "done!"
🔴 BAD: Launch without killing old instance first

---

### Rule #7: REGRESSION TESTS REQUIRED

✅ DO: Every bug fix gets a test that verifies the fix
❌ DON'T: Use placeholder or tautology assertions

🟢 GOOD: `#expect(error.code == .invalidInput)`
🟢 GOOD: `#expect(result.count == 3)`
🔴 BAD: `#expect(true)`
🔴 BAD: `#expect(value == true || value == false)`

---

### Rule #8: BUG TRACKING

✅ DO: Document bugs in TodoWrite immediately, BUG_TRACKING.md after
❌ DON'T: Try to remember bugs or skip documentation

🟢 GOOD: TodoWrite: "BUG: Menu bar - items not appearing"
🟢 GOOD: Update BUG_TRACKING.md with root cause after fix
🔴 BAD: "I'll remember to fix that later"
🔴 BAD: Fix bug without documenting what caused it

---

### Rule #9: FILE CREATION = XCODEGEN

✅ DO: Run `xcodegen generate` after creating any new file
❌ DON'T: Create files without updating project

🟢 GOOD: Create `NewService.swift` → run `xcodegen generate`
🟢 GOOD: Create `NewView.swift` in UI/ → run `xcodegen generate`
🔴 BAD: Create file and wonder why Xcode can't find it
🔴 BAD: Manually edit project.pbxproj

---

### Rule #10: FILE SIZE LIMITS (500 soft / 800 hard)

✅ DO: Keep files under 500 lines, split by responsibility
❌ DON'T: Exceed 800 lines or split arbitrarily

🟢 GOOD: Split `MenuBarManager.swift` → `MenuBarManager.swift` + `MenuBarManager+Scanning.swift`
🟢 GOOD: 650-line file with clear single responsibility = OK
🔴 BAD: 900-line file "because it's all related"
🔴 BAD: Split at line 400 mid-function to hit a number

---

### SELF-RATING (MANDATORY)

✅ DO: Rate 1-10 after every task with specific ✅/❌ items
❌ DON'T: Skip rating or give vague justification

🟢 GOOD:
```
**Self-rating: 7/10**
✅ Used SaneMaster, ran verify, added regression test
❌ Forgot to check logs after launch
```
🟢 GOOD:
```
**Self-rating: 9/10**
✅ Verified API before using, full test cycle, logs clean
❌ Minor: could have used TodoWrite for tracking
```
🔴 BAD: "Self-rating: 10/10" (no explanation)
🔴 BAD: "Self-rating: 8/10 - did good" (vague)

| 9-10 | All rules followed | 5-6 | Notable gaps |
| 7-8 | Minor miss | 1-4 | Multiple violations |


---

## 2. Directory Structure

```text
SaneBar/
├── Core/                  # Foundation types, Managers
├── UI/                    # SwiftUI views
├── SaneBarApp.swift       # Entry point
└── Scripts/               # SaneMaster automation
```

---

## 3. Style Guide & Best Practices

- **Line Length**: 120 chars max.
- **Indent**: 4 spaces.
- **Linting**: Enforced by `swiftlint`.

---

## 4. Troubleshooting

- **Ghost Beeps / No Launch**: Run `xcodegen generate`.
- **Phantom Errors**: Run `./Scripts/SaneMaster.rb clean --nuclear`.
