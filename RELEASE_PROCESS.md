# SaneBar Release Process

> **CRITICAL**: Every release requires BOTH a GitHub Release AND an appcast.xml update.
> Users only receive updates through Sparkle, which reads appcast.xml.

---

## Quick Reference

| Release Type | Command |
|--------------|---------|
| **Manual Release** | `./scripts/release_fixed.sh` then `./scripts/post_release.rb` |
| **CI Release** | Trigger workflow, then `./scripts/post_release.rb` |
| **Post-Release Only** | `./scripts/post_release.rb --version X.Y.Z` |

---

## Release Methods

### Method 1: Manual Release (Recommended)

For full control over the release process:

```bash
# 1. Build, sign, notarize, create DMG
./scripts/release_fixed.sh

# 2. Upload DMG to GitHub Releases
gh release create vX.Y.Z releases/SaneBar-X.Y.Z.dmg \
  --title "SaneBar vX.Y.Z" \
  --notes "See CHANGELOG.md"

# 3. Update appcast.xml (CRITICAL - don't skip!)
./scripts/post_release.rb

# 4. Commit and push appcast
git add docs/appcast.xml
git commit -m "chore: update appcast for vX.Y.Z"
git push
```

### Method 2: CI Release

For automated builds via GitHub Actions:

```bash
# 1. Trigger the workflow
gh workflow run weekly-release.yml -f version_bump=patch

# 2. Wait for completion (check Actions tab)
gh run list --workflow=weekly-release.yml --limit 1

# 3. Update appcast.xml (CI doesn't do this!)
./scripts/post_release.rb

# 4. Commit and push
git add docs/appcast.xml
git commit -m "chore: update appcast for vX.Y.Z"
git push
```

---

## The Scripts

### `scripts/release_fixed.sh`

Full release build script:
- Generates Xcode project
- Archives with Release config
- Exports with Developer ID signing
- Creates DMG
- Notarizes with Apple
- Staples notarization ticket
- **Prints appcast entry** (but doesn't update file)

Options:
- `--skip-notarize` - Skip notarization (local testing)
- `--skip-build` - Use existing archive
- `--version X.Y.Z` - Override version

### `scripts/post_release.rb`

Post-release automation:
- Detects latest GitHub release
- Downloads DMG
- Generates EdDSA signature
- Extracts changelog description
- Updates `docs/appcast.xml`

Options:
- `--version X.Y.Z` - Specific version
- `--dry-run` - Preview without changes

---

## Sparkle Update System

```
┌─────────────────────────────────────────────────────────────┐
│                    USER'S MAC                                │
│  ┌─────────────┐                                            │
│  │  SaneBar    │──→ Checks https://sanebar.com/appcast.xml  │
│  └─────────────┘                                            │
│        │                                                     │
│        ↓                                                     │
│  "New version X.Y.Z available!"                              │
│        │                                                     │
│        ↓                                                     │
│  Downloads DMG from GitHub Release                           │
│        │                                                     │
│        ↓                                                     │
│  Verifies EdDSA signature (MUST match!)                      │
│        │                                                     │
│        ↓                                                     │
│  Installs update                                             │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

| Component | Location | Purpose |
|-----------|----------|---------|
| **Public Key** | `project.yml` → `SUPublicEDKey` | Verifies signatures |
| **Private Key** | macOS Keychain | Signs DMGs |
| **Appcast** | `docs/appcast.xml` | Lists available versions |

### Signature Verification

The public/private key pair was verified on 2026-01-23:
- Public: `7Pl/8cwfb2vm4Dm65AByslkMCScLJ9tbGlwGGx81qYU=`
- Private: In Keychain as "EdDSA Private Key" @ sparkle-project.org

---

## Troubleshooting

### "X.Y.Z is the newest version available"

The version isn't in appcast.xml. Run:
```bash
./scripts/post_release.rb --version X.Y.Z
git add docs/appcast.xml && git commit -m "fix: add vX.Y.Z to appcast" && git push
```

### Signature verification failed

The EdDSA signature in appcast.xml doesn't match the DMG. Regenerate:
```bash
./scripts/post_release.rb --version X.Y.Z
# This will overwrite the existing entry with correct signature
```

### GitHub Pages not updating

GitHub Pages can take 1-5 minutes to deploy. Check:
- Raw file: `https://raw.githubusercontent.com/sane-apps/SaneBar/main/docs/appcast.xml`
- Live site: `https://sanebar.com/appcast.xml`

### Rollback a release

```bash
# 1. Remove entry from appcast.xml (edit manually)
# 2. Commit and push
git add docs/appcast.xml
git commit -m "rollback: remove vX.Y.Z from appcast"
git push

# 3. Optionally delete GitHub release
gh release delete vX.Y.Z --yes
```

---

## CI Workflow Gaps (Future Fix)

The GitHub Actions workflow (`weekly-release.yml`) currently:
- ✅ Builds the app
- ✅ Signs and notarizes
- ✅ Creates GitHub Release with DMG
- ❌ Does NOT update appcast.xml
- ❌ Does NOT have Sparkle private key

To fully automate CI releases:
1. Add `SPARKLE_PRIVATE_KEY` to GitHub Secrets (base64-encoded)
2. Add appcast update step to workflow
3. Add signature generation to workflow

Until then, **always run `post_release.rb` after CI releases**.

---

## Checklist

### Before Release
- [ ] CHANGELOG.md updated
- [ ] Version bumped in project.yml
- [ ] All tests pass
- [ ] Changes committed and pushed

### After Release
- [ ] GitHub Release exists with DMG
- [ ] `./scripts/post_release.rb` run
- [ ] appcast.xml committed and pushed
- [ ] Verified at sanebar.com/appcast.xml
- [ ] Tested "Check for Updates" in app
