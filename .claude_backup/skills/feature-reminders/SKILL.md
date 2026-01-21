---
name: feature-reminders
description: Remind about underutilized Claude Code features at appropriate times. Use when errors occur, context is high, or searches are large. Keywords: rewind, context, compact, explore, tip, reminder, help
allowed-tools: Read
---

# Feature Reminders

## Purpose

This skill reminds Claude about powerful features at the right moments, so you don't have to remember them.

## When to Suggest /rewind

**Triggers:**
- After a tool error or failure
- When the same approach failed 2+ times
- When code changes need to be undone

**Reminder:**
> 💡 `/rewind` can rollback both code AND conversation to a previous checkpoint. Press `Esc+Esc` as a shortcut.

## When to Suggest /compact

**Triggers:**
- Memory entity count > 60
- Estimated tokens > 8,000
- Session feels sluggish
- Context window visualization shows high usage

**Reminder:**
> 💡 `/compact [instructions]` can optimize memory. Give it focus instructions like "keep bug fixes, archive explorations".

## When to Suggest /context

**Triggers:**
- After 3+ edits without checking context
- When token usage is unclear
- When unsure what Claude "remembers"

**Reminder:**
> 💡 `/context` shows a visual grid of how the context window is being used. Helps identify what's consuming tokens.

## When to Suggest Explore Subagent

**Triggers:**
- Recursive glob patterns (`**`)
- Complex regex searches
- "Find all" or "search everywhere" requests
- Architecture questions

**Reminder:**
> 💡 Use `Task` with `subagent_type: Explore` for large codebase searches. It's Haiku-powered and saves your context.

## Keyboard Shortcuts to Remember

| Shortcut | Action |
|----------|--------|
| `Esc+Esc` | Rewind to checkpoint |
| `Shift+Tab` | Cycle permission modes |
| `Option+T` | Toggle extended thinking |
| `Ctrl+O` | Toggle verbose mode |
| `Ctrl+B` | Background running task |

## Self-Check Questions

Before making changes, Claude should ask itself:
1. Did I check `/context` recently?
2. Is memory above 60 entities?
3. Should I use Explore subagent instead of direct search?
4. If this fails, can I `/rewind`?
