# Research Cache

> Active research index only. Durable findings were promoted to Serena/memory on
> 2026-05-04. Older raw notes remain recoverable in git history.

## Bartender 6 Setapp Import Shape | Updated: 2026-04-29 | Status: active | TTL: 30d
- Keep active until 2026-05-29.
- Decision: SaneBar import/migration work must preserve Bartender/Setapp shape assumptions.
- Promotion target: ARCHITECTURE/DEVELOPMENT once the import lane is finalized.

## sanebar-customer-reality-audit-scale | Updated: 2026-05-15 | Status: verified | TTL: 14d
- Trigger: user asked whether the audit was comprehensive enough and wanted gates that push the product forward instead of false-green release confidence.
- Finding: the prior broad customer UI contract still allowed weak evidence classes to hide customer risk: stale receipts, fixture/source/prose-only `full_runtime_completion`, pathless Mini evidence, generic/reused screenshots, and support/report media proof that did not prove large media delivery handling.
- Decision: SaneBar's `Tests/CustomerUIActions.yml` is the source of truth and now declares a standard `runtime_state_matrix` for `upgrade_update`, `cold_launch_relaunch`, `wake_unlock`, `display_topology`, `fullscreen_maximize_transition`, `basic_pro_mode`, and `support_report_media`. Shared SaneProcess Q13 makes those contract failures red in the global validation report.
- Current evidence state: stricter `customer_ui_contract --json --no-exit` is intentionally red until Dock menu, Control settings, Appearance customization, startup/wake/recovery, path-backed Mini artifacts, support-report evidence, and action-specific screenshots are actually generated.

## Release-Deployed Root-Cause Gate | Updated: 2026-04-28 | Status: active | TTL: 7d
- Keep active until 2026-05-05.
- Decision: release confidence must include field-confirmed issue state, exact build/version proof, and current Mini verification.
- Supersedes older "do not publish yet" release notes from 2026-04-28.

## Browse / Move / Wake Recovery Risk | Updated: 2026-04-28 | Status: active | TTL: 7d
- Keep active until 2026-05-05.
- Current risk family: browse/move geometry, stale main-frame fallback, exact-ID identity, wake/display recovery, and visible-lane state restoration.
- Durable model promoted to Serena memory `SaneBar/research_compaction_2026_05_04.md`.

## Field Confirmation Watchlist | Updated: 2026-05-04 | Status: active | TTL: 14d
- Track customer/GitHub field state for issues `#129`, `#136`, `#138`, `#137`, and `#133`.
- Use GitHub issue state and support evidence as source of truth before reopening old raw research.

## SaneBar Mixed Test Output Verification | Updated: 2026-05-09 | Status: verified | TTL: 30d
- Trigger: a Mini verify log showed a Swift Testing pass summary while xcodebuild still ended with `** TEST FAILED **`.
- Finding: `xcrun xcresulttool get test-results summary --path <xcresult>` is the source of truth for hidden XCTest failures in mixed Swift Testing/XCTest runs.
- Decision: do not classify xcodebuild failure footers as system-log noise. Inspect `.xcresult` first, then rerun only after the current source is confirmed to contain the expected fix.

## Promoted / Superseded Archive | Updated: 2026-05-04 | Status: promoted | TTL: 90d
- Menu bar geometry/recovery, stale-frame handling, live-anchor trust, exact-ID identity, and AppKit reorder limits were promoted to Serena/memory.
- Release/preflight/runtime smoke lessons, exact-ID smoke lanes, and tautology-test cleanup were promoted to Serena/memory.
- February and March raw sections are expired unless a linked issue becomes active again.

