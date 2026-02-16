# Session Handoff — SaneBar

**Date:** 2026-02-16
**Last version:** v2.1.0 (build 2100) — Released Feb 15

---

## Done This Session

1. **Fixed rounded corners truncation (#64)** — `MenuBarOverlayView` had a horizontal inset that shrank the tint overlay away from screen edges. Removed it. `UnevenRoundedRectangle` handles bottom-corner rounding at full width. Responded to DrOatmeal on the issue.

2. **Closed stale GitHub issues** — #62 closed (fix shipped in v2.1.0, pointed Daniel to Second Menu Bar + Icon Panel). #63, #61, #55, #42 already closed.

3. **Verified all critical links** — Website, checkout, appcast, dist ZIP, license API all live. DMG not on R2 (not needed). Attached ZIP to GitHub release v2.1.0.

4. **Hook: Block unreviewed GitHub posts** — `sane_release_guard.rb` Block 14 blocks `gh issue/pr comment/close/review/create`. Forces draft approval before posting as MrSaneApps. THIS WAS MISSING AND CAUSED AN UNAUTHORIZED PUBLIC POST.

5. **Hook: Allow dist domain diagnostics** — Block 11 updated to allow read-only curl/wget to dist domains while still blocking uploads.

6. **Xcode auto-launch on session start** — `session_start.rb` detects `.xcodeproj` and launches Xcode if not running. Fixes Xcode MCP failures.

---

## Open GitHub Issues

- **#64** — Rounded corners truncation (fix committed, not yet released — will ship in next version)

---

## Known Issues (Not Yet Fixed)

- **SSMenu icon drift**: SSMenu agent icon jumps zones on reveal. Inherent limitation of length-toggle technique. User aware.
- **sane_test.rb cleanup**: Stale app copies accumulate on Mini. Script upgrade requested, not done.
- **Experimental Settings tab empty**: Promises features but contains only bug report button. Should populate or remove.

---

## Sales

- Today: 1 order / $6.99
- Yesterday: 5 orders / $34.95
- This Week: 26 orders / $177.76
- All Time: 204 orders / $1,067.76

---

## Key Learnings (Saved to Serena)

- `session-2026-02-16-status-fixes` — Rounded corners root cause, hook additions, link verification results

---

## Next Session Priorities

1. SSMenu icon drift investigation
2. Upgrade sane_test.rb to auto-clean stale copies on Mini
3. Experimental tab — populate or remove
4. Docs audit warnings (README freshness, ARCHITECTURE.md)
