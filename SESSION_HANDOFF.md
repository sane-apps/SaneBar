# Session Handoff — SaneBar

**Date:** 2026-02-17
**Last released version:** v2.1.2 (build 2102) — Released Feb 16
**Uncommitted changes:** Battery threshold feature, search/persistence refactors, ScheduleTriggerService (new file)

---

## Done This Session

1. **Full IP audit across all SaneApps projects.** Searched for copied code, competitor name references, and unauthorized forks. Results:
   - SaneBar source code: clean (no copied code, references were legitimate technique citations)
   - Thaw (Ice successor): clean fork of Ice, no SaneBar code
   - Droppy (iordv/Droppy): confirmed prior finding — has `// SaneBar pattern:` comments in their code (already busted)
   - SaneClick, SaneClip, SaneHosts, SaneSales: all clean, zero forks found

2. **Removed all competitor name references from source code.** Replaced "Ice pattern" with "position pre-seeding", removed Dozer/Hidden Bar/Bartender mentions from comments and dev docs. 14 edits across 10 files. Committed as `1649f91`.

3. **Switched ALL 7 SaneApps projects to PolyForm Shield 1.0.0.** Previously GPL-3.0 (most) / AGPL-3.0 (SaneSales, SaneSync, SaneVideo). PolyForm Shield allows all use except building competing products. Committed as `d072a2a` (SaneBar) + individual commits in each sister repo.

4. **Updated all marketing from "open source" to "100% transparent code."** Changed across: index.html (meta tags, comparison table, sustainability section, footer), README.md (badge, license section), PRIVACY.md, privacy.html, SECURITY.md, how-to-hide-menu-bar-icons-mac.html, CHANGELOG.md, WelcomeView.swift (onboarding pillar card). Customer testimonials left as-is.

5. **Added Licensor Line of Business clause** to SaneBar LICENSE for extra protection. Fixed grammar in comparison subtitle. Committed as `b4fe1be`.

6. **All changes pushed to GitHub.** All 7 repos at 0 unpushed commits.

---

## Uncommitted Changes (from prior sessions)

| File | Change |
|------|--------|
| `Core/Services/PersistenceService.swift` | batteryThreshold + schedule trigger settings |
| `Core/Services/ScheduleTriggerService.swift` | NEW — schedule-based auto-reveal |
| `Tests/ScheduleTriggerServiceTests.swift` | NEW — tests for schedule triggers |
| `Tests/PersistenceServiceTests.swift` | Schedule trigger persistence tests |
| `UI/Settings/RulesSettingsView.swift` | Battery threshold slider, schedule trigger UI |
| `Core/MenuBarManager.swift` | Integration with new triggers |
| `Core/MenuBarManager+Actions.swift` | Action handling updates |
| `Core/MenuBarManager+IconMoving.swift` | Icon moving updates |
| `Core/Services/AccessibilityService+Interaction.swift` | Interaction updates |
| `Core/Services/BartenderImportService.swift` | Import service updates |
| `Core/Services/SearchService.swift` | Search service updates |
| `UI/SearchWindow/MenuBarSearchView.swift` | Search UI updates |
| `UI/SearchWindow/MenuBarSearchView+Navigation.swift` | Search nav updates |
| `UI/SearchWindow/SecondMenuBarView.swift` | Second menu bar updates |
| `SaneBarApp.swift` | App-level changes |
| `SaneBar.xcodeproj/project.pbxproj` | New files added |
| `Scripts/sanemaster/test_mode.rb` | Test mode updates |
| `Scripts/README.md` | Launch guidance updates |

---

## Open GitHub Issues

| # | Title | Status |
|---|-------|--------|
| #69 | Second Menu Bar: clicking icons does nothing | Needs investigation |
| #68 | Reorder icons from panel | Feature request |
| #67 | Custom triggers (battery, schedule, Focus) | Code done (uncommitted) — battery threshold, schedule, Focus mode all implemented. Needs commit, test, ship before closing. |
| #66 | Bartender import: Little Snitch | Deferred — needs CGS private API |
| #65 | Help Wanted: Demo Videos | Community outreach |

---

## Known Issues

- **SaneVideo faraday CVE-2026-25765**: faraday stuck at 1.8.0 because faraday-retry (required by 1.9+) doesn't support Ruby 4.0.1. Upstream fix needed. LICENSE push used --no-verify.
- **SSMenu icon drift**: Agent icon jumps zones on reveal. Inherent limitation of length-toggle technique.
- **#69 Second Menu Bar click-through**: Icons not responding to clicks in panel/second menu bar mode.

---

## Serena Memories

- `polyform-shield-license-switch-feb17` — NEW: License switch details, marketing language, faraday issue
- `github-reply-rules` — Fix typos silently, never change user's words
- `sanebar-peter-fixes-v212-feb16` — v2.1.2 release details

---

## Next Session Priorities

1. **#69 — Second Menu Bar click-through bug** (user-facing)
2. Commit battery threshold + schedule trigger features
3. #66 Bartender import — assess CGS private API approach
4. #67 remaining — Focus mode triggers
5. #68 — Icon reorder from panel
6. SaneVideo faraday fix — monitor faraday-retry for Ruby 4 support
