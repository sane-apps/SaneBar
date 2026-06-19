# SaneBar Scripts

## Build & Test (via SaneMaster)

Canonical checked-in path is `Scripts/` with a capital `S`. Use `./Scripts/...`
in repo docs and commands; lowercase may work on default macOS volumes but is
not portable.

```bash
./Scripts/SaneMaster.rb verify          # Build + unit tests
./Scripts/SaneMaster.rb test_mode       # Kill -> Build -> Launch -> Logs
./Scripts/SaneMaster.rb logs --follow   # Stream live logs
./Scripts/SaneMaster.rb clean_system    # Remove dev artifacts
./Scripts/SaneMaster.rb launch          # Launch app (SaneBar defaults to ProdDebug)
./Scripts/SaneMaster.rb launch --proddebug # Explicit signed local launch
```

Important:
- run these from the local workspace root, not with raw `ssh mini ...`
- `SaneMaster` syncs the current workspace snapshot to Mini before routed commands like `verify`, `test_mode`, and `release_preflight`
- bypassing that sync path is how stale-code verification slips back in

Note: SaneBar defaults to `ProdDebug` launch mode because some machines can fail to render
the menu bar item reliably in unsigned `Debug` launches from DerivedData, while installer-like
signed launches work consistently.

## CI/CD Helpers (via SaneMaster)

These were previously standalone bash scripts. Now unified in SaneMaster — single source of truth for all projects.

```bash
./Scripts/SaneMaster.rb enable_ci_tests   # Enable test targets in project.yml for CI
./Scripts/SaneMaster.rb restore_ci_tests  # Restore project.yml from CI backup
./Scripts/SaneMaster.rb fix_mocks         # Add @testable import to generated mocks
./Scripts/SaneMaster.rb monitor_tests     # Run tests with timeout + progress
./Scripts/SaneMaster.rb image_info <path> # Extract image info and base64
```

## Release Commands (via SaneMaster)

```bash
./Scripts/SaneMaster.rb release_preflight   # 9 safety checks (direct download)
./Scripts/SaneMaster.rb appstore_preflight  # Only when .saneprocess appstore.enabled is true
```

Release preflight now enforces project QA guardrails for the ZIP-first direct-download/Sparkle path:
- 24h soak window between releases (override requires an interactive typed approval phrase)
- reporter confirmation check for recently closed regression issues (override requires an interactive typed approval phrase)
- dedicated stability suite focused on upgrade state + second-menu-bar behavior
- staged `Release` runtime smoke on Mini, including second-menu-bar, Find Icon, Settings, fullscreen, and tint proof
- one default runtime smoke pass plus focused exact-ID lanes for shared fixture, native Apple, and host sentinel items, so the expensive work stays bounded while the historical move failures remain release-blocking
- live-anchor structural recovery contract: dirty startup/reboot/wake/display probes must prove live SaneBar main and separator status-item anchors before trusting persisted Visible/Hidden state or cached geometry
- `/tmp/sanebar_runtime_smoke.log` now keeps the actual browse activation diagnostics when a pass fails

If a guard fails, stop and fix the root cause, verify, then rerun preflight before continuing release work.

Run the dedicated stability suite directly:

```bash
SANEBAR_RUN_STABILITY_SUITE=1 ruby ./Scripts/qa.rb
```

## Sales & Revenue (via SaneMaster)

```bash
./Scripts/SaneMaster.rb sales              # Today/yesterday/week/all-time (default)
./Scripts/SaneMaster.rb sales --products   # Revenue by product
./Scripts/SaneMaster.rb sales --month      # Monthly breakdown
./Scripts/SaneMaster.rb sales --fees       # Fee analysis
```

## Shared Scripts (Symlinks to SaneProcess)

These are canonical scripts maintained in `~/SaneApps/infra/SaneProcess/scripts/`. Do not edit locally — changes go upstream.

| Script | Purpose |
|--------|---------|
| `grant_permissions.applescript` | Auto-click permission dialogs in test environments |
| `sanemaster_completions.zsh` | Zsh tab completions for SaneMaster |
| `set_dmg_icon.swift` | Set custom icon on .dmg files |
| `sign_update.swift` | Sparkle EdDSA signing utility |

