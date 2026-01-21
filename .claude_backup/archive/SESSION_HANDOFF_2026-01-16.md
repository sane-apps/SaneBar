# SaneBar Session Handoff - 2026-01-16 (FINAL - 12:00 PM)

## Current Status: BUNDLE-ID-SPECIFIC CORRUPTION - UNFIXABLE ON SJ ACCOUNT

**Root cause: Bundle ID `com.sanebar.app` has deep WindowServer corruption on `sj` user account.**

The corruption prevents WindowServer from registering NSStatusItem windows. The code is correct, but macOS refuses to display status items for this specific bundle ID on this specific user.

---

## What Works vs What Doesn't

| Configuration | Result |
|--------------|--------|
| `com.sanebar.app` on `sj` user | ❌ BROKEN - windows not registered with WindowServer |
| `com.sanebar.app` on `sanebartest` user | ✅ WORKS |
| `com.sanebar.app2` on `sj` user | ✅ WORKS |
| `com.newsanebar.menubar` on `sj` user | ✅ WORKS |

**Cannot change bundle ID for production** - would break existing users, Sparkle updates, accessibility permissions.

---

## The Symptom (Technical Detail)

1. App creates `NSStatusBar.system.statusItem()` successfully
2. `item.button` exists
3. `item.button.window` exists with correct coordinates (x=1103, y=923)
4. Position log shows items at correct positions after 0.5s
5. **BUT** `CGWindowListCopyWindowInfo` shows NO status item windows for SaneBar
6. Only popup/settings windows appear (y=702, y=826), not status bar windows (should be y=0)
7. Control Center's 8 windows appear correctly at layer 25, y=0

**The windows exist in app memory but are never registered with WindowServer.**

---

## Everything We Tried (Chronological)

