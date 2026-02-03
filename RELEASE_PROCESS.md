# SaneBar Release Process

> **CRITICAL**: Every release requires a DMG upload to Cloudflare R2 AND an appcast.xml update.
> **We do NOT host DMGs on GitHub Releases.** GitHub is metadata only; Cloudflare R2 + `dist.sanebar.com` is the actual download.
> Users only receive updates through Sparkle, which reads appcast.xml.

---

## Weekly Release Cadence

| Day | Action |
|-----|--------|
| **Mon-Thu** | Develop features, fix bugs |
| **Friday** | Build & push to appcast. User tests over weekend. |
| **Monday** | If good, it's live. If not, fix and push again. |

---

## Quick Reference

| Release Type | Command |
|--------------|---------|
| **Manual Release** | `./scripts/SaneMaster.rb release` then `./scripts/post_release.rb` |
| **Full Release (all-in-one)** | `./scripts/SaneMaster.rb release --full --version X.Y.Z --notes "Release notes"` |
| **CI Release** | Trigger workflow, then `./scripts/post_release.rb` |
| **Post-Release Only** | `./scripts/post_release.rb --version X.Y.Z` |

---

## Release Methods

### Method 1: Manual Release (Recommended)

For full control over the release process:

```bash
# 1. Build, sign, notarize, create DMG
./scripts/SaneMaster.rb release

# 2. Upload DMG to Cloudflare R2 (this is the only hosted DMG)
npx wrangler r2 object put sanebar-downloads/SaneBar-X.Y.Z.dmg \
  --file=releases/SaneBar-X.Y.Z.dmg --content-type="application/octet-stream" --remote

# 3. Update appcast.xml (CRITICAL - don't skip!)
./scripts/post_release.rb

# 4. Deploy website + appcast to Cloudflare Pages
cp docs/appcast.xml website/appcast.xml 2>/dev/null || cp docs/appcast.xml docs/
npx wrangler pages deploy ./docs --project-name=sanebar-site \
  --commit-dirty=true --commit-message="Release vX.Y.Z"

# 5. Commit and push
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

### `SaneMaster release`

Unified release command (SaneMaster → SaneProcess `release.sh`) with per-project `.saneprocess` config:
- Generates Xcode project
- Archives with Release config
- Exports with Developer ID signing
- Creates DMG
- Notarizes with Apple
- Staples notarization ticket
- **Prints appcast entry** (but doesn't update file)

Options:
- `--full` - Version bump, run tests, commit, and create GitHub release
- `--skip-notarize` - Skip notarization (local testing)
- `--skip-build` - Use existing archive
- `--version X.Y.Z` - Override version
- `--notes "..."` - Release notes (required with `--full`)

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
│  Downloads DMG from dist.sanebar.com (Cloudflare R2)          │
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

### Website not updating

Cloudflare Pages deploys are near-instant. If stale:
- Redeploy: `npx wrangler pages deploy ./docs --project-name=sanebar-site --commit-dirty=true`
- Verify: `curl -s https://sanebar.com/appcast.xml | head -10`

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
- ✅ Creates GitHub Release (metadata only — no DMG asset)
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
- [ ] DMG uploaded to Cloudflare R2 (`sanebar-downloads` bucket)
- [ ] `./scripts/post_release.rb` run
- [ ] appcast.xml committed and pushed
- [ ] Website + appcast deployed to Cloudflare Pages
- [ ] Verified at sanebar.com/appcast.xml
- [ ] Tested "Check for Updates" in app
