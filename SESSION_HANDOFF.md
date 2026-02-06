# Session Handoff - Feb 6, 2026

## Release v1.0.18 (Production — LIVE)

**Version:** v1.0.18 (build 1018)
**Released:** Feb 5, 2026 7:32pm EST
**Pipeline:** `release.sh --full --deploy` (end-to-end automated)
**Notarization ID:** dff2edce-f9d8-4c67-b5d8-8648be421296
**SHA256:** 3809087ffbc2170c24a0b02108443084bfc5a38e86a58079ff339b05a5d14a27

### What shipped
- **Import from Bartender**: Icon layout (Hide/Show/AlwaysHide) + behavioral settings (hover delay, show on drag, rehide on app change, launch at login)
- **Import from Ice**: 9 behavioral settings (hover, scroll, rehide, spacing, drag, always-hidden, dividers)
- **Custom Menu Bar Icon**: Upload your own image (Settings → Appearance)
- **Standalone Build**: External contributors can build without SaneProcess (#39)
- **About View Fix**: Button layout no longer truncates
- **Dark Mode Tint**: Dual light/dark tint controls with sensible defaults (#34)
- **License**: MIT → GPL v3
- **App Icon**: Updated to 2D cross-app design language

### Phantom v1.0.18 cleanup
The `weekly-release.yml` cron (now deleted) had created a phantom v1.0.18 on Feb 2 that contained the v1.0.17 binary (never version-bumped). This caused a Sparkle infinite update loop. All artifacts were cleaned:
- Removed phantom appcast entry
- Deleted phantom DMG from R2 (`sanebar-dist`)
- Deleted GitHub release + tag
- Workflow file deleted entirely (release.sh is the real pipeline)
- Users who got the phantom update are fine — they got v1.0.17 binary, now see real v1.0.18

### .saneprocess config fix
Added `team_id: M78L6FXD48` and `signing_identity` to `.saneprocess` — was missing, blocked release.sh.

---

## GitHub Issues Status

| # | Title | Status | Action Taken |
|---|-------|--------|-------------|
| #38 | Customizable icons | **Closed** | Shipped in v1.0.18, commented + closed |
| #34 | Dark mode tint | Closed | Posted shipped confirmation |
| #33 | Bartender migration | Closed | Posted shipped confirmation |
| #17 | Always hidden section | Open | Actively researching, no timeline |
| #36 | Title bar bug | Closed | Already responded |
| #35 | Icons not staying visible | Closed | Already responded |

---

## System Cleanup (Feb 5)

- Trashed 9 DerivedData directories, 4 build/ dirs
- Deleted 7 stale UserDefaults, 5 stale preference plists
- Killed 3 orphan osascript processes
- Updated SaneClip v1.3→v1.4, SaneHosts v1.0.7→v1.0.8 from release DMGs
- Login items may still point to stale paths (DerivedData) — check on next launch

---

## Infrastructure Updates (Feb 6)

### Link Monitor Expansion
Enhanced `/Users/sj/SaneApps/infra/SaneProcess/scripts/link_monitor.rb`:

**Added monitoring for:**
1. **Sparkle appcast feeds** (CRITICAL - no updates if broken):
   - sanebar.com/appcast.xml
   - saneclick.com/appcast.xml
   - saneclip.com/appcast.xml
   - sanehosts.com/appcast.xml

2. **Distribution workers** (Cloudflare R2 download endpoints):
   - dist.sanebar.com
   - dist.saneclick.com
   - dist.saneclip.com
   - dist.sanehosts.com
   - Workers return 404 at root (expected) — verify they respond

3. **Domain expiry checking** (via Cloudflare API + whois fallback):
   - All 7 SaneApps domains (sanebar.com, saneclip.com, saneclick.com, sanehosts.com, saneapps.com, sanesync.com, sanevideo.com)
   - Warns if < 60 days to expiry
   - Alerts if < 30 days to expiry

**Morning report integration** (`morning-report.sh`):
- Sales Infrastructure section now includes appcast and dist worker checks
- Separate tables for checkout links, appcast feeds, and distribution workers

**Validation report integration** (`validation_report.rb`):
- Q7 (Website/Distribution Health) now includes:
  - Appcast URL availability + XML validation
  - Distribution worker endpoint checks
  - Accepts 404/403 for dist workers (they respond to specific file paths, not root)

**Test results:** All 18 checks passing (4 appcast feeds + 4 dist workers + 7 domains + existing 3 critical URLs)

---

## Next Actions

1. **Always-Hidden Section** (#17): Research three-zone architecture (visible / collapsible / always-hidden). Requires second separator + special hide logic. Significant effort.
2. **Keychain Migration**: Move `requireAuthToShowHiddenIcons` from JSON to System Keychain
3. **Version bump to v1.0.19**: project.yml still says 1.0.18 — bump when starting next feature cycle
4. **Login Items cleanup**: Verify /Applications paths are correctly registered after system cleanup
5. **MenuBarManager.swift**: SwiftLint warning — 1062 lines, should be under 1000. Consider splitting.
6. **MenuBarAppTile.swift:20**: SwiftLint warning — implicit optional initialization
