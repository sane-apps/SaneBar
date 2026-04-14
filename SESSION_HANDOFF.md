# Session Handoff — SaneBar

**Last updated:** 2026-04-14
**Current public release:** `v2.1.41` (build `2141`)

## Current State

- Use `CHANGELOG.md` for release history and GitHub for live issue state.
- `v2.1.41` is live on direct ZIP, appcast, website/download page, GitHub release, and the email/download worker.
- 2026-04-14 post-release note repair:
  - the initial `2.1.41` binary release was good, but the GitHub release body and live appcast still carried overly technical note text
  - `origin/main` was corrected in commit `295b774` (`docs: soften 2.1.41 release notes`)
  - a clean Mini temp clone then ran `bash ~/SaneApps/infra/SaneProcess/scripts/release.sh --project <clone> --website-only` successfully, which republished the softened appcast/site note text without rebuilding the app
  - the GitHub release body for `v2.1.41` was then edited to match the same customer-facing wording
  - live final state is aligned: binary, appcast, website/download page, GitHub release body, and email worker all point to `2.1.41`
- `2.1.41` shipped these customer-visible fixes:
  - Browse Icons and the second menu bar use less CPU on busy menu bars
  - layout recovery after restart and wake is more stable
  - full-screen video now hides Custom Appearance correctly, and turning it off stays off
- 2026-04-14 `#135` current-width backup follow-up:
  - root cause was two-part: `MenuBarManager` had been feeding raw live screen coordinates into current-width backup capture, and `StatusBarController` was still treating any pixel-like override pair as “restorable” even when the pair was reversed and could not actually seed a valid backup
  - `captureCurrentDisplayPositionBackupIfPossible(...)` now ignores explicit override pairs unless they are launch-safe as-is or can be reanchored toward Control Center; if the override pair cannot seed a backup but the persisted preferred-position pair can, the helper keeps the persisted pair instead of collapsing to the generic launch-safe anchor
  - fresh Mini proof passed after the hardening: `./scripts/SaneMaster.rb verify` (`1069` tests), signed `./scripts/SaneMaster.rb test_mode --release --no-logs`, `SANEBAR_SMOKE_APP_PATH=/Applications/SaneBar.app ruby scripts/startup_layout_probe.rb`, `SANEBAR_SMOKE_APP_PATH=/Applications/SaneBar.app ruby scripts/wake_layout_probe.rb`, and signed `live_zone_smoke.rb` in Pro mode
- 2026-04-14 release-lane follow-up:
  - fixed a real QA harness bug where release smoke pass 2 reused the same live process but still enforced a fresh `launch` idle budget, causing false pass-2 regressions instead of a true relaunch check
  - `Scripts/qa.rb` now relaunches the staged target before every smoke pass after pass 1, so each `launch` idle budget measures a real fresh launch
  - routed `release_preflight` no longer blocks on unrelated dirty/out-of-sync local `sane-email-automation` state; only real `release` runs sync a clean worker checkout to the Mini
  - after those tooling fixes, the real runtime blocker was an over-broad system-wide AX fallback scan in `AccessibilityService.listMenuBarItemsWithPositions()`: every refresh paid for whole-menu-bar hit testing even when only a small unresolved fallback set needed it
  - current `main` now narrows the system-wide scan to unresolved fallback owners only (`knownNoExtras + windowBacked + topBarHost - axResolved`), which dropped the signed Mini smoke back under budget
  - fresh Mini proof after the scan narrowing: targeted `AccessibilityServiceTests` passed, signed standalone `live_zone_smoke.rb` passed at `avgCpu=10.4%`, full `./scripts/SaneMaster.rb verify` passed (`1071` tests), and `release_preflight` runtime smoke x2 plus focused shared-bundle smoke all passed
  - Zoom crossover check: with the official Zoom app launched on the Mini, the same browse/settings smoke path stayed bounded at `avgCpu=6.0%` / `peakCpu=40.1%` before a known free-mode move fixture ended the direct smoke; treat the earlier Zoom slowdown complaint as plausible same-family history, but not as a currently reproducible runaway on fixed `main`
  - `2.1.41` was shipped after the required open-regression override phrase was explicitly approved for still-open `#129`
