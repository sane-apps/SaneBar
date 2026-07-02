# SaneBar Scripts

Canonical checked-in path is `Scripts/` with a capital `S`. Use `./Scripts/...`
in repo docs and commands; lowercase may work on default macOS volumes but is
not portable.

## Everyday Commands

These work for everyone on a fresh clone (no private infrastructure needed):

```bash
./Scripts/SaneMaster.rb verify     # Build + unit tests
./Scripts/SaneMaster.rb test_mode  # Kill -> Build -> Launch -> Logs
./Scripts/SaneMaster.rb launch    # Build and run
./Scripts/SaneMaster.rb build     # Build only
./Scripts/SaneMaster.rb test      # Tests only
```

`SaneMaster.rb` delegates to private SaneApps infrastructure when it exists
(maintainers only) and otherwise falls back to `SaneMaster_standalone.rb`,
which wraps plain `xcodebuild`. Only the verbs above exist in standalone mode.

Note: SaneBar launches in `ProdDebug` mode by default because some machines
fail to render the menu bar item reliably from unsigned `Debug` launches out
of DerivedData.

## Project-Specific Scripts

| Script | Purpose |
|--------|---------|
| `SaneMaster.rb` | Build/test/launch dispatcher: uses private SaneApps infra when available, falls back to standalone mode |
| `SaneMaster_standalone.rb` | Minimal standalone build/test helper (plain `xcodebuild`) for contributors |
| `button_map.rb` | Map all UI controls and their handlers — great for finding where a setting is wired |
| `sanebar_logwatch.sh` | Stream live app logs with the right predicate |
| `uninstall_sanebar.sh` | Clean uninstall (remove prefs, login items) |
| `qa.rb` | **Maintainer-only.** Pre-release QA gates (guardrails, doc checks, runtime smokes) |
| `customer_ui_action_sweep.rb` | **Maintainer-only.** Customer-facing action receipt sweep used as release proof |
| `live_zone_smoke.rb` | **Maintainer-only.** Live browse + move smoke against a running build |
| `startup_layout_probe.rb` | **Maintainer-only.** Relaunch probe for startup/layout recovery (live-anchor checks) |
| `wake_layout_probe.rb` | **Maintainer-only.** Wake/display recovery probe for hidden-state drift and the live-anchor structural recovery contract |
| `marketing_screenshots.rb` | **Maintainer-only.** Regenerates website/onboarding screenshots — writes into the live website root `docs/images/`; do not run casually |

## About the Maintainer-Only Release Tooling

The scripts marked maintainer-only were the pre-sunset release pipeline for
the ZIP-first direct-download/Sparkle channel. They are kept for reference and
for anyone reviving a full release process, but they hard-depend on private
SaneApps infrastructure and the original maintainer's build machines — they
will refuse to run (or fail loudly) on a fresh clone. Nothing about building,
testing, or contributing to SaneBar requires them; `verify` plus the Swift
test suite plus the manual checklist in
[docs/E2E_TESTING_CHECKLIST.md](../docs/E2E_TESTING_CHECKLIST.md) is the
contributor path.

Run the live browse smoke directly:

```bash
SANEBAR_SMOKE_REQUIRE_ALWAYS_HIDDEN=1 ./Scripts/live_zone_smoke.rb
```
