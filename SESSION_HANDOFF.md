# Session Handoff - Feb 9, 2026

## Release v1.0.18 (Production — LIVE)

**Version:** v1.0.18 (build 1018)
**Released:** Feb 5, 2026 7:32pm EST
**Git Tag:** `v1.0.18` on commit `c96ff59`

---

## v1.0.19 — In Progress (Not Released)

**Version:** 1.0.19 (build 1019) — set in `project.yml`

### What's in v1.0.19 so far

Everything from previous sessions (Reduce Transparency, script triggers, always-hidden fixes, shield pattern) PLUS all icon moving fixes below.

### Icon Moving — Current State (Feb 9, committed `8d12b46`)

**All move directions work.** Tested on Mac Mini. Committed and pushed to main.

**Architecture reference:** See `ARCHITECTURE.md` § "Icon Moving Pipeline" for the full technical reference (APIs tried, competitor analysis, what works/doesn't, known fragilities).

**What was fixed this session (Feb 9 afternoon):**

1. **showAll() for ALL moves** — Previously only move-to-visible expanded the separator. Move-to-hidden was blocked by the 10000px separator. Now ALL moves use the showAll() shield pattern when the bar is hidden.

2. **Move-to-visible target clamped** — Was overshooting past SaneBar icon into system area (triggered Control Center). Now: `max(separatorRightEdge + 1, mainIconLeftEdge - 2)`.

3. **Move-to-hidden AH boundary clamping** — Was overshooting past AH separator, putting icons into always-hidden zone. Now: `max(separatorOrigin - offset, ahSeparatorRightEdge + 2)`.

4. **Zone-aware context menus** — All tab now shows correct move options per icon zone. Added `appZone()` helper and `AppZone` enum. Each action factory is zone-aware.

5. **Separator cache in getSeparatorRightEdgeX()** — Also caches origin when at visual size, for classification during blocking mode.

6. **56 regression tests** — `Tests/IconMovingTests.swift` covering target calculation, drag timing, showAll requirement, verification margins, end-to-end scenarios.

### Icon Moving — Known Issues

1. **AH-to-Hidden verification too strict** — When AH and main separators are flush (both at x=1622), verification reports failure but icon moves correctly. The hidden zone between them is near-zero width. Move works visually; verification is a false negative.

2. **First drag sometimes fails** — Timing between showAll() completing and icons becoming draggable. Retry usually works.

3. **Speed** — Moves take ~2-3 seconds with the shield pattern (expand → wait → drag → restore → hide). User said "a little slow but it works." Optimize after everything is stable.

4. **Wide icons (>100px like CoinTick)** — May need special grab points. Not re-tested this session.

5. **MenuBarSearchView.swift is 1046 lines** — Over the 1000-line lint limit. Needs extraction.

### Files Changed This Session (committed in `8d12b46`)

| File | What Changed |
|------|-------------|
| `Core/MenuBarManager+IconMoving.swift` | showAll for all moves, AH separator reading, restore/re-hide for all moves |
| `Core/MenuBarManager.swift` | lastKnownSeparatorX property, screen change invalidation |
| `Core/Services/AccessibilityService+Interaction.swift` | Target calculation with AH clamping, human-like drag timing |
| `UI/SearchWindow/MenuBarSearchView.swift` | Zone-aware context menus, appZone() helper, removed loadCachedApps() |
| `UI/SearchWindow/SearchWindowController.swift` | isMoveInProgress flag + guards |
| `UI/SearchWindow/MenuBarAppTile.swift` | isMoving + isSelected properties |
| `SaneBar.xcodeproj/project.pbxproj` | Test target reference |
| `Tests/IconMovingTests.swift` | 56 regression tests (NEW) |

---

## Documentation State

- **ARCHITECTURE.md** — Updated Feb 9: Added "Icon Moving Pipeline" section with full technical reference (APIs, competitors, what works/doesn't, known fragilities). Fixed stale claims about "no CGEvent."
- **research.md** — Trimmed from 505 to ~105 lines. Icon moving research graduated to ARCHITECTURE.md. Remaining: Ice competitor analysis, Secondary Panel plan.

---

## CRITICAL RULES (Learned the Hard Way)

1. **MacBook Air = production only.** Never launch dev builds, never nuke defaults.
2. **Always show drafts** before posting GitHub comments or sending emails.
3. **Email via Worker only** — `email-api.saneapps.com/api/send-reply`, never Resend directly.
4. **Launch via `open`** — never `./SaneBar.app/Contents/MacOS/SaneBar`. Breaks TCC.
5. **300ms expand delay** — 500ms hits auto-rehide, separator reads off-screen.
6. **Read SKILL.md first** — don't fumble with headers/endpoints from memory.
7. **NEVER implement "fixes" from audits without verifying the bug exists in current code.**
8. **Read ARCHITECTURE.md § Icon Moving before touching move code.** Contains everything that works and doesn't.
9. **showAll() is required for ALL moves, not just move-to-visible.** The 10000px separator blocks in both directions.

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

1. **Fix AH-to-Hidden verification** — false negative when separators are flush. Consider relaxed margin or zone-based verification instead of position-based.
2. **Speed optimization** — explore shorter delays, parallel operations, or Ice's waitForFrameChange approach.
3. **MenuBarSearchView.swift extraction** — 1046 lines, over lint limit. Split zone helpers and action factories into separate file.
4. **CoinTick (wide icon) testing** — re-test on Mac Mini.

---

## Ongoing Items

1. **SaneBar v1.0.19**: Icon moving working, ready for broader testing
2. **Secondary Panel**: Plan complete in research.md, no code yet, user demand growing (#41, #42)
3. **GitHub Issue #42**: Script triggers request — needs acknowledgment (SHOW DRAFT FIRST)
4. **HealsCodes video**: `~/Desktop/Screenshots/HealsCodes-always-hidden-move-bug.mp4` — unreviewed
