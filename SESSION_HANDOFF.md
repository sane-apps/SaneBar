# Session Handoff — SaneBar

**Date:** 2026-02-16
**Last released version:** v2.1.2 (build 2102) — Released Feb 16
**Uncommitted changes:** Battery threshold feature (3 files, 344/344 tests pass)

---

## Done This Session

1. **Released v2.1.2** — Energy fix (24% → 0% CPU), mouse throttle, Stage Manager fix, battery polling reduction. Full pipeline: build → sign → notarize → DMG → Sparkle → R2 → appcast → website → Homebrew → GitHub.

2. **Root cause: animated MeshGradient** — `Backgrounds.swift` had a 12fps TimelineView that never paused because `onDisappear` doesn't fire for ordered-out NSWindows (`SearchWindowController` reuses windows). Replaced with static mesh per user request.

3. **Replied to Peter** (email #50, 8 issues) — Corrected wrong auto-reply ("SaneClip" → "SaneBar"). Covered energy fix, Stage Manager, Bartender import limitation, Cmd+drag layout explanation with demo video link.

4. **Battery threshold feature** (UNCOMMITTED) — `PersistenceService.swift`, `TriggerService.swift`, `RulesSettingsView.swift`. Reads actual battery % via IOPSCopyPowerSourcesInfo instead of system warning flag. Slider 5-50% in steps of 5. Triggers on transition below threshold. 344/344 tests pass.

5. **GitHub cleanup** — Deleted old releases v1.0.23–v2.1.1 (had energy bug). Uploaded ZIP to v2.1.2. Filed #68 (icon reorder from panel).

6. **Fixed rounded corners (#64)** — (previous sub-session) Removed horizontal inset from MenuBarOverlayView.

---

## Uncommitted Changes

| File | Change |
|------|--------|
| `Core/Services/PersistenceService.swift` | Added `batteryThreshold: Int = 20` + CodingKey + decoder |
| `Core/Services/TriggerService.swift` | Replaced IOPSGetBatteryWarningLevel with actual % reading via IOPSCopyPowerSourcesInfo |
| `UI/Settings/RulesSettingsView.swift` | Conditional threshold slider when battery trigger is on |
| `docs/index.html` | Website updates from release |
| `SaneBar.xcodeproj/project.pbxproj` | Xcode project changes |

---

## Open GitHub Issues

| # | Title | Scope | Status |
|---|-------|-------|--------|
| #64 | Rounded corners truncation | Fix shipped in v2.1.2 | Can close |
| #65 | Help wanted: demo videos | Community | Open |
| #66 | Bartender import: Little Snitch | Medium — needs CGS private API | Deferred |
| #67 | Custom triggers | Battery threshold done (uncommitted). Schedule + Focus mode deferred | Partial |
| #68 | Reorder icons from panel | Feature request — Cmd+drag from panel | Open |

---

## Known Issues

- **SSMenu icon drift**: Agent icon jumps zones on reveal. Inherent limitation of length-toggle technique.
- **Experimental Settings tab empty**: Only has bug report button. Should populate or remove.

---

## Serena Memories

- `sanebar-peter-fixes-v212-feb16` — Full details of v2.1.2 release, Peter's issues, uncommitted battery threshold
- `peter-energy-stage-manager-fixes-feb16` — Earlier memory with initial fix details

---

## Next Session Priorities

1. Commit battery threshold feature (tests pass, ready to go)
2. Close #64 on GitHub (fix already shipped)
3. #66 Bartender import — assess if CGS private API approach is worth it
4. #67 remaining — schedule triggers, Focus mode triggers
5. #68 — Icon reorder from panel (check if trivial to wire up)
6. SSMenu icon drift investigation
7. Experimental tab — populate or remove