- `#129` has been reopened after fresh post-`2.1.40` reporter evidence. Current `main` now carries a guarded `MenuBarManager.IconMoving` fallback that derives the main icon edge from the separator only when the separator is still present in visual mode; keep the issue open until a shipped build gets field confirmation.
- `#133` is still open, but it is no longer the only live SaneBar GitHub issue. Keep treating `#133` as the Tahoe supplemental-build Apple-side tracker unless fresh non-25D771280a evidence appears.
- 2026-04-14 permissions/privacy doc correction:
  - `PRIVACY.md` previously described an old optional Screen Recording thumbnail flow and referenced a non-existent `IconCaptureService`
  - current implementation uses Accessibility for product behavior and does not require Screen Recording permission for normal use
  - the only ScreenCaptureKit path left in the repo is a narrow self-snapshot helper for SaneBar's own settings window used by internal snapshot tooling
- 2026-04-13 appearance overlay follow-up:
  - fixed a real `MenuBarAppearanceService` lifecycle bug where turning off Custom Appearance only hid the overlay window, but later app/space changes could re-show it
  - `refreshOverlayVisibility()` now keeps the overlay hidden when appearance is disabled instead of reviving stale state
  - overlay suppression now covers true fullscreen content windows, including Apple apps, instead of only narrow third-party top-host strips
  - fresh Mini proof passed after the fix: `./scripts/SaneMaster.rb verify` (`1066` tests) and signed `./scripts/SaneMaster.rb test_mode --release --no-logs`
- 2026-04-13 icon-moving follow-up for `#129`:
  - fixed the asymmetric stale-frame fallback in `MenuBarManager.IconMoving`: separator recovery could estimate itself from the main icon, but the main icon had no reciprocal fallback when its own frame stayed stale
  - `getMainStatusItemLeftEdgeX()` now falls back to the separator's right edge only when the separator is still visually present, instead of dropping straight to `nil`
  - fresh Mini proof passed after the fix: `./scripts/SaneMaster.rb verify --quiet` (`1067` tests), signed `./scripts/SaneMaster.rb test_mode --release --no-logs`, and `SANEBAR_SMOKE_APP_PATH=/Applications/SaneBar.app ruby scripts/startup_layout_probe.rb`
- Fresh Mini release proof for `2.1.41`:
  - signed targeted `AccessibilityServiceTests` passed
  - signed standalone `live_zone_smoke.rb` passed at `avgCpu=10.4%`
  - full `./scripts/SaneMaster.rb verify` passed (`1071` tests)
  - clean routed `release_preflight` passed tests, runtime smoke x2, focused shared-bundle smoke, startup layout probe, git clean, and branch sync
  - live post-release checks now pass across direct ZIP, appcast, website, GitHub release, and email worker config
- Treat the older entries in this file as archival notes only.

## Archived Notes

## Addendum (2026-03-27 release 2.1.37)

- `v2.1.37` is live.
- Verified live channels:
  - GitHub release: `https://github.com/sane-apps/SaneBar/releases/tag/v2.1.37`
  - direct ZIP: `https://dist.sanebar.com/updates/SaneBar-2.1.37.zip`
  - appcast top entry: `https://sanebar.com/appcast.xml`
  - website download links and `softwareVersion` now point to `2.1.37`
  - Homebrew cask is live at `52c470c`
  - email worker download config now serves `SaneBar-2.1.37.zip`
- Release notes shipped:
  - keeps the SaneBar icon and hidden layout in place more reliably after login, wake, and display changes
  - reduces cases where the layout resets itself or the icon disappears
  - improves recovery on crowded and notched menu bars
- Why this release was allowed:
  - the signed Mini runtime lane was green on the targeted layout/disappearing-icon hotfix
  - manual override was used for open-regression / unconfirmed-close policy gates because unrelated open issues were still present
  - separate bugs still open and not claimed fixed by this build:
    - `#117` wrong icon mapped during hidden→visible move
    - `#122` dark tint turns black
- Follow-up completed:
  - standard retest replies posted on `#130 #129 #128 #126 #125 #124 #115 #114 #111`
- Operational note:
  - the main release script failed only at the email-worker deploy step because local `sane-email-automation` had unrelated dirty changes
  - fixed by deploying the worker from a clean temporary clone instead of touching the dirty local checkout

## Addendum (2026-03-26 website refresh deployed live)

- The SaneBar website refresh is live on `https://sanebar.com`.
- Live changes now on production:
  - new live screenshot showcase in `docs/index.html`
  - buyer-facing FAQ replacing the old compatibility-only FAQ
  - cleaned SaneSales cross-sell card copy without the `Today is free` pill
