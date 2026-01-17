# Debugging Menu Bar Interactions (Click + Order)

## Intended Behavior (Product / UX)
- Left-click on the main SaneBar icon toggles hide/show.
- Right-click opens the context menu (Find Icon, Settings, Updates, Quit).
- The separator ("/") is **visual-only** and should not be interactive.

## Evidence in Project Docs
- Right-click menu is the intended entry point for Find Icon and Settings.
  - See [docs/SCREENSHOTS.md](docs/SCREENSHOTS.md) (context menu screenshot entry).
  - See [marketing/feature-requests.md](marketing/feature-requests.md) (right-click menu request & implementation).

## Competitor Behavior (Reference)
- **Dozer**: Left-click toggles hide/show; right-click opens settings.
- **Hidden Bar**: Single arrow icon; click toggles hide/show; no left-click menu.
- **Ice**: Multiple reveal triggers (click empty menu bar area, hover, scroll). Menu actions are separate from reveal action.
- **Bartender** (closed source): Left-click reveals; right-click opens preferences/context.

## Apple API Notes
- `NSStatusItem.menu` **auto-opens** on click. If set, left-click will show the menu and bypass custom action handling.
- For custom left/right behavior:
  - Keep `NSStatusItem.menu` == nil.
  - Set `NSStatusBarButton.target` / `action`.
  - Use `sendAction(on:)` to listen for right-click, then call `popUpMenu()` manually.

Relevant docs:
- https://developer.apple.com/documentation/appkit/nsstatusitem
- https://developer.apple.com/documentation/appkit/nsstatusbarbutton
- https://developer.apple.com/documentation/appkit/nsmenu

## Regression Pattern (Observed)
- The hide-main-icon + “anchor menu to separator” changes can cause the **menu to attach to the wrong status item**.
- When swap/recovery logic reassigns status items, old menu references may persist and left-click opens the menu.
- Any path that sets `statusItem.menu = statusMenu` reintroduces left-click menu behavior.

## Hard Rule for Stability
1. **Never attach** a menu to any `NSStatusItem` (main or separator).
2. Always use right-click (`statusItemClicked`) to call `popUpMenu(statusMenu)`.
3. Always clear both:
   - `statusItem.menu`
   - `statusItem.button?.menu`
   after swaps/recovery and during setup.

## Positioning + Warning Regression Fix (2026-01)
Symptoms observed:
- False “Separator Misplaced” warnings while behavior was correct.
- Both icons launching far to the left of existing items instead of near Control Center.

Root causes:
- Validation used **separator right edge**, which becomes huge in hidden state and trips warnings.
- Missing/left-biased autosave positions caused default placement on the far left.

Fixes applied:
- **Validate using separator left edge** only (width is ignored for correctness).
- **Seed default positions** near the right edge on first run or when cached values are clearly far-left.

Regression tests:
- Menu-bar position edge cases updated in [Tests/MenuBarManagerTests.swift](Tests/MenuBarManagerTests.swift).

## Files to Audit First
- [Core/MenuBarManager.swift](Core/MenuBarManager.swift)
- [Core/MenuBarManager+Actions.swift](Core/MenuBarManager+Actions.swift)
- [Core/MenuBarManager+Monitoring.swift](Core/MenuBarManager+Monitoring.swift)
- [Core/Controllers/StatusBarController.swift](Core/Controllers/StatusBarController.swift)

## Quick Runtime Verification
- Log whether `mainStatusItem.menu` or `separatorItem.menu` is non-nil at click time.
- If `menuWillOpen` triggers on a left click, cancel tracking and toggle hide/show instead.

---

## NSStatusItem X-Coordinate System (CRITICAL)

**This caused a multi-day debugging session. Do not forget.**

### The Rule
```
HIGH X value (1200+) = RIGHT side of menu bar (near Control Center, clock)
LOW X value (0-200)  = LEFT side of menu bar (near Apple menu)
```

### Why This Matters
- macOS stores status item positions in UserDefaults as X-coordinates
- Key format: `NSStatusItem Preferred Position <autosaveName>`
- These values persist across app launches and are restored automatically
- **Corrupted/wrong values cause icons to appear offscreen or far-left**

### The Bug Pattern (2026-01-16)
1. Old code (`ensureDefaultPositions()`) wrote x=100, x=120 thinking "low = safe default"
2. These values placed icons on the FAR LEFT, not the right
3. macOS dutifully restored these wrong positions on every launch
4. Icons appeared offscreen or in wrong location
5. Misdiagnosed as "WindowServer corruption" when it was just bad preference data

### The Fix Pattern
```swift
// In seedDefaultPositionsIfNeeded():
let mainTooLeft = (mainNumber?.doubleValue ?? 9999) < 200  // Detect bad values
let base = max(1200, rightEdge - 160)                      // Seed correct values
```

### Debugging Checklist (Before Assuming "macOS Bug")
1. **Dump current position values**: `SANEBAR_DUMP_STATUSITEM_PREFS=1`
2. **Check if values are suspiciously low** (< 200 = left side)
3. **Clear and reseed**: `SANEBAR_CLEAR_STATUSITEM_PREFS=1`
4. **Verify after 1-2 seconds** - macOS needs time to settle positions

### Environment Flags for Position Debugging
| Flag | Purpose |
|------|---------|
| `SANEBAR_DUMP_STATUSITEM_PREFS=1` | Log current stored positions |
| `SANEBAR_CLEAR_STATUSITEM_PREFS=1` | Clear stored positions |
| `SANEBAR_DISABLE_AUTOSAVE=1` | Don't use autosaveName (fresh positions) |
| `SANEBAR_STATUSITEM_DELAY_MS=3000` | Delay item creation |

---

## Lessons Learned (Anti-Patterns to Avoid)

### 1. Don't Misdiagnose Data Problems as System Corruption
**Bad**: "WindowServer has deep corruption that survives Safe Boot"
**Good**: "What values are actually being restored? Are they correct?"

When status items appear in wrong positions:
- First check: What X-coordinates are stored in preferences?
- Second check: Are those values sensible (1000+ for right side)?
- Third check: Is the app writing bad values somewhere?

### 2. Don't Build Workarounds Before Understanding Root Cause
**Bad**: Recovery/nudge mechanisms to move windows after creation
**Good**: Fix the source data so windows are created in correct position

The nudge/recovery code added complexity. The actual fix was 30 lines in `seedDefaultPositionsIfNeeded()`.

### 3. Validate Using the Right Edge (Literally)
**Bad**: Check separator's right edge (width=10000 when hidden → false positives)
**Good**: Check separator's LEFT edge only (stable regardless of hidden state)

### 4. Test with Fresh Preferences
Before concluding "macOS is broken", test with:
```bash
defaults delete com.sanebar.app
# or
SANEBAR_CLEAR_STATUSITEM_PREFS=1 SANEBAR_DISABLE_AUTOSAVE=1 ./run_app
```

If it works with fresh prefs, the bug is in stored data, not macOS.
