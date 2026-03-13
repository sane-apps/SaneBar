# Session Handoff — SaneBar

**Date:** 2026-03-12
**Last released version:** `v2.1.26` (build `2126`)

---

## Session 60 (2026-03-12 late afternoon)

### Done
- Re-verified the current tree on the mini after the Browse Icons UI cleanup and drag-affordance changes:
  - `./scripts/SaneMaster.rb verify` passed with `547` tests
  - `./scripts/SaneMaster.rb release_preflight` passed build, runtime smoke x2, stability checks, channel checks, monetization checks, and webhook checks
- Visually verified the updated Browse Icons UI using fresh mini-generated PNG snapshots:
  - `outputs/icon-panel-rest.png` confirms the cleaned-up Icon Panel at rest
  - `outputs/icon-panel-drag.png` confirms real zone tabs light up during a live drag while `All` stays browse-only
  - `outputs/second-menu-bar-rest.png` confirms the compact top toggle chips and removal of sentence-level helper text
  - `outputs/second-menu-bar-visible-empty.png` confirms enabled empty rows now render as dashed drop targets with `Drag icons here`
- Added internal AppleScript snapshot commands so Browse Icons UI can be visually regression-tested from the signed running app on the mini without relying on flaky external screen capture permissions

### Release Readiness
- Technically green:
  - signed release runtime smoke passed twice on the mini
  - hidden / visible / always-hidden move actions passed in smoke
  - live customer-facing endpoint checks are green for `2.1.26` including the email worker
- Still blocked by release governance, not runtime failure:
  - open regressions `#101` and `#94`
  - closed regression without reporter confirmation `#109`
- Current `release_preflight` approval phrases required if you intentionally want to override those blockers:
  - `MR. SANE APPROVES OPEN REGRESSION RELEASE`
  - `MR. SANE APPROVES UNCONFIRMED REGRESSION CLOSE`

### Open GitHub Issues
| # | Title | Status | Action Needed |
|---|-------|--------|---------------|
| 111 | positions look right, then collapse into SaneBar after 2-3 seconds | Open | Current tree likely addresses the profile/layout part; still needs a shipped build plus reporter confirmation |
| 110 | Dock icon seems to appear for no reason | Open | Waiting for `2.1.26` confirmation |
| 107 | icon and separator not visible on Tahoe 26.3.1 | Open | Waiting for `2.1.26` confirmation |
| 101 | Second Menu Bar is not working | Open | Still a release-governance blocker |
| 94 | Not possible to start hidden app / move to visible | Open | Still a release-governance blocker |

### Key Files Changed
- `UI/SearchWindow/MenuBarSearchView.swift`
- `UI/SearchWindow/MenuBarAppTile.swift`
- `UI/SearchWindow/SecondMenuBarView.swift`
- `UI/SearchWindow/SearchWindowController.swift`
- `Core/Services/AppleScriptCommands.swift`
- `Resources/SaneBar.sdef`
- `Tests/AppleScriptCommandsTests.swift`
- `Tests/RuntimeGuardXCTests.swift`
- `Tests/SecondMenuBarDropXCTests.swift`

### Next Session Priorities
1. Decide whether to ship a new SaneBar build now with explicit governance override approval, or wait for more field confirmation on `#101`, `#94`, and `#109`
2. If shipping, keep the existing verified mini snapshot artifacts as proof of the Browse Icons UI state
3. Commit the current SaneBar changes once release timing is decided

---

## Session 59 (2026-03-12 midday)

### Done
- Fixed the feature-expectation gaps around saved configuration:
  - profiles now save and restore settings, menu bar layout snapshots, and custom icon snapshots
  - export/import now carries settings, layout snapshot, custom icon snapshot, and saved profiles
  - onboarding now imports Bartender directly from the detected plist and clearly states that Ice does not store icon positions
- Cleaned up the Second Menu Bar row language:
  - row controls now read as plain `On` / `Off` state by row name instead of duplicating `Hidden` / `Shown`
  - Browse Icons helper copy now treats the Second Menu Bar as rows and keeps Icon Panel tab language separate
  - onboarding/settings copy now says `Always Hidden` or `Always Hidden row` instead of `Always Hidden zone` where that wording was confusing