## Project-Specific Scripts

| Script | Purpose |
|--------|---------|
| `SaneMaster.rb` | Project wrapper that hydrates SaneBar metadata/signing context, delegates to SaneProcess when available, and falls back to standalone mode |
| `SaneMaster_standalone.rb` | Minimal standalone build/test helper for external contributors without SaneProcess infra |
| `qa.rb` | Project QA checks (release guardrails, docs/tooling checks, browse smoke, startup/wake probes, appcast blocks, migration guards, stability suite) |
| `customer_ui_action_sweep.rb` | Customer-facing action receipt sweep for release proof |
| `live_zone_smoke.rb` | Live browse + move smoke. Opens both the icon panel and second menu bar, captures screenshots, verifies browse left/right-click, then runs move checks. |
| `startup_layout_probe.rb` | Mini-only relaunch probe for startup/layout recovery. Backs up live prefs, poisons persisted status-item positions/currentHost state, relaunches the signed app, verifies live-anchor recovery, then restores the original state. |
| `wake_layout_probe.rb` | Mini-only wake/display recovery probe for hidden-state drift and live-anchor recovery |
| `button_map.rb` | Map all UI controls and their handlers |
| `trace_flow.rb` | Debug function call flow through the codebase |
| `functional_audit.swift` | Runtime functional verification |
| `marketing_screenshots.rb` | Automated screenshot capture for marketing |
| `verify_ui.swift` | UI state verification tests |
| `verify_crypto_payment.rb` | Validate LemonSqueezy payment integration |
| `generate_download_link.rb` | Generate signed download links |
| `uninstall_sanebar.sh` | Clean uninstall (remove prefs, login items) |
| `stress_test_menubar.swift` | Stress test with many menu bar items |
| `overflow_test_menubar.swift` | Test menu bar overflow edge cases |
| `check_outreach_opportunities.rb` | Scan for marketing opportunities |

Run the live browse smoke directly:

```bash
SANEBAR_SMOKE_REQUIRE_ALWAYS_HIDDEN=1 ./Scripts/live_zone_smoke.rb
SANEBAR_SMOKE_SCREENSHOT_DIR=~/Desktop/Screenshots/SaneBar ./Scripts/live_zone_smoke.rb
SANEBAR_SMOKE_REQUIRED_IDS=com.apple.menuextra.siri,com.apple.menuextra.spotlight,com.apple.menuextra.focusmode SANEBAR_SMOKE_REQUIRE_ALL_CANDIDATES=1 SANEBAR_SMOKE_CAPTURE_SCREENSHOTS=0 ./Scripts/live_zone_smoke.rb
```

The smoke now covers both browse layouts:
- opens `show second menu bar` and `open icon panel`
- captures a screenshot for each open panel
- verifies `activate browse icon` and `right click browse icon`
- verifies hidden/visible and always-hidden moves

When browse activation fails, the smoke now reports:
- requested icon identity
- first attempt / retry verification result
- final outcome

Notes:
- `SANEBAR_SMOKE_REQUIRED_IDS` forces an exact candidate set for scientific repro work.
- Required IDs now bypass the normal move-candidate denylist, so native-item investigations can target Focus / Siri / Spotlight without changing the default release smoke policy.
- Required-ID runs use compatibility browse checks (open/close only) so move investigations do not get blocked by unrelated browse-activation flakiness.
- `release_preflight` now treats the focused exact-ID lanes as first-class release checks. Missing deterministic fixture/sentinel coverage blocks release:
  - shared-bundle Apple extras: Control Center / Clock / Focus / Wi-Fi / Battery / Display
  - native Apple extras: Siri / Spotlight
  - host exact-id sentinel: deterministic `SaneBarHostExactIDFixture` plus Little Snitch top-bar items when present
- On Apple-heavy setups, the default conservative move pool can legitimately return `No movable candidate icon found`. That is a fixture-policy result, not proof that common native items are broken.
- When that happens, keep the default release smoke conservative and switch to `SANEBAR_SMOKE_REQUIRED_IDS=...` for focused native-item verification.
- browse panel mode + visibility + last relayout reason
