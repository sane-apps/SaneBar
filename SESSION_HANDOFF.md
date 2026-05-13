# Session Handoff — SaneBar

**Last updated:** 2026-05-13
**Current public release:** `v2.1.52` (build `2152`)
**Next release candidate:** `v2.1.53` active local/Mini worktree changes, not published

## Current State

- 2026-05-13 active release-blocker work after `v2.1.52`:
  - Found and fixed a real customer-facing no-op in Browse Icons: the visible `+ Custom` group button could fail to activate from the release-like NSPanel. The action is now outside the horizontal scroll area and opens a native `NSAlert` prompt; the Mini sweep creates a QA group, verifies it persisted, captures a screenshot, and restores the user's settings file.
  - Settings window reuse now clamps unusably small frames without overriding a valid user-resized Settings window.
  - Runtime recovery/classification no longer treats estimated separator geometry as trustworthy for startup/status-item recovery or verification. Cache warmup runs before external-monitor always-show decisions.
  - Default `live_zone_smoke.rb` no longer fails on a noisy active CPU average when fewer than five samples exist; strict fixture smoke still enforces sustained active resource behavior.
  - Customer UI release proof is now standardized in `Tests/CustomerUIActions.yml` plus `Scripts/customer_ui_action_sweep.rb`. Generate smoke evidence first, then relaunch with `./scripts/SaneMaster.rb mode SaneBar pro --launch` immediately before the sweep. `test_mode --release --no-logs` is not sufficient for that sweep because Launch Services or smoke relaunch paths can drop the no-keychain/pro-mode argument.

- 2026-05-11 `v2.1.52` is live across the direct-download release lane:
  - Release artifact: `https://dist.sanebar.com/updates/SaneBar-2.1.52.zip`
  - Appcast: `https://sanebar.com/appcast.xml`
  - GitHub release: `v2.1.52`
  - Homebrew cask, website, appcast, and email/download worker all report `2.1.52`.
  - ZIP SHA256: `a8eaa831bc8716a37ededd9d323d21c9bad71950b61870aec2a57d3578d2a734`
  - Sparkle signature: `3vJkUJJ5DQjRGeBoNM3dpzbe/pCKdLpyo+b96/CzjsbOGsLO3qawbwe3BO+1Hl99yFzGhTlxqpDCWjWR8AJLCA==`

- 2026-05-11 post-`2.1.51` `#142` follow-up shipped in `v2.1.52`:
  - Fresh `2.1.51` reporter evidence showed `mainButton.identifier: SaneBar.main`, but recovery could still restore hidden mode before a trustworthy separator anchor existed, leaving validation in estimated/missing-coordinate loops.
  - Status-item recovery now defers collapsing the replacement delimiter until post-recovery warmup gets a live/cached separator anchor or exhausts the bounded warmup window, then reapplies the preserved hidden state. Recovery warmup no longer treats estimated geometry as success.
  - Menu-bar appearance overlay refreshes now run after status-item recovery and on wake/screens-wake/session-active events, with delayed retries (`0.15`, `0.5`, `1.5`, `3.0` seconds) for VM/remote-window topology settling.
  - `MenuBarOverlayView`/view model/color helpers were split out of `MenuBarAppearanceService.swift`; the service file is now under the 800-line hard limit.
  - Follow-up root cause found during release: app-domain preferred-position writes/removes needed explicit `UserDefaults.standard.synchronize()` before the external startup probe/relaunch path could reliably read them. Commit `75bdb71` added that sync and a source guard in `Tests/RuntimeGuardXCTests.swift`.

- Release QA hardening expanded after the SaneClick-style miss:
  - `Tests/CustomerUIActions.yml` lists 20 release-required customer-facing action families: status item routes, status/Dock menus, Browse Icons, Second Menu Bar, icon moves/groups/hotkeys, every Settings tab/action family, profiles, rules, appearance, shortcuts/automation, Health/repair, data import/export/reset, onboarding, license/about/support, Basic/Pro gates, and startup/wake/recovery.
  - `Tests/CustomerUIActionContractXCTests.swift` checks that the inventory covers shipped menu, URL, App Intent, AppleScript, settings, onboarding, license/about/support, and context-action surfaces.
  - The test also requires `.sane/customer_ui_action_receipt.json` to contain `action_results` with structured evidence for each action family, so a coarse “all IDs tested” receipt cannot pass.
  - `Scripts/customer_ui_action_sweep.rb` is Mini-only and now writes per-action evidence for all 20 action families. It drives Settings tabs through real AX sidebar selection, captures per-tab screenshots, verifies `sanebar://toggle`, `show`, `hide`, `settings`, `health`, `repair`, and `search?q=Sane`, runs AppleScript toggle/show/hide/layout/list/open/search/panel/settings diagnostics, checks fresh runtime smoke/startup artifacts, and validates menu/settings/onboarding/license/support source guards.
  - Shared SaneProcess guard now blocks release when a customer UI receipt lacks `action_results` for each release-required action. SaneProcess `release_guardrail_test.rb` passed `53/53`.

