# SaneBar Development Guide (SOP)

> [README](README.md) · [ARCHITECTURE](ARCHITECTURE.md) · [DEVELOPMENT](DEVELOPMENT.md) · [PRIVACY](PRIVACY.md) · [SECURITY](SECURITY.md)

**Version 1.1** | Last updated: 2026-02-02

---

## Sane Philosophy

```
┌─────────────────────────────────────────────────────┐
│           BEFORE YOU SHIP, ASK:                     │
│                                                     │
│  1. Does this REDUCE fear or create it?             │
│  2. Power: Does user have control?                  │
│  3. Love: Does this help people?                    │
│  4. Sound Mind: Is this clear and calm?             │
│                                                     │
│  Grandma test: Would her life be better?            │
│                                                     │
│  "Not fear, but power, love, sound mind"            │
│  — 2 Timothy 1:7                                    │
└─────────────────────────────────────────────────────┘
```

→ Full philosophy: see the private SaneApps operator overlay.

---

## ⚠️ THIS HAS BURNED YOU

Real failures from past sessions. Don't repeat them.

| Mistake | What Happened | Prevention |
|---------|---------------|------------|
| **Guessed API** | Assumed `AXUIElement` has `.menuBarItems`. It doesn't. 20 min wasted. | `verify_api` first |
| **Assumed permission flow** | Called AX functions before checking `AXIsProcessTrusted()`. Silent failures. | Check permission state first |
| **Skipped xcodegen** | Created `HidingService.swift`, "file not found" for 20 minutes | `xcodegen generate` after new files |
| **Kept guessing** | Menu bar traversal wrong 4 times. Finally checked apple-docs MCP. | Stop at 2, investigate |
| **Trusted codesign verify** | DMG rejected because an executable was inside a `.zip` resource (Apple inspects it; `codesign --deep` doesn’t). | Follow docs/NOTARIZATION.md + preflight zips |
| **Classified Hidden as "offscreen"** | Find Icon showed **Hidden empty** + **Visible everything** (because SaneBar hides via separator expansion, not by pushing icons off-screen). | Hidden/Visible is **separator-relative**: compare icon X against `separatorItem.window.frame.origin.x` |
| **Deleted "unused" file** | Periphery said unused, but `ServiceContainer` needed it. Broke build. | Grep before delete |
| **Modified icon moving logic** | 6-step stealth drag (100ms settle) is battle-tested since v1.0.12. Baseline commit `3cb6e9b`. | **DO NOT MODIFY** icon moving without reading `docs/DEBUGGING_MENU_BAR_INTERACTIONS.md` |

**The #1 differentiator**: Skimming this SOP = 5/10 sessions. Internalizing it = 8+/10.

**"If you skim you sin."** — The answers are here. Read them.

### Why Catchy Rule Names?

Memorable rules + clear tool names = **human can audit in real-time**.

Names like "SANEMASTER OR DISASTER" aren't just mnemonics—they're a **shared vocabulary**. When I say "Rule #5" you instantly know whether I'm complying or drifting. This lets you catch mistakes as they happen instead of after 20 minutes of debugging.

---

## 🚀 Quick Start for AI Agents

**New to this project? Start here:**

1. **Read Rule #0 first** (Section "The Rules") - It's about HOW to use all other rules
2. **All files stay in project** - NEVER write files outside `/Users/sj/SaneApps/apps/SaneBar/` unless user explicitly requests it
3. **Use SaneMaster.rb for project work** - `./Scripts/SaneMaster.rb verify` for build+test. Public GitHub CI may call `xcodebuild test` only in the checked-in no-secrets workflow because SaneMaster is local infrastructure.
4. **Self-rate after every task** - Rate yourself 1-10 on SOP adherence (see Self-Rating section)

Bootstrap runs automatically via SessionStart hook. If it fails, run `./Scripts/SaneMaster.rb doctor`.

**Your first action when user says "check our SOP" or "use our SOP":**
```bash
./Scripts/SaneMaster.rb bootstrap  # Verify environment (may already have run)
./Scripts/SaneMaster.rb verify     # Build + unit tests
```

**Key Commands:**
```bash
./Scripts/SaneMaster.rb verify     # Build + test (~30s)
./Scripts/SaneMaster.rb test_mode  # Kill -> Build -> Launch -> Logs (full cycle)
./Scripts/SaneMaster.rb logs --follow  # Stream live logs
```

**System**: macOS 26.2 (Tahoe), Apple Silicon, Ruby 3.4+

---

## Project Rules

Global SOP lives in the nearest `AGENTS.md`. This file only adds SaneBar-specific operational rules.

