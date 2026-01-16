# SaneBar Release Workflow

## Pre-Release Checklist

Before running `release.sh`, verify:

- [ ] Version bumped in `project.yml` (MARKETING_VERSION and CURRENT_PROJECT_VERSION)
- [ ] `xcodegen generate` run after version bump
- [ ] All tests pass: `xcodebuild test -scheme SaneBar -destination 'platform=macOS'`
- [ ] Git working directory clean
- [ ] All fixes committed with descriptive messages

## Release Steps

### 1. Build, Notarize, Staple
```bash
./scripts/release.sh --version X.Y.Z
```

Wait for "Release build complete!" message. Note the:
- **DMG path**: `releases/SaneBar-X.Y.Z.dmg`
- **SHA256**: From the Homebrew cask output
- **edSignature**: For Sparkle appcast

### 2. GitHub Release
```bash
gh release create vX.Y.Z releases/SaneBar-X.Y.Z.dmg \
  --title "vX.Y.Z" \
  --notes "## Changes
- Change 1
- Change 2"
```

### 3. Update Appcast (docs/appcast.xml)
Add new `<item>` block with:
- version
- pubDate (RFC 2822 format)
- length (file size in bytes)
- sparkle:edSignature
- sparkle:version

```bash
git add docs/appcast.xml
git commit -m "Update appcast for vX.Y.Z"
git push origin main
```

### 4. Update Homebrew Cask
```bash
# Clone and update
cd /tmp
rm -rf homebrew-sanebar
git clone https://github.com/stephanjoseph/homebrew-sanebar.git
cd homebrew-sanebar

# Update Casks/sanebar.rb with new version and SHA256
# version "X.Y.Z"
# sha256 "<new-sha256>"

git add -A
git commit -m "Update to vX.Y.Z"
git push origin main

# Verify update
gh api repos/stephanjoseph/homebrew-sanebar/contents/Casks/sanebar.rb --jq '.content' | base64 -d | head -3

# Cleanup
cd /tmp && rm -rf homebrew-sanebar
```

### 5. Verify All Endpoints
```bash
# Verify GitHub Release exists
gh release view vX.Y.Z

# Verify Homebrew cask updated
gh api repos/stephanjoseph/homebrew-sanebar/contents/Casks/sanebar.rb --jq '.content' | base64 -d | head -3

# Verify appcast updated (may take a few minutes for CDN cache)
curl -s https://raw.githubusercontent.com/stephanjoseph/SaneBar/main/docs/appcast.xml | head -10
```

### 6. Respond to Open Issues
For any issues fixed in this release:
```bash
gh issue comment <issue_number> --body "Fixed in vX.Y.Z. Please download from [GitHub Releases](https://github.com/stephanjoseph/SaneBar/releases/tag/vX.Y.Z)"
```

## Post-Release Checklist

- [ ] GitHub Release published and DMG downloadable
- [ ] Homebrew cask shows correct version and SHA256
- [ ] Appcast.xml updated and pushed
- [ ] Website download link works (points to GitHub Releases)
- [ ] Open issues notified of fix
- [ ] README version badge shows new version

## Full Automated Release (Future Enhancement)

TODO: Create `scripts/full_release.sh` that automates all steps above:
1. Accepts version number
2. Runs release.sh
3. Creates GitHub release
4. Updates appcast.xml
5. Updates Homebrew cask
6. Verifies all endpoints
7. Provides summary

## What Gets Updated Each Release

| Item | Location | How |
|------|----------|-----|
| Version | `project.yml` | Manual edit |
| DMG | `releases/` | `release.sh` |
| GitHub Release | github.com | `gh release create` |
| Appcast.xml | `docs/appcast.xml` | Manual edit + push |
| Homebrew Cask | homebrew-sanebar repo | Clone, edit, push |
| README badge | Auto from GitHub | No action needed |
| Website | sanebar.com | GitHub Pages (auto from docs/) |
