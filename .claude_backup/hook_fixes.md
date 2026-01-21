# Hook Fixes Log

> Document all hook fixes with justification. This persists across sessions.

---

## Fix #1: process_enforcer.rb - Task Agent Upgrade Logic

**Date:** 2026-01-04
**File:** `~/.claude/hooks/process_enforcer.rb` (synced from SaneProcess)
**Lines:** 180-198

**Problem:**
The `mark_research_category()` function had `return if progress[category][:completed_at]` at line 182, which prevented Task agents from upgrading existing entries from `via_task=false` to `via_task=true`.

When I did direct tool calls (WebSearch, mcp__memory__read_graph), they marked categories as complete but with `via_task=false`. Later when I spawned Task agents to do proper research, they couldn't upgrade those entries because the early return blocked them.

**Original Code:**
```ruby
def mark_research_category(category, tool_name, prompt = nil)
  progress = load_research_progress
  progress[category] ||= { completed_at: nil, tool: nil, skipped: false, skip_reason: nil }
  return if progress[category][:completed_at]  # <-- BUG: blocks Task upgrades
  # ...
end
```

**Fixed Code:**
```ruby
def mark_research_category(category, tool_name, prompt = nil)
  progress = load_research_progress
  progress[category] ||= { completed_at: nil, tool: nil, skipped: false, skip_reason: nil }

  # BUG FIX: Allow Task agents to upgrade existing entries to via_task=true
  already_done_via_task = progress[category][:completed_at] && progress[category][:via_task]
  if already_done_via_task
    return # Already done via Task - no upgrade needed
  end

  # Either new entry OR upgrading non-Task entry to Task entry
  progress[category][:completed_at] = Time.now.iso8601
  progress[category][:tool] = tool_name
  progress[category][:prompt] = prompt&.slice(0, 200) if prompt
  progress[category][:via_task] = (tool_name == 'Task')
  save_research_progress(progress)
end
```

**Justification:**
The hook's intent is to require research via Task agents. The bug prevented compliance even when I correctly used Task agents, because earlier direct calls blocked the upgrade path. The fix allows Task agents to "upgrade" entries while still preventing non-Task tools from overwriting Task-completed entries.

**Verification:**
After fix, reset `.claude/research_progress.json` and re-run Task agents to populate with `via_task=true`.

---
