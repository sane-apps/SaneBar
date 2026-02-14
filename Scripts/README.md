# SaneBar Scripts

## Build & Test (via SaneMaster)

```bash
./scripts/SaneMaster.rb verify          # Build + unit tests
./scripts/SaneMaster.rb test_mode       # Kill -> Build -> Launch -> Logs
./scripts/SaneMaster.rb logs --follow   # Stream live logs
./scripts/SaneMaster.rb clean_system    # Remove dev artifacts
```

## CI/CD Helpers (via SaneMaster)

These were previously standalone bash scripts. Now unified in SaneMaster — single source of truth for all projects.

```bash
./scripts/SaneMaster.rb enable_ci_tests   # Enable test targets in project.yml for CI
./scripts/SaneMaster.rb restore_ci_tests  # Restore project.yml from CI backup
./scripts/SaneMaster.rb fix_mocks         # Add @testable import to generated mocks
./scripts/SaneMaster.rb monitor_tests     # Run tests with timeout + progress
./scripts/SaneMaster.rb image_info <path> # Extract image info and base64
```

## Release Commands (via SaneMaster)

```bash
./scripts/SaneMaster.rb release_preflight   # 9 safety checks (direct download)
./scripts/SaneMaster.rb appstore_preflight  # App Store submission compliance
```

## Sales & Revenue (via SaneMaster)

```bash
./scripts/SaneMaster.rb sales              # Today/yesterday/week/all-time (default)
./scripts/SaneMaster.rb sales --products   # Revenue by product
./scripts/SaneMaster.rb sales --month      # Monthly breakdown
./scripts/SaneMaster.rb sales --fees       # Fee analysis
```

## Shared Scripts (Symlinks to SaneProcess)

These are canonical scripts maintained in `~/SaneApps/infra/SaneProcess/scripts/`. Do not edit locally — changes go upstream.

| Script | Purpose |
|--------|---------|
| `grant_permissions.applescript` | Auto-click permission dialogs in test environments |
| `publish_website.sh` | Deploy docs/ to Cloudflare Pages |
| `sanemaster_completions.zsh` | Zsh tab completions for SaneMaster |
| `set_dmg_icon.swift` | Set custom icon on .dmg files |
| `sign_update.swift` | Sparkle EdDSA signing utility |

## Project-Specific Scripts

| Script | Purpose |
|--------|---------|
| `SaneMaster.rb` | Thin wrapper (20L) delegating to SaneProcess |
| `qa.rb` | Project QA checks (12 SaneBar-specific validations) |
| `post_release.rb` | Post-release tasks (appcast update, GitHub release) |
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
