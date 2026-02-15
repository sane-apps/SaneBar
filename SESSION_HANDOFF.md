# Session Handoff - Feb 14, 2026 (Evening)

## What Was Done This Session

### Freemium Flow Audit & Security Hardening
- **Full audit** of all 10 permission/licensing flows (new user, early adopter, paid pro, settings reset, profile load, X-button close, mid-onboarding activation, etc.)
- **Bug fix: resetToDefaults()** — wasn't preserving `hasSeenFreemiumIntro`. Free user resets settings → detected as early adopter → free Pro. Fixed in `SettingsController.swift`.
- **Bug fix: OnboardingController X-button** — Closing onboarding via X didn't call `dismiss()`, leaving `hasCompletedOnboarding=false` → onboarding re-triggers every launch. Fixed by adding `NSWindowDelegate` with `windowWillClose`. Class now inherits from `NSObject`.
- **Full /critic review** — 21 NVIDIA model reviews (7 perspectives × 3 models: mistral, deepseek, qwq). All returned successfully. Consensus findings documented below.

### Critic Findings (Accepted Risks)
These were identified but intentionally NOT fixed:
- **Settings JSON tampering** → free Pro (requires Terminal knowledge, $10 app)
- **"early-adopter" keychain string forgeable** (requires Terminal, macOS keychain protection)
- **Offline attack** (30-day grace is reasonable for indie app)
- **Old profile load vulnerability** (can't fix without breaking legitimate early adopter detection)
- **Race condition mid-onboarding** (theoretical — `@ObservedObject` handles reactively)

### GitHub Issue Triage
- **Closed:** #59, #60, #61 (all responded to, resolved)
- **Open:** #62 (Second Menu Bar always shows as panel — existing bug), #63 (can't build from source — project.yml issues)

### Files Modified
- `Core/Controllers/SettingsController.swift` — Preserve `hasSeenFreemiumIntro` in resetToDefaults()
- `UI/Onboarding/OnboardingController.swift` — NSWindowDelegate, windowWillClose, NSObject inheritance

---

## What Was Done Earlier Today (Feb 14 Afternoon)

### CX Parity Fixes — SaneClip (triggered by Glenn's email)
- Glenn reported SaneClip paste not working → root cause: missing Accessibility permission, silently failed
- **Fixed SaneClip** with: runtime permission detection (NSAlert), DiagnosticsService, FeedbackView, onboarding enforcement
- **Updated docs-audit skill** — added 15th perspective: `cx-parity` (Glenn Test)
- **Freemium plan written** — see `.claude/plans/woolly-shimmying-torvalds.md` (not yet implemented)
- **Replied to Glenn's email** with fix instructions + committed to Monday update

---

## Open GitHub Issues

| # | Title | Status | Action Needed |
|---|-------|--------|---------------|
| 63 | Can't build from source | `edsai` gave detailed report: project.yml hardcodes DEVELOPMENT_TEAM and references monorepo-only file | Fix project.yml for external contributors |
| 62 | Second Menu Bar always shows as panel | `dpmadsen` says setting doesn't work | Investigate — may be Browse Icons mode bug |

---

## Open Emails

| # | From | Subject | Action |
|---|------|---------|--------|
| 44 | You (morning report) | LemonSqueezy sales fetch broken | Fix morning report script |
| 43 | Glenn Crawford | SaneClip paste still broken after Accessibility toggle | Needs follow-up — his version predates diagnostics feature. May need remote debug or new build. |

---

## Sales Snapshot (Feb 14)

| Period | Orders | Revenue | Net |
|--------|--------|---------|-----|
| Today | 1 | $6.99 | $6.14 |
| This Week | 31 | $190.82 | $165.78 |
| All Time | 198 | $1,025.82 | $875.53 |

---

## Serena Memories Saved
- `onboarding-freemium-flow-audit` — Bug fixes, critic findings, architecture notes
- `zone-classification-architecture` — Unified backend design (prev session)
- `second-menu-bar-rendering` — Icon sizing, panel level (prev session)
- `test-quality-rules` — Mock-passthrough trap (prev session)

---

## Onboarding Simplification Plan
Plan exists at `.claude/plans/woolly-shimmying-torvalds.md`. NOT YET IMPLEMENTED.
Simplifies 7-page onboarding to teach one concept per screen. Removes "Choose Your Style" preset picker. Applies Smart defaults automatically.

---

## NEXT SESSION — Priorities

1. **Reply to Glenn** (SaneClip) — paste still broken after Accessibility toggle. His version doesn't have diagnostics. May need to send him a new build or remote debug.
2. **Issue #63** — Fix project.yml for external contributors (remove hardcoded DEVELOPMENT_TEAM, conditional MoveToApplications.swift)
3. **Issue #62** — Investigate Second Menu Bar setting not applying
4. **Fix morning report script** — LemonSqueezy sales fetch broken
5. **CX Parity Phase 2** — Shared SaneUI infrastructure
6. **Onboarding simplification** — Implement plan from `.claude/plans/woolly-shimmying-torvalds.md`
7. **Website update** — Show both viewing modes on sanebar.com (carryover)
8. **Full notarized release** — Include today's bug fixes

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
9. **Tests must call real code** — Mock-passthrough tests are useless.
10. **NSPanel level `.floating`** — `.statusBar` blocks tooltips.

---

## Mac Mini Test Environment

- **SSH:** `ssh mini`
- **Deploy:** `ruby ~/SaneApps/infra/SaneProcess/scripts/sane_test.rb SaneBar`
- **Bundle ID:** `com.sanebar.dev` for dev, `com.sanebar.app` for prod
- **ALWAYS use sane_test.rb** — handles kill, clean, TCC reset, build, deploy, launch, logs
