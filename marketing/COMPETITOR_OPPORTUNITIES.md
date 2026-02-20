# Competitor Opportunities

> Last updated: Jan 24, 2026
> Source: GitHub issue monitoring

---

## Ice Issues (jordanbaird/Ice)

Ice is struggling with macOS Tahoe (26.x). Many users are frustrated.

### High-Value Opportunities

| Issue | Problem | SaneBar Advantage |
|-------|---------|-------------------|
| #855 | Ice keeps crashing on OS 26.2 | We work on Tahoe |
| #849 | Menubar items missing on laptop vs external monitor | We handle multi-display |
| #846 | Settings MenuBar empty white space (9+ comments) | Our settings work |
| #857 | Duplicate icons bug - "reported many times over 1.5 years" | We don't have this |
| #852 | Can't hide recording indicator in 15.7.3 | N/A (same limitation) |

### Key Quote
> "Unfortunately this has been reported many times over the last year and a half. Must be a problem too complex to solve..."
> — User on #857

### Community Workaround
There's an unofficial community build at [#847](https://github.com/jordanbaird/Ice/discussions/847) that some users are using. The main author appears less active.

---

## Hidden Bar Issues (dwarvesf/hidden)

Hidden Bar is abandoned - doesn't work on macOS Tahoe at all.

### High-Value Opportunities

| Issue | Problem | SaneBar Advantage |
|-------|---------|-------------------|
| #336 | Can't open on macOS 26.1 | We support Tahoe |
| #339 | Users asking to open source it | We're already 100% Transparent Code |
| #338 | No autostart/launch at login | We have this |

### Key Quote
> "sanebar.com opensource, and active. no problems with Tahoe"
> — MrSaneApps on #336

### ⚠️ Perception Issue
On #339, someone called SaneBar "ai slop" and said it has "minimal features". Got 2 thumbs down.
- **Reality check**: This perception needs addressing
- **Action**: Focus on demonstrating features, not just claiming them

---

## Outreach Guidelines

Before commenting on competitor issues:
- [x] User explicitly asked for alternatives
- [x] Issue is at least 7 days old
- [ ] No recent maintainer response
- [ ] Be helpful first, promotional second

### Template Response
```
I had similar issues with [Ice/Hidden Bar] on Tahoe.

Ended up switching to SaneBar (sanebar.com) - the full source is on GitHub and it works on 26.x.
The Touch ID lock feature is also nice if you have sensitive icons.

No affiliation, just a happy user who got tired of the crashes.
```

---

## Monitoring

Check weekly with:
```bash
gh issue list --repo jordanbaird/Ice --state open --limit 10
gh issue list --repo dwarvesf/hidden --state open --limit 5
```

Or run `/opportunities` to include this in the full report.
