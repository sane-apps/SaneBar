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

## sanebar-browse-ux | Updated: 2026-05-04 | Status: verified | TTL: 14d
- Trigger: release guard blocked `release_preflight` for repeated Browse Icons / Second Menu Bar confusion reports.
- Apple docs: `NSStatusItem.isVisible` can remain true even when temporarily hidden for insufficient menu bar space; do not use visibility alone as visual proof. Source: https://developer.apple.com/documentation/appkit/nsstatusitem/isvisible
- Competitor/web: MacStories roundup notes Bartender-style tools rely on Accessibility/screen-observation because Apple provides no native menu-bar management API; Hidden Bar/Vanilla/Ice use divider/drawer/secondary-surface patterns. Source: https://www.macstories.net/roundups/managing-your-mac-menu-bar-a-roundup-of-my-favorite-bartender-alternatives/
- GitHub/web: Ice Tahoe issue #679 reports no visible/hidden items even after permissions and restart, matching the broader Tahoe observability/permission fragility family. Source: https://github.com/jordanbaird/Ice/issues/679
- Local finding: SaneBar release smoke now verifies both browse surfaces, but focused native Apple exact-ID smoke remains compatibility/open-close for browse activation. Host/third-party exact-ID lane is the release fixture for pinned Always Hidden browse activation.
- Decision: Release can proceed only when Browse Icons/Second Menu Bar screenshots are visually inspected and focused host exact-ID browse activation passes after pinning the fixture Always Hidden.

## sanebar-browse-move | Updated: 2026-05-04 | Status: verified | TTL: 14d
- Trigger: release guard blocked `release_preflight` for repeated icon move / visibility mismatch reports.
- GitHub local state: open issues #140, #142 are `release:patched-pending`; #141 is `release:needs-evidence`; #129/#136/#138 remain patched-pending, #137 compat-limited.
- Local root cause: pinned Always Hidden browse activation needed `showAll()` rather than `showHiddenItemsNow()`, fresh on-screen target resolution, bounded AX messaging timeouts, WindowServer reaction checks, and right-click hardware dispatch acceptance only for freshly resolved on-screen targets.
- Local verification: Mini `SaneMaster verify --timeout 900` passed after final patch; `live_zone_smoke_test.rb` passed 22/55; focused pinned-AH Lungo smoke passed; full QA runtime smoke passed with native compatibility lane and host exact-ID pinned-AH activation/move lane.
- Decision: Treat system extras (Siri/Spotlight) as compatibility/move coverage, not universal pinned-AH activation proof. Treat stable third-party exact-ID smoke as the release-blocking regression lane.
