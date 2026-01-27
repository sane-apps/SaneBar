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

### 2. Upload DMG to Cloudflare R2
```bash
npx wrangler r2 object put sanebar-downloads/SaneBar-X.Y.Z.dmg \
  --file=releases/SaneBar-X.Y.Z.dmg --content-type="application/octet-stream" --remote
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

### 4. Deploy Website + Appcast to Cloudflare Pages
```bash
CLOUDFLARE_ACCOUNT_ID=2c267ab06352ba2522114c3081a8c5fa \
  npx wrangler pages deploy ./docs --project-name=sanebar-site \
  --commit-dirty=true --commit-message="Release vX.Y.Z"

# Verify appcast is live
curl -s https://sanebar.com/appcast.xml | head -10
```

### 5. Respond to Open Issues
For any issues fixed in this release:
```bash
gh issue comment <issue_number> --body "Fixed in vX.Y.Z. Update via Check for Updates in the app."
```

## Post-Release Checklist

- [ ] DMG uploaded to Cloudflare R2 (`sanebar-downloads` bucket)
- [ ] Appcast.xml updated and pushed
- [ ] Website + appcast deployed to Cloudflare Pages
- [ ] Download verified: `curl -sI https://dist.sanebar.com/updates/SaneBar-X.Y.Z.dmg`
- [ ] Open issues notified of fix

## What Gets Updated Each Release

| Item | Location | How |
|------|----------|-----|
| Version | `project.yml` | Manual edit |
| DMG | `releases/` → Cloudflare R2 | `release.sh` then `wrangler r2 object put` |
| Appcast.xml | `docs/appcast.xml` | Manual edit + push |
| Website | sanebar.com | `wrangler pages deploy` (Cloudflare Pages) |
