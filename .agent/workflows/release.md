# SaneBar Release Workflow

## Canonical One-Liner

```bash
# Full release: build + sign + notarize + DMG + Sparkle + R2 + appcast + deploy
bash ~/SaneApps/infra/SaneProcess/scripts/release.sh \
  --project /Users/sj/SaneApps/apps/SaneBar \
  --full --version X.Y.Z \
  --notes "Description of changes" \
  --deploy
```

This single command handles the **complete** pipeline:
1. Version bump in project.yml + xcodegen
2. Build + archive (Release config, hardened runtime)
3. DMG creation (background, app icon fix, Applications alias)
4. DMG file icon (squircle via set_dmg_icon.swift)
5. Codesign the DMG (Developer ID)
6. Notarize + staple
7. Sparkle EdDSA signing (sign_update.swift)
8. R2 upload (with --remote)
9. Appcast.xml update
10. Cloudflare Pages deploy
11. Git commit + push

**Do NOT run these steps manually.** The release guard hook blocks manual invocations
of codesign, notarytool, hdiutil, wrangler r2, set_dmg_icon, fix_dmg_apps_icon,
and sign_update for SaneApps — all must go through release.sh.

---

## Pre-Release Preflight (MANDATORY)

> Derived from 46 GitHub issues, 200+ customer emails, 34 documented burns.
> Every check below exists because we shipped a bug without it.

### Phase 1: Code Readiness

- [ ] All tests pass: `./scripts/SaneMaster.rb verify`
- [ ] All fixes committed with descriptive messages
- [ ] Git working directory clean
- [ ] No compiler warnings

### Phase 2: Upgrade Safety (THIS IS WHERE WE KEEP BREAKING)

> **#1 cause of customer bugs.** v1.0.20 broke icons for 5+ users, v1.0.21 broke shortcuts.
> Settings migration + default changes = 50% of all critical bugs.

- [ ] **Did this release change any UserDefaults keys, defaults, or migration logic?**
  - If YES: test upgrade path (see below)
  - If NO: skip to Phase 3

**Upgrade path test (when defaults/migration changed):**
```bash
# 1. Install current production version
# 2. Configure it: hide some icons, set shortcuts, clear a shortcut, set preferences
# 3. Install the new build OVER it (don't wipe UserDefaults)
# 4. Verify:
#    - Hidden icons still accessible (not moved to always-hidden)
#    - Keyboard shortcuts unchanged
#    - Cleared shortcuts stay cleared (not restored to defaults)
#    - Custom preferences preserved
```

**The rule:** `setDefaultsIfNeeded()` must distinguish "never set" from "user cleared this." Use sentinel values or a `hasLaunchedBefore` / `lastMigrationVersion` key.

### Phase 3: Sparkle Update Chain (HIGHEST IMPACT IF BROKEN)

> 6 issues, 25+ users affected. Broken updates = can't push the fix.

- [ ] **SUPublicEDKey in Info.plist** matches shared key:
  ```bash
  /usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" \
    build/Release/SaneBar.app/Contents/Info.plist
  # Must be: 7Pl/8cwfb2vm4Dm65AByslkMCScLJ9tbGlwGGx81qYU=
  ```
- [ ] **Version numbers consistent** — CFBundleShortVersionString and CFBundleVersion in Info.plist match what appcast will say
- [ ] **Appcast XML valid** after update (well-formed, all URLs resolvable)

### Phase 4: Customer Impact Scan

> Catches things that slip between sessions. 44hr checkout downtime happened because nobody checked URLs.

- [ ] **Open GitHub issues reviewed:**
  ```bash
  gh issue list --repo sane-apps/SaneBar --state open
  ```
- [ ] **Pending customer emails checked:**
  ```bash
  API_KEY=$(security find-generic-password -s sane-email-automation -a api_key -w)
  curl -s "https://email-api.saneapps.com/api/emails/pending" \
    -H "Authorization: Bearer $API_KEY" | python3 -c "
  import json,sys; d=json.load(sys.stdin); print(f'{len(d)} pending')"
  ```