## sanebar-browse-ux | Updated: 2026-05-11 | Status: verified | TTL: 14d
- Trigger: fresh `verify` guard blocked after post-2.1.50 issue work; repeated Browse Icons / Second Menu Bar confusion still requires current research before changes.
- Apple docs: `NSStatusItem.isVisible` only means the item should be shown when there is room, so visual state still needs frame/window evidence and screenshots. Source: https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible
- Competitor/web: MacStories' Bartender alternatives roundup still shows the same divider/drawer/secondary-surface pattern across Hidden Bar, Vanilla, and Ice; no native Apple menu-bar management API replaces AX/window observation. Source: https://www.macstories.net/roundups/managing-your-mac-menu-bar-a-roundup-of-my-favorite-bartender-alternatives/
- GitHub/web: Ice Tahoe issue #679 remains relevant for the Tahoe observability family: permissions can be granted while visible/hidden item discovery is empty.
- Local finding: current #142 evidence is not a browse-panel UX report, but its logs overlap the same recovery substrate: repeated startup status-item validation failures, autosave namespace bumps, and later user interaction restoring usability.
- Decision: Keep browse UX changes gated by visual inspection and exact-ID smoke. For #142, do not treat a tint-only patch as complete unless status-item recovery also preserves the main button identity after recreation.

## sanebar-browse-move | Updated: 2026-05-11 | Status: verified | TTL: 14d
- Trigger: fresh runtime research required before more icon move / visibility mismatch fixes.
- GitHub local state: #136, #138, #140, #141, #143-#146 remain `release:patched-pending`; #137 remains `release:compat-limited`; #142 has new post-2.1.50 external evidence newer than the last maintainer reply.
- GitHub evidence: #142's 2026-05-10/11 report shows startup recovery looping through invalid status-item windows and missing live coordinates, then a final diagnostic where `mainButton.identifier` is `nil` even though `action=statusItemClicked:` and windows are valid.
- Local root cause update: recreated status items were manually rewired in `MenuBarManager.onItemsRecreated`, but the main button did not go back through `StatusBarController.configureStatusItems`, so the identifier/icon/action contract could drift after autosave recovery.
- Decision: Recovery fixes must preserve controller-owned button configuration, then warm geometry/AX caches. Treat stable third-party exact-ID smoke as the release-blocking move lane; native system extras remain compatibility/open-close coverage.

## sanebar-customer-ui-yaml-contract | Updated: 2026-05-12 | Status: verified | TTL: 7d
- Trigger: upgraded suite-wide customer UI manifests added proof levels and historical failure classes; SaneBar Mini verify failed in `CustomerUIActionContractXCTests` before runtime sweep could proceed.
- Local finding: the manifest remained valid YAML, but machine dumping changed top-level action indentation from `  - id:` to `- id:` and wrapped long scalar lines such as `Move to Hidden`. Existing tests were checking raw formatting instead of semantic contract content.
- Decision: keep the new proof metadata, but make SaneBar contract tests resilient to YAML indentation/wrapping before rerunning verification. This is a process-tooling failure, not an app runtime failure.

## sanebar-runtime-live-anchor-probe | Updated: 2026-05-13 | Status: verified | TTL: 14d
- Trigger: GitHub #147 reported dynamic SwiftBar/Fantastical visible items falling back into hidden on SaneBar 2.1.52 after screen-parameter validation logged repeated missing live coordinates.
- Local finding: runtime wake/screen-change validation intentionally stopped instead of autosave-repairing when only estimated separator coordinates were available. The safer fix is to avoid blessing estimated geometry in recovery/classification and warm separator caches before external-monitor always-show decisions, not to reveal protected hidden state in the background.
- Decision: status-item recovery and verification should use no-estimate separator reads. Warm caches around reveal/external-monitor paths, but do not use a background reveal probe as a release requirement.