- Verification on the mini is green for the current tree:
  - `./scripts/SaneMaster.rb verify` passed with `547` tests
  - `./scripts/SaneMaster.rb release_preflight` passed runtime smoke x2 and stability checks for the staged app

### Open GitHub Issues
| # | Title | Status | Action Needed |
|---|-------|--------|---------------|
| 111 | positions look right, then collapse into SaneBar after 2-3 seconds | Open | Likely mixes normal startup hide pass with prior profile/layout expectation gap; needs clearer user reply and fresh diagnostics if icons are being misclassified |
| 110 | Dock icon seems to appear for no reason | Open | Waiting for `2.1.26` confirmation |
| 107 | icon and separator not visible on Tahoe 26.3.1 | Open | Waiting for `2.1.26` confirmation |
| 101 | Second Menu Bar is not working | Open | Still blocks release governance |
| 94 | Not possible to start hidden app / move to visible | Open | Still blocks release governance |

### Known Operational Blockers
- `release_preflight` still blocks release on governance, not runtime failure:
  - open regressions `#101` and `#94`
  - unconfirmed close `#109`
- Separate customer-facing infra bug still exists outside this repo:
  - email webhook product config serves `SaneBar-2.1.25` while appcast is `2.1.26`
  - new customers can still get the old build from the email webhook path until `sane-email-automation` is updated

### Key Files Changed
- `Core/Models/SaneBarProfile.swift`
- `Core/Services/PersistenceService.swift`
- `Core/Controllers/StatusBarController.swift`
- `Core/MenuBarManager.swift`
- `UI/Settings/GeneralSettingsView.swift`
- `UI/Onboarding/WelcomeView.swift`
- `UI/SearchWindow/SecondMenuBarView.swift`
- `Tests/PersistenceServiceTests.swift`
- `Tests/StatusBarControllerTests.swift`
- `Tests/SecondMenuBarDropXCTests.swift`

### Next Session Priorities
1. Fix the SaneBar email webhook product-version drift in `sane-email-automation` so new customers stop receiving `2.1.25`
2. Re-triage GitHub `#111`, `#101`, and `#94` against the current tree and decide which are real runtime bugs vs expectation/copy problems
3. Decide whether to reply on `#111` immediately now that profile/layout behavior is fixed in the current tree
4. Commit the current SaneBar changes once the webhook drift plan is decided

---

## Session 58 (2026-03-11 midday)

### Done
- Shipped `v2.1.26` / build `2126`.
- Verified customer-facing release endpoints end-to-end:
  - direct download ZIP
  - Sparkle appcast
  - website download links + JSON-LD version
  - GitHub release asset
  - Homebrew cask
  - email webhook product config
- Fixed release tooling regressions in `SaneProcess`:
  - mini-routed releases now run in a clean mirrored scratch workspace instead of the dirty live mini checkout
  - mirrored `SaneProcess` into the routed workspace so wrapper + QA paths resolve correctly
  - preserved remote TTY so routed releases can accept typed approvals like `--allow-republish`
  - relaxed false-fail Homebrew verification when GitHub API is correct and raw propagation is lagging
- Posted follow-up comments on GitHub issues `#110`, `#109`, `#108`, `#107`, `#101`, and `#94` saying `2.1.26` is out.
- Replied to Kyle on email `#286` and force-resolved duplicate email `#285`.

### Open GitHub Issues
| # | Title | Status | Action Needed |
|---|-------|--------|---------------|
| 110 | Dock icon seems to appear for no reason | Open | Waiting for `2.1.26` confirmation |
| 109 | Browse Icons view not matching / drag not working | Open | Waiting for `2.1.26` confirmation |
| 108 | well it’s not showing my menu bar apps | Open | Waiting for `2.1.26` confirmation |
| 107 | icon and separator not visible on Tahoe 26.3.1 | Open | Waiting for `2.1.26` confirmation |
| 101 | Second Menu Bar is not working | Open | Waiting for `2.1.26` confirmation |
| 94 | Not possible to start hidden app / move to visible | Open | Waiting for `2.1.26` confirmation |

### Email Requiring Action
- `#298` DMARC report from Microsoft — admin/no customer action
- `#287` DMARC report from Google — admin/no customer action
- `#283` GitHub Support declined ticket — human review
- `#280` Setapp partnership inquiry — human reply