### Phase 1: Code Fixes (COMPLETED)
| Fix | Status |
|-----|--------|
| Removed `ensureDefaultPositions()` from StatusBarController.init() | ✅ Done (was writing backwards x=100,120) |
| Added `app.setActivationPolicy(.accessory)` to main.swift BEFORE `app.run()` | ✅ Done |
| Incremented autosaveName to v6 | ✅ Done (didn't help) |

### Phase 2: Preference Cleanup (ALL FAILED)
| Attempt | Result |
|---------|--------|
| Delete all SaneBar UserDefaults | ❌ Still broken |
| Delete ByHost/.GlobalPreferences position entries | ❌ Still broken |
| Delete ~/Library/Preferences/com.sanebar.app.plist | ❌ Still broken |
| Kill cfprefsd and let it restart | ❌ Still broken |
| CFPreferences force-write correct positions (x=1200) | ❌ WindowServer ignores them |

### Phase 3: System Cache Cleanup (ALL FAILED)
| Attempt | Result |
|---------|--------|
| Restart Dock | ❌ Still broken |
| Restart SystemUIServer | ❌ Still broken |
| Clear all DerivedData | ❌ Still broken |
| Delete ~/Library/Application Support/SaneBar | ❌ Still broken |
| Reset Launch Services (`lsregister -kill -r`) | ❌ Still broken (and -kill is disabled) |
| Clear /var/folders caches for com.sanebar.app | ❌ Still broken |
| Delete ~/Library/Saved Application State | ❌ Still broken |

### Phase 4: Session/Boot Level (ALL FAILED)
| Attempt | Result |
|---------|--------|
| Logout/login | ❌ Still broken |
| Safe Boot mode | ❌ Still broken |
| `sudo killall WindowServer` | ❌ macOS protects it, didn't restart |

### Phase 5: System Database Search (NO CORRUPTION FOUND)
| Location Checked | Result |
|-----------------|--------|
| TCC.db | Permission denied / No entries |
| /var/folders cache | Only Metal shader cache (identical working/broken) |
| CoreDuet/Knowledge DB | No entries |
| Extended attributes on app bundle | None |
| Notification Center DB | No access |
| WindowServer prefs | No sanebar entries |
| SystemUIServer prefs | No sanebar entries |
| Gatekeeper (spctl) | "Rejected" (normal for debug builds) |
| Saved Application State | No sanebar entries |
| Siri applications laststate | Just launch history |
| CrashReporter Intervals | Just crash history |

---

## Key Memory Observations

1. **#5208**: Forced correct positions (x=1200) written to preferences, but WindowServer ignores them and applies cached x=0.0
2. **#5164**: Three-phase fix completed, bundle ID testing proved corruption is cached per-bundle-ID
3. **#5140**: Logout/login did NOT clear corruption - survives session restart
4. **#5144**: /var/folders cleanup failed - corruption not in user-accessible caches
5. **#5227**: Persists after OS reinstall - this is the smoking gun that it's user-account-specific, not OS-level

---

## Workaround: sanebartest Dev Environment (CONFIGURED)

Since `com.sanebar.app` works correctly on `sanebartest` user, that account is now set up as a full dev environment:

### What's Configured
- **Project symlinks**: SaneBar, SaneVideo, SaneSync, SaneProcess, SaneAI, homebrew-sanebar, Dev, Scripts
- **Shell config**: .zshrc with Homebrew, Ruby, Node, Bun + Claude Code launching aliases + API keys
- **Git config**: Copied from sj
- **Claude Code config**: CLAUDE.md and settings.json copied

### To Use
1. Switch to sanebartest user (login screen or fast user switching)
2. Open Terminal
3. `cd ~/SaneBar && ./scripts/SaneMaster.rb test_mode`
4. SaneBar icons will appear correctly in menu bar

### Aliases Available
- `sb`, `sv`, `ss`, `sp`, `sa` - cd to project AND launch Claude Code
- `gsb`, `gsv`, `gss`, `gsp`, `gsa` - Gemini versions
- `cc` - claude --dangerously-skip-permissions
- `g` - gemini
- `smt` - `./scripts/SaneMaster.rb test_mode`
- `smv` - `./scripts/SaneMaster.rb verify`
- API keys: XAI, Gemini, Google, OpenAI all configured

---

## Remaining Options (If Needed)

1. **Full system restart** - Might clear WindowServer memory (untested)
2. **Reinstall macOS with full wipe** - Would create new user account anyway
3. **Different bundle ID for dev only** - Use `com.sanebar.dev` locally, `com.sanebar.app` for releases

---

## Files Changed This Session

| File | Change |
|------|--------|
| `main.swift` | Added `app.setActivationPolicy(.accessory)` BEFORE `app.run()` |
| `Core/Controllers/StatusBarController.swift` | Autosave names updated to v6 |
| `/Users/sanebartest/.zshrc` | Created with full dev environment |
| `/Users/sanebartest/.gitconfig` | Copied from sj |
| `/Users/sanebartest/.claude/` | Claude Code config copied |

---

## Quick Reference

### Test SaneBar (from sj account - will be broken)
```bash
cd ~/SaneBar && ./scripts/SaneMaster.rb test_mode
cat /tmp/sanebar_positions.log  # Shows x=1103 but CGWindowList won't have it
```

### Test SaneBar (from sanebartest account - works)
```bash
cd ~/SaneBar && ./scripts/SaneMaster.rb test_mode
# Icons appear correctly in menu bar
```

### Check if corruption still exists
```bash
swift -e '
import Cocoa
let pid = Int32(CommandLine.arguments[1])!
let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
let layer25 = windows.filter { ($0[kCGWindowLayer as String] as? Int) == 25 && ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
print("Status item windows at layer 25: \(layer25.count)")
' $(pgrep -x SaneBar)
# Should be 2+ for working, 0 for broken (only popovers show)
```

---

## Conclusion

The corruption is at a level of macOS that we cannot access or clear. It's stored somewhere that survives:
- Safe Boot
- All preference deletion
- Launch Services reset
- Logout/login
- cfprefsd restart

But does NOT survive:
- Using a different bundle ID
- Using a different user account

**Recommended path forward**: Develop in sanebartest account, test releases on sj account periodically.

---

## 2026-01-16 Follow‑Up (Scientific Method Notes)

### Instrumentation Added
- Status item visibility KVO + WindowServer layer‑25 counts in [Core/Controllers/StatusBarController.swift](Core/Controllers/StatusBarController.swift).
- Env‑gated experiments:
	- `SANEBAR_DISABLE_AUTOSAVE=1` (disable autosaveName)
	- `SANEBAR_FORCE_VISIBLE=1` (force isVisible true)
	- `SANEBAR_STATUSITEM_DELAY_MS=...` (defer creation)

### Critical Positioning Breakthrough (2026‑01‑16, sj account)
**Observed:** Status items were visible only bottom‑left (offscreen); after recovery/nudge changes and delayed creation, both separator “/” and main item became visible in the menu bar. Warning popovers moved to top‑right, confirming menu‑bar anchoring.

**What ultimately made icons visible:**
1. **Delayed status‑item creation** via `SANEBAR_STATUSITEM_DELAY_MS=3000` to let WindowServer settle (mirrors MinimalTest behavior where icons appear after ~1s). See MinimalTest notes below.
2. **Recovery + nudge**: `SANEBAR_ENABLE_RECOVERY=1` + `SANEBAR_FORCE_WINDOW_NUDGE=1` to reposition status item windows into menu‑bar coordinates and bring them front.
3. **Forced text icons** (debug) via `SANEBAR_FORCE_TEXT_ICON=1` to make visibility unambiguous.

**Code changes supporting this:**
- [Core/MenuBarManager.swift](Core/MenuBarManager.swift)
	- Recovery now retries and defers if window screens are nil.
	- Nudge uses status‑item screen, moves windows to menu bar, orders them front, and re‑binds delimiter.
	- Nudge position adjusted away from Control Center/clock with dynamic inset.
- [Core/MenuBarManager+Monitoring.swift](Core/MenuBarManager+Monitoring.swift)
	- Position validation defers until windows are on a valid screen and aligned to menu‑bar Y.
	- Forced swap attempt when separator ends right of main (env‑gated).
- [Core/Controllers/StatusBarController.swift](Core/Controllers/StatusBarController.swift)
	- Added `SANEBAR_FORCE_TEXT_ICON=1` for SB + “/” text icons.
	- Logging expanded (window visibility/screen) and emitted via unified logging.

**MinimalTest insight (relevant):**
MinimalTest shows status items can appear at x=0 initially, then settle to the right after ~1s. This supported adding `SANEBAR_STATUSITEM_DELAY_MS=3000` for SaneBar on the `sj` account.

**Known good launch recipe (ProdDebug):**
```
SANEBAR_ALLOW_PROD_BUNDLE=1 \
SANEBAR_STATUSITEM_DELAY_MS=3000 \
SANEBAR_DISABLE_AUTOSAVE=1 \
SANEBAR_FORCE_VISIBLE=1 \
SANEBAR_ENABLE_RECOVERY=1 \
SANEBAR_FORCE_WINDOW_NUDGE=1 \
SANEBAR_FORCE_TEXT_ICON=1 \
SANEBAR_DUMP_STATUSITEM_PREFS=1 \
SANEBAR_CLEAR_STATUSITEM_PREFS=1
```

**User confirmation:** Both items became visible (separator “/” and main icon text) in menu bar after applying the above. Clicking still not wired (expected while in debug state).
- Test launcher now passes SANEBAR_* env vars and supports `SANEBAR_BUILD_CONFIG` in [scripts/sanemaster/test_mode.rb](scripts/sanemaster/test_mode.rb).
- Added ProdDebug configuration (debug signing with production bundle ID) in [project.yml](project.yml).

### Baseline (Debug / com.sanebar.dev)
- Result: layer‑25 windows eventually appear (count = 1 at ~2s), with main/separator at x≈1037, y≈923.
- This is expected: dev bundle ID works on sj account.

### ProdDebug (com.sanebar.app)
- Result: items stuck at x=0, y=-22 (offscreen). layer‑25 windows count remains 0 until ~2s, then 1, but frames stay offscreen.
- Reproducible in these variants:
	- No overrides
	- `SANEBAR_DISABLE_AUTOSAVE=1`
	- `SANEBAR_FORCE_VISIBLE=1`
	- `SANEBAR_STATUSITEM_DELAY_MS=1000`
	- `SANEBAR_STATUSITEM_DELAY_MS=5000`
	- Combined overrides (disable autosave + force visible + delay)

### Recovery Attempt (com.sanebar.app)
- Enabled: `SANEBAR_ENABLE_RECOVERY=1`
- Behavior: detects offscreen at ~2.5s, resets items (autosave disabled, force visible). Still returns to y=-22.
- New experiment: `SANEBAR_FORCE_WINDOW_NUDGE=1` after reset.
	- Result: windows moved to y≈934, x≈1350/1390; layer‑25 count = 2; frames stayed on-screen after 1–2s.
	- Needs user confirmation: does the icon actually appear in the menu bar?

### Interpretation
- The fix that “worked” was likely the **dev bundle ID** (com.sanebar.dev) rather than autosave/force/delay.
- Production bundle ID remains corrupted on sj account: status item windows stay offscreen.

### Next Experiments Proposed
1. Recreate status items after detecting invalid frame (x==0/y<0) with a full remove/recreate cycle.
2. Test prod bundle on a fresh user (sanebartest) to confirm corruption is user‑scoped.
3. Consider “dev bundle for testing, prod bundle for release” as default workflow.
