# Session Handoff - Feb 7, 2026 (Afternoon)

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

**Always-Hidden critic fixes** (this session):
- Separator removed when feature disabled (was orphaned)
- Separator visibility 0.4 → 0.8 (was nearly invisible)
- Pin ID validation (reject control chars, empty, >500 chars)
- Separator ordering guard in enforcement (always-hidden must be LEFT of main)
- Stale/unparseable pin IDs auto-cleaned during enforcement
- `ShowIconCommand` now checks `alwaysHiddenSectionEnabled` (matched `HideIconCommand`)
- `alwaysHiddenSeparatorItem` added to `StatusBarControllerProtocol` + mock
- 17 new tests in `AlwaysHiddenTests.swift` (parse, zone, bundleId, pinned)

**Infra:**
- URL scheme removed from Info.plist
- SaneMaster scripts updated
- Canonical gitignore/swiftlint synced

### SwiftLint Warnings (non-blocking)
- `MenuBarManager.swift` 884 lines (warn at 800, error at 1000)
- `MenuBarSearchView.swift` 961 lines (warn at 800, error at 1000)
- `MenuBarAppTile.swift:20` implicit optional init

---

## Critic Review — Always-Hidden (18 Reviews, This Session)

Fired 6 perspectives x 3 NVIDIA models on 16-file 247KB bundle.
- 8 real issues fixed (see above)
- 2 false positives identified (unpin on Move-to-Visible already worked, SearchService already guarded)
- 1 deferred (enforcement race — cancel-and-recreate already debounces correctly)

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

## Ongoing Items

1. **SaneBar v1.0.19**: Code ready, needs final QA + release
2. **Secondary Panel**: Plan complete, no code, user demand growing (#41, #42)
3. **Issue #42 response**: Script triggers request — needs acknowledgment
4. **Always-Hidden "(beta)" label**: Still in UI — UX critic flagged, not a blocker
5. **SaneSales**: Not a git repo — needs init or monorepo integration
6. **SaneClip iOS**: Needs Apple Developer portal setup before submission

---

## All Secrets Configured

| System | Service/Account | Status |
|--------|----------------|--------|
| Email API | `sane-email-automation` / `api_key` | Configured |
| Resend | `resend` / `api_key` | Configured |
| Cloudflare | `cloudflare` / `api_token` | Configured |
| LemonSqueezy | `lemonsqueezy` / `api_key` | Configured |
| Worker secrets | All 7 via `wrangler secret` | Configured |
