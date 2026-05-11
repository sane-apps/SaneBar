# Research Cache

> Active research index only. Durable findings were promoted to Serena/memory on
> 2026-05-04. Older raw notes remain recoverable in git history.

## Bartender 6 Setapp Import Shape | Updated: 2026-04-29 | Status: active | TTL: 30d
- Keep active until 2026-05-29.
- Decision: SaneBar import/migration work must preserve Bartender/Setapp shape assumptions.
- Promotion target: ARCHITECTURE/DEVELOPMENT once the import lane is finalized.

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
