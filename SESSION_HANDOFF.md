# Session Handoff - Feb 8, 2026 (Morning)

## Release v1.0.18 (Production — LIVE)

**Version:** v1.0.18 (build 1018)
**Released:** Feb 5, 2026 7:32pm EST
**Git Tag:** `v1.0.18` on commit `c96ff59`
**Pipeline:** `release.sh --full --deploy` (end-to-end automated)
**Notarization ID:** dff2edce-f9d8-4c67-b5d8-8648be421296
**SHA256:** 3809087ffbc2170c24a0b02108443084bfc5a38e86a58079ff339b05a5d14a27

### What shipped in v1.0.18
- Import from Bartender & Ice
- Custom Menu Bar Icon
- Standalone Build support
- About View Fix, Dark Mode Tint, GPL v3, new app icon

---

## v1.0.19 — In Progress (Not Released)

**Version:** 1.0.19 (build 1019) — set in `project.yml`
**Base:** v1.0.18 tag (`c96ff59`)

### What's in v1.0.19 so far

**Reduce Transparency fix** (4 commits):
- Skip Liquid Glass when RT enabled, use solid tint
- Opacity floor `max(baseOpacity, 0.5)` when RT on
- Live observer via `accessibilityDisplayOptionsDidChangeNotification`
- DistributedNotificationCenter for appearance observer

**Script triggers & AppleScript commands** (`802401a`):
- Per-icon `hide icon` / `show icon` / `list icons` AppleScript commands

**Always-Hidden critic fixes** (Feb 7 session):
- Separator removed when feature disabled (was orphaned)
- Separator visibility 0.4 → 0.8 (was nearly invisible)
- Pin ID validation (reject control chars, empty, >500 chars)
- Separator ordering guard in enforcement (always-hidden must be LEFT of main)
- Stale/unparseable pin IDs auto-cleaned during enforcement
- `ShowIconCommand` now checks `alwaysHiddenSectionEnabled` (matched `HideIconCommand`)
- `alwaysHiddenSeparatorItem` added to `StatusBarControllerProtocol` + mock
- 17 new tests in `AlwaysHiddenTests.swift` (parse, zone, bundleId, pinned)

**Shield pattern for always-hidden moves** (Feb 7 session):
- `moveIconAlwaysHidden()` uses HidingService `showAll/restoreFromShowAll`
- Prevents position corruption from invariant violations
- Concurrency guards: `isAnimating`, `isTransitioning`
- `activeMoveTask` reject-if-busy pattern (no cancel-and-restart)
- Privacy-safe logging throughout icon-moving pipeline

**Icon move overshoot fix** (Feb 7-8 session — CRITICAL BUG FIX):
- **Root cause:** `targetX = separatorX + 100` overshot past SaneBar's own icon
- **Fix:** Added `visibleBoundaryX` parameter to `moveMenuBarIcon()` — the left edge of SaneBar's main status item
- **Clamped target:** `min(separatorX + 50, boundaryX - 20)` — icons land in the visible zone, never past our icon
- **Files changed:**
  - `Core/Services/AccessibilityService+Interaction.swift:197-204` — target calculation with clamp
  - `Core/MenuBarManager+IconMoving.swift:173-181` — `moveIcon()` computes and passes boundary
  - `Core/MenuBarManager+IconMoving.swift:279-286` — `moveIconAlwaysHidden()` same pattern
- **Key learning:** Ice doesn't programmatically move icons — it only hides/shows via separator length. SaneBar's CGEvent Cmd+drag is unique and needs careful bounds checking.

**Infra:**
- URL scheme removed from Info.plist
- SaneMaster scripts updated
- Canonical gitignore/swiftlint synced

### SwiftLint Warnings (non-blocking)
- `MenuBarManager.swift` 884 lines (warn at 800, error at 1000)
- `MenuBarSearchView.swift` 961 lines (warn at 800, error at 1000)
- `MenuBarAppTile.swift:20` implicit optional init

---

## Context Brief Pattern — NEW SKILL ARCHITECTURE (Feb 8)

### What happened
18 critic reviews (6 perspectives x 3 models) ALL missed the +100 overshoot bug because
they reviewed code syntax in a vacuum without knowing the runtime spatial layout.

### What we built
**Mandatory Context Briefs** — Claude writes a structured brief BEFORE sending code/files
to external models. The brief explains:
- What the code DOES (behavior, not syntax)
- Runtime values and spatial/temporal relationships
- Invariants that must hold
- Historical bugs (pattern recognition)
- Hardcoded constants and their assumptions
- Specific questions for reviewers

### Skills updated with Context Brief pattern