- Important deployment detail:
  - production was deployed from a clean temporary `docs/` snapshot, not the dirty worktree directly
  - this avoided shipping unrelated pending docs changes from the local checkout
- Production verification:
  - `https://sanebar.com` HTML contains `Hide the Apps.`, `Double-click any app to open it.`, `FAQ`, `What does SaneBar actually do?`, and the updated SaneSales card copy

## Addendum (2026-03-26 website live screenshot refresh)

- The website notch/showcase section in `docs/index.html` was refreshed to use the new live screenshots instead of the older staged carousel treatment.
- New website/marketing assets added:
  - `docs/images/second-menu-bar-live.png`
  - `docs/images/icon-panel-live.png`
  - `marketing/submission-images/sanebar-second-menu-bar-live.png`
  - `marketing/submission-images/sanebar-icon-panel-live.png`
- Design decision:
  - the wide live Second Menu Bar shot is now the primary full-width proof card
  - the portrait Icon Panel shot is the secondary card
  - the existing `browse-settings.png` remains as the settings card
- Local proof before any deploy:
  - Safari desktop preview looked clean
  - narrow-width preview collapsed to one column cleanly
  - local preview served from `http://127.0.0.1:8012/index.html`

## Addendum (2026-03-23 release preflight fallback)

- The signed mini release lane is technically green again on the current local tree:
  - `./scripts/SaneMaster.rb verify --quiet` passed with `1026` tests
  - `./scripts/SaneMaster.rb release_preflight` passed the real runtime path:
    - default browse smoke `2/2`
    - startup layout probe
    - focused shared-bundle exact-ID move smoke for `Focus` + `Display`
- The old startup/reset runtime bug is not what blocks release anymore.
- The release-preflight failure had become a smoke-harness policy mismatch:
  - the mini's live movable set was Apple-heavy
  - default move-candidate policy filtered every candidate out
  - release preflight was failing early with `No movable candidate icon found`
- Fix kept the default smoke conservative and changed `scripts/qa.rb` to:
  - treat that exact no-candidate failure as fixture-policy fallout
  - keep the default smoke for browse/layout coverage
  - defer move coverage to the existing shared-bundle exact-ID smoke
  - still fail if the fallback exact-ID set is empty or the focused smoke fails
- Added coverage for that behavior in:
  - `scripts/qa_test.rb`
  - `Tests/RuntimeGuardXCTests.swift`
- Current release posture:
  - technically strong enough for a new build
  - still blocked by governance only: open regression issues `#123`, `#117`, `#115`, `#113`

## Addendum (2026-03-19 move-task lifecycle centralization)

- The move pipeline is narrower and less copy-paste fragile now:
  - `moveIcon`, `moveIconAlwaysHidden`, `moveIconFromAlwaysHiddenToHidden`, and `reorderIcon` now all queue through one shared `queueDetachedMoveTask(...)` helper
  - that helper is now the single owner of:
    - `activeMoveTask` assignment/cleanup
    - `SearchWindowController.shared.setMoveInProgress(...)`
    - pre-drag `cancelRehide()`
  - awaitable move helpers now also share one `waitForActiveMoveTaskIfNeeded()` gate instead of repeating the same `if let task = activeMoveTask` block
- This change does not alter move policy; it centralizes move-task lifecycle so future move-path fixes only need one task-state implementation.
- Local proof:
  - targeted `xcodebuild test -only-testing:SaneBarTests/RuntimeGuardXCTests` passed (`102` tests)
- Mini proof on the current local tree:
  - `./scripts/SaneMaster.rb verify --quiet` passed with `1000` tests
  - `./scripts/SaneMaster.rb test_mode --release --no-logs` staged and launched the signed `/Applications/SaneBar.app`
  - direct `Scripts/live_zone_smoke.rb` passed on the staged release app
  - direct `Scripts/startup_layout_probe.rb` passed on the staged release app
  - full `SANEBAR_RUN_RUNTIME_SMOKE=1 SANEBAR_RUN_STABILITY_SUITE=1 ruby ./Scripts/qa.rb` is still technically green and still ends with policy-only blockers:
    - cadence `<24h` since `2.1.32`
    - open regression issues `#117`, `#115`, `#113`
    - unconfirmed closed regression `#94`

## Addendum (2026-03-19 recovery-anchor + manual-restore hardening)