- [ ] **Release timing:** Morning releases preferred (monitor for 4 hours same-day). Evening releases = 8-18hr discovery window if broken.

---

## Useful Flags

| Flag | Purpose |
|------|---------|
| `--full` | Full pipeline (version bump + build + sign + notarize + DMG + deploy) |
| `--version X.Y.Z` | Set version number |
| `--notes "..."` | Release notes for appcast |
| `--deploy` | Upload to R2 + update appcast + deploy Cloudflare Pages |
| `--skip-notarize` | Skip notarization (for dry-run testing) |

## Dry Run (Test Without Deploy)

```bash
bash ~/SaneApps/infra/SaneProcess/scripts/release.sh \
  --project /Users/sj/SaneApps/apps/SaneBar \
  --version X.Y.Z --skip-notarize
```

Produces `releases/SaneBar-X.Y.Z.dmg` without notarizing or deploying.
Open the DMG to visually verify: white background, squircle app icon, blue Applications folder.

---

## Post-Release Verification (MANDATORY)

### Phase 5: Artifact Validation

- [ ] **DMG downloads:**
  ```bash
  curl -sI "https://dist.sanebar.com/updates/SaneBar-X.Y.Z.dmg" | grep "HTTP.*200"
  ```
- [ ] **Appcast live and correct:**
  ```bash
  curl -s "https://sanebar.com/appcast.xml" | grep "X.Y.Z"
  ```
- [ ] **EdDSA signature in appcast matches DMG:**
  ```bash
  # Download DMG from production URL, verify signature matches appcast
  curl -sL "https://dist.sanebar.com/updates/SaneBar-X.Y.Z.dmg" -o /tmp/verify.dmg
  swift scripts/sign_update.swift /tmp/verify.dmg
  # Compare output to sparkle:edSignature in appcast.xml
  ```
- [ ] **Checkout link works:**
  ```bash
  curl -sI "https://go.saneapps.com/sanebar" | grep "HTTP"
  ```

### Phase 6: Upgrade Test (from previous version)

- [ ] **Install previous version, trigger Sparkle update, confirm it finds and installs the new version**
- [ ] After update: verify icon positions, shortcuts, and settings survived

### Phase 7: Notify

- [ ] Open issues notified:
  ```bash
  gh issue comment <number> --body "Fixed in vX.Y.Z. Update via Check for Updates in the app."
  ```
- [ ] Close resolved issues

---

## Known Failure Patterns (Reference)

| Pattern | Burned Us | Check |
|---------|-----------|-------|
| Defaults change clobbers user state | #46, #47, #48 (v1.0.20/21) | Upgrade path test |
| Sparkle key mismatch | Per-project keys incident | SUPublicEDKey verification |
| DMG not uploaded / wrong bucket | R2 --remote flag, GitHub Releases | Post-deploy URL check |
| Appcast URL 404 | #28, #31 | curl all enclosure URLs |
| Checkout URLs broken | #40 (LemonSqueezy slug change) | go.saneapps.com redirect test |
| Evening release, overnight discovery | v1.0.20 (8hr gap) | Morning release preference |
| Build number mismatch | #31 (build '5' vs '1005') | Version consistency check |
| DMG visual defects | Dark background, baked squircle | Visual inspection after dry run |
| Position reset on upgrade | #32 (recovery logic bug) | Upgrade preserves positions |

---

## Key Files

| File | Purpose |
|------|---------|
| `~/SaneApps/infra/SaneProcess/scripts/release.sh` | Complete release pipeline (1005 lines) |
| `~/SaneApps/infra/SaneProcess/scripts/fix_dmg_apps_icon.swift` | Applications alias + icon in DMG |
| `~/SaneApps/infra/SaneProcess/scripts/set_dmg_icon.swift` | Squircle DMG file icon |
| `~/SaneApps/infra/SaneProcess/scripts/generate_dmg_background.swift` | Light gradient DMG background |
| `scripts/sign_update.swift` | Sparkle EdDSA signing |
| `Resources/DMGIcon.icns` | DMG icon source (1.3MB) |
| `.saneprocess` | Project config for release.sh |
