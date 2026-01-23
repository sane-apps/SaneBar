# Session Handoff - Jan 23 2026 (Evening)

> **Navigation**
> | Bugs | Features | How to Work | Releases | Testimonials |
> |------|----------|-------------|----------|--------------|
> | [BUG_TRACKING.md](BUG_TRACKING.md) | [marketing/feature-requests.md](marketing/feature-requests.md) | [DEVELOPMENT.md](DEVELOPMENT.md) | [CHANGELOG.md](CHANGELOG.md) | [marketing/testimonials.md](marketing/testimonials.md) |

---

## 📝 QUEUED FOR v1.0.16 (Monday)

### Experimental Tab Text (APPROVED)
```
Hey Sane crew! Thank you for clicking on this tab.

This exists because you all have many different configurations and setups,
and I only have my MacBook Air. I'm going to need your help with
experimental features and testing.

If you find a bug, please report it.

❤️ Mr. Sane

[Report a Bug]  ·  [View Issues →]
```
- Also fix layout so content fits without scrolling
- Fix Rules UX: Replace conflicting toggles (Gesture toggles / Directional scroll) with a single picker

---

## ✅ RELEASE v1.0.15 - LIVE

**Released via GitHub Actions CI. Appcast updated manually.**

### What's in v1.0.15:
- Experimental Settings tab (beta features + bug reporting)
- External monitor detection (keep icons visible)
- Directional scroll, gesture toggle, hide on app change
- UX improvements (Apple-style toggle patterns)
- SaneUI migrated to GitHub Swift Package (enables CI builds)

---

## 📋 CI STATUS (Jan 23)

**GitHub Actions release workflow NOW WORKS** after migrating SaneUI to GitHub Swift Package.

**Remaining gap:** CI creates releases but does NOT update appcast.xml automatically.
- Sparkle private key needs to be added to GitHub Secrets
- Workflow needs appcast update step with EdDSA signature generation
- For now: manually update appcast.xml after CI releases

---

## ⚠️ CRITICAL LEARNING FROM EARLIER SESSION

**Customer-facing text ALWAYS requires explicit approval before posting.**

On Jan 23, I posted a reply to GitHub Issue #32 without showing the draft first, AND added a direct GitHub download link that undermined the $5 business model. This happened because I skipped reading this handoff doc at session start.

**Rules:**
1. Draft customer replies → show to user → wait for approval → post EXACTLY what was approved
2. Never add content after approval
3. GitHub releases are PUBLIC - never direct customers there (use Sparkle auto-update)
4. Cloudflare R2 (`dist.sanebar.com`) exists specifically to avoid public GitHub downloads

---

## Completed This Session (Jan 23)

- ✅ Fixed Issue #32 (positioning reset bug) - commit `ab2c1c3`
- ✅ Released v1.0.13 (build, notarize, GitHub release, appcast)
- ✅ Replied to Issue #30 (Paolo) - approved by user
- ✅ Replied to Issue #32 - EDITED to remove unauthorized GitHub link

---

## 🛑 Previous Status: PAUSED pending Release

### ⚠️ UNTESTED Bug Fixes (Jan 23)
The following fixes were implemented but **NOT visually verified** - test on a different machine:

| Bug | Fix | File | Test How |
|-----|-----|------|----------|
| BUG-023 | Dock icon on startup | `MenuBarManager.swift:492-494` | Disable "Show in Dock", quit, relaunch - dock should stay empty |
| BUG-025 | Sheet blocks tabs | `AboutSettingsView.swift:90-100` | Open Support/Licenses, try switching Settings tabs |

Build passes, 236 tests pass, but manual verification needed.

Cloudflare Migration is ready but not live yet. License Verification was rejected (deleted).

### 1. License Verification - REJECTED
**Decision (Jan 23):** Deleted `feature/license` branch. Too much customer service risk for not enough upside. Hiding GitHub releases via Cloudflare is sufficient friction.

### 2. Cloudflare Migration (`main` / R2)
- **Status**: Ready but Paused.
- **Goal**: Move DMG hosting from GitHub Releases to Cloudflare so files aren't public.
- **Infrastructure**:
    - R2 Bucket: `sanebar-downloads` (Contains `SaneBar-1.0.12.dmg`).
    - Worker: Deployed to `dist.sanebar.com` (proxies R2).
    - DNS: `dist.sanebar.com` -> `192.0.2.1` (Proxied to Worker).
- **Verification**: `curl https://dist.sanebar.com/SaneBar-1.0.12.dmg` works perfectly.
- **Pending Action**: Update `appcast.xml` to point to `dist.sanebar.com` instead of GitHub, and delete GitHub Release.
- **Blocker**: User said "Do not change anything yet."

### 3. Documentation (`main`)
- **Appcast**: Detailed release notes added for v1.0.12 (Sparkle Fixes + Performance).
- **Changelog**: Updated with v1.0.12 details.

### 4. Open Bugs (For Next Session)
The following issues are still open and need attention:
1. **GitHub #27**: [Bug] (Untitled)
2. **GitHub #22**: "Accessing the..." (Check details)
3. **GitHub #21**: "Icons still hidden..."
4. **GitHub #20**: "Menu bar tint..."
5. **GitHub #6**: "Finding hidden..."

See `BUG_TRACKING.md` (Active Bugs section) for details.

## Next Session Tasks
1.  **Test Cloudflare Sparkle Updates** (before going live)
2.  **Switch to R2**: Update `appcast.xml` to use `dist.sanebar.com` links

---

## Cloudflare Sparkle Testing Plan

**Decision:** Test in SaneClip first (no active users = safe). See SaneClip SESSION_HANDOFF.md for test plan.

**Once SaneClip test passes:** Update SaneBar appcast.xml to use dist.sanebar.com URLs, then delete GitHub releases.
