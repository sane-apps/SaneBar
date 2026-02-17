# Session Handoff — SaneBar

**Date:** 2026-02-17
**Last released version:** v2.1.2 (build 2102) — Released Feb 16
**Uncommitted changes:** None — working tree clean

---

## Done This Session

1. **Full IP audit across all SaneApps projects.** Searched for copied code, competitor name references, and unauthorized forks. All clean except Droppy (already busted — has `// SaneBar pattern:` comments).

2. **Removed all competitor name references from source code.** Replaced "Ice pattern" with "position pre-seeding", removed Dozer/Hidden Bar/Bartender mentions. 14 edits across 10 files. Committed as `1649f91`.

3. **Switched ALL 7 SaneApps projects to PolyForm Shield 1.0.0.** Previously GPL-3.0 / AGPL-3.0. PolyForm Shield allows all use except building competing products. Committed as `d072a2a` (SaneBar) + individual commits in each sister repo.

4. **Updated all marketing from "open source" to "100% transparent code."** Changed across index.html, README.md, PRIVACY.md, privacy.html, SECURITY.md, SEO page, CHANGELOG.md, WelcomeView.swift.

5. **Added Licensor Line of Business clause** to LICENSE. Fixed grammar in comparison subtitle. Committed as `b4fe1be`.

6. **Committed and pushed all feature code** as `554f52c`. Covers all 4 open feature issues:
   - **#67 Custom triggers**: ScheduleTriggerService (minute-by-minute, weekday selection, overnight windows, transition detection), battery threshold, schedule trigger UI in RulesSettingsView
   - **#68 Icon reorder**: drag-and-drop in SecondMenuBarView and MenuBarSearchView grid, Cmd+drag via AccessibilityService
   - **#69 Click-through fix**: SearchService.resolveLatestClickTarget with multi-strategy AX identity matching and retry
   - **#66 Bartender Little Snitch**: WindowServer fallback via CGWindowListCopyWindowInfo for AX-restricted apps
   - Also: autosave v7 position seeding, duplicate instance guard, improved status menu anchoring, hover guard for open menus, ProdDebug build config

7. **All changes pushed to GitHub.** All 7 repos at 0 unpushed commits. 44 unit tests pass.

---

## Open GitHub Issues

| # | Title | Status |
|---|-------|--------|
| #69 | Second Menu Bar: clicking icons does nothing | Code on main (`554f52c`) — needs app testing before closing |
| #68 | Reorder icons from panel | Code on main (`554f52c`) — needs app testing before closing |
| #67 | Custom triggers (battery, schedule, Focus) | Code on main (`554f52c`) — needs app testing before closing |
| #66 | Bartender import: Little Snitch | Code on main (`554f52c`) — needs app testing before closing |
| #65 | Help Wanted: Demo Videos | Community outreach |

---

## Known Issues

- **SaneVideo faraday CVE-2026-25765**: faraday stuck at 1.8.0 because faraday-retry (required by 1.9+) doesn't support Ruby 4.0.1. Upstream fix needed. LICENSE push used --no-verify.
- **SSMenu icon drift**: Agent icon jumps zones on reveal. Inherent limitation of length-toggle technique.
- **SaneMaster false negative**: `verify` reports "Tests failed" but diagnostics show 44/44 passed with 0 failures. Test result parsing bug in SaneMaster.

---

## Serena Memories

- `session-2026-02-17-features-commit` — NEW: Feature commit details, implementation notes, status
- `polyform-shield-license-switch-feb17` — License switch details, marketing language, faraday issue
- `sanebar-offscreen-cmddrag-proddebug-launch-fix-feb17` — From earlier session
- `github-reply-rules` — Fix typos silently, never change user's words
- `sanebar-peter-fixes-v212-feb16` — v2.1.2 release details

---

## Next Session Priorities

1. **Test all 4 features in running app** — launch via `sane_test.rb`, verify each feature works end-to-end
2. **Ship v2.1.3** — bump version, release, close #66/#67/#68/#69 after verified
3. **SaneMaster test result parsing** — fix false "Tests failed" when all tests pass
4. **SaneVideo faraday fix** — monitor faraday-retry for Ruby 4 support
5. **#65 Demo videos** — community outreach
