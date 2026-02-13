# Session Handoff - Feb 13, 2026

## What Was Done This Session

### Bug Fixes — Second Menu Bar & Find Icon (v1.0.23+)

**1. Zone Classification — Unified Backend**
- Replaced 6 separate methods (`cachedHiddenMenuBarApps`, `cachedVisibleMenuBarApps`, `cachedAlwaysHiddenMenuBarApps` + refresh variants) with single-pass `cachedClassifiedApps()`/`refreshClassifiedApps()`
- Both Find Icon AND Second Menu Bar now use the same backend — no more inconsistent fallbacks
- Fixed: fake `screenMinX = 0` AH boundary that misclassified items when AH separator position unavailable
- Added pinned-ID post-pass: when AH separator exists but position unknown, uses `alwaysHiddenPinnedItemIds` instead of faking a boundary
- Merged `classifyItems()` and `classifyItemsWithoutSeparator()` into one unified method

**2. Tooltip Hover Delay — Fixed**
- Root cause: `panel.level = .statusBar` is ABOVE macOS tooltip window level
- Fix: Changed to `panel.level = .floating` + `panel.acceptsMouseMovedEvents = true`

**3. Icon Sizing in Squircle Tiles — Fixed**
- Menu bar NSImages have ~28% transparent padding; `.fit` made icons tiny
- Fix: Overscale `iconSize = tileSize * 1.15` + `.clipShape(RoundedRectangle)` clips overflow
- System template icons (WiFi, Bluetooth) use smaller `tileSize * 0.65` to avoid deformation

**4. Test Quality — Rewrote & Enhanced Detection**
- Rewrote `Tests/SecondMenuBarTests.swift`: 10 real `classifyZone()` tests + 3 pin identity tests
- Made `classifyZone()` and `VisibilityZone` internal for testability
- Enhanced `sanetrack.rb` RULE #7: now detects mock-passthrough tests (handler setup + mock-only assertions)
- Self-tests: 25/25 pass

### Files Modified
- `Core/Services/SearchService.swift` — Unified classification engine, pinned-ID post-pass
- `UI/SearchWindow/MenuBarSearchView.swift` — Both frontends use single-pass classification
- `UI/SearchWindow/SearchWindowController.swift` — Panel level `.floating`, `acceptsMouseMovedEvents`
- `UI/SearchWindow/SecondMenuBarView.swift` — Icon overscale + clip, template icon conditional sizing
- `Tests/SecondMenuBarTests.swift` — Complete rewrite with real behavior tests
- `~/SaneApps/infra/SaneProcess/scripts/hooks/sanetrack.rb` — Mock-passthrough detection
- `~/SaneApps/infra/SaneProcess/scripts/hooks/sanetrack_test.rb` — 2 new self-tests

### Dead Code to Clean Up
Old individual methods in SearchService.swift are no longer called from UI:
- `cachedHiddenMenuBarApps()`, `cachedVisibleMenuBarApps()`, `cachedAlwaysHiddenMenuBarApps()`
- Their `refresh*` counterparts
- Corresponding protocol declarations and mock implementations

---

## Serena Memories Saved
- `zone-classification-architecture` — Unified backend design, fallback logic, post-pass pattern
- `second-menu-bar-rendering` — Icon sizing, panel level, template icon handling
- `test-quality-rules` — Mock-passthrough trap, what good tests look like, sanetrack enhancement

---

## Open GitHub Issues

| # | Title | Opened |
|---|-------|--------|
| 62 | Second menu bar for showing hidden icons does not work | Feb 13 |
| 61 | Open hidden icons in a second menu bar does not work | Feb 13 |
| 60 | Always Show on External Monitor Does Not work | Feb 12 |
| 59 | The issue is far from closed ! | Feb 12 |

Issues #61 and #62 may be addressed by this session's classification fixes. Need user to verify and respond.

---

## Release Pipeline — ZIP Format

- **v1.0.23**: Current production (DMG format, live)
- **Next release**: Will be .zip format (pipeline tested with `--skip-notarize`, full notarized run pending)
- Appcast, R2, website all ready for .zip transition

---

## NEXT SESSION — Priorities

1. **Respond to GitHub issues #61/#62** — Classification fixes may resolve these; test and reply
2. **Issue #60** — External monitor "always show" not working; needs investigation
3. **Issue #59** — Follow-up from earlier issue; review customer complaint
4. **URGENT: Website update** — Show both viewing modes on sanebar.com (carryover)
5. **Dead code cleanup** — Remove old individual classification methods from SearchService
6. **Full notarized release run** — Verify ZIP pipeline end-to-end
7. **MenuBarSearchView.swift extraction** — 1046 lines, over lint limit

---

## CRITICAL RULES (Learned the Hard Way)

1. **MacBook Air = production only.** Never launch dev builds, never nuke defaults.
2. **Always show drafts** before posting GitHub comments or sending emails.
3. **Email via Worker only** — `email-api.saneapps.com/api/send-reply`, never Resend directly.
4. **Launch via sane_test.rb** — never `open SaneApp.app` or direct binary. Breaks TCC.
5. **ALWAYS bump version** before Sparkle release — same version = invisible update.
6. **NEVER manual R2 upload** — use `release.sh --deploy`. Hook enforces this.
7. **One unified backend** — Never create separate data paths for different frontends.
8. **Don't fake separator positions** — Use pinned IDs when real position unavailable.
9. **Tests must call real code** — Mock-passthrough tests are useless. sanetrack.rb now enforces this.
10. **NSPanel level `.floating`** — `.statusBar` blocks tooltips. Always use `.floating` for panels.

---

## Mac Mini Test Environment

- **SSH:** `ssh mini`
- **Deploy:** `ruby ~/SaneApps/infra/SaneProcess/scripts/sane_test.rb SaneBar`
- **Bundle ID:** `com.sanebar.dev` for dev, `com.sanebar.app` for prod
- **ALWAYS use sane_test.rb** — handles kill, clean, TCC reset, build, deploy, launch, logs
