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

### 4. Verify All Endpoints
```bash
# Verify GitHub Release exists
gh release view vX.Y.Z

# Verify appcast updated (may take a few minutes for CDN cache)
curl -s https://raw.githubusercontent.com/sane-apps/SaneBar/main/docs/appcast.xml | head -10
```

### 5. Respond to Open Issues
For any issues fixed in this release:
```bash
gh issue comment <issue_number> --body "Fixed in vX.Y.Z. Please download from [GitHub Releases](https://github.com/sane-apps/SaneBar/releases/tag/vX.Y.Z)"
```

## Post-Release Checklist

- [ ] GitHub Release published and DMG downloadable
- [ ] Appcast.xml updated and pushed
- [ ] Website download link works (points to GitHub Releases)
- [ ] Open issues notified of fix
- [ ] README version badge shows new version

## What Gets Updated Each Release

| Item | Location | How |
|------|----------|-----|
| Version | `project.yml` | Manual edit |
| DMG | `releases/` | `release.sh` |
| GitHub Release | github.com | `gh release create` |
| Appcast.xml | `docs/appcast.xml` | Manual edit + push |
| README badge | Auto from GitHub | No action needed |
| Website | sanebar.com | GitHub Pages (auto from docs/) |
