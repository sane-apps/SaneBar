---
name: memory-compactor
description: Guide smart memory compaction with focus instructions. Use when memory is full, tokens are high, context needs optimization, or you need to archive learnings. Keywords: compact, memory full, tokens high, archive, optimize context
allowed-tools: Bash(./scripts/SaneMaster.rb:*), Read
---

# Memory Compactor

## When This Skill Activates

Claude uses this when:
- Memory entity count exceeds 60
- Token budget approaches 8,000+
- You ask about compacting or optimizing memory
- Context feels cluttered or stale

## Before Running /compact

### 1. Check Current State
```bash
./scripts/SaneMaster.rb mh        # Current entity/token count
./scripts/SaneMaster.rb mcompact  # Entities needing compaction
```

### 2. Choose Focus Instructions

| Focus | Keeps | Archives |
|-------|-------|----------|
| `"API patterns"` | API learnings, integrations | General tips |
| `"bug fixes"` | Workarounds, fixes | Feature explorations |
| `"SOP compliance"` | Rule violations, learnings | Routine operations |
| `"accessibility APIs"` | AXUIElement patterns | Generic Swift tips |

### 3. Run with Instructions
```
/compact keep SaneBar accessibility patterns and bug workarounds, archive general Swift tips
```

## Smart Compact Examples

**For SaneBar development:**
```
/compact keep accessibility API patterns, NSStatusItem positioning fixes, and SOP violations. Archive competitive research and general macOS tips.
```

**For debugging session:**
```
/compact keep all error patterns and workarounds discovered. Archive exploration attempts that didn't work.
```

**For feature work:**
```
/compact keep the feature requirements and implementation decisions. Archive research that led to dead ends.
```

## Post-Compact Verification

```bash
./scripts/SaneMaster.rb mh  # Should be < 60 entities now
```

## Thresholds

| Metric | Warning | Critical |
|--------|---------|----------|
| Entities | 60 | 80 |
| Tokens | 8,000 | 12,000 |

## Key Insight

The `/compact` command accepts **natural language instructions** about what to keep vs. discard. Be specific about SaneBar-relevant context to preserve.