- The last broad startup-reset seam was narrowed again:
  - init-time display-reset recovery now prefers a launch-safe current-display anchor instead of dropping straight to bare ordinal seeds
  - corruption migration now prefers the same launch-safe current-display anchor before any ordinal fallback
  - `recoverStartupPositions(alwaysHiddenEnabled:)` now prefers a launch-safe current-display anchor before ordinal fallback
  - `recreateItemsWithBumpedVersion()` now prefers a launch-safe current-display anchor when there is no current-width backup or reanchorable persisted pair
- The coordinator-owned restore path is also stricter now:
  - `MenuBarOperationCoordinator.manualLayoutRestoreRequest` no longer routes healthy snapshots through `repairPersistedLayoutAndRecreate`
  - healthy manual restore now uses `.recreateFromPersistedLayout(nil)`
  - unhealthy manual restore still uses `.repairPersistedLayoutAndRecreate(reason)`
- New behavior tests were added for:
  - init display-reset fallback without backup
  - startup recovery fallback without backup
  - autosave-bump fallback without backup
  - migration/upgrade corruption cases reanchoring to launch-safe recovery positions
  - healthy vs unhealthy manual restore coordinator behavior
- Mini proof on the current local tree:
  - `./scripts/SaneMaster.rb verify --quiet` passed with `1000` tests
  - `./scripts/SaneMaster.rb test_mode --release --no-logs` staged and launched the signed `/Applications/SaneBar.app`
  - direct `Scripts/live_zone_smoke.rb` passed on the staged release app
  - direct `Scripts/startup_layout_probe.rb` passed on the staged release app
  - full `SANEBAR_RUN_RUNTIME_SMOKE=1 SANEBAR_RUN_STABILITY_SUITE=1 ruby ./Scripts/qa.rb` is technically green on runtime/stability and now shows only release-policy blockers
- Current remaining QA blockers are policy-only, not runtime failures:
  - cadence `<24h` since `2.1.32`
  - open regression issues `#117`, `#115`, `#113`
  - unconfirmed closed regression `#94`
- `scripts/qa.rb` was updated to require the new migration regression title:
  - `Migration reanchors positions when legacy always-hidden position is corrupted`

## Addendum (2026-03-19 runtime hardening follow-up)

- Current local tree verification on the Mini is green:
  - `./scripts/SaneMaster.rb verify --quiet` passed with `984` tests
  - `./scripts/SaneMaster.rb test_mode --release --no-logs` staged and launched the signed `/Applications/SaneBar.app`
  - full `SANEBAR_RUN_RUNTIME_SMOKE=1 SANEBAR_RUN_STABILITY_SUITE=1 ruby ./Scripts/qa.rb` passed every technical runtime/stability check again
- The only red lines left in the full QA run are governance-only:
  - cadence `<24h` since `2.1.32`
  - open regression issues `#117`, `#115`, `#113`
  - unconfirmed closed regression `#94`
- Runtime hardening completed in this pass:
  - `list icon zones` now prefers cached classified zones before forcing a refresh
  - release smoke now requires at least one movable candidate instead of allowing a soft skip
  - browse focus proof now captures frontmost app state including window title, not just bundle id
  - always-hidden and always-hidden→hidden move flows now use `actionableMoveResolutionSafety(...)` and refuse classified-zone fallback when identity is ambiguous
- Measured AppleScript responsiveness improvement on the Mini after staging the fresh build:
  - `layout snapshot`: ~`0.09s` avg both before and after
  - `list icon zones` before fix: avg ~`0.67s`, max `2.536s`
  - `list icon zones` after fix: avg ~`0.087s`, max ~`0.089s`
- Mini hygiene finding during this pass:
  - a stale orphan `SaneSync/scripts/inference_server.py` process (parent `1`, ~`2 GB` RSS, ~`15h` old) was found and killed before the final QA/timing runs
- Current real release posture:
  - technically much stronger than `2.1.32`
  - not ready to publish without either governance override or fresh reporter confirmation on the still-open regression family

## Addendum (2026-03-18 release 2.1.32)

- `v2.1.32` published at `2026-03-18T23:03:28Z`:
  - GitHub release: `https://github.com/sane-apps/SaneBar/releases/tag/v2.1.32`
  - direct ZIP: `https://dist.sanebar.com/updates/SaneBar-2.1.32.zip`
  - appcast: `https://sanebar.com/appcast.xml`
