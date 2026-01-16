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