| Rule | SaneBar meaning |
|------|-----------------|
| #0 Name the rule | Say which rule applies before changing code or runtime state. |
| #1 Stay in lane | Edit inside `/Users/sj/SaneApps/apps/SaneBar/` unless the user approves shared infra changes. |
| #2 Verify first | Check Apple APIs with `verify_api`, apple-docs, or SDK interfaces before coding. |
| #3 Two strikes | After two failures, stop retries, read the error/transcript, and research the root cause. |
| #4 Green means go | Do not claim done with red tests, stale receipts, or skipped required gates. |
| #5 Use SaneMaster | Use `./Scripts/SaneMaster.rb` for build, test, launch, preflight, and release workflows. |
| #6 Full cycle | For app/runtime changes: verify, kill, launch/test_mode, inspect logs or screenshots. |
| #7 Real tests | Add or run tests that can fail for the bug. No tautologies. |
| #8 Write bugs down | Track active bugs in issues/memory/handoff with status and evidence. |
| #9 New files | Run `xcodegen generate` after adding Swift/source files. |
| #10 Size cap | Keep active startup docs under 500 lines unless there is a clear single-purpose reason. |
| #11 Fix tools | If SaneMaster, QA, or receipt tooling is wrong, fix the tool instead of bypassing it. |
| #12 Stay responsive | Use subagents for broad reviews or parallel investigation when useful. |

Plan format: cite the rule in each substantive step, e.g. `[Rule #5] Run ./Scripts/SaneMaster.rb verify`.

Circuit breaker: repeated failures mean stop, inspect `./Scripts/SaneMaster.rb breaker_errors`, research with local code/docs/MCPs, then continue with a concrete plan. Do not guess a third time.

Script casing: the checked-in project helper directory is `Scripts/` with a capital `S`. Use `./Scripts/...` in repo docs and commands; lowercase may work on default macOS volumes but is not portable.

---

## Available Tools

Full script catalog with descriptions: see **ARCHITECTURE.md § Operations & Scripts Reference**.

### Key Commands

```bash
./Scripts/SaneMaster.rb verify          # Build + tests
./Scripts/SaneMaster.rb verify --clean  # Full clean build
./Scripts/SaneMaster.rb test_mode       # Kill -> Build -> Launch -> Logs
./Scripts/SaneMaster.rb logs --follow   # Stream live logs
./Scripts/SaneMaster.rb verify_api X    # Check if API exists in SDK
ruby Scripts/qa.rb                      # Pre-release QA checks
```

### Tool Decision Matrix

