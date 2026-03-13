# SaneBar Research Cache

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