## sanebar-customer-ui-release-proof | Updated: 2026-05-13 | Status: verified | TTL: 14d
- Trigger: release SOP now requires visual click-through proof for every customer-facing UI action before publishing.
- Local finding: the Browse Icons `+ Custom` group control was visible but could be a no-op in the release-like NSPanel; the customer sweep now catches it by clicking on the Mini, creating a QA group, checking persisted settings, capturing a screenshot, and restoring the user's settings file.
- Tooling finding: `test_mode --release --no-logs` can report no-keychain state while Launch Services drops the runtime argument, and smoke paths can relaunch the app without the Pro/no-keychain argument. Pro-only customer UI sweeps must generate smoke evidence first, then run `./scripts/SaneMaster.rb mode SaneBar pro --launch` immediately before `ruby Scripts/customer_ui_action_sweep.rb`; the sweep now fails closed if the running process args do not include `--sane-no-keychain`.
- Decision: `Tests/CustomerUIActions.yml` is the durable customer-action inventory. `.sane/customer_ui_action_receipt.json` is the release receipt and must contain portable structured evidence for all 20 action families before release preflight; final Mini contract receipt for `v2.1.53` passed at `2026-05-13T21:49:38Z` after regenerating `SaneBar.xcodeproj` from `project.yml`.

## sanebar-custom-appearance-fullscreen-suppression | Updated: 2026-05-15 | Status: verified | TTL: 14d
- Trigger: GitHub #142 reported SaneBar 2.1.53 still turning the custom dark tint black when launching apps such as Claude, while SaneBar 2.1.37 kept the tint stable.
- Local finding: `MenuBarAppearanceService.shouldSuppressOverlay` first treated large desktop windows below the menu bar as fullscreen; `2.1.54` fixed that settled geometry case but still hid the overlay immediately when the same frontmost app produced a transient fullscreen-shaped animation/snapshot window during maximize/fullscreen transitions.
- Testing hole: coverage used static synthetic window-info snapshots and the release smoke never sampled the custom tint during maximize/fullscreen transition frames, so it proved settled classification but not "no black blink between frames."
- Decision: fullscreen suppression now requires an onscreen, nontransparent, layer-0 content window and is delayed through stable recheck before hiding. Non-content/offscreen/transparent transition windows are ignored; thin third-party top-host strips still suppress immediately.

## sanebar-always-hidden-move-verification | Updated: 2026-05-15 | Status: verified | TTL: 14d
- Trigger: refund email #720 reported Hidden/Always Hidden moves failing and the Icon Panel flipping categories within seconds.
- Local finding: Always Hidden moves applied queued pin/unpin mutations before the physical drag was proven, and classified-zone verification could then read the optimistic pin state as success. Always Hidden target resolution also returned cached targets on the final retry when live separator geometry never became ready.
- Decision: zone-move verification now uses physical classification without pinned-ID promotion, Always Hidden move targets fail closed without live separator geometry, queued pin/unpin mutations apply only after successful movement, and delayed pin enforcement/reconciliation is skipped during the post-move settle window.

## sanebar-2.1.54-current-regression-root | Updated: 2026-05-16 | Status: active | TTL: 14d
- Trigger: GitHub #147 and #142 have fresh negative evidence after public 2.1.54; user asked for root-cause/process audit before another release.
- Apple docs checked: `NSWorkspace.didWakeNotification` and `screensDidWakeNotification` carry no `userInfo`, so wake recovery must sample live state after wake rather than expecting geometry from the notification. `NSWindow.CollectionBehavior.canJoinAllSpaces` is documented as menu-bar-like, and `fullScreenAuxiliary` is documented to display a window in the same Space as a fullscreen window.
- #147 local root cause: `MenuBarOperationCoordinator` intentionally waited twice for wake/screen missing-coordinate states and then returned `.stop(.missingCoordinates)`. Field logs show that exact path leaves users in a broken layout after wake. Current patch escalates bounded missing-coordinate runtime states to `recreateFromPersistedLayout` before stopping and lets wake/screen invalid geometry use a bounded autosave-version escalation.
- #142 local root cause: Custom Appearance tests classified fullscreen-shaped windows from static CGWindow snapshots, but did not visually sample transition frames or fullscreen Spaces. Current patch stops hiding the overlay for fullscreen-shaped content windows, keeps only thin third-party top-host suppression, and adds `.fullScreenAuxiliary` to the overlay window collection behavior.
- Process gap: release confidence still depended on stale/missing customer UI receipt artifacts and did not require fresh visual proof for wake/fullscreen transition rows. The current patch requires Mini customer UI evidence, wake/display proof, fullscreen/maximize visual samples, no full-display screenshot fallback, and customer-action row evidence.
- Additional 2026-05-16 process gap: bumping `project.yml` to 2.1.55 without regenerating `SaneBar.xcodeproj` built a stale 2.1.54 app. Project QA now compares project.yml and xcodeproj marketing/build versions and fails with `Run xcodegen generate after bumping project.yml`.
- Current proof: Mini `verify --timeout 600` passed 935 tests; customer UI sweep passed on a fresh 2.1.55 build and `customer_ui_contract --no-exit` passed 20/20 action families at 2026-05-16T18:58:13Z. Release preflight runtime smoke passed native Siri/Spotlight exact-ID Hidden/Visible and Always Hidden round trips plus startup layout probe, but release remains blocked by open #142, dead 2.1.54 appcast enclosure, Homebrew/appcast/website/worker channels still pointing at 2.1.54, and the live email worker warning.