| Skill | Brief Location | What It Contains |
|-------|---------------|-----------------|
| **critic** | `/tmp/critic_context_brief.md` | Feature behavior, execution pipeline, runtime context, invariants, historical bugs, magic numbers |
| **docs-audit** | `/tmp/docsaudit_context_brief.md` | Project purpose, key features, recent changes, target audience, known doc gaps |
| **sane-audit** | `/tmp/audit_context_brief.md` | Infrastructure landscape, recent deployments, known issues, cross-project deps |
| **seo-audit** | `/tmp/seo_context_brief.md` | Product purpose, target audience, conversion goals, marketing framework |
| **orchestrate** | `/tmp/orchestrate_context_brief.md` | Problem description, execution pipeline, runtime context, invariants, investigation findings |
| **evolve** | `/tmp/evolve_context_brief.md` | What we're building, pain points, tech stack, recent struggles |

### New critic perspective: Pipeline Tracer (7th)
- `~/.claude/skills/critic/prompts/pipeline-tracer.md`
- Traces values end-to-end through call chains
- Questions every intermediate value and magic number
- Catches the exact class of bug that +100 was
- Critic now runs 7 perspectives x 3 models = 21 reviews per run

---

## Mac Mini Test Environment (Feb 8)

### Cleanup performed
- Removed duplicate `~/Applications/SaneBar.app` (was alongside `/Applications/SaneBar.app`)
- Nuked DerivedData for all Sane apps
- Rebuilt Launch Services database
- Cleaned stale `/tmp/SaneBar*.tar.gz`

### Gotcha: TCC permissions
- `tccutil reset Accessibility` was accidentally run — clears ALL app permissions
- Bundle ID is `com.sanebar.dev` for development builds
- After cleanup, user had to re-grant Accessibility permission

---

## Secondary Panel / Dropdown Bar — RESEARCH COMPLETE, PLAN READY

**Full plan:** `.claude/research.md` §"Secondary Panel / Dropdown Bar — Implementation Plan"

**User context:** Customer asked for the feature. User told them they'd look into it. User is nervous
about building it but wants the plan ready. User explicitly said NOT to build now (Feb 7).

**User demand:**
- Issue #41 (Groups, Feb 6) — wants clickable group icons
- Issue #42 (Script triggers, Feb 7) — wants per-icon script triggers
- **NO RESPONSE YET to #42**

**Decision needed when ready:** Include in 1.0.19 as experimental, or keep for 1.1?

---

## NEXT SESSION — First Priority

**Run full critic review on the entire icon-moving/positioning system.**
User wants the new 7-perspective + context brief critic to tear apart the positioning code
and find why icon moving is unreliable. This is the first real test of the context brief pattern.

Target files for the bundle:
- `Core/Services/AccessibilityService+Interaction.swift` (CGEvent drag, icon frame detection)
- `Core/MenuBarManager+IconMoving.swift` (move orchestration, separator position)
- `Core/Services/HidingService.swift` (show/hide/showAll/restoreFromShowAll)
- `Core/MenuBarManager+AlwaysHidden.swift` (always-hidden zone management)
- `Core/StatusBarController.swift` (separator creation, positioning seeds)

The context brief MUST include:
- macOS menu bar coordinate system (X increases left→right, Y=0 at top)
- SaneBar's separator positioning model (main separator, always-hidden separator)
- The CGEvent Cmd+drag mechanism (unique to SaneBar — Ice doesn't do this)
- Known bugs: +100 overshoot (fixed), position corruption (fixed with shield pattern)
- All hardcoded constants: `+50`, `-50`, `-20`, `0.25s`, `0.3s`, `6 steps`, `y=12`

---

## Ongoing Items

1. **Full critic review of positioning system** (next session, first priority)
2. **SaneBar v1.0.19**: Code ready with overshoot fix, needs final QA + release
3. **Secondary Panel**: Plan complete, no code, user demand growing (#41, #42)
4. **Issue #42 response**: Script triggers request — needs acknowledgment
5. **Always-Hidden "(beta)" label**: Still in UI — UX critic flagged, not a blocker
6. **SaneSales**: Not a git repo — needs init or monorepo integration
7. **SaneClip iOS**: Needs Apple Developer portal setup before submission

---

## All Secrets Configured

| System | Service/Account | Status |
|--------|----------------|--------|
| Email API | `sane-email-automation` / `api_key` | Configured |
| Resend | `resend` / `api_key` | Configured |
| Cloudflare | `cloudflare` / `api_token` | Configured |
| LemonSqueezy | `lemonsqueezy` / `api_key` | Configured |
| Worker secrets | All 7 via `wrangler secret` | Configured |