| Situation | Tool |
|-----------|------|
| Build/test | `./Scripts/SaneMaster.rb verify` (Rule #5) |
| Launch for testing | `sane_test.rb SaneBar` (prefers the configured remote build host) |
| API signature check | `./Scripts/SaneMaster.rb verify_api` (Rule #2) |
| API usage examples | `apple-docs` MCP |
| Library docs | `context7` MCP |
| Mock generation | `./Scripts/SaneMaster.rb gen_mock` |
| Pre-release QA | `ruby Scripts/qa.rb` |

### Build Strategy

```bash
# Prefer the configured remote build host for builds and testing
ssh -o ConnectTimeout=3 "$SANEAPPS_BUILD_HOST" 'echo ok' 2>/dev/null && echo "REMOTE" || echo "LOCAL"

# Remote build host (preferred)
ruby "$SANEAPPS_INFRA/scripts/sane_test.rb" SaneBar

# Local fallback (only if the remote host is unreachable)
ruby "$SANEAPPS_INFRA/scripts/sane_test.rb" SaneBar --local
```

---

## Release Process

1. **Bump version** — update MARKETING_VERSION + CURRENT_PROJECT_VERSION in `project.yml`
2. **Preflight** — `./Scripts/SaneMaster.rb release_preflight` (9 safety checks)
   - Enforces 24h soak window between releases
   - Runs project QA with regression close confirmation checks
   - Requires a fresh customer UI action receipt from `Tests/CustomerUIActions.yml`
     and `.sane/customer_ui_action_receipt.json`; the receipt must prove every
     customer-facing action family with structured evidence, not just list IDs.
   - Runs dedicated stability suite (upgrade-state + second-menu-bar paths)
   - Runs the staged-app runtime lane plus focused exact-ID smokes. Missing
     deterministic fixture/sentinel coverage is a release blocker, not a skip:
     - shared-bundle Apple extras: Control Center / Clock / Focus / Wi-Fi / Battery / Display
     - native Apple extras: Siri / Spotlight
     - host exact-id sentinel: Little Snitch top-bar items or a deterministic replacement fixture
   - For arrangement / drag / display-recovery patches, keep one manual external-monitor disconnect/reconnect cycle in the release checklist until that path is automated
   - Live-anchor structural recovery contract: dirty startup, reboot, wake, and display-recovery proof must show live SaneBar status-item anchors and a valid structural snapshot before saved Visible/Hidden state or cached geometry is trusted. If anchors are missing or stale, recovery must rebuild SaneBar-owned anchors or open the Health fallback instead of silently disappearing.
   - If any guard fails: stop, fix root cause, verify, then rerun preflight (no workaround release)
3. **Release** — `bash ~/SaneApps/infra/SaneProcess/scripts/release.sh --project $(pwd) --full --version X.Y.Z --notes "..." --deploy`
4. **Verify** — check appcast at https://sanebar.com/appcast.xml, confirm the ZIP-first direct-download/Sparkle artifact at `dist.sanebar.com/updates/SaneBar-X.Y.Z.zip`, and confirm the appcast enclosure, length, and signature match that ZIP
5. **Monitor** — morning releases preferred, gives full day to watch for issues

Full SOP: `SaneProcess/templates/RELEASE_SOP.md`

**Critical:** Same version number = Sparkle won't offer update. Always bump before building.

### Rollback and Current Proof

- Rollback for the direct channel means the appcast, website download route, and `dist.sanebar.com` object set all point at a known-good ZIP. Do not republish the same version/build to "fix" a bad release; Sparkle users need a higher version/build or an appcast rollback to a still-resolvable prior ZIP.
- Keep every ZIP referenced by live or historical appcast entries reachable until those entries are intentionally pruned. A docs-only/appcast repair deploy is valid when the feed is wrong and the binary is not changing.
- Current proof for a release-blocking family must name the version/build, source revision or fingerprint, Mini command/receipt paths, direct ZIP URL, appcast URL, and the issue family covered. Summary-only handoff prose is not enough release proof.

---

## Testing

- Unit tests: `Tests/` directory, Swift Testing framework (`import Testing`, `@Test`, `#expect`)
- Customer UI release gate:
  1. Generate fresh runtime evidence on the Mini, including strict Pro move smoke
     and the default smoke logs required by the sweep.
  2. Relaunch the Mini Pro-mode build with `./Scripts/SaneMaster.rb mode SaneBar pro --launch`
     immediately before the sweep. Some smoke paths relaunch the app and can drop
     the no-keychain Pro argument.
  3. Run `ruby Scripts/customer_ui_action_sweep.rb`
  4. Confirm `Tests/CustomerUIActions.yml` and `.sane/customer_ui_action_receipt.json`
     cover every customer-facing action family before `release_preflight`.
  The sweep must include visual screenshots plus functional assertions for status
  item routes, menus, Browse Icons, Second Menu Bar, icon groups/hotkeys, Settings
  tabs/actions, profiles, rules, appearance, shortcuts, health/repair, data
  import/export/reset, onboarding, license/about/support, Basic/Pro gates, and
  startup/wake recovery.
- Issue-history regression backtest:
  - Before release, every open or recently recurring GitHub issue family must map
    to a current automated or Mini runtime gate in `Tests/CustomerUIActions.yml`,
    `Scripts/live_zone_smoke.rb`, `Scripts/wake_layout_probe.rb`, or focused unit
    tests. If there is no gate that would fail if the root cause returned, the
    release is blocked.
  - Passive startup/wake recovery must not physically move the cursor or third-party
    menu extras. Use audit-only intent replay for recovery, and require explicit
    user/automation origins for any Cmd-drag path.
  - Live-anchor structural recovery contract checks are release-blocking for the
    hidden-state family: first install, update, settings changes, reboot, poisoned
    autosave/currentHost defaults, and unattached status-item windows must fail
    unless the runtime receipt reports completed scenarios proving live main and
    separator anchors.
  - The current release-blocking families are saved Visible/Hidden persistence
    after wake or display changes, helper-owned Hidden-to-Visible drift such as
    Lungo, shared-bundle exact-ID moves, Hidden vs Always Hidden move
    classification, Browse Icons / Second Menu Bar activation and rehide,
    hover/auto-rehide timing, profile apply parity, license paste/activation,
    installer Move to Applications behavior, and resource growth. Compatibility-
    limited third-party conflicts can be exempted only with an explicit issue
    label and a written reason.
- E2E checklist: `docs/E2E_TESTING_CHECKLIST.md`
- Button mapping: `ruby Scripts/button_map.rb`
- Flow tracing: `rg "functionOrHandlerName" Core UI Tests`
- Notarization: `docs/NOTARIZATION.md`

---

## SaneLoop: SOP Enforcement Loop

Forces Claude to complete ALL SOP requirements before claiming done.

**MANDATORY rules** (learned from 700+ iteration failure):
- Always set `--max-iterations` (10-20, NEVER 0)
- Always set `--completion-promise` (clear, verifiable text)

```bash
/sane-loop "Fix bug X" --completion-promise "BUG-FIXED" --max-iterations 15
/cancel-sane   # Cancel active loop
```

---

## Project Structure

```
SaneBar/
├── Core/           # Managers, Services, Models
├── UI/             # SwiftUI views
├── Tests/          # Unit tests
├── Scripts/        # SaneMaster automation and QA helpers
└── SaneBarApp.swift
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Ghost beeps / no launch | `xcodegen generate` |
| Phantom build errors | `./Scripts/SaneMaster.rb clean --nuclear` |
