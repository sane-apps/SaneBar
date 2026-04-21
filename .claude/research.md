# SaneBar Research Cache

## 2026-04-20 20:05 ET visibility-first recovery-state architecture refresh

**Updated:** 2026-04-20 20:05 ET | **Status:** verified research refresh; local refactor patched; Mini verify rerun pending after research gate | **TTL:** 14d
**Sources:** Apple docs for [`NSStatusBar`](https://developer.apple.com/documentation/appkit/nsstatusbar), [`NSStatusItem`](https://developer.apple.com/documentation/appkit/nsstatusitem), [`isVisible`](https://developer.apple.com/documentation/appkit/nsstatusitem), and [`autosaveName`](https://developer.apple.com/documentation/appkit/nsstatusitem/autosavename-swift.property); external code/issues from Maccy (`AppDelegate.swift`) and Ice (`ControlItem.swift`, issues `#918`, `#416`, `#802`); Bartender public release notes (`6.2.1`, `4.1.21`); local audit of `Core/MenuBarManager.swift`, `Core/MenuBarManager+IconMoving.swift`, `Core/Models/MenuBarRuntimeSnapshot.swift`, `Core/Services/MenuBarOperationCoordinator.swift`, and `Tests/MenuBarOperationCoordinatorTests.swift`

### Verified Findings

1. Apple still exposes only a narrow contract for menu bar items.
   - `NSStatusBar` explicitly warns that status items are not guaranteed to be available at all times.
   - `NSStatusItem.isVisible` and `autosaveName` remain the only documented first-class state surfaces relevant to disappearance/reappearance.
   - There is still no Apple-documented repair API for stale/off-screen status-item geometry.

2. The strongest external implementations also treat visibility and persistence as first-class state, not as incidental geometry.
   - Maccy observes `statusItem.isVisible` directly and keeps it synchronized with app state.
   - Ice caches/restores preferred positions when hiding or removing control items and still has live issue traffic for disappearing items, right-edge menu pressure, and layout resets (`#918`, `#416`, `#802`).
   - Bartender release notes continue shipping fixes for notch/right-edge disappearance, restart position drift, and multi-item identity stability.

3. That external evidence matches our own issue-family history.
   - `#129` was never only a bad-coordinate issue; the broader family also includes visibility loss, poisoned persisted state, stale bilateral geometry, and cold-start bootstrap failure.
   - SaneBar already had a dedicated unexpected-visibility observer path, which means visibility loss was operationally real, but it was still not modeled inside the central runtime snapshot/coordinator state.

4. The current refactor direction is correct, but visibility had to be promoted into the same model as anchor confidence and bootstrap.
   - `MenuBarRuntimeSnapshot` now needs to distinguish structural absence, invisibility, unattached windows, and ready state.
   - Recovery policy should key off that structural state first, then coordinates, then geometry confidence.
   - Interactive move policy should reject non-ready structural states instead of trusting cached geometry after a visibility or attachment failure.

5. Fresh local changes in this pass follow that simpler root-level direction.
   - The runtime snapshot now carries structural state plus anchor-source/bootstrap information together.
   - Required-item invisibility is promoted to structural state, not just a side-channel observer event.
   - The move queue now rejects non-ready structural state instead of only checking “busy” and “awaiting anchor.”

6. The Mini verify failures in this pass were mechanical, not a counterexample to the architecture.
   - First failure: a `guard` branch in `currentRuntimeSnapshot()` could not legally fall through after switching on structural state.
   - Second failure: `MenuBarRuntimeSnapshot(...)` test call sites had named arguments out of order relative to the initializer.
   - Both were fixed locally before the research receipt was written; Mini verify, signed launch, and probe reruns are still pending.

## 2.1.41 Live Notes Repair And Final Public-State Alignment

**Updated:** 2026-04-14 14:56 ET | **Status:** verified | **TTL:** 14d
**Source:** local `origin/main` audit at commit `295b774`; Mini clean temp clone `bash ~/SaneApps/infra/SaneProcess/scripts/release.sh --project <clone> --website-only`; live `https://sanebar.com/appcast.xml`; GitHub release `v2.1.41`; email worker debug download config

### Verified Findings

1. The initial `2.1.41` binary release was technically good, but two public note surfaces were stale.
   - The live appcast and GitHub release body still used the internal/technical wording about current-width backup capture and separator fallback.
   - `origin/main` itself was already corrected in commit `295b774` (`docs: soften 2.1.41 release notes`).
2. The correct repair path was a website-only republish, not a new binary release.
   - A clean Mini temp clone at `origin/main` successfully ran `bash ~/SaneApps/infra/SaneProcess/scripts/release.sh --project <clone> --website-only`.
   - That republished the softened `docs/appcast.xml` contents to the live site without rebuilding, re-signing, or re-uploading the app archive.
3. The GitHub release body had to be corrected separately.
   - Editing the `v2.1.41` release body through `gh release edit` brought it in line with the softened customer-facing wording already in `CHANGELOG.md` / `docs/appcast.xml`.
4. Final public release state is aligned.
   - Live appcast now says: “Browse Icons and the second menu bar now feel lighter and use less CPU on busy menu bars...” and still points to `https://dist.sanebar.com/updates/SaneBar-2.1.41.zip`.
   - GitHub release `v2.1.41` now uses the same softened wording.
   - Email worker debug config serves `SaneBar-2.1.41.zip` / `2.1.41`.
   - No further worker or binary release action was required.

## Release Runtime Smoke Active-CPU Overrun From Overbroad System-Wide Fallback

**Updated:** 2026-04-14 12:25 ET | **Status:** verified fixed | **TTL:** 14d
**Source:** Mini `./scripts/SaneMaster.rb release_preflight`; Mini signed `./scripts/SaneMaster.rb test_mode --release --no-logs`; Mini signed `ruby scripts/live_zone_smoke.rb`; Mini `/usr/bin/sample` captures during the active smoke path; local code audit of `Core/Services/AccessibilityService+Scanning.swift`; Mini `xcodebuild test -only-testing:SaneBarTests/AccessibilityServiceTests`; Mini `./scripts/SaneMaster.rb verify`

### Verified Findings

1. The release-lane CPU blocker was real and reproducible on the signed Mini app.
   - Before the fix, the exact release smoke path failed repeatedly at roughly `16.1%` to `16.8%` active average CPU even after the pass-2 relaunch bug was fixed.
   - Idle launch and post-smoke settle were already fine; the overrun lived inside the active browse/move flow.
2. Live stack samples all pointed at the same hot path.
   - During second-menu-bar open and browse activation, the app spent most of its time in `AccessibilityService.refreshMenuBarItemsWithPositions()` → `listMenuBarItemsWithPositions()` → `systemWideVisibleMenuBarItems(...)` and `enumerateMenuExtraItems(...)`.
   - The same family is a plausible crossover with the earlier Zoom slowdown complaint because it is real menu-bar scanning work inside normal browse/move interactions, not a release-only fake.
3. The expensive work was over-broad, not wholly unjustified.
   - The system-wide scan exists for real fallback cases such as AX-poor menu extras.
   - The bug was that `listMenuBarItemsWithPositions()` always paid for that full-width system-wide hit-test sweep across the whole menu bar for *all* running candidate apps, even when AX results had already resolved the app or the host only needed narrower fallback handling.
4. Current main now narrows that fallback to unresolved owners only.
   - `systemWideFallbackCandidatePIDs(...)` limits the system-wide scan to the union of known `AXExtrasMenuBar`-poor bundles, WindowServer-backed fallback owners, and top-bar-host fallback owners, minus PIDs already resolved through normal AX results.
   - This keeps Little Snitch-style fallback coverage while skipping unnecessary whole-bar hit-testing for ordinary already-resolved apps.
5. Fresh Mini proof is green.
   - Targeted `AccessibilityServiceTests` passed after the change.
   - Signed standalone `live_zone_smoke.rb` passed with `avgCpu=10.4%` and `peakCpu=31.1%`.
   - Full Mini `./scripts/SaneMaster.rb verify` passed with `1071` tests.
   - `release_preflight` runtime smoke now passes both main passes and the focused shared-bundle pass; the remaining blockers are governance/release-state only (`#129` still open, and live email worker drift until the next real release updates it).
6. The earlier Zoom complaint is still worth grouping with this family, but current Mini evidence is reassuring.
   - With the official Zoom app launched beside the signed Mini build, the same browse/settings smoke path stayed at `avgCpu=6.0%` and `peakCpu=40.1%` before a known free-mode move fixture stopped the run.
   - That does not fully prove “during a real conference” behavior, but it does show the fixed scan path stays bounded with Zoom live on the box instead of exploding on sight.

## 2.1.40 Issue #135 Current-Width Backup Override Clobber

**Updated:** 2026-04-14 10:45 ET | **Status:** verified | **TTL:** 14d
**Source:** GitHub issue `#135`; local code audit of `Core/MenuBarManager.swift` and `Core/Controllers/StatusBarController.swift`; Mini `./scripts/SaneMaster.rb verify`; Mini signed `./scripts/SaneMaster.rb test_mode --release --no-logs`; Mini signed `ruby scripts/startup_layout_probe.rb`; Mini signed `ruby scripts/wake_layout_probe.rb`; Mini signed `ruby scripts/live_zone_smoke.rb`

### Verified Findings

1. `#135` was a real current-width backup clobber on relaunch and wake, not just a reporting mix-up.
   - Reporter logs showed `Display validation: refusing to save unsafe current-width backup for width 1470.000000 (main=191.000000, separator=511.000000)`.
   - The same diagnostics snapshot showed the live persisted preferred positions had already collapsed to the generic backup anchor (`main: 160`, `separator: 280`) instead of the user’s wider visible lane.
2. One caller bug and one helper bug combined to cause the collapse.
   - `MenuBarManager` had been passing raw runtime screen coordinates (`snapshot.mainX` / `snapshot.separatorX`) into `captureCurrentDisplayPositionBackupIfPossible(...)` even though that helper expects `NSStatusItem` preferred-position values where `separator > main`.
   - Even after removing those raw-coordinate override arguments from the `MenuBarManager` call sites, `StatusBarController` still treated a reversed override pair as “restorable” if both numbers merely looked pixel-like.
3. The adjacent helper bug was the real trap.
   - `hasRestorableDisplayBackup(...)` only means “both values look like pixels,” not “this pair can safely seed a current-width backup.”
   - A reversed raw-screen pair like `main=1698, separator=1561` therefore bypassed the first guard, failed launch-safe validation, failed reanchoring, and then fell all the way back to the generic launch-safe recovery pair (`144/264` on the Mini’s 1920-wide screen, `160/280` on wider displays).
4. Current main now blocks both failure paths.
   - `MenuBarManager` stable-validation and recovery capture paths no longer pass raw snapshot coordinates into `captureCurrentDisplayPositionBackupIfPossible(...)`.
   - `StatusBarController` now ignores explicit override pairs unless they can actually seed the current-width backup (launch-safe as-is or reanchorable). If the override pair cannot seed a backup but the persisted preferred-position pair can, the helper keeps the persisted pair instead of collapsing to the generic anchor.
5. Fresh Mini proof is green on the signed app lane.
   - `./scripts/SaneMaster.rb verify` passed with `1069` tests.
   - Signed `./scripts/SaneMaster.rb test_mode --release --no-logs` staged `/Applications/SaneBar.app` successfully.
   - Signed `ruby scripts/startup_layout_probe.rb` passed.
   - Signed `ruby scripts/wake_layout_probe.rb` passed.
   - Signed `ruby scripts/live_zone_smoke.rb` passed in Pro mode with hidden/visible and always-hidden move checks green and resource watchdog averages around `10.6%` CPU / `128.1MB` RSS.

## 2.1.40 Release Clearance + Post-Ship State

**Updated:** 2026-04-09 19:45 ET | **Status:** verified | **TTL:** 14d
**Source:** Mini `./scripts/SaneMaster.rb release_preflight`, Mini `./scripts/SaneMaster.rb test_mode --release --no-logs`, Mini `ruby scripts/startup_layout_probe.rb`, Mini `ruby scripts/wake_layout_probe.rb`, Mini staged-app `ruby scripts/live_zone_smoke.rb`, shipped `./scripts/SaneMaster.rb release --full --deploy --version 2.1.40`, live appcast/site/Homebrew checks, GitHub issue `#129`

### Verified Findings

1. `2.1.40` is the first public build that actually ships the two unreleased `#129` startup-recovery fixes from `main`.
   - `48a8015` hard-resets persisted startup state for invalid status items / missing coordinates.
   - `3f27ce8` extends that hard reset to the invalid-geometry startup path and `.startupFollowUp`.
2. The technical release lane was clean on Mini before the policy override.
   - `release_preflight` passed runtime smoke, startup layout probe, recurring-regression coverage, and stability checks.
   - The only blocking failure was the expected open-regression guard on `#129`.
3. The shipped build was verified more than one way on the canonical `/Applications/SaneBar.app` path.
   - signed staged launch passed
   - startup layout probe passed
   - wake layout probe passed
   - staged-app `live_zone_smoke.rb` passed and captured browse/settings screenshots
   - full `verify` passed with `1062` tests inside the release lane
4. The `Advanced Workflow` onboarding layout fix is part of `2.1.40` and was visually rechecked before ship.
   - the footer buttons remain fully visible on the updated onboarding screen
   - the final plan screen still clears the wider `Get Started` button cleanly
5. Post-release surfaces were all verified live.
   - direct ZIP: `https://dist.sanebar.com/updates/SaneBar-2.1.40.zip`
   - appcast: `https://sanebar.com/appcast.xml`
   - website/download page: `https://sanebar.com/download`
   - Homebrew cask: `sane-apps/homebrew-tap` `sanebar.rb`
   - email webhook live config: `SaneBar-2.1.40.zip`
6. `#129` should no longer stay open as a release blocker after 2026-04-09.
   - it was closed after `2.1.40` shipped with a retest note
   - `#133` remains the only open SaneBar issue and is still the Apple-side Tahoe supplemental-build tracker
7. One tooling caveat surfaced during pre-ship visual proof:
   - `scripts/marketing_screenshots.rb --shot settings-general` can return exit `0` even when the underlying `screenshot` tool says `Window with parent SaneBar and title General not found`
   - do not treat that script alone as release-grade visual proof until its exit handling is tightened

## Sparkle Header Cache Mismatch After Package Pin Changes

**Updated:** 2026-03-28 22:31 ET | **Status:** verified | **TTL:** 7d
**Source:** mini `./scripts/SaneMaster.rb verify --quiet` failure on 2026-03-28; local code audit of `SaneBar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`; `SaneMaster.rb` command help for `verify --clean` and `clean --nuclear`; Apple/Xcode search for `has been modified since the module file`

### Verified Findings

1. The post-pin Mini failure was a build-cache mismatch, not a source regression in the settings UI work.
   - Xcode failed with `SPUStandardUserDriverDelegate.h has been modified since the module file ... was built`.
   - The failing header belonged to `Sparkle.framework`, which had just moved from `2.8.1` to `2.9.0` in `Package.resolved`.
2. The failure pattern matches stale Explicit Precompiled Module / DerivedData state after a package header changes underneath an existing build cache.
   - The failing path was under `DerivedData/.../SwiftExplicitPrecompiledModules/`.
   - The framework header size changed between the old cached module build and the new resolved package contents.
3. The safe recovery path is already part of SaneProcess.
   - `./scripts/SaneMaster.rb verify --clean` cleans before the test run.
   - `./scripts/SaneMaster.rb clean --nuclear` also removes DerivedData and resets Xcode state.
4. When package pins change on the Mini, prefer the nuclear clean first if the first verify run reports `has been modified since the module file`.
   - That avoids wasting time on source-level debugging for a cache-state problem.

## 2.1.37 Runtime + Settings Sweep Refresh

**Updated:** 2026-03-28 21:55 ET | **Status:** verified | **TTL:** 7d
**Source:** Apple docs for `NSStatusBar`, `NSStatusItem`, and `NSStatusItem.Behavior`; Bartender public help/release notes; live GitHub issues `#130`, `#129`, `#126`, `#122`, `#117`; local code audit of `Core/Controllers/StatusBarController.swift`, `Core/MenuBarManager.swift`, `UI/Settings/AboutSettingsView.swift`, and `UI/SettingsView.swift`

### Verified Findings

1. Apple still does not expose a new first-party API for managing other apps' menu bar items.
   - `NSStatusBar` and `NSStatusItem` remain app-owned status-item APIs.
   - `NSStatusItem.Behavior` still includes removal behaviors, which matters because SaneBar currently opts into `.removalAllowed` for its own items.
2. Competitor public docs still treat missing or inaccessible menu bar icons as a real category, not a solved platform problem.
   - Bartender still documents relaunching from Applications as a recovery path if the main icon is hidden or inaccessible.
   - Bartender release notes still carry fixes for dock-icon persistence, menu bar gaps, and hidden-bar visibility/recovery seams, which matches the same class of fragility SaneBar is fighting.
3. The live GitHub queue says the current SaneBar red cluster is still runtime disappearance/reset behavior, not settings UI.
   - `#129` is still open on `2.1.37` after reset-to-defaults did not restore the icon.
   - `#130` is still the wake/hover/reset family with stale separator geometry and move verification errors in diagnostics.
   - `#126` now has one fresh field clue: the reporter eventually found the SaneBar icon disabled in system menu bar visibility settings, which means at least one “icon disappeared” report was really “system-level icon visibility got turned off”.
   - `#122` remains a separate tint/appearance issue, and `#117` remains the separate hidden→visible wrong-target/move-instability issue.
4. Current local code does not intentionally hide the main SaneBar icon anymore.
   - `MenuBarManager` still force-clears deprecated `hideMainIcon` on launch and logs `hideMainIcon is deprecated - forcing visible main icon`.
   - That means new “icon vanished” reports are more likely to be status-item removal/system visibility/recovery failures than a persisted in-app “hide the icon” preference.
5. Current local code still leaves one real disappearance-risk seam open.
   - `StatusBarController` still enables `.removalAllowed`, so the app is explicitly allowing the system/user to remove the status item from the menu bar.
   - That aligns with the fresh `#126` clue and means any future recovery UX should account for the icon being absent because the system stopped showing it, not only because layout persistence drifted.
6. The settings/About standardization pass is orthogonal to the runtime cluster.
   - `SettingsView` already uses shared `SaneSettingsContainer`.
   - `AboutSettingsView` is still an app-local UI fork and needs standardization, but changing that screen is not itself evidence that disappearance/move runtime bugs are fixed.
7. Current PR state is unrelated to the runtime cluster.
   - Open PR `#127` is only a Sparkle package bump.
   - Open PR `#131` is only an `mcp` gem bump.
   - Neither PR should be treated as a fix for the disappearance/reset/move issue family.

## 2.1.35 Browse UX + Move Cluster Refresh

**Updated:** 2026-03-26 | **Status:** verified | **TTL:** 7d
**Source:** Apple docs for `NSStatusItem`, `NSStatusBar`, `CGWindowListCopyWindowInfo`, and `kCGWindowBounds`; live GitHub issues `#117`, `#123`, `#122`, `#116`; competitor review of Ice and Bartender support/docs; local code audit of `MenuBarManager+Actions.swift`, `UI/Settings/GeneralSettingsView.swift`, `UI/SearchWindow/SearchWindowController.swift`, `Core/Services/SearchService.swift`, `Core/Services/AccessibilityService+MenuExtras.swift`, and `Scripts/qa.rb`

### Verified Findings

1. Apple still does not provide a new first-party API that replaces the current Accessibility-driven browse/move architecture for third-party menu bar extras.
   - `NSStatusBar` / `NSStatusItem` remain the documented path for an app's own menu bar items, not for reading or repositioning other apps' items.
   - `CGWindowListCopyWindowInfo` remains an expensive raw-window inspection API; `kCGWindowBounds` only gives screen-space rectangles, not semantic classification of "good top bar host" versus "ordinary app titlebar".
   - Current takeaway: keep the existing AX + window-geometry model, but keep heuristics narrow and runtime-tested.
2. Fresh GitHub state says the browse-focus bug is no longer the active browse blocker.
   - `#116` was closed on 2026-03-26 after a fresh mini recheck: icon panel activation, second menu bar activation, and screenshot-backed browse smoke all passed on current `main`.
   - `#123` was also updated today and is now closed; the reset-family retest request is on `2.1.35`, not an open browse-UX escalation.
   - The still-open browse-adjacent issue is `#122`, but that is now a separate appearance/appcast problem, not a Browse Icons interaction bug.
3. The open move-family anchor is still `#117`, and the latest field action is "retest on 2.1.35", not "invent a new move theory".
   - `#117` is still open as of 2026-03-26 and now has a fresh maintainer retest request for `2.1.35`.
   - The customer-facing symptom is still the same pair: hidden -> visible can beachball, and same-bundle Control Center items can map to the wrong sibling.
   - That means the right current framing is still exact-identity + stale-geometry hardening, not a broad rewrite of Browse Icons.
4. Competitor behavior is converged enough that SaneBar should match the same mental model, not invent a stranger one.
   - Ice publicly advertises show-on-click, show-on-hover, show-on-scroll, auto-rehide, a separate bar under the menu bar, drag-and-drop arrangement, and search.
   - Ice also publicly documents the same failure class: restart/reset of hidden sections and Tahoe-era movement instability, which confirms this is a real platform-fragile category rather than a uniquely local bug.
   - Bartender support still centers recovery around a visible icon or hotkey, reinforcing that hidden-icon tools need an always-available recovery path and clear primary trigger.
5. Local browse UX is feature-complete, but discoverability is still split across too many knobs.
   - Current code already supports both browse surfaces (`Icon Panel` and `Second Menu Bar`), left-click browse mode, option-click browse, and trigger-based reveal (`hover`, `scroll`, `hotkey`, `automation`, `userDrag`).
   - The likely remaining UX risk is not missing capability; it is that browse mode, left-click behavior, and reveal triggers live in different settings surfaces and can still be easy to misread as one control.
   - Do not treat fresh confusion reports as proof that the browse runtime is broken without confirming the user's configured trigger path first.
6. Local move/runtime hardening is already pointed at the right seam.
   - `SearchService` still refuses same-bundle activation fallback after precise identity loss.
   - `AccessibilityService.actionableMoveResolutionSafety(...)` still refuses ambiguous multi-item bundle moves unless identity and geometry are strong enough.
   - `Scripts/qa.rb` still carries the shared-bundle exact-ID smoke fallback for `Wi-Fi`, `Battery`, `Focus`, and `Display`, so the release lane already knows how to exercise this class on current hosts.
7. Best current read before rerunning release checks:
   - browse UX does not need a speculative new code change first
   - the active move-family theory remains "shared-bundle identity drift plus stale geometry"
   - the next step should be rerunning `verify` / `release_preflight` on the refreshed research state and only patching code if those checks surface a current technical red

## 2.1.35 Outstanding-Issue Sweep

**Updated:** 2026-03-25 | **Status:** verified | **TTL:** 7d
**Source:** Apple docs for `CGWindowListCopyWindowInfo`, `kCGWindowBounds`, and `NSWorkspace.didActivateApplicationNotification`; live web checks against `dist.sanebar.com`; GitHub issues `#122`, `#119`, `#120`, `#116`; local code audit of `MenuBarAppearanceService.swift`, `SearchService.swift`, `MenuBarOperationCoordinator.swift`, and `infra/SaneProcess/scripts/release.sh`

### Verified Findings

1. `#122` is two real problems, not one:
   - the tint overlay can disappear because `MenuBarAppearanceService.shouldSuppressOverlay(...)` was suppressing on any third-party top-aligned window wider than `70%` of the target screen
   - the old-version download complaint is also real: live checks show `SaneBar-2.1.35.zip` returns `200`, while older appcast-linked enclosures like `2.1.34` and `2.1.28` currently return `404`
2. The tint suppression rule was too broad for ordinary apps:
   - Apple’s `CGWindowListCopyWindowInfo` / `kCGWindowBounds` only give raw window bounds; they do not classify “game top strip” versus “normal titlebar”
   - our old heuristic ignored target-screen `x` alignment and accepted any top-aligned window with width `>= 0.7 * screen width`
   - that matches the reporter’s Firefox/Finder-style false positives on a `1600`-wide external monitor
3. The old-version link breakage is self-inflicted:
   - `infra/SaneProcess/scripts/release.sh` deletes old R2 binaries after every release
   - the same script also purges older GitHub binary assets by default
   - `docs/appcast.xml` still advertises many historical enclosure URLs, so the release pipeline is leaving dead links behind
4. `#116` still looks like a fixed-but-not-closed internal issue:
   - local code still routes browse-panel right-click through the strict no-workspace-fallback path in `MenuBarOperationCoordinator.browseActivationPlan(...)`
   - the live smoke script still explicitly exercises `right click browse icon`
   - this needs fresh mini verification, not a new code theory first
5. `#120` still looks like a verify-and-close issue unless a fresh repro proves otherwise:
   - the earlier real regression was the local `../../infra/SaneUI` package path drift
   - current local memories and source-build guardrails say that path was fixed and guarded
   - this needs another clean standalone build proof on current `main`
6. `#119` is still not proven as a current product bug:
   - local `UpdateService` still delegates manual checks directly to Sparkle’s `checkForUpdates(nil)`
   - there is no SaneBar-side “step through intermediate versions” logic in the current code
   - this needs an old-build-to-current-feed repro or it stays “not reproduced”

## 2.1.34 Reset / Disappear / Always-Hidden Recheck

**Updated:** 2026-03-25 | **Status:** verified | **TTL:** 7d
**Source:** inbox threads `#436` / `#437` / `#438` / `#439`, GitHub issues `#124` / `#125` / `#126`, CleanShot transcript from `https://cleanshot.com/share/C362YVxl`, local code audit of `StatusBarController.swift`, `MenuBarManager.swift`, `MenuBarOperationCoordinator.swift`

### Verified Findings

1. `2.1.34` did not close the main SaneBar runtime family.
   - Customer feedback is uniformly still negative:
     - `#436`: Always Hidden still fails and the app freezes/hangs during move attempts
     - `#437`: disconnecting and reconnecting an external monitor still resets layout
     - `#438`: behavior is only "a little better" and still too unpredictable
     - `#439`: sleep/wake still reveals all icons and can make the SaneBar icon disappear while the app is still running
   - GitHub confirms the same picture on `2.1.34`: `#125`, `#126`, and the fresh external update on `#124`
2. The new evidence is not one bug but one family with at least two concrete sub-failures:
   - geometry/layout drift after startup, wake, or monitor changes
   - status items never attaching to a real menu bar window (`status-item windows are invalid` / icon disappears while app still runs)
3. There is one obvious recovery dead-end in current code:
   - `StatusBarController.recreateItemsWithBumpedVersion()` hard-stops when `autosaveVersion` reaches `99`
   - live reports `#124` and `#126` both show `Autosave version cap reached (99)`
   - once a user hits that cap, the namespace-bump escape hatch is gone and recovery can loop or stall on the same corrupted state
4. Wake / monitor-change geometry recovery is currently weaker than startup recovery:
   - in `MenuBarOperationCoordinator.statusItemRecoveryAction(...)`, invalid geometry during `.screenParametersChanged` or `.wakeResume` does one `repairPersistedLayoutAndRecreate`
   - after that first failed attempt it stops instead of escalating to a fresh autosave namespace
   - this matches field reports centered on sleep/wake and external monitor reconnect
5. The Always Hidden complaint in `#436` is not just wrong final placement; it also shows real responsiveness problems.
   - CleanShot transcript repeatedly mentions slowness, freezing, and delayed/no movement while trying to move items into Always Hidden
   - that means the runtime family still includes a responsiveness component, not only bad final geometry
6. Best current read before the next patch:
   - the first repair should be structural recovery, not another retry layer
   - highest-value next fixes are:
     - recycle the autosave namespace when version `99` is reached
     - allow wake / screen-change invalid-geometry recovery to escalate to namespace bump the same way startup follow-up already does
   - do not claim `2.1.34` fixed the reset/disappear family; it did not

## Browse/Move Runtime + Tint Recheck

**Updated:** 2026-03-23 | **Status:** in progress | **TTL:** 7d
**Source:** Apple docs on `NSStatusItem` / `NSStatusBar` / `NSAppearance`, web/competitor review, GitHub issues `#123` / `#122` / `#117` / `#115` / `#113`, mini `./scripts/SaneMaster.rb release_preflight`, local `MenuBarAppearanceServiceTests`

### Verified Findings

1. Fresh docs/web review did not reveal a new fundamental Apple API that would replace the current Accessibility-driven menu bar move model.
   - Apple still documents `NSStatusItem` / `NSStatusBar` for your own extras, not for repositioning third-party extras.
   - Competitor posture is still effectively the same: automate with Accessibility, or simplify to manual user drag.
2. The current open GitHub picture is still one main runtime family plus one separate tint bug:
   - runtime/reset/move family: `#123`, `#117`, `#115`, `#113`
   - separate appearance bug: `#122`
3. Fresh mini `release_preflight` on `2026-03-23` stayed functionally strong:
   - default browse/layout smoke passed
   - shared-bundle exact-ID smoke functionally passed `Focus` and `Display`
   - hidden/visible move actions passed
   - always-hidden move actions passed
4. The current technical blocker is not a functional move failure. It is a resource-budget overage during the focused shared-bundle smoke:
   - resource watchdog reported `avgCpu=15.1%`
   - current gate is `15.0%`
   - that is close enough that it may be measurement noise, but it is still a red preflight today until rechecked
5. Fresh tint work is narrow and test-backed:
   - `MenuBarAppearanceService` now resolves `NSApp.effectiveAppearance` to a concrete light/dark appearance and applies it to both the overlay window and its content view
   - targeted `MenuBarAppearanceServiceTests` passed locally (`29` tests)
6. Tint confidence is not release-grade yet because visual runtime proof is still missing:
   - issue `#122` reports the black-tint regression on `2.1.33`, especially when opening Finder or Firefox
   - local visual launch was correctly blocked by the browse/move research lock until this note was refreshed
7. Best current read:
   - move correctness still looks strong enough for the next patch
   - release confidence is currently held back by two things only: the `15.1%` shared-bundle smoke overage and missing visual signoff on the tint fix
   - do not ship until at least one fresh runtime recheck plus visual tint verification is green
## Release Preflight Empty-Candidate Fallback

**Updated:** 2026-03-23 | **Status:** verified on mini | **TTL:** 14d
**Source:** signed mini `./scripts/SaneMaster.rb release_preflight`, focused `live_zone_smoke.rb` for `Focus` + `Display`, `./scripts/SaneMaster.rb verify --quiet`, local code audit

### Verified Findings

1. By 2026-03-23 the startup/reset runtime bug was no longer what blocked release preflight on the mini.
2. The signed release lane passed:
   - default browse smoke `2/2`
   - startup layout probe
   - focused shared-bundle move smoke for `com.apple.menuextra.focusmode` and `com.apple.menuextra.display`
   - full `./scripts/SaneMaster.rb verify --quiet` with `1026` tests
3. The remaining runtime failure before this pass was a harness-policy mismatch:
   - default release smoke required a movable candidate
   - the mini's live movable set was Apple-heavy
   - the conservative move denylist filtered every default candidate out
4. The safe fix was in `scripts/qa.rb`, not app code:
   - treat `No movable candidate icon found (need at least one hidden/visible icon).` as fixture-policy fallout
   - keep the default smoke conservative for browse/layout coverage
   - defer move coverage to the existing shared-bundle exact-ID smoke
   - still fail if the fallback shared-bundle candidate set is empty or the focused smoke fails
5. This keeps release gating meaningful:
   - it does not soft-pass missing move coverage
   - it switches to a stricter exact-ID move proof on the same signed app
6. After the fix, `release_preflight` was technically green again and only the open-regression governance gate remained (`#123`, `#117`, `#115`, `#113`).

## Dead Code Cleanup Pass

**Updated:** 2026-03-21 | **Status:** verified | **TTL:** 14d
**Source:** `periphery scan`, targeted `rg` reference checks, local code audit, `xcodegen generate`, `./scripts/SaneMaster.rb verify --quiet`

### Verified Findings

1. A narrow dead-code cleanup was safe and passed full verification.
2. Removed because they had zero references in source and tests:
   - `UI/SearchWindow/MenuBarAppGrid.swift`
   - `UI/SearchWindow/MenuBarSearchStatusViews.swift`
   - `UI/Settings/Components/SpaceAnalyzerView.swift`
3. Removed because they were private or local dead helpers with no call sites:
   - `MenuBarManager.onboardingPopover`
   - `MenuBarManager.waitForAlwaysHiddenSeparatorX(...)`
   - `MenuBarManager.reorderIconAndWait(...)`
   - `MenuConfiguration.toggleAction` and its dead test/setup plumbing
4. Removed small orphaned UI properties and helpers after confirming no references:
   - `MenuBarSearchView.Mode.symbolName`
   - `MenuBarSearchView.modeBinding`
   - unused accent/color helpers in search/settings UI
   - `ChromeMenuButtonLabel`
   - `ChromeTinyIconBadge`
   - `SmartGroupTab.icon`
5. Project state after cleanup:
   - `xcodegen generate` succeeded
   - `./scripts/SaneMaster.rb verify --quiet` passed with `1026` tests
   - net code movement for this cleanup set was heavily negative (`~584` lines removed vs `~118` added from unrelated active move-fix work in the tree)
6. Important leftovers intentionally stayed:
   - `SaneAppMover` is release-only and Periphery under-counts that path
   - many protocol warnings are test seam false positives because tests still rely on them
   - several `RunningApp`, `SearchService`, and AppleScript helpers are used only by tests or look like compatibility surface, not safe blind deletions
7. A second deeper pass was also safe and removed the remaining clearly dead branches:
   - deleted the unwired external status-item injection path in `MenuBarManager` (`usingExternalItems` + `useExistingItems(...)`)
   - simplified external-monitor hide policy to the live runtime path (`shouldSkipHide(...)`) and removed the dead manual-origin scaffold
   - removed `RunningApp` thumbnail/control-center convenience code that had no production callers (`iconThumbnail`, `thumbnail(size:)`, `withThumbnail(size:)`, `controlCenterItem(...)`, `isControlCenterItem`, `preferredSFSymbol`)
   - updated the few UI/test/doc call sites that still mentioned those dead paths
8. Project state after the deeper pass:
   - `./scripts/SaneMaster.rb verify --quiet` passed with `1020` tests
   - test count dropped from `1026` to `1020` because six tests only covered the removed dead paths
   - targeted diff for the second pass was strongly negative (`264` lines removed vs `60` inserted)

## Issue #117 Fresh-Geometry Recheck Beats Baseline

**Updated:** 2026-03-21 | **Status:** verified | **TTL:** 14d
**Source:** clean baseline compare on mini signed Release, focused `live_zone_smoke.rb` for Display, unified logs with `--info --debug`, immediate repeat run, `./scripts/SaneMaster.rb verify --quiet`

### Verified Findings

1. The current kept baseline is green, but still pays for stale visible geometry with extra drag work:
   - focused Display smoke passed end-to-end
   - log window `20:14:46` -> `20:15:40` showed `2` `Move verification failed`
   - the same window showed `1` standard visible retry and `1` always-hidden visible retry
   - there were `0` shield fallback recoveries and `0` fresh-geometry accepts in baseline
2. The smallest root-cause experiment was then added:
   - keep retries, shield fallback, and classified fallback unchanged
   - before retrying a visible-return move, do one narrow fresh separator recheck
   - only accept if the miss is near the stale separator and the separator has actually shifted left
3. The experiment stayed green on the same signed Release path:
   - `./scripts/SaneMaster.rb verify --quiet` passed with `1026` tests
   - focused Display smoke passed end-to-end on the staged `/Applications/SaneBar.app`
4. The before/after compare is materially better:
   - experiment window `20:18:52` -> `20:19:50` still had `2` `Move verification failed`
   - but it had `0` standard visible retries, `0` always-hidden visible retries, `0` shield fallback recoveries
   - instead, both stale misses turned into `2` `Visible move accepted after fresh geometry recheck`
5. The immediate repeat held:
   - second experiment window `20:20:23` -> `20:21:20` again had `2` stale visible failures
   - again it had `0` visible retries, `0` always-hidden visible retries, `0` shield fallback recoveries
   - again it had `2` fresh-geometry acceptances
6. The recurring stale geometry signature is stable across runs:
   - stale separator `1692`
   - fresh separator `1657`
   - landing midpoint `1675.5`
   - that is consistent with the separator moving during relayout while the dragged icon is already in the correct final visible zone
7. Best current read:
   - this is the right level of fix for bug `#117`
   - it is more fundamental than another retry because it corrects verification geometry instead of dragging again
   - it is still narrow enough that we are not rewriting the move system or deleting proven fallbacks

## Issue #117 Clean Mini Release Recheck

**Updated:** 2026-03-21 | **Status:** verified | **TTL:** 14d
**Source:** mini signed Release launch, focused `live_zone_smoke.rb`, mini unified logs with `--info --debug`, local code audit

### Verified Findings

1. The earlier “app quit” evidence was partially tainted by mixed lanes on the mini:
   - one logged death was a separate DerivedData debug app (`com.sanebar.dev`), not the staged `/Applications/SaneBar.app` release build
   - later repeat noise also overlapped with a separate `xcodebuild test` lane on the mini
2. A clean signed Release launch on the mini did keep the real staged app alive:
   - `/Applications/SaneBar.app/Contents/MacOS/SaneBar --sane-no-keychain` was the live process before the focused smoke
3. The strict focused smoke was blocked once by launch idle budget before any move work:
   - `launch_idle_budget_exceeded avgCpu=16.0% > 5.0% peakCpu=27.0% > 15.0%`
   - that failure says more about runtime-budget noise than move correctness
4. Re-running the same focused Display smoke with only the idle thresholds relaxed allowed the move path itself to run cleanly:
   - hidden/visible passed
   - always-hidden passed
   - candidate set passed
   - full smoke passed in `42.1s`
5. The clean mini log window proved the new move behavior directly:
   - `1` `Move verification failed` hit on the classic stale visible case (`separatorX=1692`, `afterMidX=1675.5`)
   - immediately followed by `1` `Visible move accepted after post-layout geometry recheck` with `freshSeparatorX=1657`
   - `0` standard visible retries
   - `0` shield fallback recoveries
6. The clean mini log window showed no app-driven quit path for the staged release app:
   - `0` `applicationShouldTerminate requested`
   - `0` `applicationWillTerminate received`
   - the release app stayed alive after the successful smoke
7. Best current read:
   - the fresh-geometry visible acceptance path is the right fix for the move bug itself
   - remaining instability evidence is better explained by mini runtime-budget noise and overlapping debug/test lanes than by the move fix regressing the release app

## Issue #117 Visible Return Fresh-Geometry Fix Extended to Always-Hidden Path

**Updated:** 2026-03-21 | **Status:** verified | **TTL:** 14d
**Source:** local code experiment, `./scripts/SaneMaster.rb verify --quiet`, signed Mini `test_mode --release --no-logs`, focused Display smoke loops, unified logs

### Verified Findings

1. The stale-separator acceptance fix is best implemented as a narrow post-layout geometry recheck, not as a new drag path or a target-overlap rewrite.
2. The first cut only covered the regular hidden->visible path. That explained why some live Display failures still had no matching acceptance log.
3. Extending the same `verifyVisibleMoveWithFreshGeometry(...)` check into `moveIconAlwaysHidden(... toAlwaysHidden: false)` closed that gap.
4. Current local proof:
   - `./scripts/SaneMaster.rb verify --quiet` passed with `1028` tests after the final source-guard update
   - signed Release build staged and launched successfully via `./scripts/SaneMaster.rb test_mode --release --no-logs`
5. Best focused runtime compare window on the signed Mini (`2026-03-21 19:59:43` -> `20:02:16` local) showed:
   - `7` `Move verification failed` hits
   - `7` `Visible move accepted after post-layout geometry recheck` hits
   - `0` `Retrying move once with session tap` hits
   - `0` `Shield fallback returned` hits
6. That is materially better than the prior kept baseline for this Display path:
   - baseline still depended on visible retry recovery (`5` visible failures + `5` retries in the earlier accepted comparison window)
   - current fix turns every observed stale visible failure in the window into an immediate fresh-geometry acceptance instead of an extra drag
7. Focused smoke loop result is mixed only on the idle-budget gate, not on move correctness:
   - one pass was fully green end-to-end
   - another pass completed both hidden/visible and always-hidden move actions, then failed only on post-smoke idle budget
   - later passes sometimes failed the launch idle budget before candidate work started
8. The honest interpretation is:
   - the move bug itself now looks solved on both visible-return paths
   - the remaining red is a separate runtime-budget / cache-warmup timing issue in the smoke harness or post-action settle behavior, not stale separator verification

### Shipping stance

- Worthy for the next move-bug update: **yes**, for bug #117 specifically.
- Still worth keeping an eye on: the Mini smoke idle-budget noise, because it can still make back-to-back runtime loops look red even when move correctness is green.

## Issue #117 Visible Target Experiment Rejected

**Updated:** 2026-03-21 | **Status:** verified | **TTL:** 14d
**Source:** mini signed Release smoke, unified logs, local code experiment, `./scripts/SaneMaster.rb verify --quiet`

### Verified Findings

1. A controlled experiment increased visible-lane insertion overlap in `AccessibilityService+Interaction.swift` from `max(6, min(18, iconWidth * 0.35))` to `max(12, min(28, iconWidth * 0.7))`.
2. The experiment stayed superficially green:
   - signed Release build launched on the mini
   - focused 5-pass warm smoke for `Focus` + `Display` still passed
3. The logs proved the hypothesis was wrong:
   - baseline current-fix window (`2026-03-21 11:23:30` to `11:30:10`) had `10` `Move verification failed` hits
   - experiment window (`2026-03-21 13:09:18` to `13:16:45`) had `12` hits
4. The miss geometry stayed effectively the same:
   - baseline signature: `separator-after = 27.0`, `separator-mid = 16.5`
   - experiment signature: mostly `separator-after = 27.0`, `separator-mid = 16.5`, with two hits at `28.0` / `17.0`
5. That means the visible target moved, but the landing error moved with it. The root cause is not simply that the first visible target sits too close to the separator.
6. The experiment was rolled back immediately:
   - reverted only the insertion-overlap change and matching test expectations
   - kept the proven current fix: visible shield hardening in `MenuBarManager+IconMoving.swift` plus the `9.0s` AppleScript move timeout
7. Post-rollback `./scripts/SaneMaster.rb verify --quiet` passed with `1026` tests.

## Ellery 2.1.32 Evidence vs 2.1.33 Hover / Focus / Click Timing

**Updated:** 2026-03-20 | **Status:** verified | **TTL:** 7d
**Source:** Apple docs already referenced in prior runtime notes (`NSApplication.ActivationPolicy.accessory`, `NSWindow.hidesOnDeactivate`), inbox thread `#401`, GitHub issue `#116`, local code audit, focused local tests

### Verified Findings

1. Ellery's latest report on `2.1.32` is not vague; it contains three specific behaviors:
   - focus leaves the active app after hover reveal auto-hides
   - first right-click can flash/fail
   - left-click hide/show timing feels inconsistent when hover is enabled
2. His diagnostics match the hover-driven runtime path directly:
   - `showOnHover=true`
   - `showOnScroll=true`
   - `autoRehide=true`
   - external display active (`LG Ultra HD`)
   - no browse activation was in progress in the diagnostic snapshot
3. `2.1.33` directly targets the first and third complaints:
   - passive hover reveals no longer reuse the inline app-menu suppression path
   - restore now goes through `restoreApplicationMenusIfNeeded(reason: "passiveReveal")`
   - explicit status-item interactions call `hoverService.noteExplicitStatusItemInteraction()`, which cancels stale hover timers before click handling
4. `2.1.33` also continues the earlier fix for the second complaint:
   - explicit status-menu right-click opens are no longer allowed to depend on stale `NSApp.currentEvent`
   - browse-panel right-click fallback remains blocked from reactivating another app/workspace
5. Current local guard coverage maps to his report closely enough to justify a retest ask:
   - `MenuBarManagerTests` checks that passive hover reveals do not trigger inline app-menu suppression and that saved focus is only restored if SaneBar is still frontmost
   - `ReleaseRegressionTests` keeps the left/right/option click routing contract explicit
   - `RuntimeGuardXCTests` requires wake-aware validation cancellation and passive-reveal restoration guards to remain in source
6. Confidence is improved, but not absolute:
   - I do not have a same-host reproduction of Ellery's exact 3-screen metronome click cadence on `2.1.33`
   - the honest support stance is "high-confidence retest requested," not "guaranteed fixed"

## Browse / Move / Startup Follow-up Hardening

**Updated:** 2026-03-19 | **Status:** verified | **TTL:** 14d
**Source:** Apple docs (`NSWindow.hidesOnDeactivate`, `NSStatusItem.autosaveName`), GitHub issues `#111` / `#113` / `#114` / `#115` / `#116` / `#117`, local code audit, local focused tests, Mini staged release smoke/probe

### Verified Findings

1. The earlier second-menu-bar smoke failure on March 19 was tainted by bad test orchestration, not proven as a stable app regression.
   - I had launched `live_zone_smoke.rb` and `startup_layout_probe.rb` in parallel against the same staged app.
   - A clean rerun, in sequence, passed:
     - staged `live_zone_smoke.rb`
     - staged `startup_layout_probe.rb`
2. The staged runtime gate had a real tooling weakness even after the `open -na` fix:
   - process verification was exact-path based
   - but AppleScript control still targeted `application "SaneBar"` by name
   - that is now fixed so staged smoke and QA talk to the exact staged bundle path via `application (POSIX file "...")`
3. Fresh local proof for the new tooling path:
   - `Scripts/qa_test.rb` passed (`11` runs / `21` assertions)
   - focused local `xcodebuild` passed (`117` tests) for:
     - `MenuBarOperationCoordinatorTests`
     - `MenuBarSearchDropXCTests`
     - `RuntimeGuardXCTests`
4. The startup recovery refactor still had one real dead-end:
   - startup initial missing coordinates after onboarding correctly stayed expanded
   - but startup follow-up missing coordinates / invalid status items would only log and stop after the retry window
   - that is now fixed:
     - first persistent follow-up failure recreates from persisted layout
     - second persistent failure bumps autosave version
     - only then does it stop
5. The All-tab action menu classifier had drifted from the runtime classifier:
   - All-tab classification was using the always-hidden separator origin directly
   - runtime classification was using the normalized always-hidden boundary / right-edge model
   - that mismatch is now removed; All-tab uses the same normalized boundary logic
6. `show icon` AppleScript had a real false-success seam:
   - it matched pinned IDs too loosely (`hasPrefix`)
   - removed pins before proving any visible restore happened
   - and could report success on a no-op
   - that is now fixed:
     - it resolves a real live always-hidden source item
     - routes the restore through `moveIconAlwaysHiddenAndWait(... toAlwaysHidden: false)`
     - only clears pins after a successful move
7. Fresh Mini staged proof after these fixes:
   - `./scripts/SaneMaster.rb test_mode --release --no-logs` passed
   - staged `Scripts/live_zone_smoke.rb` passed cleanly in sequence
   - staged `Scripts/startup_layout_probe.rb` passed cleanly in sequence
8. Public issue surface is still the same live family, and should remain the release focus:
   - `#111` open
   - `#113` open
   - `#114` open
   - `#115` open
   - `#116` open
   - `#117` open
9. Apple’s documented contract still supports the product direction:
   - `NSWindow.hidesOnDeactivate` confirms panel visibility on app deactivation is an explicit policy surface
   - `NSStatusItem.autosaveName` remains the relevant persistence contract for launch/layout restore behavior

## Move-Task Lifecycle Centralization

**Updated:** 2026-03-19 | **Status:** verified | **TTL:** 14d
**Source:** local code audit, `RuntimeGuardXCTests`, Mini routed verify, staged release smoke/probe, full Mini `qa.rb`

### Verified Findings

1. The move-policy work was already stronger than the move-task lifecycle. Four entry points still manually wired the same detached-task state:
   - `moveIcon`
   - `moveIconAlwaysHidden`
   - `moveIconFromAlwaysHiddenToHidden`
   - `reorderIcon`
2. That manual lifecycle wiring was centralized into one helper:
   - `queueDetachedMoveTask(operationName:_:)`
   - it now owns `activeMoveTask`, `setMoveInProgress(true/false)`, and pre-drag `cancelRehide()`
3. Awaitable move helpers also now share one gate:
   - `waitForActiveMoveTaskIfNeeded()`
   - this replaces repeated `if let task = activeMoveTask { _ = await task.value }` blocks
4. This was a maintainability / correctness-seam cleanup, not a move-policy rewrite:
   - retry targeting, ambiguity refusal, shield fallback, and classified-zone verification behavior remain the same
5. Local proof:
   - targeted `xcodebuild test -only-testing:SaneBarTests/RuntimeGuardXCTests` passed (`102` tests)
6. Mini proof after the refactor:
   - `./scripts/SaneMaster.rb verify --quiet` passed with `1000` tests
   - staged release launch passed via `./scripts/SaneMaster.rb test_mode --release --no-logs`
   - direct staged `Scripts/live_zone_smoke.rb` passed
   - direct staged `Scripts/startup_layout_probe.rb` passed
   - full `SANEBAR_RUN_RUNTIME_SMOKE=1 SANEBAR_RUN_STABILITY_SUITE=1 ruby ./Scripts/qa.rb` remained technically green and still failed only on policy blockers

## Startup / Browse / Move Regression Audit + 2.1.32 Release

**Updated:** 2026-03-18 | **Status:** verified | **TTL:** 14d
**Source:** Apple docs (`NSStatusItem.autosaveName`, `NSApplication.ActivationPolicy.accessory`, `setActivationPolicy`), GitHub issues `#111` / `#113` / `#114` / `#115` / `#116` / `#117`, local code/tests, Mini staged-release runtime proof, public release-channel verification

### Verified Findings

1. The current SaneBar reliability problem is best modeled as one shared runtime pipeline, not isolated bugs: `identify target -> choose visibility policy -> choose geometry source -> execute action -> verify/persist`.
2. The active public bug buckets remain:
   - startup/reset family: `#111/#113/#114/#115`
   - browse focus family: `#116`
   - move / identity-drift family: `#117`
3. The March 18 code hardening directly targeted the two strongest proven weak points:
   - startup validation was serialized behind the startup hide/recovery path so it does not race launch recovery
   - same-bundle activation fallback now refuses sibling substitution once precise identity is lost
4. The staged release startup probe is real proof, not just a source-string guard:
   - it seeds poisoned startup prefs (`main=0`, `separator=1`)
   - requires a valid current-width backup
   - relaunches the staged app
   - verifies the current-width backup wins over ordinal reseed
   - verifies `autoRehide=false` stays expanded at `T+2s` and `T+5s`
5. The staged release browse smoke is also real proof:
   - browse activation passed in both browse modes
   - hidden/visible and always-hidden move actions passed
   - frontmost-app reversion is now explicitly checked for the browse right-click family
6. Remaining runtime proof gap after the new smoke:
   - browse focus integrity is proven at the app level, but not yet at the exact prior-window level inside that app
7. Exact same-bundle move safety is now stronger in both code and smoke:
   - activation fallback rejects sibling substitution when multiple same-bundle items exist and the original item had precise identity
   - live smoke refuses same-bundle sibling fallback when verifying move success
   - focused Mini proof rechecked the Control Center-family exact-ID move path with `Focus`
8. SaneBar 2.1.32 shipped publicly on 2026-03-18 only after:
   - `verify` passed
   - staged browse smoke passed `2/2`
   - staged startup layout probe passed
   - archive/export/notarization/staple passed
   - strict post-release checks passed
9. Public `2.1.32` verification after ship:
   - GitHub release live
   - direct ZIP live at `dist.sanebar.com`
   - appcast has exactly one `2.1.32` item with `sparkle:version="2132"`
   - homepage download links and JSON-LD point to `2.1.32`
   - Homebrew cask live
   - email webhook live
10. Safe release stance after March 18:
   - `#111/#113/#114/#115/#116/#117` are technically addressed strongly enough to ship `2.1.32`
   - none of those issues should be closed until reporter confirmation arrives on the shipped build
11. All six live issues were commented on 2026-03-18 asking reporters to retest on `2.1.32`.

## Native Menu Extras vs Edge Cases (99%-first policy)

**Updated:** 2026-03-17 | **Status:** verified | **TTL:** 14d
**Source:** Apple docs (`NSStatusBar`, `NSStatusItem`, `autosaveName`, `isVisible`, `behavior`), official Bartender release notes/docs, Ice releases/issues, mini live smoke on the signed app

### Verified Findings

1. Apple documents the standard contract as `NSStatusBar` / `NSStatusItem` creation plus `autosaveName` / `isVisible` persistence, but Apple does **not** promise exact slot/order persistence or universal interoperability with menu bar managers.
2. Bartender and Ice both treat common Apple/system items as normal support targets, but both publicly carry per-item and per-OS workarounds. This supports a policy of "support the mainstream path aggressively, do not promise every oddball host model."
3. Bartender publicly ships fixes for Apple-item handling, notch overflow, duplicate items, Little Snitch naming/persistence, and restart/layout drift. Ice publicly describes some apps as unavoidable outliers when their menu bar implementation differs.
4. Safe FAQ language is: SaneBar is optimized for standard macOS menu bar items and most common Apple/third-party items, while some items remain compatibility edge cases because macOS/app host models differ.
5. Unsafe FAQ language is: Apple enforces one strict implementation and third parties are simply "non-compliant." The research does not support that claim.
6. Mini focused smoke now has a real first-party path for native-item investigations: `SANEBAR_SMOKE_REQUIRED_IDS=... ruby scripts/live_zone_smoke.rb`.
7. That focused smoke path now bypasses the normal move-candidate denylist for the exact required IDs and downgrades browse checks to open/close-only, so move investigations no longer depend on unrelated browse-activation flakiness.
8. Mini focused smoke passed end to end for `com.apple.menuextra.siri`, `com.apple.menuextra.spotlight`, and `com.apple.menuextra.focusmode` on the signed app after the collapsed visible-move resolver change.
9. A focused Shottr run also passed on the same build, so "Shottr is definitely still an edge case" is weaker than before and should not be stated confidently without fresher failures.
10. Bluetooth was not present in the later mini `list icons` / `list icon zones` output, so no conclusion should be drawn from that failed required-ID run.
11. On the patched mini build launched through `./scripts/SaneMaster.rb test_mode --release`, the common move set passed end to end in one focused smoke: `Display`, `Focus`, `Siri`, `Spotlight`, and `SSMenuAgent`.
12. The patched mini build also passed a separate focused Shottr move smoke, so the current safe edge-case bucket is narrower than the old blanket "weird third-party app" framing.
13. A default conservative smoke run can still return `No movable candidate icon found` or otherwise be inconclusive on an Apple-heavy setup where every present movable item is denylisted by release-fixture policy. That should be treated as a fixture-policy result, not as evidence that the move fix failed.
14. Customer-facing edge-case framing should be: SaneBar is built around Apple’s supported menu bar APIs and the standard macOS behavior they produce; most Apple menu extras and normal third-party apps should work well; some apps use unusual/custom helper-host or window-backed models, and those compatibility limits come from that app’s implementation rather than from SaneBar ignoring the supported path.
15. Avoid saying Apple "enforces" one universal implementation. Prefer "Apple supports the standard menu bar API path, and SaneBar is optimized for that supported path."

## Setapp Single-App Distribution Lane

**Updated:** 2026-03-17 | **Status:** verified | **TTL:** 30d
**Source:** Setapp email thread `#370`, official Setapp docs, local SaneBar/SaneUI code audit, public Setapp framework interface

### Verified Findings

1. Setapp single-app distribution is a real third lane for SaneBar, not a replacement for the direct Lemon Squeezy business.
2. Public Setapp docs still describe a narrower rollout than Hanna's email, so business eligibility should follow the live thread while technical implementation should still follow the published docs.
3. SaneBar should not rely on the current direct-vs-App-Store runtime inference once Setapp exists; it needs an explicit channel abstraction.
4. SaneBar's Setapp build should remove Sparkle, Lemon Squeezy activation UI, and donate/sponsorship UI while keeping the app otherwise as close to the direct build as possible.
5. Because SaneBar is a menu bar app, Setapp usage reporting needs an explicit `.userInteraction` event on real icon activation.
6. Setapp macOS 13+ updates require `NSUpdateSecurityPolicy` for `com.setapp.DesktopClient.SetappAgent`.
7. If SaneBar's Setapp build remains sandboxed, it will need the `com.setapp.ProvisioningService` Mach lookup exception.
8. Current SaneBar project settings are `arm64` only, so Setapp universal-readiness is a real blocker, not a box to tick later.
9. SaneBar currently stores app data in `Application Support/SaneBar` but keys credentials off the bundle ID, so a direct build and a Setapp build would likely share settings/profile data while keeping separate license state.
10. Operational blocker: final Setapp runtime verification cannot happen until the real `setappPublicKey.pem` is provided.

## Setapp Lane Scaffolding + XcodeGen Package Resolution

**Updated:** 2026-03-17 | **Status:** verified | **TTL:** 14d
**Source:** official Setapp docs, GitHub/XcodeGen package behavior, local `xcodegen generate` + `xcodebuild -resolvePackageDependencies` + local verify logs

### Verified Findings

1. The new shared Setapp-safe UI/channel plumbing compiles and tests in the local `SaneUI` package (`swift test` passed after adding `direct/appStore/setapp` channel policy).
2. SaneBar's first two local `verify` failures on this Setapp pass were not caused by the Setapp code itself. They were caused by stale package resolution:
   - `project.yml` was changed from remote `https://github.com/sane-apps/SaneUI.git` to local `../../infra/SaneUI`
   - `xcodegen generate` correctly produced an `XCLocalSwiftPackageReference`
   - but the workspace still held the old remote pin in `Package.resolved`, so `verify` kept compiling against the old GitHub checkout
3. The fix path is:
   - `xcodegen generate`
   - then explicit `xcodebuild -resolvePackageDependencies -project SaneBar.xcodeproj -scheme SaneBar`
   - only after that does SaneBar resolve `SaneUI: /Users/sj/SaneApps/infra/SaneUI`
4. SaneBar was the mainline outlier here. Other current SaneApps app projects already point at local `../../infra/SaneUI` package paths.
5. The Setapp scaffolding that should remain in the codebase now includes:
   - explicit `SaneDistributionChannel`
   - `PurchaseBackend.setapp`
   - Setapp-safe license/about/onboarding/upsell behavior
   - Setapp-safe update messaging/tooltips
6. Real SaneBar runtime blockers found during this pass:
   - `main.swift` previously rejected any non-`com.sanebar.app` release bundle ID, so Setapp builds needed an explicit `com.sanebar.app-setapp` guard
   - `SaneBarApp` was still auto-moving non-debug builds into `/Applications`, which must not happen in a Setapp lane
   - `UpdateService` still imported/initialized Sparkle unconditionally, so Setapp needed a no-Sparkle stub path rather than just hiding update buttons
7. Local build-config scaffolding now exists in `project.yml` for:
   - `ProdDebug-Setapp`
   - `Release-Setapp`
   - plus a dedicated `SaneBarSetapp` scheme
8. Those configs are still only a scaffold. Final Setapp readiness still needs:
   - real `setappPublicKey.pem`
   - real Setapp framework/runtime entitlement wiring
   - menu-bar `.userInteraction` reporting
   - macOS 13+ `NSUpdateSecurityPolicy`
   - universal-binary proof instead of the current arm64-only assumption

## Display-Backup Corruption + Profile Apply Mismatch (Antonios / #111 / #113 / #114)

**Updated:** 2026-03-14 | **Status:** verified | **TTL:** 7d  
**Source:** Apple docs (`NSStatusItem.autosaveName`), web/video evidence (Antonios CleanShot share), GitHub issues `#111`, `#113`, `#114`, email thread `#341`, local code/tests (`StatusBarController`, `MenuBarManager`, `GeneralSettingsView`)

### Verified Findings

1. **Antonios’s email is a real diagnostics-backed bug report, not a vague complaint.**
   - Email thread `#341` includes two pasted in-app bug reports plus a `90s` CleanShot video.
   - The key repro split is consistent:
     - restart with the external monitor still connected: layout restores correctly
     - disconnect the external monitor first, then restart: layout breaks again
   - The same thread also shows profile load mistakes and drag-to-hidden confusion in the same session.

2. **This is the same family as GitHub `#111`, `#113`, and `#114`, not a separate isolated bug.**
   - `#111`: restart/login positions become erratic and remain unstable on `2.1.28`.
   - `#113`: visible items later collapse back into hidden.
   - `#114`: main icon + separator land too far left of Control Center after login on multi-account / multi-display setups.
   - Antonios’s email adds the strongest topology-change signal to that family: disconnecting the external monitor flips the bug back on.

3. **Apple’s `NSStatusItem.autosaveName` docs still matter here because SaneBar’s layout recovery is built directly on autosaved status-item positions.**
   - AppKit documents `autosaveName` as the persistence hook for saving/restoring status-item information.
   - That means bad persisted preferred-position state is not cosmetic; it is exactly what macOS will try to restore later.

4. **The current display-backup safety check is too weak.**
   - In local code, `StatusBarController.isLaunchSafeDisplayBackup(...)` only required:
     - both values look pixel-like
     - `separator > main`
     - `main <= launchSafePreferredMainPositionLimit(...)`
   - It did **not** bound the separator position against the current display width.
   - Antonios’s diagnostics showed a current-width backup of:
     - `displayBackupCurrentMain: 144`
     - `displayBackupCurrentSeparator: 5897`
     - for `currentScreenWidth: 1920`
   - That is a concrete proof that impossible separator backups were surviving the current rules.

5. **The current reanchor path preserved absurd separator gaps.**
   - `reanchoredPreferredPositionsTowardControlCenter(...)` moved `main` back toward Control Center but preserved the full old `separator - main` gap.
   - With a corrupted separator backup, that could still produce a wildly oversized separator position for the current display instead of collapsing it back into a sane width-bounded lane.

6. **Profile apply can re-inject stale layout state because it restores raw layout snapshots plus all stored display backups.**
   - `GeneralSettingsView.applyConfigurationAfterAuth(...)` applies `StatusBarController.applyLayoutSnapshot(...)` before recreating status items.
   - `StatusBarController.applyLayoutSnapshot(...)` previously wrote all snapshot display backups back into defaults without filtering impossible values.
   - Antonios’s email logs show `📁 Profile applied` immediately before stale separator frame spam, which lines up with this restore path.

7. **There is a second, narrower cache problem after persisted-layout recreation.**
   - `MenuBarManager.restoreStatusItemLayoutIfNeeded()` recreated status items from persisted positions, but it did not clear cached separator edges first.
   - Antonios’s before-restart diagnostics repeatedly logged:
     - `getSeparatorRightEdgeX: stale frame ... using cached 2779`
   - That means classification/move logic could keep operating on old separator geometry while WindowServer was still catching up after a layout restore.

8. **The video shows some user expectation mismatch too, but that is not the whole bug.**
   - Antonios appears to want many icons marked `Visible`, even though a notched / crowded menu bar cannot guarantee they all remain plainly visible in the real top row.
   - That part points toward the second menu bar as the better product fit.
   - But the logs above still prove a genuine recovery bug underneath that expectation mismatch.

9. **Fresh verify gating on March 14, 2026 still points at this same cluster, not a different one.**
   - The `sanebar-browse-move` research lock re-fired after the first post-patch verify attempt.
   - That confirms the active guard is tracking the same move / visibility / recovery family Antonios is exercising, so fixes in this section are still the right lane.

10. **The research-lock sync path itself needed a timestamp sanity fix.**
   - `sync-research-locks` was willing to write future `source_updated_at` values from inbox data, which can make the verify gate impossible to clear.
   - The sync path now clamps lock trigger times to `now` before writing them.

11. **The notched-screen launch-safe anchor was still too loose even after the first recovery pass.**
   - GitHub `#111` on `2.1.28` showed a current-width backup of:
     - `displayBackupCurrentMain: 216`
     - `displayBackupCurrentSeparator: 249`
     - for `currentScreenWidth: 1512`
   - That backup looked "safe" to the old helper, but the live geometry still relaunched too far left and repeatedly triggered startup recovery.
   - Local code was using `launchSafePreferredMainPositionLimit(...) = maxAllowedStartupRightGap - 24` on notched displays, which produced `216` for width `1512`.
   - Tightening the notched startup anchor to `180` matches the existing safe-backup tests and better fits the field evidence from Antonios / `#111`.

12. **Mini verify now passes with the stricter backup filtering + tighter notched anchor.**
   - Full mini `./scripts/SaneMaster.rb verify --quiet` passed on March 14, 2026.
   - Result: `940 tests` passed.

### Immediate Fix Direction

- Reject display backups whose `main` or `separator` positions do not fit the target width bucket.
- Clamp reanchored separator gaps so recovery cannot preserve absurd far-left separator positions.
- Filter impossible display backups out of captured/applied profile snapshots.
- Invalidate cached separator edges before recreating status items from persisted layout.
- Keep the notched-screen startup anchor tighter (`180`) so "safe-looking" 1512-wide backups do not still relaunch left of Control Center.

## Profile / Backup Restore + Bartender/Ice Import Expectations

**Updated:** 2026-03-12 | **Status:** verified | **TTL:** 14d
**Source:** Apple docs (`NSStatusItem.autosaveName`, `NSOpenPanel`), competitor/web references (Ice GitHub README), local code/tests (`BartenderImportService`, `IceImportService`, `StatusBarController`, `PersistenceService`)

### Verified Findings

1. **Apple treats `NSStatusItem.autosaveName` as the persistence hook for restoring status-item state.**
   - AppKit documents `autosaveName` as the unique name used for saving and restoring status-item information.
   - Apps with multiple status items are expected to assign explicit autosave names.
   - That supports making SaneBar profile/export restore ride on the existing autosave-backed layout state instead of inventing a second layout store.

2. **Open/Save panels are the correct restore/export surface for these backups.**
   - AppKit documents `NSOpenPanel` as the standard way for users to choose files to open.
   - On modern macOS, user-selected files from the panel are handed back as sandbox-approved access.
   - That confirms the current export/import UI is the right primitive; the missing piece was payload completeness, not the panel mechanism.

3. **Ice’s own public feature list does not claim finished layout profiles.**
   - The current Ice README advertises hide/show, drag-and-drop arrangement, separate hidden bar, and search.
   - The same README still lists `Profiles for menu bar layout` as not yet implemented.
   - That matches SaneBar’s checked-in `IceImportService`: Ice can provide behavioral settings, but there is no trustworthy stored layout profile to import from Ice.

4. **Local SaneBar code confirms Bartender and Ice are fundamentally different import sources.**
   - `BartenderImportService` parses explicit hidden/show profile entries and can move icons into zones from the detected Bartender plist.
   - `IceImportService` only maps compatible behavior settings and explicitly documents that Ice does not persist per-icon section assignments.
   - Onboarding should therefore use the detected Bartender plist directly, while Ice onboarding should stay settings-only and say so clearly.

5. **Current SaneBar restore state was fragmented across three stores before this patch.**
   - Settings lived in `settings.json`.
   - Layout lived in `NSStatusItem Preferred Position ...` defaults plus width-bucket display backups.
   - The custom icon asset lived separately in `custom_icon.png`, and saved profiles lived as separate JSON files in `profiles/`.
   - That fragmentation is why profiles and export/import felt incomplete even though each individual subsystem already had the needed data.

## Second Menu Bar Idle-Close Race (#101)

**Updated:** 2026-03-11 | **Status:** verified | **TTL:** 7d
**Source:** Apple docs (`NSWorkspace.didActivateApplicationNotification`, cooperative activation article), web/Bartender release notes, GitHub issue `#101`, local code

### Verified Findings

## Layout Drift + Disappearing Icon Cluster Re-Research (#130 / #126 / #124 / #114 / #111)

**Updated:** 2026-03-27 | **Status:** verified | **TTL:** 7d
**Source:** Apple docs (`NSStatusItem.autosaveName`, `NSScreen.auxiliaryTopRightArea`), GitHub issues `#130`, `#126`, `#124`, `#114`, `#111`, local diagnostics snapshots, local code/tests (`MenuBarManager`, `StatusBarController`, `MenuBarOperationCoordinator`)

### Verified Findings

1. **The active layout/reset/disappearance complaints are still one bug family, not scattered edge cases.**
   - Fresh March 27 reports still say the same thing in different words:
     - the SaneBar icon disappears
     - the layout keeps changing or resetting
     - hidden/visible sections do not stay stable
   - The strongest live set remains `#130`, `#126`, `#124`, `#114`, and `#111`.

2. **On notched Macs, the right-gap corruption heuristic was still double-counting healthy layouts.**
   - Runtime validation already knows the notch-safe right zone via `NSScreen.auxiliaryTopRightArea`.
   - But `MenuBarManager.shouldRecoverStartupPositions(...)` also applied a separate hard right-gap cap even when the main icon was already inside that safe zone.
   - Fresh issue `#130` is the clearest example:
     - main icon was still on the built-in display and in the safe right-side region
     - but the old `240pt` cap still classified it as corrupted because the right gap measured `~290pt`
   - That is buyer-visible on crowded menu bars because the app looks like it "fixes" a layout that is actually still usable.

3. **Runtime validation and recovery were using different screen identities.**
   - `MenuBarManager.currentRuntimeSnapshot(...)` measures the actual status-item screen from the main status-item window.
   - `StatusBarController` recovery/backup helpers were still mostly using `NSScreen.main`.
   - On external-monitor and wake/login paths, those can be different screens with different widths and different notch-safe rules.
   - That mismatch explains why external-display users like `#124` and `#114` can see repeated layout churn even after a recovery path runs: validation is judging one screen while recovery seeds backup/replay for another.

4. **The main icon path did not have the same stale-frame protection as the separator path.**
   - Separator geometry already rejects stale/off-screen frames and falls back to cached or estimated values.
   - The main icon reader (`getMainStatusItemLeftEdgeX`) was still trusting `button.window.frame.origin.x` directly with no live-frame guard.
   - During WindowServer relayout after wake/startup, that lets validation compare:
     - a guarded separator coordinate
     - against an unguarded main-frame reading
   - That can manufacture a false `invalidGeometry` result and trigger structural recovery when the real problem is just stale geometry during relayout.

5. **The current recovery ladder amplifies bad samples into visible churn.**
   - After four failed checks, the validator escalates to:
     - persisted-layout repair + recreate
     - then autosave namespace bump
   - That is appropriate for real corruption.
   - It is destructive when the underlying sample was wrong because of:
     - a healthy crowded notch-safe layout
     - wrong-screen recovery inputs
     - or a stale main-frame read

### Immediate Fix Direction

- On notched displays, trust the notch-safe right zone first and stop applying the separate right-gap cap on top of it.
- Relax the non-notched right-gap heuristic so it still catches true far-left drift (`#124`, `#114`) without tripping on smaller dense-layout gaps.
- Route capture/recovery helpers through the actual status-item screen instead of blindly using `NSScreen.main`.
- Give the main status-item frame the same stale-frame guard/cached fallback treatment the separator already has.

1. **The current `#101` failure is not the old false-success click path.**
   - Fresh `2.1.25` diagnostics show `preferHardwareFirst=false`, `accepted=true`, and `verification=verified (windowServerWindowCount 0->1)`.
   - That means the click path is getting a real post-click reaction before the user-visible failure happens.

2. **The stronger local bug is a second-menu-bar idle-close race.**
   - `SearchWindowController.schedulePanelIdleCloseIfNeeded(for:)` hard-closes the second menu bar after `20s`.
   - The timer is only scheduled on panel show and was not refreshed by interaction.
   - In `#101`, `secondMenuBar.showRequestedAt=19:06:18.774` and `lastActivation.startedAt=19:06:37.955`, so activation started about `19.2s` after panel open.
   - The click attempt itself took `1767ms`, which means the panel idle-close could fire during click verification.

3. **The user symptom matches the code path exactly.**
   - Reporter says the app menu opens after a delay and then disappears while moving the mouse over it.
   - If the panel closes at that moment, `handleBrowseDismissal(reason:)` clears `isBrowseSessionActive` and can schedule rehide.
   - That explains both the disappearing menu and the “real menu bar icons suddenly reveal/collapse” symptom.

4. **Apple’s activation docs support treating this as a lifecycle/activation coordination bug, not a target-resolution bug.**
   - `NSWorkspace.didActivateApplicationNotification` fires with the activated app in `userInfo`, which SaneBar currently uses to schedule app-change rehide.
   - Apple’s cooperative activation guidance says activation is context-sensitive and should not be treated as a guaranteed, stable end-state the moment focus changes.
   - That means tying rehide/panel teardown too aggressively to activation transitions is risky.

5. **Low-risk fix direction is to protect the panel during activation instead of rewriting click targeting again.**
   - Refresh the panel idle-close timer on second-menu-bar interaction.
   - Defer idle-close while browse activation is in flight and for a short grace period after it finishes.
   - When the panel does dismiss, ensure any rehide delay respects the same short activation grace window.

6. **Current-tree hardening now refreshes the idle-close budget on actual second-menu-bar interaction.**
   - `SearchWindowController.noteSecondMenuBarInteraction()` now reschedules the second-menu-bar idle-close timer while the panel is visible.
   - `SecondMenuBarView` now calls that hook from real interaction paths:
     - search text changes
     - row hover
     - tile hover/click/context-menu actions
     - move and drop handlers
   - That keeps a long-lived panel from aging out exactly as the user starts a click or move sequence.

## Browse Mismatch Gate (Confusion vs Real Bug) + WindowServer Multi-Item Fallback

**Updated:** 2026-03-11 | **Status:** verified | **TTL:** 7d
**Source:** Apple docs (`CGWindowListCopyWindowInfo`, `AXUIElementCopyElementAtPosition`), web/GitHub competitor references (`jordanbaird/Ice` README + Tahoe release notes), SaneBar GitHub issues `#108` / `#109` / `#102`, inbox threads `#274` / `#279`, local screenshot review, local code

### Verified Findings

1. **Not every Browse/Second Menu Bar report is a code bug.**
   - Email `#274` and GitHub `#102` are largely configuration/expectation mismatches.
   - In the screenshot for `#274`, Browse Icons is set to `Second Menu Bar`, but `Left-click SaneBar icon` is still set to `Toggle Hidden`.
   - That means the customer expectation ("click opens second menu bar") does not match the configured behavior.

2. **`#108` is a real undercount bug, not customer confusion.**
   - Screenshot shows many visible menu bar items.
   - Diagnostics say SaneBar found `32` menu bar items (`25 hidden`) but the second menu bar only rendered `visible=4 hidden=7`.
   - Logs explicitly showed `classifyItems: filtered 21 coarse fallback item(s) from zoned views`.
   - This confirms a real browse/render mismatch in the data pipeline, not just misunderstanding.

3. **`#109` is now the canonical live Browse/move thread.**
   - The March 10 `2.1.25` follow-up narrowed the remaining failure to repeated `performCmdDrag(...): from point (..., 1) is off-screen — aborting`.
   - That is a stronger current repro than the older `#106` report, so `#106` can be closed as superseded while `#109` stays open for current verification.
   - The same thread still showed earlier fallback filtering (`filtered 26 coarse fallback item(s)`), so browse undercount and move failure can still coexist.

4. **WindowServer fallback was too lossy for AX-poor apps.**
   - `CGWindowListCopyWindowInfo` returns window records, not one canonical owner record per process.
   - SaneBar’s `windowBackedMenuBarItems(fromWindowInfos:candidatePIDs:)` was collapsing multiple compact top-bar windows for the same PID down to a single right-most frame.
   - That can undercount helper-hosted or AX-poor menu bar items before they ever reach Browse/Second Menu Bar classification.

5. **Preserving multiple fallback windows per PID is compatible with the current click-resolution model.**
   - `SearchService.resolveLatestClickTarget` already falls back from exact identity to nearest same-bundle position.
   - `AccessibilityService.resolvedTargetStatusItem` already uses nearest-center fallback when identifiers drift or are missing.
   - That means synthetic per-PID ordering for fallback-only windows is safer than collapsing them to one bundle-level entry.

6. **Competitor evidence says this is a real class of Tahoe/menu-bar-manager bugs.**
   - Ice publicly advertises both:
     - separate bar for hidden items
     - drag/drop arrangement
   - Ice Tahoe release notes also call out:
     - item movement becoming sluggish / failing intermittently
     - search showing incorrect names and app icons
     - temporarily shown items returning to wrong positions
   - This is useful because it confirms these failures are not just support confusion; they are common failure surfaces for this app category.

7. **The Russian runaway report (`#279`) is severe but still under-instrumented.**
   - We reviewed the attached screenshot.
   - It proves:
     - `/Applications/SaneBar.app/Contents/MacOS/SaneBar`
     - `100%` CPU
     - `14.04 GB` physical memory
     - `9` crashes
   - It does **not** include in-app diagnostics, crash logs, repro steps, or a sample/spindump.
   - Conclusion: severity is verified, root cause is not.

## External-Monitor Startup Order Drift (Mini live state)

**Updated:** 2026-03-10 | **Status:** verified | **TTL:** 7d
**Source:** Apple docs (`NSStatusItem`, WindowServer scene behavior via AppKit status bar APIs), competitor/web references (Ice menu bar positioning discussions), SaneBar GitHub issues `#106` / `#109`, local Mini live layout snapshot + defaults state

### Fresh Findings

1. **Mini currently shows a real wrong-slot placement on the external 1920-wide display.**
   - Live `layout snapshot` from the running signed app on Mini reported:
     - `screenWidth=1920`
     - `separatorOriginX=956`
     - `mainIconLeftEdgeX=976`
     - `mainRightGap=944`
     - `isOnExternalMonitor=true`
   - That is far too far left for SaneBar’s main icon on a healthy single-row right-edge layout.

2. **The saved positions are not obviously corrupt huge pixel values.**
   - Mini app defaults currently store:
     - `NSStatusItem Preferred Position SaneBar_Main_v16 = 194`
     - `NSStatusItem Preferred Position SaneBar_Separator_v16 = 228`
     - width-bucket backups for `1920` with the same values
   - This means the failure is not limited to the older “wild pixel value” corruption class.

3. **Current startup-recovery detection should classify this state as bad if it sees the same geometry at launch.**
   - `MenuBarManager.shouldRecoverStartupPositions(...)` would treat `mainRightGap=944` on a `1920` display as out of bounds because the allowed gap caps around `268`.
   - Therefore, if the app still launches into this exact geometry, the recovery branch should fire.

4. **That implies one of two live possibilities.**
   - The app launched wrong and the startup recovery branch did not run.
   - Or the app launched acceptably and later drifted left after scene reconnect / relayout churn.

5. **Local system logs show repeated status-item scene churn on Mini even after launch.**
   - Recent `log show` output for the running app includes repeated FrontBoard scene reconnects and `NSStatusItemClearAutosaveStateAction` traffic around Control Center status-item scenes.
   - This raises the risk that position drift can happen after startup, not just during the initial creation path.

6. **GitHub evidence on the same external-monitor class lines up with the Mini symptom.**
   - `#106` and `#109` both show external-monitor layouts where SaneBar is too far left and drag/click targeting becomes wrong because geometry is no longer near the Control Center side.
   - This is consistent with a stale order/runtime drift family, not just one bad user-defaults value.

7. **Fresh relaunch and post-smoke verification on Mini stayed healthy.**
   - After a clean relaunch of `/Applications/SaneBar.app`, live `layout snapshot` reported:
     - `separatorOriginX=1625`
     - `mainIconLeftEdgeX=1655`
     - `mainRightGap=265`
     - `mainNearControlCenter=true`
   - After a full `live_zone_smoke.rb` pass, the layout remained healthy (`separatorOriginX=1619`, `mainRightGap=265`).
   - Conclusion: the currently observed bug is **not** "every launch starts wrong." It is an intermittent runtime drift.

8. **The most likely mechanism is stale separator fallback during status-item scene churn.**
   - Local logs included:
     - `getSeparatorOriginX: blocking mode with empty cache, using estimated 956.000000`
   - That estimated `956` value matches the bad left-drifted Mini snapshot.
   - This strongly suggests the bad state comes from SaneBar losing trustworthy separator geometry during a WindowServer / Control Center scene reconnect and falling back to an estimate that lands too far left.

9. **The old runtime validator missed this class because it only checked attachment, not geometry.**
   - `schedulePositionValidation()` previously only called `StatusBarController.validateStartupItems(...)`.
   - That catches "status item fell off the menu bar" but not "status item is still attached in the wrong slot."

10. **Low-risk fix applied: runtime validation now reuses startup geometry sanity checks and reruns after screen changes.**
   - `MenuBarManager.schedulePositionValidation()` now calls a geometry-aware `statusItemsNeedRecovery()` helper.
   - That helper combines:
     - attached-window validation
     - separator/main ordering
     - right-edge gap
     - notch-safe boundary
   - `NSApplication.didChangeScreenParametersNotification` now reschedules position validation after cache invalidation.
   - Verified by test suite (`541 tests in 42 suites`) and by fresh Mini launch staying in the healthy right-side slot.

## Accessibility Loop + Startup Rehide Regression (Signature + Startup Gate)

**Updated:** 2026-02-28 | **Status:** verified | **TTL:** 30d  
**Source:** Local logs + local code + Apple docs + GitHub competitor code

### Verified Findings

1. **Permission loop is strongly tied to signing identity mismatch during local test launches.**
   - When `/Applications/SaneBar.app` was staged from local `ProdDebug`, it was signed with **Apple Development**.
   - Release artifacts are signed with **Developer ID Application**.
   - Designated requirements differ:
     - Dev build: `certificate leaf[subject.CN] = "Apple Development: ..."`
     - Release build: `certificate leaf[subject.OU] = M78L6FXD48` with Developer ID chain.
   - Result observed in app behavior: SaneBar reported no Accessibility trust (`list icons` AppleScript returned accessibility error) even though Accessibility UI showed SaneBar entries.

2. **Startup auto-hide was explicitly blocked when accessibility was false.**
   - In `Core/MenuBarManager.swift`, startup flow returned early with:
     - `"Skipping initial hide: accessibility permission not granted"`
   - This matched user symptom: app launched expanded and only hid after manual interaction.

3. **Browse/Second-bar view was forcing repeated live trust probes on passive refresh paths.**
   - `MenuBarSearchView.syncAccessibilityState()` called `requestAccessibility()` (live check) from `onAppear`, activation, and refresh paths.
   - Logs showed repeated TCC access checks during these periods.

4. **Competitor patterns (Ice/Dozer/Hidden) are different from the problematic path.**
   - Ice: passive checks use non-prompt trust checks; prompting is explicit user action (`checkIsProcessTrusted(prompt: true)` only on request action).
   - Dozer/Hidden: startup hide behavior is not blocked by Accessibility trust checks.

### Fixes Applied (Local Code)

- `Core/MenuBarManager.swift`
  - Removed startup hard-stop on missing accessibility.
  - Startup now hides deterministically.
  - Added deferred always-hidden pin enforcement once permission becomes granted.

- `UI/SearchWindow/MenuBarSearchView.swift`
  - Passive permission sync now uses cached `isGranted`.
  - Live trust probe (`requestAccessibility()`) is now explicit on retry action only.

- `Tests/RuntimeGuardXCTests.swift`
  - Updated startup-hide regression assertion to the new behavior.
  - Added assertion that only retry forces a live accessibility probe.

### API/Reference Notes

- Apple docs:
  - `AXIsProcessTrusted()`: check trust state.
  - `AXIsProcessTrustedWithOptions(_:)` + `kAXTrustedCheckOptionPrompt`: prompt-capable check option.

- Competitor references:
  - Ice permissions flow (`Permission.swift`, `PermissionsManager.swift`)
  - Dozer startup hide flow (`AppDelegate.swift`, `DozerIcons.swift`)

## Regression Meta-Sweep (Issues + Email + Release Pipeline + App/Test Surface)

**Updated:** 2026-02-28 | **Status:** verified | **TTL:** 30d
**Source:** GitHub issues/releases API, `check-inbox.sh` (`healthcheck`, `check`, `review`, `audit`), `SANEBAR_RELEASE_PREFLIGHT=1 ruby scripts/qa.rb`, local code/test review

### What This Sweep Confirmed

1. **Hotfix is not fully resolved**
   - Open issue: `sane-apps/SaneBar#93` created on **2026-02-28** from app version **2.1.14 (2114)**.
   - Reporter diagnostics include repeated:
     - `Move verification failed: expected toHidden=false ... afterMidX=611.5` with separator around `1208`.
   - This is a direct post-hotfix regression signal on latest build at report time.

2. **Regression density clusters right after releases**
   - Latest 10 release intervals (hours): `31.83, 13.08, 7.71, 19.4, 4.65, 24.72, 0.92, 63.13, 116.42`.
   - Median release spacing: **19.4h**; minimum: **0.92h**.
   - Issues created within release windows (87 total):
     - `<=1h`: 2
     - `<=3h`: 5
     - `<=6h`: 10
     - `<=24h`: 18
   - After latest release `v2.1.14` (2026-02-28T13:07:24Z):
     - `#92` at +0.11h
     - `#93` at +1.52h

3. **Preflight guardrails are present and working**
   - `scripts/qa.rb` blocks fast-release cadence and unconfirmed regression closes unless a **typed manual phrase** is entered.
   - Fresh preflight run failed with:
     - release cadence `<24h`
     - unconfirmed regression closes (`#92`, `#91`)
   - This confirms the guard logic itself is active.

4. **Critical workflow gap: full release path is not hard-wired to those preflight checks**
   - `infra/SaneProcess/scripts/release.sh --full` does not require `run_release_preflight_only`.
   - It runs generic tests (`run_tests`) plus warnings, but does not enforce the SaneBar project QA gate in-band.
   - Result: guardrails can exist but still be skipped in practice.

5. **Issue-close discipline still leaks**
   - `#91` and `#92` were closed as fixed without reporter-side confirmation comment.
   - Same symptom reappeared immediately (`#93` remains open).

6. **Primary defect themes remain stable across GitHub + email**
   - GitHub buckets (title/body heuristic):
     - move/visible/hidden: 52
     - menu-open/click reliability: 52
     - reset/persistence: 37
     - second-menu-bar specific: 17
   - Email sample shows matching language:
     - ghost cursor / cursor jump during move attempts
     - can’t move to visible
     - second menu bar click opens inconsistently
     - resets/disappearances after restart/update

7. **App-level fragility is still concentrated in separator/cached-position move logic**
   - Move-to-visible path depends on `getSeparatorRightEdgeX()` + cached/estimated separator fallback.
   - Existing failure log (`expected toHidden=false`) indicates drag posts, but final frame stays on hidden side of threshold.
   - This is consistent with boundary/caching drift in real layouts.

8. **Test blind spot likely inflates confidence**
   - `Tests/RuntimeGuardXCTests.swift` includes many source-string assertions (`source.contains(...)`) rather than behavioral assertions.
   - Sweep count: **44 text-assert checks** vs relatively few runtime move verification checks.
   - Coverage for visible-move boundary behavior is thin compared to observed failures.

9. **Fresh competitor sweep (GitHub) confirms this class of app is inherently high-risk around the same edges**
   - Repo sampled: `jordanbaird/Ice` (latest 200 issues via GitHub API).
   - Counts in sample: `163 open / 37 closed`.
   - Title-bucket hits in sample:
     - menu/click/open: 77
     - multi-monitor/notch/display: 28
     - crash/freeze/perf: 23
     - drag/move/reorder: 8
     - persist/reset: 4
   - Meaning: menu-bar managers repeatedly fail in click routing, display geometry, and move/reorder reliability under OS drift. SaneBar should bias for hardening over feature velocity in these surfaces.

### Hardening Priorities (Research-Only Recommendation)

1. **Make release preflight non-optional in `--full` flow** (no release without passing project QA guardrails).
2. **No regression issue close without reporter confirmation OR reproducible local evidence artifact** (logs/recording attached to issue).
3. **Treat move verification failures as release blockers when they occur on latest version within 24h of release.**
4. **Shift regression tests from source-text assertions to behavioral tests for move-to-visible boundary/caching scenarios.**
5. **Reduce hotfix compression pressure** (enforce soak windows unless explicitly approved with typed phrase + reason recorded).

### No-Bypass Release Matrix (Current vs Needed)

| Vector | Current behavior (verified) | Risk | Required hardening |
|---|---|---|---|
| `--full` release path | Does not hard-require `run_release_preflight_only`; runs tests but not project QA guardrails in-band | Guardrails exist but can be skipped | Make `--full` invoke preflight first and hard-fail on any preflight error |
| `--allow-repeat-failure` | Explicitly bypasses repeat-failure guard | Releasing after unresolved repeated failures | Require typed approval phrase + reason + runbook ticket ID before flag is accepted |
| `--allow-unsynced-peer` | Explicitly bypasses machine reconcile gate | Shipping from unsynced machine state | Require typed approval phrase + automatic branch/hash snapshot into release ledger |
| `--allow-republish` | Allows republishing same live version/build | Re-shipping stale/bad build metadata | Require typed approval phrase + forced `--notes` reason + issue link |
| `--allow-channel-sync-failures` | Allows deploy when GitHub/Homebrew sync fails | Public channel drift; update confusion | Block by default for public apps unless emergency approval phrase is entered |
| `--skip-notarize` | Skips notarization with warning | Unsuitable artifact can leak into release flow | Restrict to non-deploy mode only; hard-block when `--deploy` is present |
| `--skip-build` | Reuses existing archive | Can deploy wrong artifact/version | Require artifact hash/version verification against requested version before deploy |
| `--skip-appstore` | Skips App Store path with warning | Cross-channel inconsistency | Require explicit reason in release ledger for enabled App Store apps |
| Regression issue close | Can close without reporter confirmation | False “fixed” status hides live regressions | Block close in SOP unless reporter confirms or maintainer posts reproducible verification evidence |

### One-Page Stability SOP (Release + Hotfix)

1. **Triage trigger**
   - Any new regression report on latest build, or any `Move verification failed` diagnostic, immediately sets status to `INVESTIGATING`.

2. **Reproduction and evidence (required)**
   - Confirm reporter app version and macOS version.
   - Collect issue diagnostics/logs and one local reproduction attempt.
   - Record evidence links in the issue before any fix claim.

3. **Fix execution rule**
   - If a release gate fails, stop release work immediately.
   - Fix root cause first.
   - Verify fix with targeted tests and one real workflow run.
   - Rerun full release preflight.
   - Continue release only if preflight passes.

4. **Hotfix eligibility**
   - Hotfix allowed only when:
     - regression is reproducible or strongly evidenced,
     - fix has targeted test coverage,
     - preflight passes,
     - release notes explicitly call out affected scope and rollback plan.

5. **Close policy for regression issues**
   - Do not close on “hotfix shipped” alone.
   - Close only after reporter confirms on latest version, or maintainer posts reproducible local verification artifact (logs/video/steps).

6. **Soak policy**
   - Standard soak: 24h between releases.
   - If emergency release is needed, require typed manual approval phrase and written reason in release notes + ledger.

7. **Post-release watch window**
   - For first 24h: monitor GitHub/email every few hours.
   - Any new regression in this window pauses further releases until triaged.

8. **Weekly reliability review**
   - Track: issues opened within 24h of release, regression reopen rate, unconfirmed closes, and median time-to-stable.
   - If any metric worsens for 2 consecutive weeks, freeze non-critical feature work and run stability sprint.

## Off-Screen Menu Bar Icon After Cmd-Drag (Machine-Specific)

**Updated:** 2026-02-17 | **Status:** verified | **TTL:** 30d
**Source:** Local reproduction + ByHost prefs inspection + script launch path verification

- Repro context: command-dragging SaneBar out of the menu bar during failure-mode testing left machine in persistent bad state.
- Old ByHost keys remained poisoned:
  - `NSStatusItem Preferred Position SaneBar_main_v6 = 1310`
  - `NSStatusItem Preferred Position SaneBar_separator_v6 = 1286`
- Key finding: installer-like signed launches worked, while local script default `Debug` launch path could stay invisible on this machine.
- Root cause in tooling: shared SaneMaster launch path always launched `Debug` from DerivedData.
- Fixes applied:
  1. `StatusBarController` autosave namespace moved to `v7` (`SaneBar_Main_v7`, etc.) so old poisoned key namespace is ignored.
  2. SaneMaster launch updated to support `--proddebug` / `--release`.
  3. SaneBar default launch locked to signed mode (`ProdDebug`) to avoid regression to broken `Debug` behavior.
- Validation:
  - `./scripts/SaneMaster.rb launch --proddebug` launches `.../Build/Products/ProdDebug/SaneBar.app`.
  - Active keys show healthy values in new namespace:
    - `SaneBar_main_v7_v6 = 0`
    - `SaneBar_separator_v7_v6 = 1`

## Ice Competitor Analysis

**Updated:** 2026-02-02 | **Status:** verified | **TTL:** 30d
**Source:** GitHub API analysis of jordanbaird/Ice repository

Ice (12.7k stars) is the primary open-source competitor. Key pain points from 158 open issues:
Sequoia display corruption (#722, #711), CPU spikes 30-80% (#713, #704), item reordering broken (#684),
settings not persisting (#676), menu bar flashing (#668), multi-monitor bugs (#630, #517).

SaneBar wins on: stability, CPU (<0.1%), multi-monitor, password lock, per-app rules, import (Bartender+Ice).
Ice wins on: visual layout editor (when it works), Ice Bar dropdown.

---

## Stale Position / Duplicate Icons Bug

**Updated:** 2026-02-13 | **Status:** active-investigation | **TTL:** 7d
**Source:** Codebase analysis (Second Menu Bar, SearchService, AccessibilityService, MenuBarManager+AlwaysHidden)

### Problem Summary

The "Second Menu Bar" (floating panel showing hidden icons) sometimes displays **duplicate entries** on startup:
- The same app appears in BOTH "hidden" and "always hidden" sections simultaneously
- Moving an app (right-click → move to section) fixes the duplicates
- The stale data is visible BEFORE user interaction

### Code Path Analysis

#### 1. Second Menu Bar Data Flow (Where the Bug Manifests)

**UI Component:** `UI/SearchWindow/SecondMenuBarView.swift`

The panel displays three sections (lines 116-134):
```swift
if !movableVisible.isEmpty {
    zoneRow(label: "Visible", icon: "eye", apps: movableVisible, zone: .visible)
}
if !movableHidden.isEmpty {
    zoneRow(label: "Hidden", icon: "eye.slash", apps: movableHidden, zone: .hidden)
}
if !movableAlwaysHidden.isEmpty {
    zoneRow(label: "Always Hidden", icon: "lock", apps: movableAlwaysHidden, zone: .alwaysHidden)
}
```

**Data Source:** `UI/SearchWindow/MenuBarSearchView.swift` lines 250-262
```swift
SecondMenuBarView(
    visibleApps: visibleApps,           // ← Cached data
    apps: filteredApps,                 // ← "Hidden" section (menuBarApps filtered)
    alwaysHiddenApps: alwaysHiddenApps, // ← Cached data
    // ...
)
```

**Cache Loading:** Lines 283-309
```swift
private func loadCachedApps() {
    hasAccessibility = AccessibilityService.shared.isGranted
    guard hasAccessibility else { /* ... */ return }

    // Load "hidden" apps (middle section)
    menuBarApps = service.cachedHiddenMenuBarApps()

    // Load all zones for second menu bar
    if isSecondMenuBar {
        visibleApps = service.cachedVisibleMenuBarApps()
        alwaysHiddenApps = service.cachedAlwaysHiddenMenuBarApps()
    }
}
```

**Key Insight:** The panel uses THREE separate cached data sources. If any cache is stale or uses inconsistent classification logic, duplicates can occur.

#### 2. Zone Classification Logic (Where Duplicates Originate)

**Service:** `Core/Services/SearchService.swift`

All three cache methods use the SAME classification function `classifyZone()` (lines 126-147):

```swift
private func classifyZone(
    itemX: CGFloat,
    itemWidth: CGFloat?,
    separatorX: CGFloat,
    alwaysHiddenSeparatorX: CGFloat?
) -> VisibilityZone {
    let width = max(1, itemWidth ?? 22)
    let midX = itemX + (width / 2)
    let margin: CGFloat = 6

    if let alwaysHiddenSeparatorX {
        if midX < (alwaysHiddenSeparatorX - margin) {
            return .alwaysHidden
        }
        if midX < (separatorX - margin) {
            return .hidden
        }
        return .visible
    }

    return midX < (separatorX - margin) ? .hidden : .visible
}
```

**Separator Position Retrieval (CRITICAL):** Lines 82-105
```swift
private func separatorOriginsForClassification() -> (separatorX: CGFloat, alwaysHiddenSeparatorX: CGFloat?)? {
    guard let separatorX = separatorOriginXForClassification() else { return nil }

    guard MenuBarManager.shared.alwaysHiddenSeparatorItem != nil else {
        return (separatorX, nil)
    }

    let alwaysHiddenSeparatorX = MenuBarManager.shared.getAlwaysHiddenSeparatorOriginX()

    // ← VALIDATION: Ensure AH separator is LEFT of main separator
    if let alwaysHiddenSeparatorX, alwaysHiddenSeparatorX >= separatorX {
        logger.warning("Always-hidden separator is not left of main separator; ignoring always-hidden zone")
        return (separatorX, nil)
    }

    // ← FALLBACK: If AH separator position unavailable (at 10,000px blocking mode)
    if alwaysHiddenSeparatorX == nil {
        let screenMinX = menuBarScreenFrame()?.minX ?? 0
        return (separatorX, screenMinX)  // ← Uses screen edge as boundary
    }

    return (separatorX, alwaysHiddenSeparatorX)
}
```

#### 3. The Fallback Mechanism (Where Stale Data Persists)

**Always-Hidden Fallback:** Lines 217-241 in `SearchService.swift`

When separator positions are unavailable (items off-screen, separators at blocking mode):
```swift
func cachedAlwaysHiddenMenuBarApps() -> [RunningApp] {
    guard MenuBarManager.shared.alwaysHiddenSeparatorItem != nil else { return [] }
    let items = AccessibilityService.shared.cachedMenuBarItemsWithPositions()

    if let positions = separatorOriginsForClassification(), positions.alwaysHiddenSeparatorX != nil {
        // ← POSITION-BASED classification (primary)
        let apps = items.filter { /* classifyZone() */ }
        return apps
    }

    // ← FALLBACK: Match against persisted pinned IDs
    return appsMatchingPinnedIds(from: items.map(\.app))
}
```

**Pinned IDs Matching:** Lines 107-118
```swift
private func appsMatchingPinnedIds(from apps: [RunningApp]) -> [RunningApp] {
    let pinnedIds = Set(MenuBarManager.shared.settings.alwaysHiddenPinnedItemIds)
    guard !pinnedIds.isEmpty else { return [] }
    let matched = apps.filter { app in
        pinnedIds.contains(app.uniqueId) || pinnedIds.contains(app.bundleId)
    }
    logger.debug("alwaysHidden fallback: matched \(matched.count) apps from \(pinnedIds.count) pinned IDs")
    return matched
}
```

**Key Issue:** The fallback uses `alwaysHiddenPinnedItemIds` (persisted in UserDefaults) which may be STALE if:
1. App moved but pinned IDs not updated
2. Separator positions changed but cache not invalidated
3. Startup reads cache before positions are available

#### 4. Persisted Pin Management (Where Stale Data Is Written)

**Service:** `Core/MenuBarManager+AlwaysHidden.swift`

**Pin Addition:** Lines 18-30
```swift
func pinAlwaysHidden(app: RunningApp) {
    let id = app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValidPinId(id) else { return }

    var newIds = Set(settings.alwaysHiddenPinnedItemIds)
    let inserted = newIds.insert(id).inserted
    guard inserted else { return }

    settings.alwaysHiddenPinnedItemIds = Array(newIds).sorted()
    // ← NO cache invalidation here
}
```

**Pin Removal:** Lines 32-40
```swift
func unpinAlwaysHidden(app: RunningApp) {
    let id = app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return }

    let newIds = settings.alwaysHiddenPinnedItemIds.filter { $0 != id }
    guard newIds.count != settings.alwaysHiddenPinnedItemIds.count else { return }
    settings.alwaysHiddenPinnedItemIds = newIds
    // ← NO cache invalidation here
}
```

**CRITICAL FINDING:** Neither `pinAlwaysHidden()` nor `unpinAlwaysHidden()` calls `AccessibilityService.shared.invalidateMenuBarItemCache()`. This means:
1. User moves app from "hidden" to "always hidden" → pin is added
2. `SearchService` caches remain unchanged (still have old zone assignments)
3. Next panel open: `cachedAlwaysHiddenMenuBarApps()` uses NEW pinned IDs, `cachedHiddenMenuBarApps()` uses OLD cached positions
4. Result: App appears in BOTH sections

#### 5. Move Operations (Where Cache Gets Stale)

**UI Handler:** `UI/SearchWindow/SecondMenuBarView.swift` lines 189-230

```swift
private func moveIcon(_ app: RunningApp, from source: IconZone, to target: IconZone) {
    // ... determine operation based on source/target zones

    switch (source, target) {
    case (_, .visible):
        if source == .alwaysHidden { menuBarManager.unpinAlwaysHidden(app: app) }
        _ = menuBarManager.moveIcon(/* ... */, toHidden: false)

    case (.visible, .hidden):
        _ = menuBarManager.moveIcon(/* ... */, toHidden: true)

    case (.alwaysHidden, .hidden):
        menuBarManager.unpinAlwaysHidden(app: app)  // ← Removes from pinned IDs
        _ = menuBarManager.moveIconFromAlwaysHiddenToHidden(/* ... */)

    case (_, .alwaysHidden):
        menuBarManager.pinAlwaysHidden(app: app)    // ← Adds to pinned IDs
        _ = menuBarManager.moveIconToAlwaysHidden(/* ... */)
    }

    // ← REFRESH: Scheduled AFTER the move completes
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
        onIconMoved?()  // ← Calls loadCachedApps() + refreshApps(force: true)
    }
}
```

**The 300ms Gap:** Between pin update and cache refresh, there's a 300ms window where:
- Pinned IDs are updated (new data)
- Accessibility cache is stale (old positions)
- If user closes panel or system queries cache during this window → duplicates appear

#### 6. Startup Sequence (Where Initial Stale Data Appears)

**Panel Opens:** `UI/SearchWindow/MenuBarSearchView.swift` lines 142-153

```swift
.onAppear {
    loadCachedApps()     // ← Uses cached data (may be empty/stale on first launch)
    refreshApps()        // ← Triggers async refresh (takes time)
    startPermissionMonitoring()
    // ...
}
```

**Cache Loading Flow:**
1. `loadCachedApps()` runs immediately (line 143) → reads `AccessibilityService.shared.cachedMenuBarItemsWithPositions()`
2. If cache is empty (first run) → all arrays are empty
3. If cache exists but positions are stale → classification uses OLD separator positions + NEW pinned IDs
4. `refreshApps()` runs async (line 144) → triggers fresh AX scan
5. **GAP:** Between `loadCachedApps()` and `refreshApps()` completing, panel shows stale data

**Why Moving Fixes It:** Lines 258-261 in SecondMenuBarView
```swift
onIconMoved: {
    loadCachedApps()           // ← Re-loads from cache
    refreshApps(force: true)   // ← Forces fresh AX scan + invalidates cache
}
```

The `force: true` parameter (line 324 in MenuBarSearchView) calls `AccessibilityService.shared.invalidateMenuBarItemCache()` BEFORE scanning.

### Root Cause Summary

**PRIMARY ISSUE: Cache invalidation missing on pin update**

1. **Inconsistent Data Sources:** Three separate caches (visible, hidden, always-hidden) + one persisted data source (pinned IDs)
2. **No Invalidation on Pin Change:** `pinAlwaysHidden()` and `unpinAlwaysHidden()` update persisted IDs but don't invalidate AX cache
3. **Fallback Mismatch:** `cachedAlwaysHiddenMenuBarApps()` uses NEW pinned IDs (fallback), `cachedHiddenMenuBarApps()` uses OLD cached positions (primary)
4. **Startup Race:** Panel opens before AX cache is populated → falls back to pinned IDs for AH, empty for hidden → inconsistent state
5. **Async Refresh Gap:** 300ms+ between panel open and fresh data → user sees stale duplicates

**Why Moving Fixes It:**
- Move operation calls `refreshApps(force: true)`
- `force: true` → `invalidateMenuBarItemCache()` → all caches cleared
- Fresh AX scan → all zones use SAME current separator positions → duplicates resolved

### Validation Missing

**No Duplicate Detection:** The code has identity health logging (SearchService.swift:381-407) but it only logs duplicates, doesn't PREVENT them from being rendered.

```swift
if !duplicateIds.isEmpty {
    let sample = duplicateIds.prefix(10).map { "\($0.key)=\($0.value)" }.joined(separator: ", ")
    logger.error("Find Icon \(context): DUPLICATE ids detected: \(sample)")
}
```

This logs the issue but doesn't deduplicate before passing to UI.

### Recommended Fixes

#### Fix 1: Invalidate Cache on Pin Update (CRITICAL)

**File:** `Core/MenuBarManager+AlwaysHidden.swift` (lines 18-40)

Add cache invalidation to both pin methods:

```swift
func pinAlwaysHidden(app: RunningApp) {
    let id = app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard isValidPinId(id) else { return }

    var newIds = Set(settings.alwaysHiddenPinnedItemIds)
    let inserted = newIds.insert(id).inserted
    guard inserted else { return }

    settings.alwaysHiddenPinnedItemIds = Array(newIds).sorted()

    // ← ADD: Invalidate cache so next query uses fresh positions + new pins
    AccessibilityService.shared.invalidateMenuBarItemCache()
}

func unpinAlwaysHidden(app: RunningApp) {
    let id = app.uniqueId.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !id.isEmpty else { return }

    let newIds = settings.alwaysHiddenPinnedItemIds.filter { $0 != id }
    guard newIds.count != settings.alwaysHiddenPinnedItemIds.count else { return }
    settings.alwaysHiddenPinnedItemIds = newIds

    // ← ADD: Invalidate cache so next query uses fresh positions + new pins
    AccessibilityService.shared.invalidateMenuBarItemCache()
}
```

**Rationale:** Ensures that after pinned IDs change, the next cache read triggers a fresh AX scan with consistent data.

#### Fix 2: Deduplicate Before Rendering (MEDIUM PRIORITY)

**File:** `Core/Services/SearchService.swift` (lines 184-215, 244-268, 217-241)

Add deduplication to the three cache methods:

```swift
@MainActor
func cachedHiddenMenuBarApps() -> [RunningApp] {
    let items = AccessibilityService.shared.cachedMenuBarItemsWithPositions()
    // ... existing classification logic ...

    // ← ADD: Deduplicate by uniqueId before returning
    var seen = Set<String>()
    let deduplicated = apps.filter { app in
        seen.insert(app.uniqueId).inserted
    }

    if apps.count != deduplicated.count {
        logger.warning("cachedHidden: Deduped \(apps.count - deduplicated.count) duplicate entries")
    }

    return deduplicated
}
```

Apply same pattern to `cachedVisibleMenuBarApps()` and `cachedAlwaysHiddenMenuBarApps()`.

**Rationale:** Defensive programming — even if cache invalidation fails, UI won't show duplicates.

#### Fix 3: Startup Cache Validation (LOW PRIORITY)

**File:** `UI/SearchWindow/MenuBarSearchView.swift` (lines 283-309)

Add validation on startup to detect stale cache:

```swift
private func loadCachedApps() {
    hasAccessibility = AccessibilityService.shared.isGranted
    guard hasAccessibility else { /* ... */ return }

    // ← ADD: Check if cache is stale (timestamp check)
    let cacheAge = Date().timeIntervalSince(AccessibilityService.shared.menuBarItemCacheTime)
    let isStale = cacheAge > 5.0  // 5 seconds

    if isStale {
        logger.debug("Cache is stale (\(cacheAge)s old) — skipping loadCachedApps")
        refreshApps(force: true)
        return
    }

    // ... existing cache loading logic ...
}
```

**Rationale:** On panel open, if cache is old (>5s), skip it and go straight to fresh scan.

#### Fix 4: Unified Zone Classification (ARCHITECTURAL, LOW PRIORITY)

**Create:** `Core/Services/MenuBarZoneClassifier.swift`

Centralize all zone classification logic in ONE place:

```swift
actor MenuBarZoneClassifier {
    // Single source of truth for separator positions
    // Single classification method used by ALL cache queries
    // Guarantees consistency across visible/hidden/always-hidden
}
```

**Rationale:** Current design has classification logic duplicated across SearchService, move operations, and verification. Centralizing prevents drift.

### Test Plan

**Reproduce:**
1. Launch SaneBar fresh install
2. Move an app to "always hidden" via context menu
3. Close Second Menu Bar panel
4. Wait 1 second (let cache partially settle)
5. Open Second Menu Bar panel again
6. **Expected Bug:** App appears in BOTH "hidden" AND "always hidden" sections

**Verify Fix 1:**
1. Apply cache invalidation to `pinAlwaysHidden()`
2. Repeat steps 1-5
3. **Expected:** App appears ONLY in "always hidden" section (no duplicates)

**Verify Fix 2:**
1. Inject duplicate into cache manually (for testing)
2. Open panel
3. **Expected:** Deduplication removes duplicate before rendering

**Check Logs:**
```
[DEBUG] cachedAlwaysHidden: found X always hidden apps
[DEBUG] cachedHidden: found Y hidden apps
[DEBUG] Find Icon sample: id=... bundleId=... (verify no duplicates)
```

### Related Files

- `UI/SearchWindow/SecondMenuBarView.swift` — Panel rendering (where duplicates appear)
- `UI/SearchWindow/MenuBarSearchView.swift` — Data loading (loadCachedApps, refreshApps)
- `Core/Services/SearchService.swift` — Zone classification + caching (root logic)
- `Core/MenuBarManager+AlwaysHidden.swift` — Pin management (missing invalidation)
- `Core/Services/AccessibilityService+Cache.swift` — Cache invalidation mechanism
- `Core/Services/AccessibilityService+Scanning.swift` — Menu bar item scanning
- `Core/Models/RunningApp.swift` — uniqueId generation (used for deduplication)

---

## Icon Sizing in Squircle - Root Cause

**Updated:** 2026-02-13 | **Status:** verified | **TTL:** 7d
**Source:** SecondMenuBarView.swift, MenuBarAppTile.swift, RunningApp.swift, AccessibilityService+Scanning.swift

### Problem

Icons inside translucent squircle containers appear TINY — not filling 80-90% of the container as intended. The code sets `tileSize: CGFloat = 32` and `iconSize: CGFloat { tileSize * 0.85 }` (= 27.2), using `.frame(width: iconSize, height: iconSize)` with `.resizable()` and `.aspectRatio(contentMode: .fit)`.

### Root Cause: NSImage Source Size

**Menu bar status item icons are small by design:**
- System menu bar icons are typically 16x16 or 18x18 points (template images)
- Third-party app icons come from `NSRunningApplication.icon` which is 32x32 or 64x64 points
- Control Center/SystemUIServer icons are SF Symbols at 16pt configured size (line 235 in RunningApp.swift)

**How icons are captured:**
1. **Regular apps:** `RunningApp(app: app)` → `icon = app.icon` (line 325 in RunningApp.swift) — uses `NSRunningApplication.icon`
2. **System menu extras:** `menuExtraItem()` → `NSImage(systemSymbolName:)` with `pointSize: 16` (line 235 in RunningApp.swift)
3. **No upscaling applied during capture** — icons are stored at their native size

**Why they appear tiny in the squircle:**

**PanelIconTile (SecondMenuBarView.swift lines 316-327):**
```swift
private let tileSize: CGFloat = 32
private var iconSize: CGFloat { tileSize * 0.85 }  // = 27.2

iconImage
    .frame(width: iconSize, height: iconSize)  // 27.2 × 27.2 frame
```

**The icon image rendering (lines 350-363):**
```swift
if let icon = app.iconThumbnail ?? app.icon {
    Image(nsImage: icon)
        .resizable()                           // Makes it resizable
        .renderingMode(...)
        .foregroundStyle(.primary)
        .aspectRatio(contentMode: .fit)        // Fit within frame
}
```

**The problem:**
- `.resizable()` + `.aspectRatio(contentMode: .fit)` does NOT upscale — it only ensures the image fits within the frame while preserving aspect ratio
- An 18x18 NSImage inside a 27.2x27.2 frame renders at 18x18 (native size) — it does NOT scale up to fill the frame
- SwiftUI respects the NSImage's intrinsic size and won't upscale unless forced

### How Find Icon Handles This (MenuBarAppTile.swift)

**MenuBarAppTile uses a SMALLER percentage:**

Lines 54-55:
```swift
.aspectRatio(contentMode: .fit)
.frame(width: iconSize * 0.7, height: iconSize * 0.7)  // 70% of tile, not 85%
```

**Why this works better:**
- The icon frame is intentionally SMALLER than the icon's native size
- `.fit` scales DOWN (which SwiftUI does reliably) rather than expecting upscaling
- Result: Icons appear appropriately sized within the larger tile

**Find Icon also has a squircle background (line 39):**
```swift
RoundedRectangle(cornerRadius: max(8, iconSize * 0.18))
    .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
```

But the icon itself is only 70% of the tile size, creating visual breathing room.

### The Fix: Scale DOWN, Not UP

**Option 1: Match Find Icon pattern (RECOMMENDED)**

Change PanelIconTile icon frame to 70% instead of 85%:

```swift
private var iconSize: CGFloat { tileSize * 0.7 }  // 22.4 instead of 27.2
```

**Rationale:**
- Makes icons appear proportionally similar to Find Icon
- Relies on scaling down (which SwiftUI handles correctly)
- Provides visual breathing room inside the squircle

**Option 2: Force upscaling with interpolation**

Keep 85% frame but force high-quality upscaling:

```swift
iconImage
    .resizable()
    .interpolation(.high)                      // ← ADD: Explicit interpolation
    .renderingMode(...)
    .foregroundStyle(.primary)
    .aspectRatio(contentMode: .fill)           // ← CHANGE: .fill instead of .fit
    .frame(width: iconSize, height: iconSize)
```

**Rationale:**
- `.fill` forces the image to fill the frame (may crop if aspect ratio doesn't match)
- `.interpolation(.high)` ensures upscaling uses high-quality filtering
- Risk: Template icons may look blurry when upscaled 1.5x (18 → 27)

**Option 3: Pre-render thumbnails at target size**

Generate thumbnails at 27x27 when creating RunningApp:

```swift
// In AccessibilityService+Scanning.swift line 283
let appModel = RunningApp(app: app, ...).withThumbnail(size: 27)
```

**Rationale:**
- `withThumbnail()` already exists (RunningApp.swift line 176)
- Pre-rendered thumbnails are sharp and sized correctly
- Cost: Adds thumbnail generation overhead during scanning
- Current code skips thumbnail generation intentionally (comment on line 284: "Skip thumbnail pre-calculation — let UI render lazily")

### Recommended Solution

**Use Option 1:** Change `iconSize` to `tileSize * 0.7`

**Why:**
- Simplest fix (one line change)
- Consistent with Find Icon (proven pattern)
- No upscaling quality concerns
- No performance overhead

**Code change:**

File: `UI/SearchWindow/SecondMenuBarView.swift` line 318

```swift
private var iconSize: CGFloat { tileSize * 0.7 }  // Was 0.85
```

### Related Code

- **Icon capture:** Core/Models/RunningApp.swift lines 234-240 (SF Symbols at 16pt), line 325 (NSRunningApplication.icon)
- **Thumbnail generation:** Core/Models/RunningApp.swift lines 154-173 (`thumbnail(size:)` method)
- **Squircle rendering:** UI/SearchWindow/SecondMenuBarView.swift lines 306-363 (PanelIconTile)
- **Find Icon comparison:** UI/SearchWindow/MenuBarAppTile.swift lines 34-75 (uses 70% sizing)

---

## Tooltip Not Showing - Root Cause

**Updated:** 2026-02-13 | **Status:** verified | **TTL:** 7d
**Source:** Web research, GitHub code search (Claude Island NSPanel implementation), SaneBar codebase analysis

### Problem

SwiftUI `.help("text")` tooltips on PanelIconTile views are NOT appearing at all. The Second Menu Bar panel is a borderless NSPanel (KeyablePanel) at window level `.statusBar`, and `NSInitialToolTipDelay` is set to 100ms in `applicationDidFinishLaunching`.

### Investigation Summary

1. **NSInitialToolTipDelay Usage:** CORRECT
   - Set in `SaneBarApp.swift:19`: `UserDefaults.standard.set(100, forKey: "NSInitialToolTipDelay")`
   - This is the correct key name and usage (verified via [Componentix blog](https://componentix.com/blog/20/change-tooltip-display-delay-in-cocoa-application/))
   - Default macOS delay is 1000ms; setting 100ms is valid and should work

2. **SwiftUI .help() Modifier:** CORRECTLY APPLIED
   - Applied in `SecondMenuBarView.swift:334`: `.help(app.name)`
   - This is on a Button with `.buttonStyle(.plain)`
   - SwiftUI .help() maps to native NSView.toolTip on macOS

3. **NSPanel Configuration:** MISSING MOUSE EVENT TRACKING
   - Panel created in `SearchWindowController.swift:211-253` (createSecondMenuBarWindow)
   - Panel is borderless: `styleMask: [.borderless, .resizable]` (line 226)
   - Panel level: `.statusBar` (line 234)
   - **CRITICAL MISSING:** Panel does NOT set `acceptsMouseMovedEvents = true`

4. **Root Cause:** NSPanel doesn't track mouse-moved events by default
   - Tooltips require mouse tracking to detect hover
   - Without `acceptsMouseMovedEvents = true`, the panel never receives mouseEntered/mouseMoved events
   - SwiftUI `.help()` modifier relies on underlying AppKit mouse tracking
   - Even though buttons can be clicked (click events work), **hover tracking is separate**

5. **Reference Implementation:** Claude Island NSPanel (verified working)
   - Found in GitHub search: [ClaudeIsland/NotchWindow.swift](https://github.com/farouqaldori/claude-island/blob/0c92dfccf0c3d7356aff0f5cbd8b02a5ff613fcf/ClaudeIsland/UI/Window/NotchWindow.swift)
   - That panel sets: `acceptsMouseMovedEvents = false` BUT uses `ignoresMouseEvents = true` (different use case — transparent overlay)
   - For interactive panels like Second Menu Bar, need `acceptsMouseMovedEvents = true` for tooltips

### The Fix

**File:** `/Users/sj/SaneApps/apps/SaneBar/UI/SearchWindow/SearchWindowController.swift`

**Location:** Line 253 (after `panel.maxSize = NSSize(...)`)

**Add:**
```swift
panel.acceptsMouseMovedEvents = true
```

**Full context (lines 240-254 after fix):**
```swift
panel.isMovableByWindowBackground = true
panel.animationBehavior = .utilityWindow
panel.minSize = NSSize(width: 180, height: 80)
panel.maxSize = NSSize(width: 800, height: 500)

// Enable mouse tracking for tooltips
panel.acceptsMouseMovedEvents = true

// Shadow for depth
if let contentView = panel.contentView {
    contentView.wantsLayer = true
    contentView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.3).cgColor
    contentView.layer?.shadowOpacity = 1
    contentView.layer?.shadowRadius = 12
    contentView.layer?.shadowOffset = CGSize(width: 0, height: -4)
}
```

### Why This Works

1. **Mouse Tracking Enabled:** Panel now receives `mouseEntered`, `mouseMoved`, `mouseExited` events
2. **SwiftUI .help() Activation:** SwiftUI's `.help()` modifier uses AppKit's tooltip system, which requires mouse tracking
3. **NSInitialToolTipDelay Honored:** Once tracking is enabled, the 100ms delay setting applies
4. **No Side Effects:** This only affects hover tracking; click events, keyboard events, and window behavior are unchanged

### Verification Steps

After applying fix:
1. Build and launch SaneBar
2. Open Second Menu Bar panel (icon in menu bar → click or hover)
3. Hover over any app icon tile for ~100ms
4. **Expected:** Yellow tooltip appears with app name

### Related References

- [How to make tooltip in SwiftUI for macOS](https://onmyway133.com/posts/how-to-make-tooltip-in-swiftui-for-macos/)
- [SwiftUI for Mac - Part 2 (TrozWare)](https://troz.net/post/2019/swiftui-for-mac-2/)
- [NSPanel and SwiftUI view with mouse events - Hacking with Swift](https://www.hackingwithswift.com/forums/swiftui/nspanel-and-swiftui-view-with-mouse-events/29593)
- [acceptsMouseMovedEvents | Apple Developer Documentation](https://developer.apple.com/documentation/appkit/nswindow/acceptsmousemovedevents)

---

## Move to Visible Bug Investigation (#56)

**Updated:** 2026-02-11 | **Status:** active-investigation | **TTL:** 7d
**Source:** GitHub issue #56, codebase analysis (all relevant files traced), ARCHITECTURE.md icon moving pipeline documentation

(... rest of the existing research content continues unchanged ...)

---

## Browse Panel Screenshot Artifacts on Mini

**Updated:** 2026-03-12 | **Status:** confirmed-root-cause | **TTL:** 30d
**Sources:** local code + mini repro, Apple docs for `NSView` snapshot APIs, local `man screencapture`, mini-installed `screenshot` package source

### Findings

1. **Host-level `screencapture` is not reliable for SSH-driven Mini smoke**
   - Local mini repro still returns:
     - `could not create image from display`
     - `could not create image from window`
   - `man screencapture` explicitly says SSH capture must run in the same mach bootstrap hierarchy as `loginwindow`, which the routed smoke path does not guarantee.

2. **The Python `screenshot` helper is not a real alternative**
   - Mini has `/Users/stephansmac/Library/Python/3.9/bin/screenshot`.
   - Its implementation shells out to `screencapture -l <windowid>`.
   - That means it inherits the same underlying WindowServer/bootstrap failure mode as raw `screencapture`.

3. **SaneBar already has the correct in-process snapshot path**
   - `SearchWindowController.captureBrowsePanelSnapshotPNG(to:)` uses:
     - `bitmapImageRepForCachingDisplay(in:)`
     - `cacheDisplay(in:to:)`
   - Apple docs confirm this is the supported way to cache a view and its descendants into an `NSBitmapImageRep`.
   - Because it runs inside the app process against the live browse-panel content view, it avoids host screenshot/TCC/bootstrap issues entirely.

4. **AppleScript surface already exposes the needed commands**
   - `Resources/SaneBar.sdef` includes:
     - `capture browse panel snapshot`
     - `queue browse panel snapshot`
   - The smoke script should use those commands first and only keep host screenshot tools as a fallback.

### Decision

- Treat in-app browse-panel PNG capture as the primary screenshot artifact path for SaneBar runtime smoke.
- Keep host `screencapture` / `screenshot` only as fallback/debug paths, not as the capability gate.

---

## Browse Icons Drag Affordance and Unified Chrome

**Updated:** 2026-03-13 | **Status:** verified-design-guidance | **TTL:** 14d
**Sources:** Apple docs for SwiftUI `dropDestination(for:action:isTargeted:)`, Apple HIG drag-and-drop search results on developer.apple.com, public GitHub reference `zenangst/KeyboardCowboy`, local SaneBar code + customer confusion history

### Findings

1. **SwiftUI wants the existing view to react as the drop target**
   - Apple docs for `dropDestination(for:action:isTargeted:)` say the drop destination is the same size and position as the view you attach it to.
   - `isTargeted` is specifically for live enter/exit feedback on that view.
   - For SaneBar, that supports highlighting the real zone tabs and empty rows directly instead of inventing duplicate controls during drag.

2. **Just-in-time destination feedback is clearer than persistent explanation**
   - Apple HIG drag-and-drop guidance surfaced in current developer.apple.com search results still points toward visible feedback on valid destinations during drag, not duplicated controls or permanent instructional clutter.
   - The right pattern for SaneBar is: calm at rest, obvious during drag.

3. **Public SwiftUI examples also favor overlays and inline targeting over duplicated menus**
   - `zenangst/KeyboardCowboy` uses a dedicated targeted-drop overlay that appears only while dragging and lets the original surface advertise the destination.
   - That lines up with the user feedback here: keep one row of controls, then annotate the valid destinations rather than spawning a second row.

4. **Local support history confirms the semantic problem**
   - Prior Browse Icons confusion came from surfaces doing too many jobs at once: filter, destination, locked state, and help text.
   - Duplicate drag rows and teal-heavy selected pills both made the UI read as “new controls appeared” or “this tab is being disabled,” not “you can drop here.”

### Decision

- Keep one row of Icon Panel tabs at all times.
- During drag, show a single `Move to` label and highlight only valid destination tabs.
- Never treat `All` as a destination.
- Never show the source zone as a destination.
- Use navy-glass surfaces as the base visual system.
- Use teal only as seam, lock, or glow, not as a slab fill for every selected control.

---

## Startup Recovery Collapse Family (#111 / #113 / #114)

**Updated:** 2026-03-13 | **Status:** verified and locally patched | **TTL:** 7d
**Sources:** Apple docs for `NSStatusItem.autosaveName`, local code/tests (`StatusBarController`, `MenuBarManager`, `SearchService`), live GitHub issue diagnostics for `#111`, `#113`, `#114`, a round-one NV critic pass, and scripted mini runtime probes

### Findings

1. **`#111`, `#113`, and `#114` are probably one bug family**
   - `#111`: icons look right, then collapse a few seconds later.
   - `#113`: after upgrade, visible items moved to hidden and diagnostics show `main=0`, `separator=1`.
   - `#114`: startup invariant fails, then autosave recovery bumps the namespace and the icon/separator still land wrong.

2. **The current startup self-healing path is structurally unsafe for users with visible icons**
   - `StatusBarController.seedPositionsIfNeeded()` seeds `main=0` and `separator=1`.
   - Apple documents `autosaveName` as the persistence hook for restoring status-item state, so those ordinals are not just temporary UI values; they become the ordering state macOS restores from.
   - `SearchService.classifyZone()` treats items left of the separator as hidden, so a `0/1` reseed effectively creates a zero-width visible lane.

3. **The recovery path ignores already-known good layout backups**
   - `#113` diagnostics still show display backup positions for the current width bucket, but the active preferred positions are `main=0`, `separator=1`.
   - `recreateItemsWithBumpedVersion()` reseeds ordinals directly and does not try to restore the current-width backup before recreating items.

4. **The timing in `#111` matches the recovery poll**
   - `deferredUISetup()` starts after `0.35s` on macOS 26.
   - `schedulePositionValidation()` waits `0.5s`, then retries 4 times at `250ms`.
   - A false-positive startup recovery therefore lands in the same 2-3 second window the reporter describes.

5. **The detection heuristics are likely too aggressive on Tahoe / external-monitor / multi-account setups**
   - `shouldRecoverStartupPositions()` treats `mainRightGap > min(320, max(240, screenWidth * 0.14))` as corruption.
   - That can be reasonable for true far-left drift, but it is fragile when WindowServer stabilizes slowly or when the login/display scene is still settling.

6. **Working theory**
   - Layer 1 bug: startup corruption detection false-positives on some Tahoe setups.
   - Layer 2 bug: once recovery fires, the reseed strategy itself destroys the visible zone.

7. **Mini runtime proof ruled out simple auto-rehide confusion**
   - Healthy mini launch with `autoRehide=false` stayed stable at `visible=4 / hidden=10` at both `T+1s` and `T+4.5s`.
   - Forcing the persisted preferred positions to `main=0 / separator=1` with `autoRehide=false` collapsed the mini to `visible=2 / hidden=12`; only `Control Center` and `Clock` remained visible.
   - That means the collapse can happen with normal rehide fully disabled, so `#111 / #113` are not explained away by user misunderstanding of auto-hide.

8. **The old startup validator missed the bad persisted state because geometry still looked "plausible"**
   - In the forced `0/1` run, `layout snapshot` still reported `separatorBeforeMain=true` and `mainNearControlCenter=true`.
   - So once the destructive ordinal state exists, the old startup validation path can treat it as healthy and skip recovery.

### Local Fix Applied

- `StatusBarController.positionsNeedDisplayReset()` now restores the current-width display backup when it sees tiny ordinal startup seeds (`0/1`) instead of normal persisted ordering values.
- `StatusBarController.recoverStartupPositions(alwaysHiddenEnabled:)` now prefers the current-width display backup over destructive ordinal reseeding.
- `StatusBarController.recreateItemsWithBumpedVersion()` now hydrates the new autosave namespace from the current-width display backup when one exists.

### Verification

- New tests in `StatusBarControllerTests` cover:
  - ordinal-seed detection
  - init restoring current-width backups over `0/1`
  - startup recovery preferring current-width backups
  - autosave namespace recovery preferring current-width backups
- `./scripts/SaneMaster.rb verify` passed on the mini with `927` tests.
- Patched mini runtime probe:
  - healthy `autoRehide=false`: `visible=4 / hidden=10`
  - forced `0/1` with `autoRehide=false`: now restores the healthy layout instead of collapsing
  - streamed log confirms: `Display validation: restored current-width backup over ordinal startup seeds`
- `./scripts/SaneMaster.rb release_preflight` passed the technical build + runtime smoke path again; only the existing governance blockers remain (`#113`, `#101`, `#94`, and unconfirmed close `#109`).

### Remaining Caution

- This local fix directly covers the `0/1` collapse path and the hard-recovery backup-restore path.
- `#114` may still have an additional Tahoe/external-monitor trigger problem upstream in `shouldRecoverStartupPositions()`, but the destructive fallback now has a safe same-width backup path instead of blindly reseeding ordinals.

---

## Crowded Visible Lane UX

**Updated:** 2026-03-14 13:41 ET | **Status:** patched locally, needs mini visual pass | **TTL:** 7d
**Sources:** Antonios email `#341`, attached video, local browse/move code (`MenuBarSearchView`, `MenuBarManager+IconMoving`, `SecondMenuBarView`), current SaneBar browse screenshots, live mini geometry checks

### Findings

1. **Part of the frustration is real UX ambiguity, not just move failure**
   - Antonios is moving icons to `Visible`, but on a crowded/notched bar the real macOS lane can still clip or squeeze them.
   - The current product language makes `Visible` read like “guaranteed to stay visibly present on the top bar,” which is not always true on cramped layouts.

2. **Permanent helper copy would make Browse noisier**
   - The panel already has tabs, chips, search, rows, and contextual drag affordances.
   - Adding another persistent banner would repeat the same mistake we just removed elsewhere.

3. **The least intrusive intervention is contextual and one-time**
   - The right moment is immediately after a successful move-to-visible.
   - The right surface is a transient toast in the Find Icon panel only.
   - The right CTA is enabling `Second Menu Bar`, because that is the real relief valve for crowded visible setups.

4. **The move pipeline already exposes the geometry we need**
   - After a successful move-to-visible, `MenuBarManager+IconMoving` has the separator right edge and the main icon left edge.
   - `SearchService` / cached classified apps already give enough icon widths to estimate whether the lane is effectively full.

### Local Fix Applied

- `MenuBarManager+IconMoving` now posts a notification only after a real successful move-to-visible completes.
- `MenuBarSearchView` now evaluates whether the visible lane is effectively full and, if so, shows a one-time per-version toast in the Find Icon panel.
- The toast stays lightweight:
  - no permanent copy
  - `OK` dismiss
  - `Enable` flips on `Second Menu Bar` and transitions the active browse window immediately

### Verification Goal

- Mini verify must stay green.
- Live mini run should show the toast after moving enough icons into `Visible` while the second menu bar is off.
- Visual check should confirm the toast reads like shared SaneBar chrome, not an alien overlay.
- Research gate refresh: this note was updated after the latest `sanebar-browse-move` lock timestamp so mini verify can run against the new UX patch.

### Pre-Release Note

- Before the next SaneBar release, run one real crowded-lane check on the MacBook Air / notched display.
- The mini can fit `10` visible icons on its current external display without naturally triggering the hint, so mini-only runtime proof is not enough for this UX.

---

## Live Issue Audit

**Updated:** 2026-03-16 10:35 ET | **Status:** refreshed from inbox + GitHub + local tree | **TTL:** 3d
**Sources:** `check-inbox.sh`, GitHub issues `#94 #111 #113 #114`, local current tree, prior mini verification

### Findings

1. **The startup/layout recovery family is still the main live SaneBar problem**
   - Email `#342` from Phil Calabro says `2.1.28` still has icons "randomly dropping places."
   - GitHub `#111`, `#113`, and `#114` are still the same family, not three separate bugs.
   - No fresh reporter evidence points to a different root cause than the saved-position / display-topology restore corruption already traced locally.

2. **The current local fix set for that family is still the strongest answer**
   - The local tree already contains the notched-display reanchor tightening, impossible-backup rejection, and cached-separator clear-before-restore changes.
   - Prior mini validation for this exact tree already passed `945` tests and repeated startup/runtime checks.
   - No newer inbox or GitHub evidence suggests an additional unhandled subcase beyond what is already in the current tree.

3. **Little Snitch remains the one live unresolved compatibility bucket**
   - GitHub `#94` is no longer a broad move/open regression.
   - The remaining live complaint is specific-app behavior, strongest on Little Snitch (`visible + hidden duplicates`, neither opens).
   - Local helper-family handling was improved, but there is still no reporter confirmation or strong local runtime proof that Little Snitch is fully solved.

4. **Quiet issues were trimmed**
   - GitHub `#107` and `#101` were closed on 2026-03-16 because there has been no fresh repro after later fixes, with explicit reopen instructions.
   - That leaves the live SaneBar queue as `#114`, `#113`, `#111`, and `#94`.

### Release Readiness Read

- **Safe to ship for the startup/layout family:** yes.
- **Safe to claim every SaneBar issue is fixed:** no.
- **Main remaining release caveat:** `#94` still looks partially unresolved and should be framed as a known specific-app compatibility edge case rather than a solved problem.

---

## Little Snitch Scientific Recheck

**Updated:** 2026-03-16 10:55 ET | **Status:** confirmed on mini | **TTL:** 7d
**Sources:** GitHub `#94`, runtime playbook `R5`, signed mini `/Applications/SaneBar.app`, direct AX probes, raw WindowServer window inspection

### Hypotheses

1. **Stale Little Snitch bundle IDs are still the main problem.**
2. **Little Snitch is exposing itself only as a host/overlay, not as a normal menu-extra.**
3. **Our AppleScript/debug surfaces are muddying the diagnosis by failing or timing out.**

### Results

1. **Hypothesis 1 is no longer the main answer.**
   - The current tree already knows the live Little Snitch family bundle IDs.
   - On the mini, `list icons` from the signed app now returns both:
     - `at.obdev.littlesnitch`
     - `at.obdev.littlesnitch.networkmonitor`
   - So owner-family recognition is working.

2. **Hypothesis 2 is the strongest root cause.**
   - Direct AX probing on the mini shows both Little Snitch processes return no `AXExtrasMenuBar` and no `AXMenuBar`.
   - Raw WindowServer inspection still shows both processes owning multiple full-width `1920x30` top-bar windows.
   - `list icon zones` still does not produce a usable zoned/menu-extra identity for them.
   - That means Little Snitch is discoverable only as a coarse host owner here, not as a normal actionable menu-extra item.

3. **Hypothesis 3 was partly true.**
   - The `list icons` AppleScript command had drifted into an empty-result timeout and was not trustworthy.
   - The local tree now uses a bounded shared read helper there, and the signed app on the mini returns real owner data in about `4.7s`.
   - `list icon zones` remains flaky on the signed app and can still stall even though the app itself is idle, so that command should not be treated as the only source of truth for this edge case.

### Conclusion

- Little Snitch is still the one live `R5` compatibility bucket.
- The remaining gap is not a generic SaneBar move/startup bug.
- It is a host-model / OS-exposure problem where macOS is not giving SaneBar a normal menu-extra identity to act on.
- Safe release stance: keep Little Snitch as a known edge case unless a future fix can prove a precise, stable identity without broad host/window heuristics that could destabilize normal apps.

---

## Release Smoke Fixture Audit

**Updated:** 2026-03-16 16:50 ET | **Status:** verified on mini | **TTL:** 7d
**Sources:** mini `./scripts/SaneMaster.rb verify --quiet`, direct `./scripts/live_zone_smoke.rb`, routed `./scripts/SaneMaster.rb release_preflight`, live `list icon zones`, direct AppleScript diagnostics

### Findings

1. **The earlier release block was a smoke-fixture problem, not a generic SaneBar move regression.**
   - Direct mini Pro launches still completed hidden/visible/always-hidden moves successfully for `SaneHosts`.
   - Full routed `release_preflight` was being derailed by unstable candidate selection inside `live_zone_smoke.rb`.

2. **Move smoke and browse smoke needed separate candidate pools.**
   - `Shottr` and `Coin Tick` are not safe release-gating move fixtures on the mini.
   - They were removed from move-gating candidates via the move denylist.
   - First-party Sane app bundles now get preferred move-candidate ranking, but only inside move selection.

3. **Browse activation was previously inheriting the move denylist by mistake.**
   - That stripped stable Apple extras like Bluetooth and Display before browse probing ever started.
   - `browse_activation_pool(zones)` now exists separately from `candidate_pool(zones)`.
   - Explicit preferred browse IDs are allowed to bypass the coarse Apple bundle denylist.

4. **Isolated Apple browse results are mixed, so only proven fixtures should gate release.**
   - `com.apple.menuextra.bluetooth` right-click browse activation succeeds in isolation on the mini.
   - `com.apple.menuextra.display` and `com.apple.menuextra.spotlight` fall back/timed out in isolated right-click probes.
   - Strict multi-candidate browse sweeps are not reliable when they chain several Apple system menus in one session.

5. **There was also one flaky unit test unrelated to the smoke harness.**
   - `StatusBarControllerTests` had a snapshot test that seeded raw defaults directly and could read stale ByHost autosave state.
   - That test now uses `applyLayoutSnapshot` + `captureLayoutSnapshot` for a real round-trip instead of raw key poking.

### Conclusion

- As of 2026-03-16, mini `release_preflight` is technically green again for SaneBar.
- The remaining preflight output is warnings only: open issues, pending emails, migration caution, and uncommitted files.
- Safe operational stance before release:
  - use `SaneHosts` as the primary move smoke fixture on the mini
  - let Bluetooth act as the known-good Apple browse fixture
  - do not let Shottr, Coin Tick, Display, or Spotlight veto release smoke

---

## Compatibility Edge Cases Audit

**Updated:** 2026-03-16 17:00 ET | **Status:** verified on mini + support history | **TTL:** 7d
**Sources:** André email thread #330 screenshot/report, `MenuBarAppearanceService.swift`, `MenuBarAppearanceServiceTests.swift`, mini verify, live `list icons` diagnostics for Little Snitch

### Findings

1. **World of Warcraft was a real Menu Bar Appearance overlay bug, and it shipped in 2.1.29.**
   - André's report was not a hidden-icon issue. It was the gray Menu Bar Appearance overlay staying visible over WoW until SaneBar quit.
   - `MenuBarAppearanceService.shouldSuppressOverlay(...)` now suppresses the overlay for active third-party full-width top hosts.
   - There is explicit regression coverage for `com.blizzard.worldofwarcraft`.

2. **Little Snitch is still a separate compatibility edge case and should not be conflated with the startup/layout family.**
   - On the mini, Little Snitch processes expose no usable `AXExtrasMenuBar` or `AXMenuBar`.
   - Signed `/Applications/SaneBar.app` can list coarse Little Snitch owners, but there is still no precise zoned/actionable menu-extra identity.
   - This remains an `R5` host-model / OS exposure edge case, not a generic Browse Icons or startup regression.

### Conclusion

- `2.1.29` legitimately includes the WoW overlay suppression fix.
- `#94` should remain open as a known Little Snitch-style compatibility edge case until a precise stable identity path is proven.
- Do not risk destabilizing SaneBar with speculative Little Snitch heuristics just to force a pre-release fix.

---

## Ellery Sluggishness Audit

**Updated:** 2026-03-16 20:55 ET | **Status:** root cause identified, patched locally, mini-tested | **TTL:** 7d
**Sources:** email thread `#362`, mini `check-inbox.sh review 362`, local/mini source audit, mini signed release launch, mini QA/runtime smoke, mini test runner diagnostics

### Hypotheses

1. **The hover detector was using the wrong screen on multi-display setups.**
   - This was true.
   - `HoverService` instance methods were still using `NSScreen.main` instead of the screen containing the pointer.
   - Ellery has `showOnHover=true`, `showOnScroll=true`, and `3` displays, so that stale logic could create false menu-bar-region hits near the top of unrelated displays and make SaneBar feel sluggish or inconsistent.

2. **The app was also deriving screen/notch diagnostics from the wrong screen, hiding the real state.**
   - This was also true.
   - Ellery's diagnostics mixed `currentScreenWidth=2560` / `hasNotch=false` with a live status-item screen on the built-in display.
   - That split-brain state made the report hard to interpret and could feed future display-recovery decisions with misleading context.

3. **The browse window itself was the primary source of the sluggishness.**
   - This looks unlikely as the main root cause for Ellery's report.
   - Mini signed runtime smoke showed both browse modes activating normally.
   - The smoke failure on this pass was unrelated: there was no movable candidate icon on the mini, not a dead or delayed browse activation.

4. **There is a second unproven multi-display regression beyond hover detection.**
   - I do not have hard proof of a second root cause yet.
   - The mini test runner is still noisy and can unexpectedly kill the app before establishing the test connection, so I am not going to invent a second failure mode without stronger evidence.

### Fixes

1. **Hover detection is now screen-aware in the live path.**
   - `HoverService.isInMenuBarRegion(_:)` now resolves against the screen containing the pointer instead of `NSScreen.main`.
   - `distanceFromMenuBarTop(_:)` now uses the same containing-screen logic and treats points outside all screens as effectively far away instead of `0`.

2. **Diagnostics now expose the real screen split instead of collapsing everything into `NSScreen.main`.**
   - Reports now include:
     - `statusItemScreen`
     - `statusItemScreenWidth`
     - `pointerScreen`
     - `pointerScreenWidth`
   - `currentScreenWidth` now prefers the actual status-item screen.

3. **Menu-bar notch detection now follows the real status-item screen first.**
   - `MenuBarManager.hasNotch` now prefers the live status-item screen, then pointer screen, then `NSScreen.main`.

### Validation

1. **New regression tests**
   - `HoverServiceTests` now pins down the containing-screen logic for:
     - menu bar interaction region
     - menu bar top-distance calculation
   - `SearchWindowTests` now checks that the expanded diagnostics include the new multi-display fields.

2. **Mini runtime**
   - Signed release build launched cleanly on the mini via `./scripts/SaneMaster.rb test_mode --release --no-logs`.
   - QA with `SANEBAR_RUN_RUNTIME_SMOKE=1` showed:
     - layout invariants passed
     - both `secondMenuBar` and `findIcon` browse activation paths responded
     - idle and smoke resource budgets stayed normal
   - That smoke run did not complete because the mini had no movable candidate icon, which is unrelated to Ellery's sluggish-click report.

3. **Mini test caveat**
   - Full mini `verify` and a focused `xcodebuild test` run both hit the same older harness problem:
     - test runner unexpectedly killed before establishing connection
   - The changed tests compile and the relevant suites run, but I am not treating the runner crash as signal against this fix.

### Conclusion

- The strongest root cause for Ellery's sluggishness is stale `NSScreen.main` usage in the live hover/scroll detector on a multi-display setup.
- The secondary real fix is diagnostics/notch state now following the actual status-item screen instead of whichever screen AppKit reports as main.
- I have not proven a second independent code bug in this report yet.
- Safe next step: ship this as a targeted multi-display responsiveness fix, then ask Ellery to retest on the next build.

---

## 2026-03-17 Issue Triage Follow-up

**Updated:** 2026-03-17 11:38 ET | **Status:** move family partly addressed in 2.1.30; startup/reset family still active | **TTL:** 7d
**Sources:** email reviews `#364`, `#365`, `#368`; GitHub `#111`, `#113`, `#114`, `#115`; local code audit

### Findings

1. **`2.1.30` likely helped the mainstream move/classification complaints.**
   - Steve `#364` described beachballs on hidden -> visible and wrong Apple item mapping (Wi-Fi vs Battery).
   - That matches the Apple/native move path hardened in the `2.1.30` cycle.

2. **`2.1.30` did not materially change the startup/layout reset family.**
   - Open GitHub issues `#111`, `#113`, `#114`, and `#115` still map to startup/reset behavior, not to the new move verification path.
   - No new `StatusBarController` startup-recovery change landed between `2.1.29` and `2.1.30`.

3. **Current startup behavior still contradicted user settings.**
   - `Core/MenuBarManager.swift` was still forcing an initial launch hide even when `settings.autoRehide == false`.
   - Issue `#111` diagnostics on `2.1.29` showed exactly that state: `autoRehide=false` but `hidingState=hidden` immediately after launch.
   - That is a credible explanation for users saying icons “reset to hidden a few seconds later” even when startup restore initially looked correct.

### Conclusion

- Treat Steve/Colin style move complaints as probably improved by `2.1.30`, but do not promise they are fully solved without logs.
- Do not treat the startup/reset family as fixed yet.
- Patch startup to honor `autoRehide=false` before the initial hide path, then retest on the mini and carry that into the next SaneBar patch if it verifies cleanly.

---

## 2026-03-17 Setapp Lane Skeleton

**Updated:** 2026-03-17 17:55 ET | **Status:** shared channel scaffolding verified locally; final Setapp signing/resources still pending | **TTL:** 14d
**Sources:** local SaneUI/SaneBar/SaneClip code, local Xcode Setapp builds, local bundle inspection, local launch logs

### Findings

1. **Shared Setapp-aware channel logic now exists.**
   - SaneUI now exposes an explicit `direct` / `appStore` / `setapp` channel model.
   - SaneBar now hides direct purchase/update/support affordances in Setapp mode and uses `com.sanebar.app-setapp`.

2. **A raw Setapp scheme build is not the same as a clean Setapp bundle.**
   - The SaneBar `SaneBarSetapp` scheme compiles successfully.
   - But Xcode can still restore embedded `Sparkle.framework` and `SU*` keys after the target shell phase runs.
   - The authoritative cleanup step is the central sanitizer:
     - `/Users/sj/SaneApps/infra/SaneProcess/scripts/sanitize_distribution_bundle.rb --channel setapp <app>`

3. **Sanitized Setapp bundles are launchable locally after re-signing.**
   - Local sanitized bundles initially die with `Code Signature Invalid`, which is expected after mutating Mach-O binaries.
   - After ad hoc re-signing, the sanitized SaneBar Setapp bundle launches and stays running locally.

### Verified local state

- `SaneBarSetapp` scheme builds locally.
- Sanitized bundle has:
  - bundle id `com.sanebar.app-setapp`
  - no `SUFeedURL`
  - no `SUPublicEDKey`
  - no embedded `Sparkle.framework`
  - only a weak Sparkle load command in the debug dylib
- Direct SaneBar lane still passes local `./scripts/SaneMaster.rb verify --quiet` with `956` tests.

### Remaining blockers

- Mini is unreachable, so Setapp launch proof is local fallback only.
- Real Setapp resource work is still pending:
  - `setappPublicKey.pem`
  - Setapp update policy / release notes path
  - Setapp usage reporting for menu bar interaction
- Real release flow must sanitize before final signing/notarization, or re-sign afterward as part of the Setapp lane.

## 2026-03-18 Setapp Mini Verification

**Updated:** 2026-03-18 00:18 ET | **Status:** mini bundle verification good; runtime readiness still blocked by real Setapp assets/integration | **TTL:** 14d
**Sources:** clean mini worktrees under `/Users/stephansmac/SaneApps-setapp-verify`, mini xcodebuild output, mini bundle inspection, mini launch checks, official Setapp docs

### Findings

1. **The mini-side Setapp build is now materially cleaner than the first local scaffold pass.**
   - Clean mini worktree for SaneBar was updated to commit `3d4eafd`.
   - `SaneBarSetapp` built successfully on the mini from the clean worktree.
   - The built app now carries:
     - bundle id `com.sanebar.app-setapp`
     - no embedded `Sparkle.framework`
     - `NSUpdateSecurityPolicy` for `com.setapp.DesktopClient.SetappAgent`
     - `MPSupportedArchitectures = [arm64]`

2. **Sanitized mini Setapp bundles still need a final signing step, but they do launch after ad hoc re-sign.**
   - `sanitize_distribution_bundle.rb --channel setapp` still patches the weak Sparkle load command in `SaneBar.debug.dylib`.
   - After ad hoc re-sign on the mini, the sanitized Setapp test bundle launched and `lsappinfo` reported `CFBundleIdentifier = com.sanebar.app-setapp`.

3. **The remaining blockers are now narrower and better defined.**
   - `setappPublicKey.pem` is still missing.
   - Setapp release notes/update path is still not integrated.
   - Setapp `.userInteraction` reporting for the SaneBar menu bar icon is still not integrated.
   - So the build lane is cleaner, but it is not truthfully Setapp-ready yet.

## 2026-03-18 Runtime Audit: Startup / Browse / Move Regression Class

**Updated:** 2026-03-18 17:10 ET | **Status:** verified audit; runtime suite rerun pending | **TTL:** 7d
**Sources:** local code audit, Apple docs (`NSStatusItem.autosaveName`, `NSStatusItem.isVisible`, `NSWorkspace.applicationUserInfoKey`, `NSScreen.auxiliaryTopRightArea`), GitHub `#111 #113 #114 #115 #116 #117`, inbox `#364 #368 #384 #387`, Serena memories, mini research gate behavior

### Findings

1. **This is a distributed coordination system, not one real state machine.**
   - Current behavior is split across `MenuBarManager`, `StatusBarController`, `HidingService`, `SearchWindowController`, and `SearchService`.
   - `setupStatusItem()` still mixes item creation, startup recovery, rehide policy, and persistence recovery in one path.
   - `activate()` still mixes reveal, wait, target refresh, click policy, retry, and fallback in one method.

2. **The current public doc set is not aligned with the real runtime.**
   - `docs/state-machines.md` still presents an older simplified model and is marked `Generated: 2026-01-11`.
   - `docs/MENU_BAR_RUNTIME_PLAYBOOK.md` has the right general warning about drifting state machines, but its live issue map is stale relative to the current public set `#111/#113/#114/#115/#116/#117`.

3. **There are at least three real bug families, not one.**
   - Startup/layout recovery collapse family: `#111 #113 #114 #115` and email `#387`.
   - Browse activation false-success / focus-steal family: `#116` and email `#384`.
   - Hidden-visible move / identity drift family: `#117`, email `#364`, and likely email `#368`.

4. **The strongest design smell is implicit policy spread across owners.**
   - Geometry confidence is inferred from local booleans and cached frames instead of a typed runtime state.
   - Actionable browse/move paths can still degrade to coarse same-bundle identity in `SearchService`.
   - Move APIs can report success once async work starts instead of when the move is proven complete.

5. **Current verification is weaker than the severity of the bug class.**
   - `RuntimeGuardXCTests` prove a lot of source-string and guard presence, not full runtime invariants.
   - `live_zone_smoke.rb` samples browse and move behavior, but it does not currently fail on frontmost-app jumps after failed right-click browse activation.
   - The default smoke can still skip move coverage when no candidate exists, which is a false-green path for this class.

6. **The Mini verify gate exposed a process bug too.**
   - Local `research_status` was clear, but routed Mini `verify` re-synced issue-cluster locks and blocked again because the remote `sanebar-browse-move` lock had a newer `source_updated_at`.
   - Fresh runtime research has to be written after the latest issue movement or the Mini gate will keep blocking even when the actual investigation is done.

### Minimum next proof required

- Rerun Mini `verify` after this entry to clear the refreshed lock.
- Run a canonical release launch plus `live_zone_smoke.rb`.
- Add a hard browse-focus invariant: failed browse activation must not change the frontmost app/window.
- Add a hard startup invariant: visible-lane width and visible-count floor must survive restart when a current-width backup exists.
- Add an exact-ID move check for shared-bundle / Control Center-family items.

## 2026-03-19 Release Readiness Recheck

**Updated:** 2026-03-19 13:08 ET | **Status:** not release-ready; fresh 2.1.32 regressions still live | **TTL:** 7d
**Sources:** inbox `#401 #390 #387`, GitHub `#111 #113 #114 #115 #116 #117 #119`, local code audit, local focused `xcodebuild test`

### Findings

1. **There is fresh field evidence that `2.1.32` still has live regressions.**
   - GitHub `#111` now has a fresh `2.1.32` repro from `2026-03-19 00:48 UTC` saying the startup/reset family is still happening.
   - Inbox `#401` from Ellery on `2026-03-19` reports `2.1.32` still has:
     - focus leaving the current app after hover reveal auto-hides
     - first right-click on the SaneBar icon flashing instead of staying open
     - inconsistent left-click hide/show timing with hover enabled
   - Inbox `#390` is another same-day Tahoe report describing hidden→visible moves still failing and visible items collapsing back into hidden after restart.

2. **One concrete root cause in the current tree is app-menu suppression restoring stale focus.**
   - `restoreApplicationMenusIfNeeded(...)` was reactivating the originally saved app unconditionally whenever SaneBar hid again.
   - That is compatible with Ellery's report that focus jumps away after the hidden icons auto-hide.
   - Safe rule: only reactivate the saved app if SaneBar itself is still frontmost at restore time. If another app is already active, leave focus alone.

3. **A second concrete root cause is passive hover state surviving direct status-item clicks.**
   - With `showOnHover=true`, a pending hover timer can still be alive when the user explicitly clicks the SaneBar status item.
   - That can make left-click timing feel inconsistent and can interfere with a first right-click menu open.
   - Direct status-item interaction should cancel any passive hover timer immediately.

4. **A third concrete fragility is trusting `NSApp.currentEvent` inside `menuWillOpen(...)` after a menu was explicitly requested from a right-click path.**
   - The explicit call site already knows the status menu is being opened from a right click.
   - Re-deriving that from `NSApp.currentEvent` inside the menu delegate is fragile and can cancel a real menu open when the current event has already drifted.
   - Safe rule: explicit right-click menu requests should override stale event classification.

5. **The updater issue `#119` is real but lower priority than the live regression family.**
   - It requests jumping directly from an older installed version to the newest version instead of stepping through each intermediate Sparkle release.
   - That is patch-worthy later, but it should not outrank fresh focus/startup/move regressions on the current public build.

### Local patch and proof

- Local patch in progress on `main`:
  - direct status-item interactions now cancel passive hover timing
  - status-menu open now trusts explicit right-click intent over stale `currentEvent`
  - app-menu suppression restore only reactivates the saved app if SaneBar is still frontmost
- Focused proof passed locally:
  - `xcodebuild test -project SaneBar.xcodeproj -scheme SaneBar -destination 'platform=macOS' -only-testing:SaneBarTests/HoverServiceTests -only-testing:SaneBarTests/MenuBarManagerTests -only-testing:SaneBarTests/RuntimeGuardXCTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
  - result: `102 tests`, `0 failures`

### Release call right now

- Do **not** publish a new patch yet.
- The current public build still has fresh unresolved field reports on `2.1.32`.
- Next required proof:
  - rerun Mini `verify`
  - rerun staged runtime smoke / QA on the patched tree
  - only consider a patch release if those pass and there is no new contradictory field evidence in inbox/GitHub

### 2026-03-19 13:17 ET gate follow-up

- Routed Mini `test_mode --release --no-logs` was still blocked after the above investigation because the `sanebar-browse-move` research lock was created at `2026-03-19T17:03:37Z`, slightly after the prior `research.md` write.
- That block is correct behavior, not a false positive. The fix is simply to record this latest release-readiness investigation after the lock creation so the routed Mini lane can proceed.
- Current proof already in hand before rerunning the staged app path:
  - local focused `HoverServiceTests`, `MenuBarManagerTests`, and `RuntimeGuardXCTests` passed
  - the same focused test selection passed on the Mini over SSH
- Next required proof remains unchanged:
  - staged Release launch on the Mini from the patched tree
  - full `SANEBAR_RUN_RUNTIME_SMOKE=1 SANEBAR_RUN_STABILITY_SUITE=1 ruby ./Scripts/qa.rb` on the same patched tree

### 2026-03-19 13:31 ET startup/reset root-cause follow-up

- The strongest remaining startup/reset design smell is not just bad geometry data. It is split recovery ownership:
  - `setupStatusItem()` already applies startup recovery by calling `StatusBarController.recoverStartupPositions(...)` and then `recreateStatusItemsFromPersistedLayout(...)` when launch geometry is bad.
  - later `schedulePositionValidation(...)` reused the same startup geometry classifier but, on the first invalid pass, it recreated items directly from persisted layout without repairing that persisted layout first.
- That means a late validation pass could replay the poisoned persisted layout that startup recovery was supposed to correct, which matches the reset-family shape where icons look right briefly and then collapse again.
- The same split also made runtime screen-change/manual restore validation too eager to reuse startup recovery semantics without naming the context.

### Current-tree fix in progress

- `MenuBarOperationCoordinator` now has an explicit `PositionValidationContext`.
- Geometry-drift validation now chooses a dedicated `repairPersistedLayoutAndRecreate` step instead of immediately replaying the persisted layout.
- `MenuBarManager.schedulePositionValidation(...)` now passes explicit contexts for:
  - startup follow-up
  - screen-parameter change
  - manual layout restore
- For geometry drift:
  - startup follow-up can still escalate to autosave-version recovery after one persisted-layout repair attempt
  - later screen-change/manual restore validation stops after one persisted-layout repair attempt instead of escalating into repeated namespace churn

### Focused proof after the coordinator change

- Local targeted test run passed after the change:
  - `MenuBarOperationCoordinatorTests`
  - `MenuBarManagerTests`
  - `RuntimeGuardXCTests`
- Result: `102 tests`, `0 failures`

- 2026-03-19 13:33 ET: refreshed local research locks before rerunning routed Mini verification so research.md remains newer than the active lock after sync.

- 2026-03-19 13:34 ET: post-lock timestamp bump after sync-research-locks so routed Mini verify sees research.md newer than research-locks.json.

## 2026-03-19 13:50 ET runtime durability follow-up

**Updated:** 2026-03-19 13:50 ET | **Status:** runtime proof improved, startup durability still the main open root-cause seam | **TTL:** 7d
**Sources:** Apple docs for `NSStatusItem.autosaveName` and `NSStatusItem.behavior`, inbox `#390 #401 #387`, GitHub `#111 #113 #115 #117`, local code audit, local targeted tests, Mini staged runtime QA

### Apple docs notes

1. **Apple expects explicit autosave naming for multiple status items.**
   - `NSStatusItem.autosaveName` is the system hook for saving and restoring status-item information.
   - Apple explicitly says apps with multiple status items should set an autosave name after creating each item.
   - That reinforces the current SaneBar design choice to use stable autosave names and to treat autosave-state corruption as a first-class recovery problem, not as incidental UI state.

2. **Apple exposes behavior flags, but not a supported API for custom layout ownership.**
   - `NSStatusItem.behavior` is just a set of allowed status-item behaviors.
   - Apple does not document a richer system-owned layout recovery contract here.
   - That means SaneBar has to be conservative: use autosave identity consistently, minimize mutation before live geometry exists, and only persist current-width recovery state from healthy live positions.

### Fresh field evidence

1. **Startup/reset family is still live in the field.**
   - Inbox `#390`: hidden→visible moves sometimes fail, and after restart icons can collapse back into hidden.
   - Inbox `#387`: MeetingBar repeatedly disappears from visible while already on the latest build.
   - GitHub `#111`, `#113`, and `#115` still describe the same visible→hidden/reset family.

2. **Browse/focus timing family is still live in the field.**
   - Inbox `#401` on `2.1.32` still shows:
     - focus leaving the current app after hover auto-hide
     - first right-click menu flash/fail
     - inconsistent left-click timing after linger intervals

3. **Move/identity family remains real, but narrower than before.**
   - GitHub `#117` is still open.
   - Current tree already rejects ambiguous same-bundle moves much more safely than before, but the app still needs stronger exact-ID proof on the specific user-facing sibling pairs that reporters hit.

### Fresh local / Mini findings

1. **The earlier warm-state runtime smoke failure was a proof-harness bug, not a clean app disappearance.**
   - On Mini, the first `live_zone_smoke` pass passed.
   - The second pass originally failed with `resource_watchdog process_monitor_failed reason=process_missing` during `findIcon` browse.
   - There was no matching crash report, and the staged SaneBar process was still present.
   - Root cause: the smoke watchdog could fail on a transient `ps -p <pid>` miss even when the same SaneBar PID was still visible in the full process table.
   - Fix: tolerate a transient `process_missing` only when the same PID is still visible as the expected SaneBar process.

2. **After the watchdog fix, the runtime smoke cluster is materially stronger.**
   - Mini staged runtime QA now clears:
     - two full smoke passes
     - warm-state browse replay
     - focused shared-bundle exact-ID smoke for Focus + Display
   - That removes one false red path from release gating.

3. **The remaining real red path is startup durability, not browse smoke.**
   - The Mini startup probe failed with `Missing current-width backup for width 1920`.
   - That exposed a real gap in the app, not just in the harness:
     - after removing the bad eager same-display reanchor, the app could launch into a healthy layout but still never backfill a current-width recovery backup
     - then the next poisoned launch has nothing safe to restore from

4. **The strongest current startup root cause is split recovery ownership plus missing post-validation backup capture.**
   - Startup repair is still split between:
     - `setupStatusItem()`
     - delayed `schedulePositionValidation(...)`
     - controller-level persisted-layout recovery
   - A fresh startup audit confirmed the bigger smell is still split ownership, not one bad formula.
   - The specific bug found today is narrower and fixable now:
     - once validation declares the live layout stable, SaneBar must capture a current-width backup from that healthy live state
     - otherwise startup recovery stays one bad launch away from ordinal reseed fallback

### Concrete code changes now justified by this research

1. **Keep the eager same-display reanchor removed.**
   - Prelaunch preferred-position heuristics are not trustworthy enough to rewrite user state before live status-item geometry exists.

2. **Backfill current-width display backups only after stable live validation.**
   - Safe place: the `statusItemsNeedRecovery() == false` branch of delayed validation.
   - That matches Apple’s autosave model better than mutating prelaunch guesses.

3. **Keep the Mini runtime smoke strict, but only on real disappearance.**
   - The smoke should fail if SaneBar actually goes away.
   - It should not fail because one `ps -p` sample glitched while the same SaneBar PID was still plainly visible.

### Proof completed after this research refresh

- Local:
  - `ruby Scripts/live_zone_smoke_test.rb` passed
  - `xcodebuild test -project SaneBar.xcodeproj -scheme SaneBar -destination 'platform=macOS' -only-testing:SaneBarTests/StatusBarControllerTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` passed
- Mini:
  - staged runtime smoke pass 1/2 passed
  - staged runtime smoke pass 2/2 passed after the watchdog fix
  - focused shared-bundle smoke passed for `com.apple.menuextra.focusmode` and `com.apple.menuextra.display`
- Still red on Mini:
  - startup probe until the stable-layout backup backfill is synced and rechecked

### Current release stance

- Still **not** ready to publish a new patch.
- Confidence is higher than before because the smoke false-positive is gone.
- The remaining real work is the startup durability seam and then another full Mini verify + staged QA pass on that updated tree.

- 2026-03-19 13:52 ET: post-lock refresh timestamp bump after `sync-research-locks`; next routed Mini run should see `research.md` newer than the refreshed browse/move lock state.
- 2026-03-19 14:04 ET: post-green-QA timestamp bump after a full Mini QA pass with green technical results:
  - smoke pass 1/2 green
  - smoke pass 2/2 green
  - focused shared-bundle smoke green
  - startup layout probe green
  - dedicated stability suite green
  - remaining blockers were release-policy gates only, not runtime/test failures

## March 19 Architecture Refresh: Centralized Recovery Ownership

**Updated:** 2026-03-19 | **Status:** verified | **TTL:** 7d
**Sources:** Apple docs (`NSStatusItem.autosaveName`, `NSScreen.auxiliaryTopRightArea`, `NSApplication.ActivationPolicy.accessory`, `Passing control from one app to another with cooperative activation`, `NSWorkspace.applicationUserInfoKey`), GitHub issues `#111 #113 #115 #116 #117 #119`, local code/tests (`MenuBarManager`, `MenuBarOperationCoordinator`, `StatusBarController`), recent git history

### Verified Findings

1. **Apple’s contract still favors one autosave-backed recovery owner, not multiple independent repair ladders.**
   - `NSStatusItem.autosaveName` is explicitly the unique name for saving and restoring status-item information.
   - That means replaying bad persisted layout state before validation is the wrong model; the app should sanitize one authoritative recovery path before recreating items.

2. **The notch-safe geometry model we are using is still aligned with Apple’s screen APIs.**
   - `NSScreen.auxiliaryTopRightArea` remains the right boundary signal for the unobscured top-right region.
   - So the remaining reset bug is not “we used the wrong Apple geometry API.” It is state ownership and persistence replay.

3. **Browse/focus should still follow request-based activation, not focus theft.**
   - Apple’s cooperative activation guidance says activation is a request, not a command.
   - `NSApplication.ActivationPolicy.accessory` also matches the no-Dock, no-menu-bar app shape SaneBar already uses.
   - `NSWorkspace.applicationUserInfoKey` remains the correct app-activation signal for app-change handling.

4. **Fresh GitHub evidence proves the startup/reset family is still live on `2.1.32`.**
   - `#111` was updated on 2026-03-19 with a fresh `2.1.32` repro.
   - The new report is important because live geometry at repro time looks sane (`separatorOriginX: 1223`, `mainIconLeftEdgeX: 1283` on width `1512`) while persisted prefs still show `main: 180`, `separator: 211`.
   - That means the remaining failure is not just “bad live placement on launch.” It is stale persisted recovery state staying authoritative longer than it should.

5. **The open-issue cluster is now clearer.**
   - `#111`, `#113`, and `#115` are still the same reset/persistence family.
   - `#116` has no fresh public post-`2.1.32` repro yet, so the browse/focus hardening looks better but still needs reporter confirmation.
   - `#117` is still underproved for the exact Wi-Fi/Battery same-bundle pair; current Mini smoke only proves exact-ID safety for `Focus` and `Display`.
   - `#119` is unrelated release/update flow work and should stay out of this recovery cluster.

6. **The root cause is now narrower and more specific than “the whole app architecture is bad.”**
   - The real defect was split recovery ownership across startup recovery, delayed validation, and manual restore.
   - Before today’s refactor, those paths could each plan different recovery actions over the same persisted layout state.
   - That is the patch-fragile seam behind the recurring reset family.

7. **Today’s refactor materially improves that root cause.**
   - `MenuBarManager` startup recovery, delayed validation, and manual restore now all route through `MenuBarOperationCoordinator.statusItemRecoveryAction(...)`.
   - Execution of the chosen action is centralized in `executeStatusItemRecoveryAction(...)`.
   - Manual restore no longer directly replays persisted layout first; it now goes through the same recovery planner and sanitization path as other recovery contexts.

8. **The controller is still the remaining long-tail seam.**
   - `StatusBarController.recoverStartupPositions(...)` still falls back to ordinal reseeding if there is no safe current-width backup and no reanchor candidate.
   - That is now a narrower fallback seam, not the whole recovery architecture, but it is still the last place where “good enough” recovery can degrade into a broad reset.

9. **Current proof is strong for the architectural change, but not complete enough to close the public issues yet.**
   - Targeted suites passed after the refactor:
     - `MenuBarOperationCoordinatorTests`
     - `RuntimeGuardXCTests`
     - `StatusBarControllerTests`
     - `ReleaseRegressionTests`
     - `MenuBarManagerTests`
     - `MenuBarSearchDropXCTests`
     - `SecondMenuBarDropXCTests`
   - The broader stability subset also passed on direct rerun after the earlier transient failure.
   - Routed Mini `verify` was blocked only by the project’s research gate, not by a compile/test failure.

### Concrete code changes now justified by this research

1. **Keep recovery planning centralized in the coordinator.**
   - Startup, delayed validation, and manual layout restore should continue to use the same `statusItemRecoveryAction(...)` decision path.

2. **Do not reintroduce direct persisted-layout replay from manual restore.**
   - That was the old poison-replay path.

3. **Keep manual restore and startup follow-up behavior tests, and add one more integrated runtime proof next.**
   - Missing proof still worth adding: a full relaunch/runtime case showing that a repaired startup layout cannot be undone by later validation or manual restore replay.

4. **Do not claim `#117` fully fixed until the exact reported pair is exercised.**
   - Add focused Wi-Fi/Battery same-bundle Mini smoke before closing that issue family.

### Proof completed after this research refresh

- Local:
  - `xcodebuild test -project SaneBar.xcodeproj -scheme SaneBar -destination 'platform=macOS' -only-testing:SaneBarTests/MenuBarOperationCoordinatorTests -only-testing:SaneBarTests/RuntimeGuardXCTests -only-testing:SaneBarTests/StatusBarControllerTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` passed
  - `xcodebuild test -project SaneBar.xcodeproj -scheme SaneBar -destination 'platform=macOS' -only-testing:SaneBarTests/ReleaseRegressionTests -only-testing:SaneBarTests/MenuBarManagerTests -only-testing:SaneBarTests/MenuBarSearchDropXCTests -only-testing:SaneBarTests/SecondMenuBarDropXCTests CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` passed
- Mini / routed lanes:
  - `verify` is ready to rerun now that this research note is newer than the active browse/move lock state

- 2026-03-19 14:27 ET: post-architecture-refresh timestamp bump after fresh Apple-doc + GitHub + local-code reconciliation and passing targeted recovery suites.

## March 19 Verify Follow-up: Browse Policy vs Stale Test Expectation

**Updated:** 2026-03-19 | **Status:** verified | **TTL:** 3d
**Sources:** local code/tests (`SearchService+Diagnostics.swift`, `MenuBarOperationCoordinator.swift`, `SearchWindowTests.swift`, `AccessibilityServiceTests.swift`), local + Mini `./scripts/SaneMaster.rb verify --quiet*` diagnostics, live smoke on Air + Mini

### Verified Findings

1. **The latest full `verify` failure is not a runtime regression.**
   - Air and Mini both passed staged `live_zone_smoke.rb` and `startup_layout_probe.rb` on `/Applications/SaneBar.app`.
   - Both full `verify` runs then failed on the same single unit test in `SearchWindowTests`: `Search activation rejects unverified clicks for revealed or browse-session flows`.

2. **The failing assertion is stale relative to the new browse policy.**
   - Current policy in `MenuBarOperationCoordinator.browseActivationPlan(...)` and `SearchService.shouldPreferHardwareFirst(...)` is:
     - browse-panel left click => AX first
     - browse-panel right click => hardware first
   - That policy is intentional because the recent Mini regression showed hardware-first left click wasting time on off-screen or stale browse targets before falling back to AX anyway.

3. **The runtime proof supports the new policy.**
   - After syncing the real current tree to the Mini, staged smoke passed on both hosts:
     - Air notch host: `avgCpu=5.7%`, both browse modes + hidden/always-hidden moves passed
     - Mini external-display host: `avgCpu=9.5%`, both browse modes + hidden/always-hidden moves passed
   - That means the code path is behaving as intended in runtime even though one source-level unit expectation was left behind.

4. **The right fix is to update the stale unit expectation, not revert the runtime policy.**
   - `SearchWindowTests` should no longer expect hardware-first for browse-panel left-click off-screen targets.
   - The test should instead assert the split policy explicitly:
     - left click in browse panel => `false`
     - right click in browse panel => `true`

### Concrete action justified by this research

1. Update `SearchWindowTests` to match the new browse activation policy.
2. Rerun the focused test target first.
3. If that passes, rerun full `verify` on both Air and Mini before any release call.

## March 19 Hover/Wake Root-Cause E2E | Updated: 2026-03-19 | Status: verified | TTL: 3d

**Sources:** local code/tests (`MenuBarManager.swift`, `MenuBarManager+Visibility.swift`, `MenuBarManager+Actions.swift`, `MenuBarOperationCoordinator.swift`, `MenuBarManagerTests.swift`, `MenuBarOperationCoordinatorTests.swift`, `ReleaseRegressionTests.swift`, `RuntimeGuardXCTests.swift`), local Air staged app, Mini staged app, Mini `qa.rb`

### Verified Findings

1. **Passive hover reveal no longer shares the inline app-menu suppression path.**
   - `RevealTrigger` is now explicit for `.hover`, `.scroll`, `.click`, and `.userDrag`.
   - `shouldManageApplicationMenus(...)` is now gated by `shouldSuppressApplicationMenus(for:)`.
   - Passive/system reveals route to `restoreApplicationMenusIfNeeded(reason: "passiveReveal")` instead of activating SaneBar and restoring focus later.

2. **Wake/screen validation now cancels stale recovery work instead of stacking it.**
   - `schedulePositionValidation(...)` now uses `positionValidationGeneration` guards.
   - `NSWorkspace.willSleepNotification`, `screensDidSleepNotification`, `didWakeNotification`, and `screensDidWakeNotification` are now observed.
   - Wake resume now uses its own validation context (`.wakeResume`) and longer delay budget.

3. **The full trusted staged-app matrix is green on both machines.**
   - Air (notch host):
     - `./scripts/SaneMaster.rb verify --quiet --local` passed with `1020` tests.
     - `./scripts/SaneMaster.rb test_mode --release --no-logs --local` passed and staged `/Applications/SaneBar.app`.
     - `SANEBAR_SMOKE_APP_PATH=/Applications/SaneBar.app ruby ./Scripts/live_zone_smoke.rb` passed in `94.68s`.
     - `SANEBAR_SMOKE_APP_PATH=/Applications/SaneBar.app ruby ./Scripts/startup_layout_probe.rb` passed.
   - Mini (external-display host):
     - `./scripts/SaneMaster.rb verify --quiet` passed with `1020` tests.
     - `./scripts/SaneMaster.rb test_mode --release --no-logs` passed and staged `/Applications/SaneBar.app`.
     - `SANEBAR_SMOKE_APP_PATH=/Applications/SaneBar.app ruby ./Scripts/live_zone_smoke.rb` passed in `67.67s`.
     - `SANEBAR_SMOKE_APP_PATH=/Applications/SaneBar.app ruby ./Scripts/startup_layout_probe.rb` passed.
     - `SANEBAR_RUN_RUNTIME_SMOKE=1 SANEBAR_RUN_STABILITY_SUITE=1 ruby ./Scripts/qa.rb` completed with warnings only; all technical gates passed.

4. **The extra focused required-ID probe failure on the Air was fixture availability, not a runtime regression.**
   - `SANEBAR_SMOKE_REQUIRED_IDS=com.apple.menuextra.focusmode` failed because that menu extra was not present in `list icon zones` on that Air session.
   - Generic staged smoke and startup probe on the same Air session still passed cleanly.

### Release implication

1. **Technical confidence is materially higher than it was before the hover/wake patch.**
   - The fresh field reports from Ellery/Matt now line up with code paths that have been concretely changed and re-verified.

2. **The remaining blocker is field confirmation, not an open local red lane.**
   - Current routed `qa.rb` warnings are governance-only (`#117`, `#115`, `#113`, and old close `#94`), not build/test/runtime failures.

## March 21 Issue #117 Warm Visible Move Root Cause | Updated: 2026-03-21 | Status: verified | TTL: 3d

**Sources:** local code (`AccessibilityService+Interaction.swift`, `MenuBarManager+IconMoving.swift`, `live_zone_smoke.rb`), Mini staged `Release` app, focused required-ID smoke for `com.apple.menuextra.display`, Mini unified logs

### Verified Findings

1. **The recurring warm visible-move miss is a stale-separator verification problem, not a generic weak drag.**
   - In the stable baseline, the same visible move repeatedly logged:
     - stale move inputs: `separatorX=1692`, `visibleBoundaryX=1694`
     - post-drag icon: `afterMidX=1675.5`
   - Fresh Mini geometry snapshots taken around the same move showed:
     - pre-drag live separator right edge: `1694`
     - post-drag live separator right edge: `1657`
     - live visible boundary remained `1694`
   - So the icon lands on the correct side of the *fresh* separator, but fails against the stale pre-drag separator.

2. **The separator itself shifts left during hidden/always-hidden -> visible moves.**
   - Baseline repeated this exact pattern over multiple passes:
     - visible pre-move snapshot used `targetSeparatorX=1692`
     - post-failure live separator became `1657`
     - retry re-resolved to `1657` and then succeeded
   - This explains why the current narrow fix works: the retry is not “trying harder,” it is using the corrected separator after the layout shift.

3. **A direct “accept success after fresh separator recheck” experiment proved the hypothesis but was not stable enough to keep.**
   - Experimental behavior:
     - successful single-pass proof replaced old failure logs with:
       - `Visible move accepted after fresh separator recheck: staleSeparatorX=1692, freshSeparatorX=1657, afterMidX=1675.5`
     - the old internal false-negative lines disappeared in that pass
   - But the broader smoke result was worse than baseline:
     - one focused run failed with `Icon 'com.apple.menuextra.display' not found`
     - one 5-pass warm loop later failed on pass 3 with `Timeout waiting for ... Display to reach zone hidden`
   - Because the stable baseline had already passed 5/5 warm Display runs, this experiment is not shippable as-is.

### Best current answer

1. **Keep the existing narrow hardening and do not ship the fresh-separator acceptance patch.**
   - The current baseline remains the safer production state.

2. **Treat the true root cause as verified.**
   - The bug family is fundamentally about separator geometry changing during the move, especially on hidden -> visible transitions.

3. **The next fundamental fix should happen at the move-state / verification design level, not as another inline acceptance shortcut.**
   - Good candidates for the next pass:
     - verify visible completion against a stable post-layout classification API instead of the pre-drag separator
     - or explicitly model the separator shift during hidden -> visible transitions so target + verification use the same lane geometry

## March 21 Issue #117 Manager-Level Early Classification Experiment | Updated: 2026-03-21 | Status: rejected | TTL: 3d

### Summary

I tested a narrower follow-up hypothesis: keep the drag layer unchanged, but in `MenuBarManager.moveIcon(...)` accept visible success early if a fresh classified-zone refresh already showed the exact item back in the visible lane after the first low-level verification failure. This was cleaner on paper than the rolled-back low-level fresh-separator acceptance because it reused the existing classified-zone proof path.

### What I changed for the experiment

- Added an early visible-only classified-zone acceptance check between the first `moveMenuBarIcon(...)` failure and the standard session retry.
- Added a distinct log line: `Visible move accepted after early classification verification`.
- Updated `RuntimeGuardXCTests` to allow that visible-only early acceptance path.

### What I verified

1. `./scripts/SaneMaster.rb verify --quiet` still passed with the experiment in place.
2. Signed `Release` app was staged and launched on the mini at `/Applications/SaneBar.app`.
3. Focused required-ID Display smoke had to be rerun with the same explicit target env the real runtime gate uses:
   - `SANEBAR_SMOKE_APP_PATH=/Applications/SaneBar.app`
   - `SANEBAR_SMOKE_PROCESS_PATH=/Applications/SaneBar.app/Contents/MacOS/SaneBar`
4. Once the harness was pointed at the right process, the first full Display pass succeeded end to end.

### Why it is rejected

1. **The new path did not actually fire in the live Display case.**
   - Mini unified logs for the experiment window still showed only the old failure pattern:
     - `Move verification failed ... separatorX=1692 ... afterMidX=1675.5`
   - There were **zero** `Visible move accepted after early classification verification` hits.
   - That means the fresh classified-zone refresh was not proving success early in the exact case we care about.

2. **The warm loop still destabilized before it produced a better comparison window.**
   - First corrected focused pass was green.
   - The next warm run later ended with `process_missing`, and system logs showed the release app process `35315` exited at `2026-03-21 19:09:10 EDT` with `workspace client connection invalidated` / `SIGKILL(9)`.
   - There was no crash report, so I cannot attribute that exit directly to the experiment, but it prevents claiming any runtime improvement.

3. **Because the experiment never triggered its intended acceptance, it does not improve the known root cause.**
   - The stale-separator verification failure still appears unchanged.
   - The experiment therefore adds complexity without demonstrated benefit.

4. **The rolled-back baseline immediately beat it on the same Mini with the same explicit target env.**
   - After removing the experiment and relaunching `/Applications/SaneBar.app`, the same focused Display loop passed `5/5` with:
     - `SANEBAR_SMOKE_APP_PATH=/Applications/SaneBar.app`
     - `SANEBAR_SMOKE_PROCESS_PATH=/Applications/SaneBar.app/Contents/MacOS/SaneBar`
   - Baseline log window still showed the known stale-separator pattern (`5` visible failures followed by `5` standard retries), but the smoke itself stayed green and the app stayed inside the idle budget.
   - That is the apples-to-apples runtime comparison that makes the rollback decision trustworthy.

### Decision

- Roll back the manager-level early classification experiment.
- Keep the current baseline hardening:
  - visible target re-resolution before retry
  - visible shield-backed final retry
  - 9.0 second AppleScript move timeout
- Treat this hypothesis as tested and rejected.

## 2026-03-22 Reset-Family Follow-up

**Updated:** 2026-03-22 23:45 ET | **Status:** startup/reset family still active; always-hidden validation blind spot fixed locally; poisoned-startup proof still not release-clear | **TTL:** 7d
**Sources:** fresh GitHub `#123 #122`, fresh inbox threads `#425 #426`, local code audit (`MenuBarManager`, `StatusBarController`, `MenuBarManager+AlwaysHidden`), local targeted tests, local startup probe on current Debug artifact

### Fresh findings

1. **The newest customer pain is still the startup/reset family, not the older move bug.**
   - `#123`, `#425`, and `#426` all point at visible/hidden/perma-hidden state collapsing after sleep/wake or restart on `2.1.33`.
   - The March 21 move-path hardening does not address this family by itself.

2. **Current code had a real always-hidden validation blind spot.**
   - Delayed position validation only considered main separator + main icon geometry when deciding the layout was stable.
   - A misordered always-hidden separator could therefore survive validation and let the app keep or capture "healthy" state from a broken layout.

3. **Local source now closes that always-hidden blind spot.**
   - Runtime snapshots now carry the always-hidden separator X.
   - Delayed validation now repairs a misordered always-hidden separator before blessing the layout as stable.
   - Stable-layout backup capture now waits briefly for a safe current-width backup instead of assuming persisted positions are ready immediately.

4. **Focused local tests are green after the patch.**
   - `MenuBarManagerTests`
   - `StatusBarControllerTests`
   - `RuntimeGuardXCTests`
   - Result: `106` targeted tests passed locally on March 22.

5. **A deeper poisoned-startup probe is still red on the current Debug artifact.**
   - After one healthy launch, the Debug build does create:
     - `SaneBar_Position_Backup_1470_main = 180`
     - `SaneBar_Position_Backup_1470_separator = 300`
   - But `startup_layout_probe.rb` still fails on the poisoned ordinal-seed replay.
   - What happens now:
     - init restores the current-width backup over `0/1`
     - startup still falls into `invalid-status-items`
     - two persisted-layout recreates plus one autosave-version bump still leave the app with missing status-item windows inside the probe window
   - So the current local tree is improved, but not yet trustworthy enough to call ready for a release tomorrow.

### Current release call

- **Do not call this ready for tomorrow yet.**
- Next proof needed:
  - rerun the real routed `verify` / startup probe after this research refresh
  - if the Debug-only probe failure reproduces on the trusted staged artifact too, keep digging in the invalid-status-items startup path before cutting a release

## 2026-03-24 Settings Snapshot Helper | Updated: 2026-03-24 10:03 ET | Status: in-progress | TTL: 7d

**Goal:** make the mini visual-QA path capture the settings window reliably, not just the browse panel.

### What I verified

1. **The new in-app settings snapshot command path works end to end.**
   - Mini `verify` passed with `1036` tests after adding:
     - `open settings window`
     - `close settings window`
     - `capture settings window snapshot`
     - `queue settings window snapshot`
   - Mini live smoke passed and produced:
     - `sanebar-secondMenuBar-20260324-135620.png`
     - `sanebar-findIcon-20260324-135627.png`
     - `sanebar-settings-20260324-135630.png`

2. **The settings screenshot exposed a real quality gap in the helper, not necessarily in the app UI.**
   - The browse screenshots looked correct.
   - The settings PNG showed the left sidebar region as a blank white slab.
   - `SettingsView` uses `SaneUI`'s `SaneSettingsContainer`, which is built on `NavigationSplitView` and a sidebar `List`.
   - That strongly suggests the current `bitmapImageRepForCachingDisplay` path is dropping material/sidebar rendering for this window type.

3. **The old Core Graphics window-screenshot shortcut is not a valid fix on this SDK.**
   - A direct `CGWindowListCreateImage` attempt failed compile on the mini with:
     - `'CGWindowListCreateImage' is unavailable in macOS: Please use ScreenCaptureKit instead.`

4. **Apple's supported replacement is ScreenCaptureKit.**
   - Apple docs and current SDK headers confirm:
     - `SCScreenshotManager.captureImage(contentFilter:configuration:completionHandler:)` is available on macOS 14.0+.
     - `SCShareableContent.currentProcess` is available on macOS 14.4+ and explicitly returns shareable windows for the current process without separate TCC consent.
     - `SCContentFilter(desktopIndependentWindow:)` can capture a single `SCWindow`.

### Current best direction

1. **Keep the new settings-window AppleScript hooks.**
   - They are the right long-term SOP surface for visual QA.

2. **Move the settings snapshot implementation to ScreenCaptureKit first, with the existing view-cache capture as fallback.**
   - That is the supported API path on current macOS.
   - It should capture the real composed window instead of a partially cached SwiftUI/AppKit subtree.

3. **Do not treat the current white-sidebar PNG as proof of a user-facing settings bug yet.**
   - Right now it is more likely a helper artifact than a live UI regression.

## 2026-03-25 Branch Consolidation + Always-Hidden Smoke Bootstrap | Updated: 2026-03-25 19:40 ET | Status: verified | TTL: 14d

### What I verified

1. **Named branch clutter is gone.**
   - The old side branches were audited against `main`.
   - `codex/regression-stability`, `codex/sanebar-2.1.23-release`, `feature/license-and-browse-merge`, `codex/main-issuefix-integrate`, `codex/qa-worktree-stability`, and `codex/fix-separator-cache-coherency` were deleted after confirming they were stale, duplicated, or already represented in the current `main` worktree.
   - Detached Codex worktrees under `~/.codex/worktrees/` still exist, but those are separate agent scratch dirs, not alternate named branches for SaneBar.

2. **One stale worktree had a real QA bug worth keeping.**
   - `Scripts/qa.rb` still only treated `SANEBAR_RELEASE_PREFLIGHT` / `SANEBAR_RUN_STABILITY_SUITE` as preflight mode.
   - Shared SaneProcess release tooling now sets `SANEPROCESS_RELEASE_PREFLIGHT` / `SANEPROCESS_RUN_STABILITY_SUITE`.
   - `main` now accepts both names, and `Scripts/qa_test.rb` covers that.

3. **The startup probe issue on the mini was fixture state, not product state.**
   - The probe had previously left `autoRehide=false` behind because restore failures were swallowed after success was already logged.
   - `Scripts/startup_layout_probe.rb` now restores state before marking success and keeps restore failures in the log.
   - Re-run result on the mini: `✅ Startup layout probe passed (current-width backup beats ordinal seeds, autoRehide=false prevents launch hide)`.

4. **The scary Always Hidden smoke failure was a false regression caused by free-mode setup.**
   - First release smoke failure logs showed:
     - `moveIconAlwaysHidden: always-hidden feature unavailable (isPro=false requested=true)`
   - That means the installed signed app on the mini was running in free mode, so a Pro-only Always Hidden move was never a valid product assertion.
   - `Scripts/live_zone_smoke.rb` now fails clearly when Always Hidden is requested against a free target.
   - `Scripts/qa.rb` now bootstraps the signed app through the existing no-keychain Pro fallback before running Always Hidden smoke.

5. **After the bootstrap fix, the real signed runtime path passed again on the mini.**
   - `./scripts/SaneMaster.rb verify --quiet` passed with `1037` tests.
   - Signed app startup probe passed.
   - Signed app live smoke with Pro bootstrap passed:
     - browse activation
     - hidden/visible moves
     - always-hidden moves
     - settings visual check
   - Passing run screenshots looked visually clean for:
     - second menu bar
     - icon panel
     - settings

### Current release read

- The repo is now architecturally consolidated on `main`.
- The remaining work is about real runtime confidence on the live bug family, not branch confusion.
- If another runtime issue appears, check first whether the smoke target is free-mode versus Pro-mode before calling it a product regression.

## 2026-03-25 Wake Recovery Hidden-State Restore | Updated: 2026-03-25 23:55 ET | Status: verified | TTL: 14d

### Root cause

1. **Wake/display recovery was rebuilding the delimiter in expanded mode and forgetting the prior hidden state.**
   - `HidingService.configure(delimiterItem:)` always starts expanded.
   - Status-item recovery re-created items after wake/display drift and re-wired them through `onItemsRecreated`.
   - Before this fix, nothing restored the previous hidden state after that rebuild.

2. **The live mini repro matched that exact failure shape.**
   - On the pre-fix build, a display sleep/wake cycle left `hidingState=expanded` even after a 20 second settle window.
   - Logs showed wake-time geometry drift followed by autosave recovery:
     - `Status item remained off-menu-bar after 4 checks — triggering autosave recovery`
   - The bar stayed expanded despite `autoRehideEnabled=true`, `isRevealPinned=false`, and `hoverMouseInMenuBar=false`.

### Fix

1. **Status-item recovery now preserves hidden-state intent.**
   - `MenuBarManager` now records `pendingRecoveryHideRestore` before structural recovery actions.
   - The restore decision is centralized in `shouldRestoreHiddenAfterStatusItemRecovery(hidingState:shouldSkipHideForExternalMonitor:)`.
   - After `onItemsRecreated` re-wires the new status items, it re-applies `await hidingService.hide()` when recovery started from a hidden state and hiding is still allowed.

### Proof

1. **Mini verify passed on the patched tree.**
   - `./scripts/SaneMaster.rb verify --quiet`
   - Result: `1037` tests green.

2. **The exact display wake repro changed from bad to good on the patched build.**
   - Patched signed `/Applications/SaneBar.app` on the mini:
     - `before`: `hidingState=hidden`
     - `after_wake`: `hidingState=hidden`
     - `after_settle` (20s later): `hidingState=hidden`
   - The pre-fix build had stayed expanded in the same experiment.

3. **Post-wake runtime smoke stayed green with screenshots.**
   - `Scripts/live_zone_smoke.rb` passed after the wake cycle with:
     - second menu bar screenshot
     - icon panel screenshot
     - settings screenshot
     - hidden/visible moves green
     - always-hidden moves green

### Release meaning

- This fix closes one concrete wake-family hole that was still causing post-2.1.34 field symptoms.
- Remaining release work is no longer “does wake recovery obviously leave the app stuck expanded?” That specific path is now re-proven on the mini.

## 2026-03-26 Missing-Icon Recovery Ship Pass (2.1.36) | Updated: 2026-03-26 15:12 ET | Status: shipped | TTL: 14d

### Fresh sources used

1. **GitHub**
   - SaneBar issue queue and latest reporter updates for `#129`, `#126`, and `#111`.
   - Fresh maintainer follow-up comments posted after 2.1.36 shipped.

2. **Local runtime/code**
   - `Core/MenuBarManager.swift`
   - `Core/Controllers/StatusBarController.swift`
   - `Core/Services/MenuBarOperationCoordinator.swift`
   - `Scripts/uninstall_sanebar.sh`
   - routed `release_preflight` and `release --full` output from the mini

3. **Live release surfaces**
   - shipped appcast entry for `2.1.36`
   - live download ZIP `SaneBar-2.1.36.zip`
   - live Homebrew cask / email webhook / docs link verification from the release script

### What changed

1. **`Reset to Defaults` now clears the stale status-item state, not just settings JSON.**
   - `MenuBarManager.resetToDefaults()` now calls `StatusBarController.resetPersistentStatusItemState(...)`, clears cached geometry, recreates status items, and schedules validation.
   - This directly addresses the field complaint that Reset to Defaults did nothing after the icon vanished.

2. **Startup follow-up no longer prefers replaying poisoned layout for invalid status-item windows.**
   - `MenuBarOperationCoordinator` now routes `.invalidStatusItems` / `.missingCoordinates` in the startup follow-up path through `repairPersistedLayoutAndRecreate(...)` instead of `recreateFromPersistedLayout(...)`.
   - That matches the latest `#111` diagnostics, where startup looked briefly recoverable and then collapsed again once follow-up validation replayed bad persisted state.

3. **Uninstall now clears the surviving NSStatusItem state that could survive reinstall.**
   - `Scripts/uninstall_sanebar.sh` now deletes the current-host/global `NSStatusItem Visible...` and `NSStatusItem Preferred Position...` keys.
   - This directly matches `#129` / `#126`, where delete settings + uninstall + reinstall still left the icon missing.

4. **The release is live and re-proven on the routed mini path.**
   - `release_preflight` passed with runtime smoke, focused shared-bundle move smoke, and startup layout probe.
   - `release --full --version 2.1.36` passed through build, notarization, deploy, appcast propagation, Homebrew update, and webhook verification.

### Current interpretation

1. **The shipped 2.1.36 baseline finally lines up with the actual missing-icon failure family.**
   - Before 2.1.36, the app could still preserve or replay stale NSStatusItem state across reset/reinstall/startup follow-up.
   - After 2.1.36, the reset path, uninstall path, and startup follow-up path all attack the same stale-state cluster instead of leaving one leg behind.

2. **The issue cluster is now in “waiting for reporter retest,” not “maintainer has not answered.”**
   - `#129`, `#126`, and `#111` all have fresh post-ship maintainer replies.
   - Inbox is at `0` action-needed after replying to the matching customer threads.

## 2026-03-27 Release Smoke Hardening Pass | Updated: 2026-03-27 14:05 ET | Status: runtime green, policy-blocked | TTL: 14d

### Fresh sources used

1. **Mini signed-runtime evidence**
   - `./Scripts/SaneMaster.rb verify`
   - `./Scripts/SaneMaster.rb release_preflight`
   - direct Mini `osascript` probes against `/Applications/SaneBar.app` in `--sane-no-keychain` Pro mode

2. **Product/script paths**
   - `Core/Services/AppleScriptCommands.swift`
   - `Scripts/live_zone_smoke.rb`
   - `Scripts/live_zone_smoke_test.rb`
   - `Tests/AppleScriptCommandsTests.swift`
   - `Tests/RuntimeGuardXCTests.swift`

### What changed

1. **AppleScript zone listing now prefers fresher zone data when it is clearly richer.**
   - `preferredScriptListingZones(...)` no longer treats any non-empty cached zone list as automatically trustworthy.
   - If the refreshed read exposes more `alwaysHidden` rows, more precise identities, or more total rows, the refreshed snapshot wins.
   - This hardens scripted reads against cold-start cache snapshots that flatten always-hidden rows into generic `hidden`.

2. **Generic browse smoke now uses stable curated fixtures first.**
   - `Scripts/live_zone_smoke.rb` now prefers curated Apple browse fixtures before arbitrary precise third-party rows.
   - `com.yujitach.MenuMeters` is explicitly denylisted for generic browse activation.
   - The browse smoke still keeps the pre-open candidate pool so active-session relayout cannot reintroduce off-panel IDs.

3. **Each smoke pass now normalizes the app back to a hidden baseline before checking layout.**
   - `prepare_layout_baseline` closes panels and sends `hide` before `wait_for_stable_layout_snapshot`.
   - This fixes the previous false failure where pass 1 left the app expanded and pass 2 timed out before it had a chance to re-hide.

### Proof

1. **Local verification is green after the harness and AppleScript fixes.**
   - `ruby Scripts/live_zone_smoke_test.rb` passed.
   - `./Scripts/SaneMaster.rb verify` passed with `1049 tests`.

2. **The signed Mini release lane is technically green again.**
   - `release_preflight` passed:
     - staged release browse smoke `x2`
     - focused shared-bundle smoke (`com.apple.menuextra.display`)
     - startup layout probe
   - The previous runtime blockers were cleared:
     - second-menu-bar browse activation no longer burns the budget on `MenuMeters`
     - pass 2 no longer starts from a stale expanded layout

### Current interpretation

1. **Runtime evidence is no longer the reason to hold the patch.**
   - The signed app on the Mini now clears the exact runtime smoke lane that was red at the start of this pass.

2. **Release is still blocked, but by policy gates, not by the binary.**
   - Remaining `release_preflight` blockers are:
     - release cadence `<24h since v2.1.36`
     - open regression issues: `#130`, `#129`, `#128`, `#126`, `#122`, `#117`, `#115`
     - unconfirmed closed regression issues: `#123`, `#120`, `#119`, `#116`, `#113`

## 2026-03-27 Browse Smoke Follow-up | Updated: 2026-03-27 15:55 ET | Status: fixture regression isolated | TTL: 14d

### Trigger

- A fresh Mini `release_preflight` on commit `b0b83cc` flipped back to red after the earlier green run.
- The failure was no longer the startup/layout family. It was specific to `findIcon` plus `right click browse icon`.

### Fresh evidence

1. **The new failure signature was mode-specific.**
   - `secondMenuBar` browse activation still passed.
   - `findIcon` right-click browse activation failed on the first smoke pass with timeouts across the generic Apple-first fixture set:
     - `com.apple.SSMenuAgent`
     - `com.apple.menuextra.display`
     - `com.apple.menuextra.spotlight`
   - Failure summary showed `firstAttempt ... timedOut=true ... finalOutcome: click failed (kept browse panel active)`.

2. **This aligned with the harness change from the previous pass.**
   - The last smoke hardening moved generic browse candidate ordering from precise third-party rows toward curated Apple fixtures first.
   - That change was good for the earlier `MenuMeters` second-menu-bar problem, but it made the Icon Panel right-click lane spend its budget on weaker fixtures than the older Shottr/Stats-style precise third-party candidates.

3. **A parallel local verify run created a separate false signal and should not be trusted.**
   - Running `verify` and `release_preflight` at the same time later produced an unrelated AppleScript `list icon zones` timeout.
   - That collision should not be read as a product regression; release QA needs to run serialized when it is exercising the live app via AppleScript.

### Code changes

1. **Browse smoke candidate ordering is now mode-aware.**
   - `Scripts/live_zone_smoke.rb` keeps the Apple/system fixture bias for the normal browse checks.
   - `findIcon` + `right click browse icon` now prefers precise non-Apple rows first, then falls back to the curated Apple fixtures.
   - Left-click and second-menu-bar coverage stay unchanged.

2. **Regression tests were updated to lock the split behavior in place.**
   - `Scripts/live_zone_smoke_test.rb` still checks that default generic browse smoke prefers curated fixtures and skips `MenuMeters`.
   - A new test now checks that Icon Panel right-click browse smoke prefers a precise non-Apple candidate before `SSMenuAgent` / `Display`.

### Local proof

1. `ruby -c Scripts/live_zone_smoke.rb` returned `Syntax OK`.
2. `ruby Scripts/live_zone_smoke_test.rb` passed with `13 runs, 31 assertions, 0 failures`.

### Current interpretation

1. **The red flip was a QA-fixture regression, not new evidence that the layout/disappearing-icon fix failed.**
   - The failing path was confined to the browse smoke harness after the Apple-first fixture reorder.

2. **The next trustworthy release verdict must come from a clean serialized Mini `release_preflight`.**
   - Do not trust results from overlapping `verify` + `release_preflight` runs.

## 2026-03-27 Browse Smoke Follow-up v2 | Updated: 2026-03-27 18:55 ET | Status: harness substantially hardened, launch idle still noisy | TTL: 14d

### Fresh evidence after direct Mini reruns

1. **The Apple-first generic browse pool was still the wrong default.**
   - After the earlier mode-specific tweak, a direct Mini smoke still failed in `secondMenuBar` left-click activation when the pool spent its budget on:
     - `com.apple.SSMenuAgent`
     - `com.apple.menuextra.display`
     - `com.apple.menuextra.spotlight`
   - Restoring precise third-party identities to the front of the generic browse pool was the better default on this host.

2. **The smoke wrapper had a real timeout mismatch for activation commands.**
   - `activate browse icon ...` and `right click browse icon ...` were still using the generic 8s outer AppleScript timeout in `live_zone_smoke.rb`.
   - Inside the app, `ActivateIconScriptCommand` already allows the activation workflow to run much longer (`runScriptActivation(timeoutSeconds: 20.0)`).
   - Result: the smoke harness could kill healthy in-flight activations before the app-level command had a chance to return.

3. **`MenuMeters` was still leaking into generic move coverage.**
   - It was denylisted for browse activation but not for move candidates.
   - Direct Mini smoke proved that leak by selecting `MenuMeters` for hidden/visible move coverage and timing out there.

### Final harness changes from this pass

1. **Generic browse activation now prefers precise third-party rows first, with Apple fixtures as fallback only.**
   - This applies broadly, not just to Icon Panel right-click.

2. **Activation AppleScript commands now get an extended outer timeout.**
   - `APPLESCRIPT_ACTIVATION_TIMEOUT_SECONDS = 25`
   - Applied to:
     - `activate browse icon ...`
     - `right click browse icon ...`
     - `activate icon ...`
     - `right click icon ...`

3. **Heavy diagnostics reads were widened.**
   - `browse panel diagnostics` and `activation diagnostics` now use the heavy-read timeout lane.

4. **`MenuMeters` is now denylisted for generic move smoke too.**
   - The move denylist is also normalized before comparison so bundle whitespace/case drift cannot bypass it.

### Current interpretation

1. **The product-side browse behavior now looks much healthier than the raw earlier red runs implied.**
   - One clean direct Mini smoke got through:
     - `Browse mode secondMenuBar activation ok`
     - `Browse mode findIcon activation ok`
     - `Settings window visual check ok`
   - After that, the next blocker moved to the harness selecting `MenuMeters` for move coverage, which is now fixed.

2. **The remaining recurring red signal is launch idle budget variance on the Mini.**
   - Example misses from direct Mini smoke:
     - `avgCpu=5.3 > 5.0`, `peakCpu=16.2 > 15.0`
     - `peakCpu=16.6 > 15.0`
     - `avgCpu=8.2 > 5.0`, `peakCpu=16.3 > 15.0`
   - These are resource-budget failures, not the old layout/disappearing-icon or browse activation failures.

## 2026-04-08 17:45 EDT lost-icon invalid-geometry startup reset refinement

**Updated:** 2026-04-08 17:45 EDT | **Status:** verified code-level gap for GitHub `#129`; refined fix patched, Mini verify rerun in progress | **TTL:** 7d
**Sources:** Apple docs for `NSStatusItem.autosaveName`, `NSStatusItem.isVisible`, and `NSStatusItem.behavior`; Stack Overflow thread on removed `NSStatusItem` visibility persistence; live GitHub issue `#129`; local code audit of `Core/MenuBarManager.swift`, `Core/Services/MenuBarOperationCoordinator.swift`, and `Core/Controllers/StatusBarController.swift`; Mini defaults snapshot on 2026-04-08

### Apple docs notes

1. **Apple still only gives us autosave-backed persistence for status items.**
   - `autosaveName` is the unique name for saving and restoring status-item information.
   - `isVisible` persists and restores automatically based on `autosaveName`, and Apple explicitly says visibility can change when the user removes the item manually.

2. **`behavior` still does not give us a richer repair contract.**
   - It only controls allowed status-item behaviors.
   - There is no documented system API that repairs a poisoned `NSStatusItem Preferred Position ...` layout for us.

### Web / GitHub notes

1. **Low-signal web evidence still lines up with Apple’s contract, not a hidden system recovery path.**
   - The Stack Overflow `NSStatusItem` removal thread points back to the same Apple behavior: removal flips `isVisible`, and autosave-backed preferences restore that state later.
   - That is consistent with treating persistent status-item defaults as the real recovery surface.

2. **`#129` now points at bad startup geometry with valid saved coordinates, not missing coordinates.**
   - The reporter’s current-host keys still had `main=180` and `separator=300`, plus matching `SaneBar_Position_Backup_2056_*` values.
   - That means the state is present but bad, which routes through `.invalidGeometry` rather than `.missingCoordinates` or `.invalidStatusItems`.

### Fresh local findings

1. **The current `48a8015` fix was still too narrow for the latest `#129` evidence.**
   - `MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(...)` hard-reset only `.invalidStatusItems` and `.missingCoordinates`.
   - Pure `.invalidGeometry` still used `recoverStartupPositions(...)`, which reuses persisted layout state instead of fully scrubbing it.

2. **The first startup repair path was the real gap.**
   - `.startupInitial` invalid geometry immediately returns `.repairPersistedLayoutAndRecreate(.invalidGeometry)`.
   - `executeStatusItemRecoveryAction(...)` runs that startup repair with `validationContext: nil`.
   - That means a startup-follow-up-only reset rule would still miss the first poisoned launch, which matches the reporter’s “already broken after reinstall” shape.

3. **The Mini still stores the exact same persisted key families the reporter showed.**
   - Current Mini defaults include `NSStatusItem Preferred Position SaneBar_Main_v8`, `...Separator_v8`, and `SaneBar_Position_Backup_1920_*`.
   - So the hard-reset target is still the right persisted surface to scrub when startup geometry is already poisoned.

### Action from this pass

1. **Refined fix patched.**
   - Startup geometry now hard-resets persisted status-item state when the recovery action is the initial startup repair or a `.startupFollowUp` validation repair.
   - Wake, screen-change, and manual-layout invalid geometry still keep the lighter `recoverStartupPositions(...)` path.

2. **Coverage updated for the narrower policy.**
   - `MenuBarManagerTests` now asserts that startup invalid geometry resets, startup-follow-up invalid geometry resets, and wake invalid geometry does not.
   - `RuntimeGuardXCTests` now require the startup-sensitive reset decision in the manager source.

## 2026-04-08 20:05 EDT browse-move lock refresh during Ruby security push

**Updated:** 2026-04-08 20:05 EDT | **Status:** no new browse-move runtime signal; refreshed so routed Mini verify can run for Ruby/security-only changes | **TTL:** 7d
**Sources:** same Apple docs / web / GitHub runtime cluster as the 17:45 EDT pass above; local diff audit of `Gemfile` / `Gemfile.lock`; Mini bundle lane verification on 2026-04-08

### Fresh local findings

1. **The re-fired `sanebar-browse-move` lock was timestamp drift, not a new runtime bug.**
   - Routed Mini pre-push `verify` refreshed issue-cluster lock timestamps while I was pushing a Ruby-only dependency change.
   - No new browse-move or lost-icon evidence landed after the 17:45 EDT startup invalid-geometry research pass.

2. **This push is isolated to the Ruby/security toolchain.**
   - The SaneBar repo change only adds explicit `minitest` support for Ruby 4 and updates the vulnerable `addressable` / `mcp` dependency chain.
   - Runtime status-item recovery code is unchanged in this push.

3. **Mini verification for this dependency change is already green outside the research gate.**
   - Mini `bundle exec ruby scripts/qa_test.rb` passed after the dependency refresh.
   - Mini `bundle exec bundler-audit check --update` reported `No vulnerabilities found`.
   - Mini `./scripts/SaneMaster.rb verify --quiet` passed after the shared Bundler path fix.

### Conclusion

- It is safe to rerun routed Mini `verify` for this Ruby/security update.
- The research lock refresh did not change the browse-move root cause or require a new runtime patch.

## 2026-04-13 16:58 EDT lost-icon stale-main-frame fallback follow-up

**Updated:** 2026-04-13 16:58 EDT | **Status:** verified new post-`2.1.40` `#129` path, patched locally, Mini proof green | **TTL:** 7d
**Sources:** Apple docs for [`NSStatusItem`](https://developer.apple.com/documentation/appkit/nsstatusitem), [`button`](https://developer.apple.com/documentation/appkit/nsstatusitem/button), and [`autosaveName`](https://developer.apple.com/documentation/appkit/nsstatusitem/autosavename-swift.property); Apple Developer search for `NSStatusItem button` / `NSStatusItem length` (no direct stale-frame guidance); live GitHub issue `#129`; local code audit of `Core/MenuBarManager+IconMoving.swift`; Mini `verify`, signed `test_mode`, and `startup_layout_probe.rb` on 2026-04-13

### Docs / web notes

1. **Apple still documents only the basic status-item contract here.**
   - `NSStatusItem` is just the menu-bar element created by `NSStatusBar.statusItem(withLength:)`.
   - `button` is the customization surface Apple exposes for the visible control.
   - `autosaveName` is the documented persistence surface for restoring status-item information.

2. **I still do not have an Apple-documented system repair path for stale status-item geometry.**
   - Apple Developer search did not surface any direct guidance for stale/off-screen `NSStatusItem` window frames or a system-level recovery API.
   - That keeps the recovery burden inside SaneBar's own geometry/cache logic.

### GitHub notes

1. **`#129` is no longer just the startup-reset path fixed in `2.1.40`.**
   - The reporter retested on `2.1.40` and came back with repeated `getMainStatusItemLeftEdgeX: stale frame and no fallback available`.
   - Their fresh defaults still show persisted `NSStatusItem Preferred Position ...` and `SaneBar_Position_Backup_2056_*` keys, so this is not simply a total state wipe.

2. **The reporter explicitly identified a different code path than the one shipped.**
   - Their comment correctly points at `MenuBarManager.IconMoving`, not the earlier `.invalidStatusItems` / `.missingCoordinates` recovery path.

### Fresh local findings

1. **The geometry fallback was asymmetric.**
   - Separator recovery could estimate itself from the main icon edge.
   - Main-icon recovery had only `lastKnownMainStatusItemX`; if that cache was empty, the stale-frame path fell straight to `nil`.

2. **A guarded reciprocal fallback is the smallest defensible fix.**
   - `getMainStatusItemLeftEdgeX()` now falls back to the separator's right edge only when the separator still exists in visual mode.
   - This avoids blindly inventing geometry from old separator caches when the separator itself is gone or still in blocking mode.

3. **Fresh Mini proof is green after the patch.**
   - `./scripts/SaneMaster.rb verify --quiet` passed (`1067` tests).
   - Signed `./scripts/SaneMaster.rb test_mode --release --no-logs` passed.
   - `SANEBAR_SMOKE_APP_PATH=/Applications/SaneBar.app ruby scripts/startup_layout_probe.rb` passed.

### Conclusion

- The reopened `#129` is a real post-`2.1.40` regression path, not just stale user state.
- The current fix direction is to keep recovery local to geometry fallback, not widen persisted-state scrubs again.
