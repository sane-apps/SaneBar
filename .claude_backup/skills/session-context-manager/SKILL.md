---
name: session-context-manager
description: Manage session lifecycle, memory state, and context windows. Use when starting sessions, checking memory health, optimizing tokens, or understanding session state. Keywords: session start, memory health, context, compact, token usage, circuit breaker
allowed-tools: Bash(./scripts/SaneMaster.rb:*), Read, Grep
---

# Session Context Manager

## When This Skill Activates

Claude automatically uses this when you:
- Start a new session or ask "what's the session state?"
- Ask about "memory health", "context", or "token usage"
- Need to check circuit breaker status
- Want to understand current compliance state

## Key Commands

### Memory Health
```bash
./scripts/SaneMaster.rb mh              # Show entity/token counts
./scripts/SaneMaster.rb mcompact        # List entities needing compaction
```

### Circuit Breaker
```bash
./scripts/SaneMaster.rb breaker_status  # Check OPEN/CLOSED
./scripts/SaneMaster.rb breaker_errors  # Show failure messages
./scripts/SaneMaster.rb reset_breaker   # Reset after investigation
```

### Session Management
```bash
./scripts/SaneMaster.rb compliance      # SOP compliance report
./scripts/SaneMaster.rb session_end     # End session + memory prompt
```

## Quick Decision Tree

| Situation | Action |
|-----------|--------|
| Starting work | Check memory health + circuit breaker |
| Token usage high | Run `/compact` with focus instructions |
| Something failed repeatedly | Check breaker → review errors → investigate |
| Session ending | Run compliance report → save learnings |

## Thresholds

- **Entities**: 60 (warn), 80 (critical)
- **Tokens**: 8,000 (warn), 12,000 (critical)
- **Circuit breaker**: Trips at 3 consecutive failures

## Session ID

Current session: `${CLAUDE_SESSION_ID}`

Use for session-specific logging to `.claude/audit_log.jsonl`.

## See Also

- `/compact [instructions]` - Smart memory compression
- `/context` - Visualize context window usage
- `/rewind` - Rollback code AND conversation
