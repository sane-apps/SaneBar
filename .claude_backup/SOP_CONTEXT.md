# SOP ENFORCEMENT ACTIVE

You are working on **SaneBar**. The following rules are MANDATORY.

---

## Communication Style

**PLAIN ENGLISH ALWAYS** - Explain jargon in simple terms. No technical gatekeeping.

❌ Wrong: "The actor isolation semantics require nonisolated(unsafe)"
❌ Wrong: "The Sendable conformance is violated across actor boundaries"

✅ Right: "Swift thinks this code might run on different threads at once. We need to tell it 'trust me, I know what I'm doing' with nonisolated(unsafe)"
✅ Right: "You can't pass a Notification directly into a background task because Swift can't guarantee it won't change. Extract the values first, then pass those."

---

## On Session Start (IMMEDIATE - Before anything else)

The bootstrap hook outputs a ready toast automatically:
```
──────────────────────────────────────────────────
✅ Ready — Ruby, tools, hooks, MCP servers checked.
🧠 Memory will load on first response.

What would you like to work on today?
──────────────────────────────────────────────────
```

**Your first action** when the user sends any message: Call `mcp__memory__read_graph` to load cross-session context. This happens automatically - no need to mention it to the user.

---

## Before ANY Code Change

- [ ] **EXPLORE FIRST** - Read files, grep patterns, understand context BEFORE editing
- [ ] If API involved: `./Scripts/SaneMaster.rb verify_api <API> [Framework]` (Rule #2)
- [ ] Two failed attempts = stop and research (Rule #3)

## After ANY Code Change (Rule #6)

```bash
./Scripts/SaneMaster.rb verify        # Build + test
killall -9 SaneBar                     # Kill old instances
./Scripts/SaneMaster.rb launch         # Start fresh
./Scripts/SaneMaster.rb logs --follow  # Watch logs
```

## For Bug Fixes (MANDATORY)

- [ ] Add regression test in `Tests/` (Rule #7)
- [ ] Document in `BUG_TRACKING.md` if persistent (Rule #8)
- [ ] Run `xcodegen generate` if new files created (Rule #9)
- [ ] Search for similar patterns: `grep -r "pattern" Core/ UI/`

## Before Claiming Done

- [ ] Self-rate 1-10 with checklist (MANDATORY)
- [ ] Format: `**Self-rating: X/10**` with what you did well / missed

---

## SaneLoop Usage

For complex tasks requiring iteration:

```bash
/sane-loop "TASK: [description]

SOP Requirements:
1. verify passes
2. kill -> launch -> logs checked
3. regression test added (if bug fix)
4. self-rating provided

<promise>SOP-COMPLETE</promise> only when ALL verified." --completion-promise "SOP-COMPLETE" --max-iterations 10
```

---

## Session Start (MANDATORY - DO IMMEDIATELY)

**Before doing ANYTHING else, execute these two steps:**

1. **Check Memory** - Call `mcp__memory__read_graph` to load cross-session context
   - Bug patterns, architecture decisions, file violations already tracked
   - Recent fixes and learnings from past sessions

2. **Health Check** - Run `./Scripts/SaneMaster.rb health`

⚠️ **If you skipped memory check, STOP and do it now.** Past context prevents repeated mistakes.

## Session End

Run the session end command:

```bash
./Scripts/SaneMaster.rb session_end
```

This will:
- Prompt for memory-worthy insights (bug patterns, concurrency gotchas, architecture decisions)
- Auto-record insights to Memory MCP
- Show session summary with memory stats
- Warn if entity count > 60 (consolidation needed)

Note: The SessionEnd hook automatically runs `health` - no need to run it manually.

---

## Quick Reference

| Command | Purpose |
|---------|---------|
| `./Scripts/SaneMaster.rb health` | Quick health check |
| `./Scripts/SaneMaster.rb verify` | Build + unit tests |
| `./Scripts/SaneMaster.rb test_mode` | Kill -> Build -> Launch -> Logs |
| `./Scripts/SaneMaster.rb logs --follow` | Stream live logs |
| `./Scripts/SaneMaster.rb verify_api X` | Check if API exists in SDK |
