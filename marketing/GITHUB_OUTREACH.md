# GitHub Outreach Strategy

> **Philosophy**: Be helpful, not spammy. Only comment where users explicitly seek alternatives or where SaneBar solves a documented pain point.

---

## Competitive Landscape

| App | Repo | Status | Issues | Last Commit | Opportunity |
|-----|------|--------|--------|-------------|-------------|
| **Ice** | jordanbaird/Ice | Active but struggling | 320+ open | Sep 2025 | macOS 26 bugs, feature gaps |
| **Hidden Bar** | dwarvesf/hidden | Abandoned | 39 open | Nov 2025 (PR only) | Explicitly abandoned, macOS 26 broken |
| **Dozer** | Mortennn/Dozer | Abandoned | ? | Nov 2023 | 2+ years no updates |

---

## Guide Citation Strategy (High Trust)

**Core Principle:** Don't just link the homepage. Link the *specific guide* that solves their problem. This builds authority and reduces "spam" perception.

| User Pain Point | Link Target | Context to Use |
|-----------------|-------------|----------------|
| **Privacy / Security** | `https://sanebar.com/docs/how-to-lock-menu-bar-icons-touch-id.html` | "How do I lock icons?" "Is this secure?" "Can I hide VPN status?" |
| **Notch / Spacing** | `https://sanebar.com/docs/how-to-reorder-menu-bar-icons-mac.html` | "Icons disappearing behind notch", "Menu bar too full" |
| **Clutter / Hiding** | `https://sanebar.com/docs/how-to-hide-menu-bar-icons-mac.html` | "Too many icons", "How to hide items" |
| **General / "Alternative"** | `https://sanebar.com` | Generic "What's a good alternative?" |

---

## High-Value Opportunities (EASY WINS)

### Tier 1: Explicit "What Alternative?" Asks

These are the safest - users literally asking for help.

| Repo | Issue | Title | Reactions | Why It's Safe |
|------|-------|-------|-----------|---------------|
| Ice | [#823](https://github.com/jordanbaird/Ice/issues/823) | "Are we ever going to get a stable version for Tahoe?" | **68 reactions** | Users asking if app is abandoned |
| Hidden | [#289](https://github.com/dwarvesf/hidden/issues/289) | "Add disclaimer and link to maintained fork" | 4 | Project acknowledged as abandoned |
| Hidden | [#336](https://github.com/dwarvesf/hidden/issues/336) | "Unable to open on macOS 26.1" | 2 | Broken, users need alternative NOW |

### Tier 2: Features SaneBar Already Has

Comment only if users express frustration, not just feature requests.

| Repo | Issue | Feature | SaneBar Status |
|------|-------|---------|----------------|
| Ice | [#91](https://github.com/jordanbaird/Ice/issues/91) | Spacers between icons | ✅ SaneBar has spacers |
| Ice | [#326](https://github.com/jordanbaird/Ice/issues/326) | Export/sync settings | ✅ SaneBar stores in ~/Library |

### Tier 3: macOS 26 (Tahoe) Compatibility Issues

SaneBar works on Tahoe. Only comment if issue has been open 30+ days with no maintainer fix.

| Repo | Issue | Problem | Status |
|------|-------|---------|--------|
| Ice | [#699](https://github.com/jordanbaird/Ice/issues/699) | Check for updates stuck | Open since Sep 2025 |
| Ice | [#832](https://github.com/jordanbaird/Ice/issues/832) | Menu Bar Layout broken | Open since Dec 2025 |
| Ice | [#710](https://github.com/jordanbaird/Ice/issues/710) | "Unable to display menu bar item" | Open since Sep 2025 |
| Hidden | [#306](https://github.com/dwarvesf/hidden/issues/306) | Doesn't support macOS 15 | Open since Sep 2024 |

### Tier 4: Critical Bugs (Memory Leaks, Crashes)

| Repo | Issue | Problem | Impact |
|------|-------|---------|--------|
| Ice | [#819](https://github.com/jordanbaird/Ice/issues/819) | WindowServer memory leak | Requires reboot |
| Hidden | [#326](https://github.com/dwarvesf/hidden/issues/326) | Uses 2.89GB memory | Severe performance |

---

## Comment Templates

### Template A: Abandoned Project Response
```markdown
Hey! I ran into the same frustration. I ended up trying [SaneBar](https://sanebar.com)
which works well on macOS 26 (Tahoe). The full source is on GitHub if you want to check the code.
Hope you find something that works!
```

### Template B: Feature Exists Response
```markdown
Just wanted to mention - if you're still looking for this, [SaneBar](https://sanebar.com)
has [feature] built in. I switched after running into similar issues. It's $6.99 or free
to build from source.
```

### Template B2: The "Citation" Response (Higher Trust)
*Use this when the user describes a specific problem like the Notch or Privacy.*

```markdown
This is actually a common issue with [specific problem].
We wrote a guide on how to fix this (manual vs software method) here:
[How to Fix Menu Bar Spacing on Mac](https://sanebar.com/docs/how-to-reorder-menu-bar-icons-mac.html)

TL;DR: You can tweak `NSStatusItemSpacing` defaults in Terminal, or SaneBar handles it natively.
```

### Template C: macOS Compatibility Response
```markdown
For anyone else hitting this on macOS 26 - I switched to [SaneBar](https://sanebar.com)
and it's been stable for me. Different approach under the hood. Might be worth a look
while waiting for a fix here.
```

---

## Rules of Engagement

### DO Comment When:
- [ ] User explicitly asks "any alternatives?"
- [ ] Issue open 30+ days with no maintainer response
- [ ] User says "giving up" or "switching to something else"
- [ ] Multiple users asking same question in thread
- [ ] Project explicitly marked as abandoned

### DON'T Comment When:
- [ ] Maintainer is actively working on fix
- [ ] It's a fresh issue (< 7 days old)
- [ ] It's a feature request (not a broken experience)
- [ ] You'd be the first/only comment
- [ ] The fix is already merged/released

### Never:
- Comment on multiple issues in same repo same day (looks like spam campaign)
- Use marketing language ("best", "superior", "amazing")
- Criticize the other project
- Comment on closed issues

---

## GitHub Notification Watches

Set up notifications for these search queries:

### Ice
```
repo:jordanbaird/Ice "alternative" OR "replacement" OR "switched to" OR "any other app"
```

### Hidden Bar
```
repo:dwarvesf/hidden "alternative" OR "not working" OR "broken" OR "macOS 26"
```

### General Menu Bar
```
"menu bar" "macos" "hide" "alternative" -repo:sanebar
```

---

## Tracking

| Date | Repo | Issue | Action | Response |
|------|------|-------|--------|----------|
| | | | | |

---

## Weekly Review Checklist

- [ ] Check Ice issues for new Tahoe bugs
- [ ] Check Hidden Bar for abandon complaints
- [ ] Search "menu bar manager macos" on Reddit/HN
- [ ] Update this doc with any new opportunities
- [ ] Remove any issues that got fixed

---

*Last updated: 2026-01-21*
