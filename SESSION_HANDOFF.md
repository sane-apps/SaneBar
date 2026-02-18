# Session Handoff — SaneBar

**Date:** 2026-02-17 (afternoon session)
**Last released version:** v2.1.2 (build 2102) — Released Feb 16
**Uncommitted changes:** Yes (current SaneBar working tree includes Bernard-hardening + test updates; see latest update section below).

---

## Update — 2026-02-17 15:50 ET (latest verification pass)

- Open SaneBar issues are now only `#65` (help/community request). `#66-#69` are closed.
- Release-readiness verification was rerun in 3 independent paths:
  1. `./scripts/SaneMaster.rb verify` (PASS, 106 tests)
  2. `./scripts/SaneMaster.rb monitor_tests SaneBar` (PASS)
  3. `./scripts/SaneMaster.rb test_scan -v` (PASS, no anti-patterns)
- Runtime smoke path:
  - `./scripts/SaneMaster.rb test_mode` (PASS)
  - single-instance launch confirmed (no duplicate SaneBar processes)
- New hardening added this session:
  - Icon-panel zone-drop fallback when classified cache misses current UI list (`Hidden -> Visible` no-op prevention)
  - Runtime guard tests for coordinate normalization and external-monitor skip policy
  - Repaired accidental duplicate `schemes.SaneBar.test.targets` entries in `project.yml`, regenerated project with `xcodegen generate`
- Preflight still warns (non-blocking by script):
  - uncommitted changes
  - migration/defaults touched
  - one open issue (`#65`, expected)
  - pending inbox threads (Bernard follow-ups + non-product legal/support mail)

---

## Done This Session

1. **Full status audit with live data** — emails, GitHub, traffic, sales, process health. Found 7 unread emails, 7 GitHub notifications, Bernard's video attachment, Martin's lost-icon bug.

2. **Unified `check-inbox.sh read`** — one call now shows body + attachments + reply status. No more hunting for separate subcommands. Reply detection uses Worker D1 first, Resend fallback with subject-matching + system-email filtering.

3. **Added Worker `/api/compose` endpoint** — new outbound emails now tracked in D1 `sent_replies` table. `check-inbox.sh compose` routes through Worker instead of direct Resend. Deployed to Cloudflare (version `7a38279a`).

4. **Upgraded `/status` skill** — email as primary signal source (step 2), positive comment scanning for marketing/testimonials, stale data warnings, media download instructions, investigate-don't-assume rule.

5. **Saved Serena memory** `status-data-freshness-rule` — handoff/issues are stale references, always pull live data.

6. **Updated docs** — global CLAUDE.md (email command reference), sane-email-automation ARCHITECTURE.md (new endpoints), status skill.

---

## Open GitHub Issues

| # | Title | Status |
|---|-------|--------|
| #69 | Second Menu Bar: clicking icons does nothing | Code on main (`554f52c`) — needs app testing |
| #68 | Reorder icons from panel | Code on main — needs app testing |
| #67 | Custom triggers (battery, schedule, Focus) | Code on main — needs app testing |
| #66 | Bartender import: Little Snitch | Code on main — needs app testing |
| #65 | Help Wanted: Demo Videos | Community outreach |

**Closed with new external activity:**
- #63 (can't build) — edsai: `project.yml` hardcodes `DEVELOPMENT_TEAM`, blocks external contributors. Needs fix or reply.
- #62 (second menu bar) — dpmadsen: panel always shows regardless of setting, wants second-row option
- #61 (second menu bar) — MartySkinner: notch laptops can't rearrange icons

---

## Email Inbox (7 action needed)

| # | From | Summary | Attachments | Replied? |
|---|------|---------|-------------|----------|
| 60 | GitHub T&S | DMCA vs Droppy — under review | none | NO (wait) |
| 59 | Martin Schotterer | Cmd-dragged divider, main icon vanished, can't recover. iMac M1, macOS 26.3 | none | **NO — needs reply** |
| 58 | Reddit Legal | DMCA vs Droppy — under review | none | NO (wait) |
| 57 | GitHub copyright | DMCA confirmation receipt | none | YES (submission sent) |
| 56 | Bernard (bledu) | v2.1.2: popovers close in 1-2 sec, wrong positions, erratic mouse. External monitor. | none | YES (earlier reply) |
| 55 | Bernard (bledu) | Same + full diagnostic: separator ordering errors, hardware click fallbacks at wrong coords (9, 1451), 40 items, external monitor | **1 video (1MB zip)** — downloaded to `~/Desktop/Screenshots/email55-bernard/` | YES (earlier reply) |
| 54 | Bernard (bledu) | Acknowledged bug report request | none | YES |

**Bernard's bug analysis (from email #55 diagnostics):**
- `[ERROR] Always-hidden separator is not left of main separator` — spamming
- Hardware click fallback coordinates: `(9.0, 1451.0)` — Y=1451 is window frame Y, not menu bar Y (~15)
- Environment: Mac14,2, external monitor VX3276-QHD, `disableOnExternalMonitor: true` but IS on external monitor

---

## DMCA Status

GitHub and Reddit both confirmed receipt. Ball is in their court. No action needed unless they ask for more info.

---

## Positive Feedback (marketing potential)

| Source | Who | Quote |
|--------|-----|-------|
| GitHub #64 | DrOatmeal | "Found your app on reddit, works great, love it." |
| Email #13 | Tony Dessablons | "I have already purchased SaneBar (I love it)" |
| Email #17 | aleeas user | "love your app. I will happily pay $5 if you offer..." |
| Email #42 | Glenn Crawford | "I purchased Saneclip because I loved the free version. You do amazing work." |

---

## Known Issues

- **SaneMaster false negative**: `verify` reports "Tests failed" but 44/44 pass. Test result parsing bug.
- **SSMenu icon drift**: Agent icon jumps zones on reveal. Inherent limitation.
- **SaneVideo faraday CVE**: faraday-retry doesn't support Ruby 4.0.1. Upstream fix needed.

---

## Serena Memories

- `status-data-freshness-rule` — NEW: handoff/issues are stale, always pull live data
- `session-2026-02-17-features-commit` — Feature commit details
- `polyform-shield-license-switch-feb17` — License switch details
- `sanebar-offscreen-cmddrag-proddebug-launch-fix-feb17` — Earlier session fixes

---

## Next Session Priorities

1. **Reply to Martin (#59)** — icon vanished after Cmd-drag. Likely needs `defaults delete` for NSStatusItem position keys.
2. **Investigate Bernard's bugs** — watch his video, analyze separator ordering logic, fix hardware click coordinate calculation
3. **Fix #63 contributor build** — `project.yml` hardcodes signing identity, blocking external contributors
4. **Test 4 features in running app** (#66-#69) — code committed but zero testing
5. **Ship v2.1.3** — after features verified + Bernard's bugs addressed
6. **Reply to positive feedback** — DrOatmeal, Tony, Glenn deserve personal thank-yous
7. **SaneMaster test parsing fix** — false "Tests failed" on 44/44 pass

---

## Infrastructure Changes (not git-committed)

- `~/SaneApps/infra/scripts/check-inbox.sh` — unified `read`, routed `compose` through Worker
- `~/SaneApps/infra/sane-email-automation/src/index.js` — added `/api/compose` endpoint (deployed)
- `~/SaneApps/infra/sane-email-automation/ARCHITECTURE.md` — updated endpoint table
- `~/.claude/CLAUDE.md` — added email command reference
- `~/.claude/skills/status/skill.md` — upgraded with email, positive feedback, stale data rules