## sanebar-browse-ux | Updated: 2026-05-15 | Status: verified | TTL: 14d
- Trigger: pre-push guard required fresh Apple docs, competitor UX, GitHub, and local research before more Browse Icons / Second Menu Bar behavior changes.
- Apple docs: `NSStatusBar.system` starts on the right side of the menu bar and grows left; `NSStatusBar` docs warn status items are not guaranteed to be available because menu bar space is limited. Apple HIG says macOS may hide menu bar extras when space is constrained and fullscreen can hide the menu bar until pointer reveal. Source: developer.apple.com AppKit `NSStatusBar` / HIG menu bar pages, checked 2026-05-15.
- Competitor UX: Bartender exposes hidden items by swipe, scroll, click, or hover; Bartender/Ice public reports show section drift, hover reveal, and crowded/notch menu bars are a category-wide failure mode, not a SaneBar-only edge. Sources checked 2026-05-15: macbartender.com, Ice issue #344, Badgeify Ice compatibility note, Macworld Bartender 4 review.
- GitHub context: SaneBar `#143` and `#146` remain browse/rehide reports labeled `release:patched-pending`; `#140` and refund email `#720` overlap with Browse Icons / Second Menu Bar move expectations.
- Local decision: Browse UX verification must include real Mini exact-ID runtime activation for both `secondMenuBar` and `findIcon`, not only source guards. `2.1.54` preflight passed exact-ID Focus/Siri/Spotlight Browse mode open/close plus customer UI contract coverage for 20 action families.

## sanebar-browse-move | Updated: 2026-05-15 | Status: verified | TTL: 14d
- Trigger: pre-push guard required fresh research before more icon move / visibility mismatch fixes.
- Apple docs constraint: AppKit status items live in a constrained system status bar where availability/position can change; this supports treating physical AX geometry as the source of truth and failing closed when live separator geometry is unavailable.
- Competitor context: Ice issue #344 and Badgeify's compatibility note describe items unexpectedly moving between Hidden and Always Hidden sections; Reddit/Bartender reports describe icons rearranging, refusing to hide, or hidden bars not appearing after macOS changes. These reinforce that optimistic persisted state must not be accepted as movement proof.
- GitHub context: SaneBar `#138` and `#140` directly report drag/move failures between hidden, always hidden, and visible sections; `#136`, `#139`, and `#147` are adjacent persistence/reset reports; refund email `#720` gives the same symptoms on the latest public build.
- Local decision: `2.1.54` delays queued pin mutation until after successful physical move verification, excludes pinned-ID promotion from move verification classification, rejects cached-only Always Hidden targets, and skips pin enforcement/reconciliation while a manual zone move is settling.
