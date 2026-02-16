# Session Handoff — SaneBar

**Date:** 2026-02-15 (late night session)
**Last version:** v2.1.0 (build 2100) — RELEASED AND DEPLOYED

---

## Done This Session

1. **Fixed Always-Hidden separator position bug** — AH was devouring all menu bar items. Root cause: UserDefaults positions are pixel offsets from right edge, not ordinals. Ordinals 2 and 50 both failed. Reverted to 10000 (macOS clamps to far left). Toggle off now clears position key for clean re-seed. Migration v4 clears positions < 200.

2. **Released v2.1.0** — Full release pipeline: build, sign, notarize, ZIP, R2 upload, appcast, Homebrew cask, GitHub release, website deploy, email webhook update.

3. **Fixed website download links** — Were pointing to v1.5.0 (!). Updated all 3 download URLs + softwareVersion to 2.1.0 in docs/index.html.

4. **Automated release pipeline** — Added two new steps to release.sh (benefits ALL apps):
   - Step 2.5: Auto-updates website download links before Cloudflare Pages deploy
   - Step 9: Auto-updates email webhook PRODUCT_CONFIG, commits, pushes, deploys to Workers

5. **Debug Pro mode** — `#if DEBUG` auto-grants Pro in dev builds (stripped from Release). XCTestCase detection prevents it from breaking tests.

6. **GitHub community** — Posted Homebrew update on issue #26, enabled Discussions on the repo.

7. **15-perspective docs audit** — Full report generated. No ship-blocking issues. Website/brand/marketing polish items identified for future.

---

## Open GitHub Issues

- **#62** — Second menu bar for showing hidden icons does not work
- **#26** — Homebrew installation (OPEN for comments, Homebrew is back and working)

---

## Known Issues (Not Yet Fixed)

- **SSMenu icon drift**: SSMenu agent icon jumps from hidden to visible zone when clicking SaneBar to reveal hidden items. Inherent limitation of length-toggle hide/show technique. User aware, separate from AH fix.
- **sane_test.rb cleanup**: Stale app copies accumulate in ~/Applications/ and build/ on Mini. User requested script upgrade to auto-clean. Not yet done.

---

## Sales

- Today: 5 orders / $34.95 (SaneBar, SaneClip, SaneHosts)
- This week: 28 orders / $185.77
- All time: 203 orders / $906.23 net

---

## Key Learnings (Saved to Serena)

- `ah-position-fix-v2.1.0` — Full root cause analysis of AH position bug
- `release-automation-v2` — What was automated in release.sh and why

---

## Next Session Priorities

1. Investigate SSMenu icon drift (may need different hide/show technique)
2. Upgrade sane_test.rb to auto-clean stale app copies on Mini
3. Address docs audit warnings (README freshness, ARCHITECTURE.md updates)
4. Consider adding FeedbackView (in-app bug reporting) — SaneClip has it, SaneBar doesn't
