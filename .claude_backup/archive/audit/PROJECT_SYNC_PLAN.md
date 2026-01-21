# SaneBar ↔ SaneVideo Sync Plan

**Generated**: 2026-01-02
**Purpose**: Bidirectional sync of all improvements between projects

---

## Executive Summary

### SaneBar Upgrades to Apply to SaneVideo

| Component | Status | Files |
|-----------|--------|-------|
| **Memory Management** | PARTIAL | `memory.rb` missing auto_memory_check, auto_maintain, archive |
| **Circuit Breaker Commands** | MISSING | SaneMaster.rb needs breaker commands |
| **Compliance Report** | PARTIAL | Module copied, command not added |
| **MCP Memory Cleanup** | MISSING | mcleanup command not added |
| **Ralph Validator** | MISSING | ralph_validator.sh not copied |
| **SOP: Circuit Breaker Protocol** | MISSING | Section not in DEVELOPMENT.md |
| **SOP: Research Protocol** | MISSING | Section not in DEVELOPMENT.md |
| **SOP: Ralph Wiggum Section** | MISSING | Section not in DEVELOPMENT.md |

### Research Insights to Apply to Both

| Insight | Source | Action |
|---------|--------|--------|
| **Rolling window + summaries** | LLM best practices | Add to session handoff |
| **Memory as versioned API** | Handoff patterns | Add schemaVersion to memory |
| **Proactive recall** | Memory patterns | Add to bootstrap |
| **Archival memory** | MemGPT pattern | Already added (memory_archive.jsonl) |

---

## Phase 1: File Sync (SaneBar → SaneVideo)

### 1.1 Core Files to Copy

```bash
# Already copied (need update):
# - memory.rb (missing latest auto-maintenance functions)
# - session.rb

# Still need to copy:
cp /Users/sj/SaneBar/Scripts/sanemaster/hooks/ralph_validator.sh \
   /Users/sj/SaneVideo/Scripts/sanemaster/hooks/
```

### 1.2 SaneMaster.rb Updates for SaneVideo

Add to COMMANDS hash (memory section):
- `mcleanup` - Analyze MCP memory, generate cleanup commands

Add to dispatch_command:
- `memory_cleanup`, `mcleanup`
- `reset_breaker`, `rb`
- `breaker_status`, `bs`
- `breaker_errors`, `be`
- `compliance`, `cr`

Add helper methods:
- `show_breaker_status`
- `show_breaker_errors`

---

## Phase 2: SOP Documentation Sync

### 2.1 Add to SaneVideo DEVELOPMENT.md

**Circuit Breaker Protocol** (from SaneBar lines 389-442):
- When it triggers (3x same error OR 5 total)
- Commands (breaker_status, breaker_errors, reset_breaker)
- Recovery flow diagram

**Research Protocol** (from SaneBar lines 337-386):
- Tools to use table
- Research output format
- When to use triggers

**Ralph Wiggum Section** (from SaneBar lines 472-539):
- How it works
- MANDATORY rules (max-iterations, completion-promise)
- Usage examples

### 2.2 Both Projects: Add Memory Health Section

New section: **Memory Health & Maintenance**

```markdown
## Memory Health

The Memory MCP can bloat and fill context. Monitor with:

```bash
./Scripts/SaneMaster.rb mh              # Check entity/token counts
./Scripts/SaneMaster.rb mcompact --dry-run  # Preview compaction
./Scripts/SaneMaster.rb mcleanup        # Generate MCP cleanup commands
```

Thresholds:
- Entities: 60 (warn), 80 (critical)
- Tokens: 8000 (warn), 12000 (critical)
- Observations per entity: 15 (trim older)

Auto-maintenance runs at session end if thresholds exceeded.
```

---

## Phase 3: Research-Based Improvements

### 3.1 Session Handoff Schema (Both Projects)

Update `SESSION_HANDOFF.md` generation to include:

```yaml
schemaVersion: "1.0"
trace_id: "<session_uuid>"
timestamp: "2026-01-02T03:00:00Z"

# Core Context (short-term)
recent_commits: [...]
uncommitted_changes: [...]
active_todos: [...]

# Memory Health (long-term)
memory_stats:
  entities: 64
  tokens_estimated: 55000
  needs_compaction: true

# Proactive Recall Hints
relevant_entities:
  - "SaneBar-ComplianceEngine"
  - "BUG-006-ScanFeedback"
```

### 3.2 Proactive Memory Recall (Both Projects)

Add to bootstrap.rb:
```ruby
def proactive_memory_hint
  # At session start, identify most relevant memory entities
  # based on recent git activity and uncommitted changes
  # Output as "Relevant context from memory:" summary
end
```

---

## Phase 4: Verification

### 4.1 SaneBar Verification
```bash
./Scripts/SaneMaster.rb verify
./Scripts/SaneMaster.rb mh
./Scripts/SaneMaster.rb breaker_status
```

### 4.2 SaneVideo Verification
```bash
./Scripts/SaneMaster.rb verify
./Scripts/SaneMaster.rb mh
./Scripts/SaneMaster.rb breaker_status
```

---

## Phase 5: Commit

### SaneBar Commit Message
```
Add memory management + sync tooling with SaneVideo

- memory.rb: auto_memory_check, auto_maintain_memory, memory_archive_stats
- session.rb: Enhanced stats with token counts, health warnings
- SaneMaster.rb: mh, mcompact, mcleanup commands
- All hooks synced with SaneVideo
```

### SaneVideo Commit Message
```
Sync compliance engine + memory management from SaneBar

Phase 4 Compliance Engine:
- circuit_breaker.rb, edit_validator.rb, test_quality_checker.rb
- audit_logger.rb, compliance_report.rb
- Circuit breaker commands (reset_breaker, breaker_status, breaker_errors)

Memory Management:
- memory_health, memory_compact, memory_cleanup commands
- Auto-maintenance with archival
- Enhanced session summary with token stats

SOP Updates:
- Circuit Breaker Protocol section
- Research Protocol section
- Ralph Wiggum section with mandatory rules
- Memory Health section
```

---

## Files Changed Summary

### SaneBar (to commit)
- `Scripts/SaneMaster.rb` (modified)
- `Scripts/sanemaster/memory.rb` (modified)
- `Scripts/sanemaster/session.rb` (modified)

### SaneVideo (to commit)
- `Scripts/SaneMaster.rb` (modified)
- `Scripts/sanemaster/memory.rb` (modified)
- `Scripts/sanemaster/session.rb` (modified)
- `Scripts/sanemaster/circuit_breaker_state.rb` (new)
- `Scripts/sanemaster/compliance_report.rb` (new)
- `Scripts/sanemaster/hooks/audit_logger.rb` (new)
- `Scripts/sanemaster/hooks/circuit_breaker.rb` (new)
- `Scripts/sanemaster/hooks/edit_validator.rb` (new)
- `Scripts/sanemaster/hooks/test_quality_checker.rb` (new)
- `Scripts/sanemaster/hooks/skill_validator.rb` (new)
- `Scripts/sanemaster/hooks/ralph_validator.sh` (new)
- `Scripts/sanemaster/hooks/failure_tracker.rb` (modified)
- `Scripts/sanemaster/hooks/two_fix_reminder.rb` (modified)
- `.claude/settings.json` (modified)
- `DEVELOPMENT.md` (modified)
