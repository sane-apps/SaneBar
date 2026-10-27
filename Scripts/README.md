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
| `uninstall_sanebar.sh` | Clean uninstall (remove prefs, login items) |

The maintainer QA harness (qa.rb, smokes, probes, sweeps) was removed in 2.1.91 and is in git history.
