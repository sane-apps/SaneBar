# Session Handoff - Feb 10, 2026

## Release v1.0.22 (Production — LIVE)

**Version:** v1.0.22 (build 1022)
**Released:** Feb 10, 2026 ~6:30pm EST
**Distribution:** DMG via Sparkle + R2 (`dist.sanebar.com`)

### What shipped in v1.0.22
- **Fix**: Always-Hidden separator position migrates from ANY broken value < 1000 (fixes #52 — icons vanishing)
- **Fix**: Settings toggle renamed "Use floating panel instead of Find Icon" (fixes #50/#51 confusion)
- **Fix**: Onboarding now explains both viewing modes (Find Icon + floating panel)

### GitHub Issues — All Closed
- **#50**: Closed as duplicate of #51
- **#51**: Replied with fix (disable toggle), wording fixed in release
- **#52**: Replied with AH position bug explanation + terminal workaround

---

## Release Pipeline — SWITCHED FROM DMG TO ZIP

### Why
DMG custom file icons are stored in macOS resource forks (extended attributes). HTTP download strips them — customers always saw a plain white DMG icon. Confirmed via [create-dmg issue #42](https://github.com/sindresorhus/create-dmg/issues/42).

### What Changed
- **`release.sh`**: Now produces `.zip` instead of `.dmg`. Entire DMG pipeline removed (create-dmg, hdiutil, background generation, Applications icon fix, volume icon, file icon). Replaced with: `ditto -c -k --keepParent` → notarize zip → staple .app → re-zip with stapled app.
- **Sparkle appcast**: `type="application/octet-stream"` for `.zip` entries. Old DMG entries preserved for backward compat.
- **Size**: 3.7MB zip vs 5.4MB DMG (32% smaller)
- **Move-to-Applications prompt**: Added to `SaneBarApp.swift`. Release builds detect if not in /Applications, show alert offering to move. Tested on Mac Mini — works.
- **LemonSqueezy**: User already updated to .zip manually.

### Trial Run Status
- `--skip-notarize` trial: PASSED (builds, exports, zips, signs Sparkle, generates metadata)
- Full notarized run: NOT YET DONE — do this before next release

### Files Modified (uncommitted)
- `~/SaneApps/infra/SaneProcess/scripts/release.sh` — DMG→ZIP pipeline
- `SaneBarApp.swift` — Move-to-Applications prompt
- `~/SaneApps/infra/SaneProcess/scripts/hooks/sane_release_guard.rb` — Upgraded hook

---

## Release Guard Hook — Upgraded

`sane_release_guard.rb` was upgraded after a manual R2 upload bypassed it:

- **Block 6**: Now catches ANY `wrangler r2` command (not just `object put`) touching SaneApp buckets. Matches both app names AND bucket names (`sanebar-downloads`, etc.)
- **Block 6b (new)**: Catches `wrangler pages deploy` for SaneApp sites
- **Block 11 (new)**: Catches `curl`/`wget` to `dist.*.com` domains
- **Patterns added**: `SANE_BUCKET_PATTERN`, `SANE_PAGES_PATTERN`, `SANE_DIST_PATTERN`
- **Allowlist expanded**: `full_release.sh`, `SaneMaster_standalone.rb`
- **All 6 test cases pass** (blocks manual ops, allows release scripts)

---

## URGENT: Website Update Needed

User said this is urgent and important but didn't have time this session.

**What needs updating on sanebar.com:**
- Show both viewing modes: Find Icon (default) and Floating Panel (opt-in)
- Current website mentions "Second Menu Bar" as a feature card but doesn't explain it's opt-in
- Screenshots needed for both modes
- Feature cards are currently `<div>` (non-clickable) — need screenshots for lightbox

---

## Documentation State

- **README.md** — Last updated Feb 9
- **ARCHITECTURE.md** — Last updated Feb 9
- **appcast.xml** — v1.0.22 entry live (DMG format — next release will be .zip)
- **SESSION_HANDOFF.md** — This file (Feb 10)

---

## GitHub Issues — All Closed

All SaneBar issues are closed. No open issues.

---

## CRITICAL RULES (Learned the Hard Way)

1. **MacBook Air = production only.** Never launch dev builds, never nuke defaults.
2. **Always show drafts** before posting GitHub comments or sending emails.
3. **Email via Worker only** — `email-api.saneapps.com/api/send-reply`, never Resend directly.
4. **Launch via sane_test.rb** — never `open SaneApp.app` or direct binary. Breaks TCC.
5. **ALWAYS bump version** before Sparkle release — same version = invisible update.
6. **NEVER manual R2 upload** — use `release.sh --deploy`. Hook enforces this.
7. **R2 key has NO `updates/` prefix** — Worker strips it from URL. Key = `SaneBar-X.Y.Z.zip`.
8. **Brand: "Mr. Sane" (person), "SaneApps" (org), `MrSaneApps` (GitHub/X handle).**
9. **Customer emails**: Start with "Thank you for taking the time to report this", sign off "— Mr. Sane".
10. **Signing identity: use generic `"Developer ID Application"`** — codesign resolves automatically.
11. **DMG file icons don't survive HTTP download** — use .zip distribution instead.
12. **Read SKILL.md first** — don't fumble with headers/endpoints from memory.

---

## Mac Mini Test Environment

- **SSH:** `ssh mini`
- **Deploy:** `ruby ~/SaneApps/infra/SaneProcess/scripts/sane_test.rb SaneBar`
- **Bundle ID:** `com.sanebar.dev` for dev, `com.sanebar.app` for prod
- **ALWAYS use sane_test.rb** — handles kill, clean, TCC reset, build, deploy, launch, logs

---

## NEXT SESSION — Priorities

1. **Run `/docs-audit`** — Skipped at end of this session, must run first thing
2. **URGENT: Website update** — Show both viewing modes (Find Icon + floating panel) on sanebar.com
3. **Full notarized release run** — Verify ZIP pipeline end-to-end with notarization
4. **MenuBarSearchView.swift extraction** — 1046 lines, over lint limit
5. **Security hardening** — AppleScript sanitization, auth for HideCommand
6. **SaneVideo README** — 17 undocumented features

---

## Recent Changes — XcodeBuildMCP Migration (Feb 13, 2026)

**XcodeBuildMCP → Apple xcode MCP migration COMPLETE for SaneBar.**

Community XcodeBuildMCP replaced with Apple's official xcode MCP (via `xcrun mcpbridge`). Global config already updated in `~/.claude/settings.json`.

**Files Updated:**
- `CLAUDE.md` — Removed "XcodeBuildMCP Session Setup" section (lines 209-217)
- `.claude/settings.json` — Removed `mcp__XcodeBuildMCP__*` from allow list and server config
- `scripts/sanemaster/dependencies.rb` — Removed XcodeBuildMCP from MCP verification list
- `scripts/sanemaster/verify.rb` — Updated comments to reference "xcode MCP server" instead of "xcodebuildmcp"

**Status:** Migration complete. No action needed. Global xcode MCP is already configured and working.

---

## Ongoing Items

1. **SaneBar v1.0.22**: Live, DMG format. Next release will be .zip format.
2. **ZIP pipeline**: Tested with --skip-notarize. Full notarized run pending.
3. **Website**: Needs update for dual viewing modes (urgent per user)
4. **HealsCodes video**: `~/Desktop/Screenshots/HealsCodes-always-hidden-move-bug.mp4` — unreviewed
