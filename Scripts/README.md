# SaneBar Scripts

## Build & Test (via SaneMaster)

```bash
./scripts/SaneMaster.rb verify          # Build + unit tests
./scripts/SaneMaster.rb test_mode       # Kill -> Build -> Launch -> Logs
./scripts/SaneMaster.rb logs --follow   # Stream live logs
./scripts/SaneMaster.rb clean_system    # Remove dev artifacts
```

## Shared Scripts (Symlinks to SaneProcess)

These are canonical scripts maintained in `~/SaneApps/infra/SaneProcess/scripts/`. Do not edit locally — changes go upstream.

| Script | Purpose |
|--------|---------|
| `enable_tests_for_ci.sh` | Enable test targets for CI builds |
| `extract_image_info.rb` | Extract metadata from images |
| `grant_permissions.applescript` | Auto-click permission dialogs in test environments |
| `monitor_tests.sh` | Test execution monitor with timeout detection |
| `post_mock_generation.sh` | Post-process generated mocks |
| `publish_website.sh` | Deploy docs/ to Cloudflare Pages |
| `restore_tests_after_ci.sh` | Restore project.yml after CI modifications |
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
