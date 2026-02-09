# Session Handoff - Feb 9, 2026

## Release v1.0.18 (Production — LIVE)

**Version:** v1.0.18 (build 1018)
**Released:** Feb 5, 2026 7:32pm EST
**Git Tag:** `v1.0.18` on commit `c96ff59`

---

## v1.0.19 — In Progress (Not Released)

**Version:** 1.0.19 (build 1019) — set in `project.yml`

### What's in v1.0.19 so far

Everything from previous sessions (Reduce Transparency, script triggers, always-hidden fixes, shield pattern, icon moving fixes) PLUS:

### Always-Hidden Graduation (Feb 9, committed + pushed)

Always-hidden promoted from experimental to permanent first-class feature:
- Default changed to `true` in PersistenceService (backward-compat `decodeIfPresent` kept)
- All guards/conditionals removed across 9 files
- Settings toggle removed from ExperimentalSettingsView
- Dead code cleaned: `showResetConfirmation`, unused `menuBarManager` in AboutSettingsView, `hasExperimentalFeatures` dead block in ExperimentalSettingsView

### Documentation Updates (Feb 9, committed + pushed)

- **README.md**: Graduated always-hidden, added Second Menu Bar + Onboarding Wizard + Always-Hidden Zone sections, updated How It Works (three-zone architecture), updated comparison table, updated AppleScript docs, updated project structure
- **docs/index.html (website)**: Added 3 rows to comparison table (Always-Hidden Zone, Second Menu Bar, Onboarding Wizard), added 2 feature cards (non-clickable `<div>` pending screenshots)
- **DOCS_AUDIT_FINDINGS.md**: Full 14-perspective audit results

### Icon Moving — Current State (Feb 9, committed `8d12b46`)

**All move directions work.** Tested on Mac Mini. Committed and pushed to main.

**Architecture reference:** See `ARCHITECTURE.md` § "Icon Moving Pipeline" for the full technical reference.

### Icon Moving — Known Issues

1. **AH-to-Hidden verification too strict** — When AH and main separators are flush, verification reports failure but icon moves correctly.
2. **First drag sometimes fails** — Timing between showAll() and icons becoming draggable.
3. **Speed** — Moves take ~2-3 seconds with shield pattern.
4. **Wide icons (>100px like CoinTick)** — May need special grab points.
5. **MenuBarSearchView.swift is 1046 lines** — Over lint limit. Needs extraction.

---

## Documentation State

- **README.md** — Updated Feb 9: Graduated always-hidden, documented second menu bar, onboarding, zone management, comparison table
- **docs/index.html** — Updated Feb 9: Comparison table + feature cards (screenshots needed)
- **ARCHITECTURE.md** — Updated Feb 9: "Icon Moving Pipeline" section
- **DOCS_AUDIT_FINDINGS.md** — Created Feb 9: Full 14-perspective audit (7.7/10 overall)
- **research.md** — Trimmed to ~105 lines. Icon moving graduated to ARCHITECTURE.md.

---

## FOLLOW-UPS

### Screenshots Needed (User will do later)
- **Second Menu Bar** — New feature card on website needs screenshot for lightbox
- **Always-Hidden Zone** — New feature card on website needs screenshot for lightbox
- **Onboarding Wizard** — Consider adding feature card + screenshot
- Feature cards are currently `<div>` (non-clickable). Convert to `<a>` with lightbox once screenshots exist.

### From Docs Audit (DOCS_AUDIT_FINDINGS.md)
- **Security items**: AppleScript input sanitization (#11), auth for HideCommand (#12), plaintext sensitive settings (#13)
- **UX discoverability**: Dropdown panel has no visual cue for new users (#9), no feedback on failed icon moves (#10)
- **Design**: Dropdown panel spacing, keyboard nav, light mode contrast (#15-#18)
- **MenuBarSearchView extraction**: 1046 lines → split zone helpers + actions (#6)
- **Website**: Update sanebar.com to fully match current feature set (#5)

---

## CRITICAL RULES (Learned the Hard Way)

1. **MacBook Air = production only.** Never launch dev builds, never nuke defaults.
2. **Always show drafts** before posting GitHub comments or sending emails.
3. **Email via Worker only** — `email-api.saneapps.com/api/send-reply`, never Resend directly.
4. **Launch via `open`** — never `./SaneBar.app/Contents/MacOS/SaneBar`. Breaks TCC.
5. **300ms expand delay** — 500ms hits auto-rehide, separator reads off-screen.
6. **Read SKILL.md first** — don't fumble with headers/endpoints from memory.
7. **NEVER implement "fixes" from audits without verifying the bug exists in current code.**
8. **Read ARCHITECTURE.md § Icon Moving before touching move code.**
9. **showAll() is required for ALL moves, not just move-to-visible.**

---

## Mac Mini Test Environment

- **SSH:** `ssh mini` → `Stephans-Mac-mini.local` as `stephansmac`
- **Deploy pipeline:** `tar czf` on Air → `scp mini:/tmp/` → extract → `mv ~/Applications/` → `open`
- **Bundle ID:** `com.sanebar.dev` for dev builds
- **Logging:** `nohup log stream --predicate 'subsystem BEGINSWITH "com.sanebar"' --info --debug > /tmp/sanebar_stream.log 2>&1 &`
- **ALWAYS launch via `open`** — direct binary execution breaks TCC grants
- **NEVER run dev builds on MacBook Air** — production only on Air

---

## NEXT SESSION — Priorities

1. **Screenshots** — Take screenshots for Second Menu Bar and Always-Hidden Zone feature cards, convert `<div>` to `<a>` with lightbox
2. **Fix AH-to-Hidden verification** — false negative when separators are flush
3. **Speed optimization** — explore shorter delays, parallel operations
4. **MenuBarSearchView.swift extraction** — 1046 lines, over lint limit
5. **Security hardening** — AppleScript sanitization, auth for HideCommand
6. **CoinTick (wide icon) testing** — re-test on Mac Mini

---

## Ongoing Items

1. **SaneBar v1.0.19**: Always-hidden graduated, icon moving working, docs updated
2. **Secondary Panel**: Plan complete in research.md, no code yet, user demand growing (#41, #42)
3. **GitHub Issue #42**: Script triggers request — needs acknowledgment (SHOW DRAFT FIRST)
4. **HealsCodes video**: `~/Desktop/Screenshots/HealsCodes-always-hidden-move-bug.mp4` — unreviewed