- Current release gate state:
  - Mini release script completed successfully with notarization accepted/stapled, GitHub release created, R2 download verified, appcast propagated with exactly one `v2.1.52` entry, Cloudflare Pages deployed, Homebrew updated, and email webhook deployed.
  - Post-release `./scripts/SaneMaster.rb release_preflight` passed release-critical checks after publishing: customer UI contract, monetization guardrails, API compatibility, appcast ZIP/version integrity, Homebrew, email webhook PRODUCT_CONFIG, Worker signed download, and runtime startup layout probe.
  - Remaining warnings are operational follow-up, not release blockers: UserDefaults/migration changed, 11 open GitHub issues, 6 pending customer emails, and evening release timing.

## Verification Ledger

- 2026-05-11 SaneBar Mini verify: `./scripts/SaneMaster.rb verify` passed `1159` tests.
- 2026-05-11 SaneBar Mini per-action sweep: `Scripts/customer_ui_action_sweep.rb` passed and wrote `.sane/customer_ui_action_receipt.json` at `2026-05-12T01:24:16Z`.
- 2026-05-11 SaneBar Mini release preflight: passed all runtime/customer UI/monetization/API/appcast/channel checks, blocked only by release cadence guard.
- 2026-05-11 SaneProcess guardrail tests: `ruby scripts/sanemaster/release_guardrail_test.rb` passed `53/53`.
- 2026-05-11 validation report: global app readiness still flags other app QA snapshots stale and Sonoma-minimum warnings for SaneBar/SaneClip. For this SaneBar release candidate, the active release blocker is cadence approval.
- 2026-05-11 SaneBar Mini release: `release.sh --full --version 2.1.52 --deploy` passed embedded QA (`1171` tests in release workspace), startup layout probe, archive, signature verification, Sparkle config verification, notarization, staple, GitHub release, R2 upload, appcast, Cloudflare Pages, Homebrew, email webhook, and strict post-release checks.
- 2026-05-11 SaneBar post-release preflight: `./scripts/SaneMaster.rb release_preflight` passed on Mini-routed workspace after publication. Runtime smoke covered Browse Icons, Second Menu Bar, settings visual check, Hidden/Visible moves, Always Hidden moves, shared-bundle relaunch smoke, native Siri/Spotlight exact-ID smoke, and startup layout probe.
- 2026-05-13 SaneBar Mini customer UI sweep: strict Pro fixture smoke, startup probe, default smoke, then `./scripts/SaneMaster.rb mode SaneBar pro --launch` followed by `ruby Scripts/customer_ui_action_sweep.rb` passed and wrote `.sane/customer_ui_action_receipt.json` at `2026-05-13T20:48:02Z`. Receipt covers 20/20 action families with portable per-action evidence artifacts; `icon-hotkeys-and-groups` includes real Mini click, persisted group creation, screenshot, and settings restoration evidence.
- 2026-05-13 SaneBar Mini full verify: `./scripts/SaneMaster.rb verify` passed `1172` tests. Remaining warnings are pre-existing SwiftLint opening-brace warnings in `Core/Services/AccessibilityService+Interaction.swift`.
- 2026-05-13 runtime proof: default `live_zone_smoke.rb` passed, strict fixture smoke passed with Lungo exact-ID activation/move checks, and `startup_layout_probe.rb` passed.
- 2026-05-13 SaneBar Mini release preflight: `./scripts/SaneMaster.rb release_preflight` passed with no blockers. Customer UI action contract passed `20` action families. Runtime fallback coverage passed shared-bundle Focus plus native Siri/Spotlight exact-ID smokes and startup layout probe. Remaining warnings: 18 uncommitted files, defaults/migration touched, 12 open GitHub issues, 8 pending emails, known Swift script parse warnings, and classified non-blocking regression issues.
- 2026-05-13 `v2.1.53` release-candidate preflight: after regenerating `SaneBar.xcodeproj` from `project.yml`, rebuilding the Mini Release app, and refreshing the customer UI receipt, `./scripts/SaneMaster.rb release_preflight` passed with no blockers. Customer UI action contract passed `20` action families at `2026-05-13T21:49:38Z`; runtime fallback coverage passed shared-bundle Focus plus native Siri/Spotlight exact-ID smokes and startup layout probe. Expected pre-publish warnings remain for appcast/Homebrew/email webhook still pointing at `v2.1.52`.

## Open Issues

- Keep `#142` open until the reporter confirms reboot/Dock-launch tint and startup recovery behavior on the next patch.
- Open regression issues currently classified non-blocking for release in QA: `#146`, `#145`, `#144`, `#143`, `#142`.
- Closed regression with fresh negative evidence classified non-blocking: `#133` (`release:compat-limited`).
- Do not close or comment on public GitHub issues without drafting exact text for approval first.

## Research Cache

- `.claude/research.md` has active SaneBar browse/move/runtime topics. Keep active topics short and graduate durable conclusions into this handoff, `ARCHITECTURE.md`, `DEVELOPMENT.md`, GitHub issues, or memory.
- Older March/April session addenda were compacted on 2026-05-11 to keep this active handoff under the 800-line cap. Durable release facts remain in `CHANGELOG.md`, Git history, GitHub releases/issues, and the current-state bullets above.

## Next

- Publish `v2.1.53` with release notes covering customer-facing UI/action reliability fixes; after publish, verify appcast/Homebrew/email webhook move from `2.1.52` to `2.1.53`.
- Keep `#142` open until the reporter confirms reboot/Dock-launch tint and startup recovery behavior on `v2.1.52` or the next patch.
- Continue expanding the customer-facing UI action contract to the other apps before their next releases.