### Key Files Changed
- `Core/Services/AccessibilityService+Interaction.swift`
- `UI/SearchWindow/SearchWindowController.swift`
- `UI/SearchWindow/SecondMenuBarView.swift`
- `Tests/IconMovingTests.swift`
- `Tests/RuntimeGuardXCTests.swift`

### Next Session Priorities
1. Watch for confirmations or fresh regressions on `#110`, `#109`, `#108`, `#107`, `#101`, and `#94`
2. Decide whether to close stale confirmations after `2.1.26` feedback comes in
3. Clean up local stale tags in the Air repo if tag drift becomes annoying (`v2.1.26` was force-retargeted during republish)
4. Review non-SaneBar inbox items `#283` and `#280`

## Session 57 (2026-03-04 evening)

### Done
- Checked inbox + GitHub issues post-release. No new user confirmations on v2.1.20 fixes yet.
- **Feature requests roadmap overhaul** — `marketing/feature-requests.md` fully audited against v2.1.20 codebase:
  - Cleared 12 shipped features to compact archive table
  - Removed 3 rejected items (bulk icon moves, third-party overlay detection, Intel support)
  - Added 4 new open features with verified implementation plans and breakage ratings
- **Competitive gap analysis** — researched Ice and Bartender for features SaneBar is missing. Found 4 viable gaps:
  1. Gradient tint (1/5 risk, ~1 day)
  2. New icon placement control (3/5 risk, 2-3 days)
  3. Auto-hide app menus / #103 (2/5 risk, 3-5 days) — Ice uses activation policy stealing, NO private APIs
  4. Per-profile trigger assignment (3/5 risk, 3-5 days)
- **Labeled GitHub #103** as `feature-request`
- **Bernard Le Du testimonial** — verified real quote ("I use SaneBar daily." from email Feb 11, 2026). Updated website to credit "Bernard Le Du, VVMac". Removed unverified Discord quote from all files.
- **#92 icon reset** — flowsworld returned with new finding: reset triggered when updating while MacBook disconnected from external monitor. Issue is closed but may need reopening.
- **Email #201** — DMCA reply from Discord (`copyright@discord.com`). Needs human review — legal matter, untouched.

### Open GitHub Issues
| # | Title | Status | Action Needed |
|---|-------|--------|---------------|
| 103 | Missing Option to Hide App Menus | Open | Feature request, labeled. Implementation plan in feature-requests.md |
| 102 | Second Menubar not working | Open | Responded with fix (left-click setting). Awaiting confirmation |
| 101 | Second Menu Bar not working | Open | Likely duplicate of #102 |
| 95 | Right/Left click on icon search | Open | Asked to update to 2.1.20 |
| 94 | Not possible to start hidden app | Open | Asked to update to 2.1.20 |
| 93 | Can not move items to visible | Open | Asked to update to 2.1.20 |
| 92 | Update resets icons (closed) | New comment | flowsworld: monitor-disconnect triggers reset. May need reopening |

### Email Requiring Action
- **#201** — DMCA from Discord. Legal. User must review.

### Key Files Changed
- `marketing/feature-requests.md` — full rewrite (roadmap + implementation plans)
- `docs/index.html` — Bernard Le Du testimonial attribution updated
- `.claude/projects/.../memory/MEMORY.md` — created with session findings

### Additional Finding (late session)
- **#92 icon position reset: ROOT CAUSE FOUND** — it's SaneBar's own `positionsNeedDisplayReset()` in `StatusBarController.swift`, not macOS. The function wipes positions when screen width changes >10%. Sparkle relaunch on different display config triggers it. No other app has this problem. Fix: per-display position backup (~30 lines, 1/5 risk). Full analysis in `marketing/feature-requests.md` and `/tmp/position_reset_research.md`.

### Next Session Priorities
1. **Fix #92 position reset** — root cause found, fix is ~30 lines in `StatusBarController.swift`, 1/5 risk. Strongest candidate for v2.1.21.
2. Respond to any user confirmations on #93/#94/#95/#101/#102
3. Review DMCA email #201
4. Consider implementing gradient tint (easiest feature win, 1/5 risk)
5. Website docs are still out of date (medium priority)