- Release proof before publish:
  - `./scripts/SaneMaster.rb verify --quiet` passed
  - staged browse smoke passed `2/2`
  - staged startup layout probe passed:
    - poisoned relaunch state restored from current-width backup
    - `autoRehide=false` stayed expanded at `T+2s` and `T+5s`
  - strict post-release checks passed
- Public channel verification after publish:
  - GitHub release `v2.1.32` is live with `SaneBar-2.1.32.zip`
  - `dist.sanebar.com` serves the ZIP with `content-length=8248171`
  - `sanebar.com/appcast.xml` has exactly one `2.1.32` entry with `sparkle:version="2132"`
  - `sanebar.com` download links and JSON-LD now point to `2.1.32`
  - Homebrew cask is live at `d45d66e`
  - email webhook config is live at `a406498`
- Local workspaces synced after release:
  - SaneBar local main: `9b797b5`
  - homebrew-tap local main: `d45d66e`
  - sane-email-automation local main: `a406498`
- All six open GitHub issues were updated on 2026-03-18 asking reporters to retest on `2.1.32`.
- Remaining proof gap:
  - `#111/#113/#114/#115/#116/#117` still need reporter confirmation on the shipped build
  - browse focus smoke now proves frontmost-app integrity, but not the exact prior window inside that app

## Addendum (2026-03-18 late runtime audit)

- New audit commits on `main`:
  - `654bb23` `Document SaneBar runtime regression audit`
  - `5c81fed` `Harden browse smoke focus integrity`
- Active bug families are now tracked as:
  - startup / layout / reset family: `#111 #113 #114 #115`
  - browse right-click / focus family: `#116`
  - wrong-target move / beachball family: `#117`
- Mini runtime proof completed during this pass:
  - `./scripts/SaneMaster.rb verify --quiet` passed at push time with `957` tests
  - signed `/Applications/SaneBar.app` live smoke passed with the new browse focus probe in `86.89s`
  - poisoned startup prefs + valid current-width backup restored cleanly on the Mini (`main=144`, `separator=247`) instead of falling through to ordinal reseed
  - `autoRehide=false` launch probe stayed `expanded` at `T+2s` and `T+5s`
  - same-bundle exact-ID probe on the Control Center family moved `Focus` itself, then moved it back cleanly
- Newly confirmed risks:
  - startup recovery still has multiple planners in one launch (`StatusBarController.init`, `setupStatusItem`, `schedulePositionValidation`)
  - `moveIcon(...)` still has a false-success seam because it returns before the detached drag task finishes
  - browse-session correctness is still caller-owned across UI, AppleScript, and `SearchService`
  - `docs/state-machines.md` and the old handoff were stale enough to overstate confidence
- Shared runtime model now documented:
  - startup recovery, browse activation, and move actions all follow the same fragile pipeline: `identify target -> choose visibility policy -> choose geometry source -> execute action -> verify/persist`
  - the bug families differ mainly by which stage fails first, not by being unrelated systems
- Standard rule for this bug family:
  - do not call it fixed unless the relevant row passed in real Mini runtime
  - label proof as `runtime`, `logic/unit`, or `source-guard`
  - if runtime did not pass, say `unconfirmed in runtime`, not fixed

### Open GitHub Issues (current)
| # | Title | Status | Action Needed |
|---|-------|--------|---------------|
| 111 | positions look right, then collapse into SaneBar after 2-3 seconds | Open | Waiting for reporter retest on `2.1.32` |
| 113 | All visible items moved to hidden | Open | Waiting for reporter retest on `2.1.32` |
| 114 | menubar icon and separator always placed left of Control Center on login | Open | Waiting for reporter retest on `2.1.32` |
| 115 | menu bar icon and hidden icons keep resetting while app is open | Open | Waiting for reporter retest on `2.1.32` |
| 116 | right-click browse flashes and focus jumps back to prior app | Open | Waiting for reporter retest on `2.1.32` |
| 117 | wrong icon mapped during hidden→visible move and beachballs during add | Open | Waiting for reporter retest on `2.1.32` |

## Addendum (2026-03-17)

- Setapp single-app distribution is now documented as SaneBar's likely third channel alongside direct download.
- Direct Lemon Squeezy + Sparkle remains the website/direct business path.
- The current full-featured Mac App Store lane stays intentionally disabled.
- Setapp-specific blockers/gotchas are now captured in `ARCHITECTURE.md` and `.claude/research.md`:
  - separate `-setapp` bundle ID
  - no Sparkle / no direct licensing UI / no donate UI in the Setapp build
  - explicit Setapp `.userInteraction` reporting because SaneBar is a menu bar app
  - universal-binary readiness and real `setappPublicKey.pem` still need proof

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

