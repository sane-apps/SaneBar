# SaneBar Development Guide

> [README](README.md) · [ARCHITECTURE](ARCHITECTURE.md) · [DEVELOPMENT](DEVELOPMENT.md) · [PRIVACY](PRIVACY.md) · [SECURITY](SECURITY.md)

Everything you need to build, test, and change SaneBar. For how the app works
internally, read [ARCHITECTURE.md](ARCHITECTURE.md).

---

## Quick Start

```bash
git clone https://github.com/sane-apps/SaneBar.git
cd SaneBar
./Scripts/SaneMaster.rb verify     # build + run the unit tests
./Scripts/SaneMaster.rb test_mode  # kill -> build -> launch -> stream logs
```

Requirements:

- **Xcode 16+** (which needs macOS Sequoia or later to build; the app itself runs on macOS 14.0+)
- **Apple Silicon** (arm64 only)
- **Ruby 3+** for the helper scripts (macOS ships one; no gems needed)
- **XcodeGen** (`brew install xcodegen`) — only needed when you add or remove
  source files; the tracked `SaneBar.xcodeproj` builds as-is

`Scripts/SaneMaster.rb` is a thin dispatcher: on the original maintainer's
machines it delegates to private SaneApps infrastructure; everywhere else it
falls back to `Scripts/SaneMaster_standalone.rb`, which wraps plain
`xcodebuild`. The standalone commands are `build`, `test`, `verify`,
`test_mode`, `launch`, and `help`. No wrapper required if you prefer:

```bash
xcodebuild -scheme SaneBar -configuration Debug build
```

Community builds use the `Debug` configuration (ad-hoc signing). The `Release`
configuration requires the original maintainer's Developer ID and will not
sign for anyone else.

## Adding or Removing Files

`project.yml` is the source of truth; the committed `.xcodeproj` is a
convenience snapshot. CI regenerates the project with `xcodegen generate`
before building, so **a file added only through Xcode's GUI will silently
vanish from the CI build**. After adding or removing source files, run:

```bash
xcodegen generate
```

and commit the regenerated project alongside your change.

## Things That Have Burned People

Real failures from this repo's history. Learn from them cheaply:

| Mistake | Lesson |
|---------|--------|
| Guessed an Accessibility API shape | Verify AX APIs against Apple docs before coding; several "obvious" properties don't exist |
| Skipped `xcodegen generate` after adding a file | 20 minutes of "file not found" — see the section above |
| Classified Hidden icons as "offscreen" | Hidden vs. Visible is **separator-relative**: compare an icon's X to the separator item's window frame, not to screen bounds |
| Deleted an "unused" file a tool flagged | It was load-bearing (`ServiceContainer`). Grep for the type name before deleting anything |
| Trusted `codesign --verify --deep` | It does not inspect executables inside `.zip` resources; Apple's notarization does |
| Modified icon-moving logic casually | The CGEvent drag pipeline is battle-tested and fragile. **Do not touch it** without reading ARCHITECTURE.md § Known Fragilities |

## Fragile Zones

The icon-moving, geometry, separator/zone, and recovery code paths look
refactorable and are not. Before changing anything there, read:

- [ARCHITECTURE.md](ARCHITECTURE.md) § Known Fragilities

## Testing

- `Tests/` (Swift Testing) covers the macOS 27 notice and the upgrade path from 2.1.90
  (`UpgradePathTests`, also the release upgrade proof).
  The older suite was removed in 2.1.91 to keep the sunset repo small; it is in
  git history.
- On macOS 27 the app shows only the notice in `UI/GoldenGateNotice.swift`. Set
  `SANEBAR_SHOW_MACOS27_NOTICE=1` to see it on earlier macOS, and
  `SANEBAR_SETTINGS_FALLBACK_TEST=app` or `=none` to try its fallbacks.
- Stream live app logs: `log stream --predicate 'subsystem == "com.sanebar.app"' --level info`.

## Releases (maintainer history)

SaneBar shipped as a ZIP-first direct-download/Sparkle app: the feed at
`https://sanebar.com/appcast.xml` points at
`dist.sanebar.com/updates/SaneBar-X.Y.Z.zip`, signed and notarized with the
maintainer's Developer ID. That pipeline retired with the sunset. Practical
consequences:

- **Never touch `docs/appcast.xml` or `docs/_redirects` in a PR** — they drive
  live auto-updates and downloads for existing users.
- GitHub Releases mirrors every shipped ZIP and is the permanent archive.
- A fork that wants auto-updates must generate its own Sparkle EdDSA keys and
  set its own `SUFeedURL`; the private key is not in this repo.

### Rollback and Current Proof

Historical maintainer rules, kept for reference: a rollback means the appcast,
website download route, and dist object set all point at a known-good ZIP —
never republish the same version/build. Release-blocking fixes required
runtime receipts with completed scenarios proving live main and separator
status-item anchors; Summary-only handoff prose is not enough release proof.

## Troubleshooting

| Problem | Fix |
|---------|-----|
| "File not found" after adding a file | `xcodegen generate` |
| Phantom build errors | Delete DerivedData for SaneBar and rebuild |
| Menu bar item won't render from an unsigned Debug launch | Use `./Scripts/SaneMaster.rb test_mode`, which launches the way that works |