## Session 58 (2026-03-19 early morning)

### Done
- Hardened the menu-bar cache layer so visibility transitions now schedule a background warmup instead of leaving the next interaction to pay the cold scan.
- Added `AccessibilityService.CacheWarmupReason` plus delayed warmup scheduling in `Core/Services/AccessibilityService.swift` and `Core/Services/AccessibilityService+Cache.swift`.
- Updated `HidingService` and the always-hidden separator structural repair path to invalidate with explicit warmup reasons.
- Added regression coverage:
  - `Tests/AccessibilityServiceTests.swift`
  - `Tests/RuntimeGuardXCTests.swift`

### Proven Result
- Mini `verify` passed with `987` tests.
- Mini staged release `qa.rb` is technically green again; only release-policy blockers remain (`#117`, `#115`, `#113`, unconfirmed `#94`, and <24h cadence).
- Real Mini release-app timings improved on the exact bad path:
  - baseline `list icon zones`: `0.102s`
  - after `toggle` + `0.5s`: `0.151s`
  - after `toggle` + `1.5s`: `0.151s`
- Before this change, the same post-toggle path was taking roughly `1.2s` to `2.8s`.

### Current Read
- The beachball/stall complaint was not explained by dead Mini junk at this point.
- The remaining cold-path issue was in SaneBar’s own cache invalidation behavior after reveal transitions.
- The new warmup path did **not** break browse, move, always-hidden, startup recovery, or shared-bundle exact-ID flows in Mini E2E.

### Key Files Changed
- `Core/Services/AccessibilityService.swift`
- `Core/Services/AccessibilityService+Cache.swift`
- `Core/Services/HidingService.swift`
- `Core/MenuBarManager.swift`
- `Tests/AccessibilityServiceTests.swift`
- `Tests/RuntimeGuardXCTests.swift`

### Next Session Priorities
1. Watch whether the beachball complaint is materially reduced in real use after this warmup change.
2. If there is still visible lag, profile the remaining cold path around `listMenuBarItemsWithPositions()` and reveal-triggered relayout rather than patching blindly.
3. Only consider a new release after the regression-issue policy blockers are honestly cleared.

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

---

## 2026-03-19 Telemetry Rollout

### Done
- Expanded SaneBar anonymous telemetry to include `app_version`, `build`, `os_version`, `platform`, `channel`, `tier`, and optional `target_version` / `target_build`.
- Added SaneBar startup launch events plus Sparkle update events for manual checks, update availability, and install start.
- Aligned public privacy copy across app UI, README, `PRIVACY.md`, `SECURITY.md`, and website docs to say `On-Device by Default` / `No Personal Data`.
- Deployed the local-only `sane-dist` worker live with D1 `event_dimensions` support and `launch_versions` rollups.

### Verification
- `./scripts/SaneMaster.rb verify --quiet --local` passed on SaneBar with `1020` tests.
- `./scripts/SaneMaster.rb test_mode --release --no-logs` passed on the Mini and staged `/Applications/SaneBar.app`.
- `swift test` passed in `infra/SaneUI`.
- `npx --yes wrangler d1 execute sane-dist-analytics --remote --file schema.sql` succeeded.
- `npx --yes wrangler deploy` succeeded for the worker with Version ID `5c1a9c9b-2831-4918-910d-bf0e4b2a4cb1`.
- Live checks passed:
  - `https://dist.saneapps.com/health` -> `OK`
  - synthetic `sanebar` + `sanesales` event posts -> `204`
  - `api/stats` with `DIST_ANALYTICS_KEY` returned `event_dimensions`
  - synthetic `app_launch_free` proved `launch_versions` now rolls up by version

### Commits
- `SaneBar` -> `ab98e1d` (`Add anonymous telemetry dimensions`)
- `SaneUI` -> `bcf5cdb` (`Add telemetry dimensions and unlock Setapp builds`)

### Notes
- Historical version-adoption before 2026-03-19 is still incomplete because older launch events did not include `app_version` / `build`.
- `sane-dist-worker` is still a local-only workspace, not a tracked git repo.
- `SaneBar` worktree still has untracked `.claude/sop-verify-state.json` generated by verification; it was left alone.
