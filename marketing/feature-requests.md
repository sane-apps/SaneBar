# SaneBar Feature Requests

> **Navigation**
> | Session | How to Work | Releases | Testimonials |
> |---------|-------------|----------|--------------|
> | [../SESSION_HANDOFF.md](../SESSION_HANDOFF.md) | [../DEVELOPMENT.md](../DEVELOPMENT.md) | [../CHANGELOG.md](../CHANGELOG.md) | [testimonials.md](testimonials.md) |

Tracking user-requested features from Reddit, GitHub, and support channels.
Priority based on: frequency of requests, alignment with vision, implementation effort.

---

## High Demand Features

### 1. Menu Bar Spacing Control
**Priority: HIGH** | **Requests: 2+** | **Status: ✅ COMPLETED**

| Requester | Request | Notes |
|-----------|---------|-------|
| u/MaxGaav | "spacing possibilities?" | Top 1% commenter badge |
| u/Mstormer (MOD) | "compact spacing is the main reason I need a menubar manager" | r/macapps moderator |

**Analysis:**
- High ROI if we keep it purely visual and user-controlled via ⌘-dragging in the menu bar (no auto-reordering)
- Sindre Sorhus has a separate app "Menu Bar Spacing" for this
- Users want "all things in one app" (per MaxGaav)
- Could differentiate SaneBar from Ice/HiddenBar

**Implementation Notes:**
- Would require injecting spacing between AXUIElements
- May need to use different technique than current approach
- Reference: https://sindresorhus.com/menu-bar-spacing

**Implemented (Jan 11, 2026):**
- Toggle in Advanced > System Icon Spacing ("Tighter menu bar icons")
- Uses `NSStatusItemSpacing` + `NSStatusItemSelectionPadding` defaults (1-10 range)
- Defaults to 4,4 - helps recover icons hidden by notch on MacBook Pro
- Requires logout/login for changes to take effect

---

### 2. Find Icon Speed Improvement
**Priority: HIGH** | **Requests: 2** | **Status: ✅ FIXED v1.0.12**

| Requester | Request | Notes |
|-----------|---------|-------|
| u/Elegant_Mobile4311 | "Find Icon function is slow to respond..." | Primary use case for them |
| bleducnx (Discord) | "searching always takes more than 6 seconds!" | MBA M2, 19 hidden modules |

**Fixed (v1.0.12):**
- Instant tab switching (no reload on tab change)
- Lazy thumbnail loading with caching
- Fixed "beach ball" spinning cursor for users with 50+ apps
- Cache-first open + background refresh (from v1.0.3)

---

### 3. Find Icon in Right-Click Menu
**Priority: MEDIUM** | **Requests: 1** | **Status: Implemented**

| Requester | Request | Notes |
|-----------|---------|-------|
| u/a_tsygankov | "It would be great if it was available in the menu that appears when you right-click" | Also gave testimonial |

**Analysis:**
- Currently only available via Option-click or hotkey
- Right-click menu is discoverable without documentation
- Low effort, high usability improvement

**Implementation:**
- Add "Find Icon..." item to the right-click menu
- Keep the menu compact (removed redundant "Toggle Hidden Items")

---

### 4. Custom Dividers (Visual Zones)
**Priority: MEDIUM** | **Requests: 1** | **Status: Implemented**

| Requester | Request | Notes |
|-----------|---------|-------|
| u/MaxGaav | "other dividers like vertical lines, dots and spaces?" | Top 1% commenter badge |

**Analysis:**
- High ROI because it’s purely visual and user-controlled via ⌘-dragging in the menu bar (no auto-reordering)

**Implemented Scope:**
- Increase divider limit (0–3 → 0–12)
- Global divider **style**: line (—), dot (•)
- Global divider **width** presets: Compact / Normal / Wide

---

### 5. Secondary Menu Bar Row
**Priority: LOW** | **Requests: 2** | **Status: Not Planned**

| Requester | Request | Notes |
|-----------|---------|-------|
| u/MaxGaav | "a 2nd menubar below the menubar for hidden icons" | Alternative to full-width expansion |
| bleducnx (Discord) | "secondary bar system used by Bartender, Barbee, Ice... is more efficient" | Power user with 40-50 icons |

**Analysis:**
- Significant UI/architecture change
- Not aligned with current "clean menu bar" vision
- Would require substantial work for unclear benefit
- Mark as "considering" but not prioritized

---

### 6. Icon Groups / Organization
**Priority: MEDIUM** | **Requests: 1** | **Status: ✅ Already Implemented**

| Requester | Request | Notes |
|-----------|---------|-------|
| s/macenerd (Reddit) | "I'd love to have groups. I have so many icons I'll divide them up into groups to help organize them" | Jan 11, 2026 |

**Analysis:**
- Would allow users to categorize icons (e.g., "Social", "Dev Tools", "System")
- Could integrate with Find Icon for filtering by group
- Medium complexity - need UI for group management

**Status (Shipped):**
- Create custom groups in Find Icon (tabs row)
- Drag and drop icons onto a group to assign
- Filter icons by group

---

### 7. Third-Party Overlay Detection (Virtual Notch)
**Priority: LOW** | **Requests: 1** | **Status: Not Planned (Edge Case)**

| Requester | Request | Notes |
|-----------|---------|-------|
| bleducnx (Reddit) | "Atoll Dynamic Island... Alter AI assistant... aren't detected by SaneBar" | Uses 32" monitor with center overlays |

**Analysis:**
- User has apps like Atoll (Dynamic Island clone) and Alter AI (15cm overlay) in top-center
- When revealing icons via Find Icon, they appear in original position - potentially behind the overlay
- Very niche use case: intersection of dynamic island apps + AI overlays + many menu bar items + SaneBar

**User's Proposed Solutions:**
1. **Secondary menu bar** - Not feasible (macOS doesn't support multiple NSStatusItem bars)
2. **"Reveal to Front"** - When showing via Find Icon, move icon to far-right (near Control Center) where it's always accessible

**Cost-Benefit Assessment:**
- NSStatusItem positioning is macOS-controlled; we'd be fighting the system
- Risk of introducing positioning bugs for 99% of users to serve 0.1%
- Recommended workaround: temporarily quit/minimize overlay apps when accessing hidden icons

**Decision:** Not pursuing unless more users report similar conflicts

---

### 8. Visual Icon Grid (No Search Required)
**Priority: MEDIUM** | **Requests: 1** | **Status: ✅ Already Implemented**

| Requester | Request | Notes |
|-----------|---------|-------|
| bleducnx (Discord) | "I have 19 modules... I don't know their names, but I do know their icons. The search field is completely useless." | Wants instant visual grid |

**Status (Verified Jan 11, 2026):**
- Default mode is "All" - shows ALL icons immediately
- Search field is HIDDEN by default (`isSearchVisible = false`)
- User sees icon grid on open, no typing required
- Search is optional filter, toggled via magnifying glass button
- **User likely didn't notice because:** slow cache load made it seem broken

---

### 9. Find Icon Move Improvements
**Priority: MEDIUM** | **Requests: 1** | **Status: Partially Done**

| Requester | Request | Notes |
|-----------|---------|-------|
| Internal | "Move icon is slow, should support bulk moves" | Jan 11, 2026 |

**Implemented (Jan 11, 2026):**
- ✅ Cursor position restored after move (no more "mouse hijacking")
- ✅ Hidden/Visible/All tabs work correctly (separator origin fix)

**Still Needed:**
- **Speed optimization**: Current delays ~100ms (20+30+50ms safety margins). Could potentially reduce but risky without extensive testing.
- **Bulk moves**: Multi-select icons and "Move All to Hidden/Visible" button. Requires UI changes (checkboxes or shift-click), loop logic, single cursor restore at end.

**Complexity Assessment:**
- Speed optimization: MEDIUM (risky to reduce timing without testing)
- Bulk moves: HIGH (UI changes + loop logic + state management)

---

### 10. Auto-Disable on External Monitors
**Priority: MEDIUM** | **Requests: 1** | **Status: ✅ IMPLEMENTED v1.0.15**

| Requester | Request | Notes |
|-----------|---------|-------|
| u/genius1soum | "I don't want SaneBar to do its job on my external monitor..." | Reddit, Jan 23 2026 |

**Implemented (Jan 23, 2026):**
- Settings → Rules → "Keep visible on external monitors"
- Uses `CGDisplayIsBuiltin()` to detect external displays
- Icons stay visible when on external monitor (plenty of space)

---

### 11. Scroll/Click to Toggle (Hide When Visible)
**Priority: MEDIUM** | **Requests: 1** | **Status: ✅ IMPLEMENTED**

| Requester | Request | Notes |
|-----------|---------|-------|
| Rembrandt74 / Paolo (GitHub #30) | "Scroll does nothing when icons are visible" | Wants scroll to hide, not just reveal |

**User's Pain Point:**
Scroll/click gestures only REVEAL hidden icons. Once visible, scrolling again does nothing. User expected toggle behavior (scroll to show, scroll again to hide).

**Implemented (Jan 23, 2026):**
- New setting: `gestureToggles` (default: false, preserves existing behavior)
- When enabled, scroll/click in menu bar toggles visibility
- Hover remains reveal-only (toggling on hover would be annoying)
- Located in Settings → Rules → Revealing → "Also hide when visible"

**Related Request (NOW IMPLEMENTED):**
- Suspend auto-hide during ⌘+drag rearranging → See Ice-Compatible Features below

---

### 12. Ice-Compatible Features (Migration from Ice)
**Priority: HIGH** | **Requests: Multiple** | **Status: ✅ IMPLEMENTED**

| Feature | Ice Setting | SaneBar Setting | Notes |
|---------|-------------|-----------------|-------|
| Directional Scroll | up=show, down=hide | `useDirectionalScroll` | Only when toggle mode disabled |
| Show on User Drag | `showAllSectionsOnUserDrag` | `showOnUserDrag` | Reveal all icons during ⌘+drag |
| Rehide on App Change | `focusedApp` strategy | `rehideOnAppChange` | Auto-hide when switching apps |

**Implemented (Jan 23, 2026):**
- **Directional Scroll** (`useDirectionalScroll`): When enabled, scroll up shows icons, scroll down hides them (Ice-style). Mutually exclusive with gesture toggle mode.
- **Show When Rearranging** (`showOnUserDrag`): When user ⌘+drags to rearrange menu bar icons, all hidden icons are revealed until drag ends. Enabled by default.
- **Hide When App Changes** (`rehideOnAppChange`): Auto-hides icons when you switch to a different app (Ice's "focusedApp" rehide strategy).

**UI Location:** Settings → Rules
- "Scroll direction matters" (under Revealing, conditional)
- "Show when rearranging icons" (under Revealing)
- "Hide when app changes" (under Hiding Behavior)

---

## Bug Reports / UX Issues

### 1. Menu Bar Tint Not Working on M4 Macs
**Priority: HIGH** | **Status: Open (GitHub #20)**

| Requester | Environment | Notes |
|-----------|-------------|-------|
| Reddit user | M4 Air, dark mode | Tint flashes on boot only |
| MaxGave (GitHub) | M4, Sequoia, normal mode | No tint at all, toggle doesn't help |
| u/digger27410 (Reddit) | M4 Air, Tahoe 26.2, dark mode, Reduce Transparency ON | Height changes but color doesn't; Ice works |

**Key Finding (Jan 16, 2026):**
- Toggle causes bar HEIGHT to increase slightly, but color doesn't change
- Ice's tint works on same hardware → different implementation technique needed
- Possible causes: Reduce Transparency setting, M4 GPU/display stack incompatibility

**Action:** Investigate how Ice implements tint overlay vs our approach.

---

### 2. Global Shortcut Conflicts
**Priority: HIGH** | **Status: Fixed (v1.0.3)**

| Requester | Issue | Notes |
|-----------|-------|-------|
| u/a_tsygankov | "cmd + , for 'Open settings' overrides all other apps" | Should disable by default |

**Fixed:**
- Changed Find Icon shortcut from `⌘Space` to `⌘⇧Space` to avoid Spotlight conflict
- Settings shortcut `⌘,` is app-specific (only works when SaneBar menu is open)

---

### 2. Website Documentation Out of Date
**Priority: HIGH** | **Status: Needs Update**

| Requester | Issue | Notes |
|-----------|-------|-------|
| maddada_ (Discord) | "May I know how it works please? I can't find anything about this on the website" | Asking about notch feature |

**Action Required:**
- Update sanebar.com with current feature documentation
- Add notch-awareness explanation
- Add Find Icon documentation
- Add Visual Zones documentation

---

### 3. Auto-Hide Window Stacking Issue
**Priority: MEDIUM** | **Status: Needs Investigation**

| Requester | Issue | Notes |
|-----------|-------|-------|
| u/JustABro_2321 | "when hiddenbar collapses, it buries the menubar app's settings window to the back" | Comparing to HiddenBar bug |

**Investigation:**
- Does SaneBar have this same issue?
- If auto-hide triggers while interacting with a menu bar app popup, does it bury the window?
- May need "smart" detection of active interactions

---

## Feature Request Sources

| Source | Link | Date Checked |
|--------|------|--------------|
| Reddit r/macapps | Launch thread | Jan 2026 |
| GitHub Issues | (check weekly) | - |

---

## Decision Log

| Date | Feature | Decision | Rationale |
|------|---------|----------|-----------|
| Jan 2026 | Menu Bar Spacing | ✅ Implemented | High demand, notch-friendly defaults recover hidden icons |
| Jan 2026 | Visual Zones (Dividers) | Implemented | Low effort, high reliability, high user ROI |
| Jan 2026 | Secondary Menu Bar | Deprioritized | Architectural complexity, unclear demand |

---

## Next Steps

1. **Immediate (v1.0.x)**
   - [x] Fix shortcut conflict (changed to `⌘⇧Space`)
   - [x] Add Find Icon to right-click menu
   - [x] Improve Find Icon performance (cache pre-warming)
   - [ ] Further optimize Find Icon (still slow for some users)
   - [ ] Update website documentation

2. **Short Term (v1.1)**
   - [x] Spacing control (System Icon Spacing toggle)
   - [ ] Research auto-hide interaction detection
   - [x] Implement visual zones (custom dividers/spacers)
   - [ ] Icon Groups feature
   - [ ] Visual icon grid (instant display without search)

3. **Evaluate Later**
   - Secondary menu bar row
   - Third-party overlay detection (Atoll, etc.)
   - Reduce Transparency compatibility for tint (see Issue #20)

---

## Testimonials (Jan 2026)

| User | Quote | Source |
|------|-------|--------|
| ujc-cjw | "Finally, a replacement app has arrived—I'm so glad! It's been working perfectly so far." | Reddit r/macapps |
| bleducnx | "The product is very stable and offers a wide range of options." | Discord |
| u/a_tsygankov | "I really like that I can adjust SaneBar's behavior with AppleScript" | Reddit r/macapps |

---

## Technical Investigations

### Reduce Transparency Compatibility (Issue #20)
**Priority: LOW** | **Status: Deferred**

**Problem:** Menu bar tint doesn't work when macOS "Reduce Transparency" is enabled (System Settings → Accessibility → Display).

**Reports:** M4 MacBook Air users report tint flashes on boot but doesn't persist. Confirmed working on M4 with Reduce Transparency OFF.

**Research (Jan 17, 2026):**
- SaneBar uses SwiftUI `Rectangle().fill(Color.opacity())` - relies on compositor blending
- Ice uses AppKit `NSView.draw()` with `NSColor.setFill(); rect.fill()` - Core Graphics direct drawing
- Ice also uses different window styleMask: `.fullSizeContentView, .nonactivatingPanel`
- Both approaches use alpha values, so unclear why Ice would work if we don't

**Fix Options:**
1. Quick test: Add `.fullSizeContentView, .nonactivatingPanel` to window styleMask
2. Full port: Rewrite `MenuBarOverlayView` as `NSView` subclass with `draw(_:)` override (2-4 hours, risk of new bugs)

**Decision:** Defer until we confirm users actually need Reduce Transparency ON. Not worth the regression risk for an edge case.

---

## Tools Mentioned by Users

| Tool | Purpose | Notes |
|------|---------|-------|
| TighterMenubar | Menu bar spacing | Free, https://github.com/vanja-ivancevic/TighterMenubar |
| Menu Bar Spacing | Menu bar spacing | By Sindre Sorhus |
| Atoll | Dynamic Island clone | Third-party overlay that users want detected |
| Alter AI | AI assistant | Sits in top-center, users want detected |

---

## Platform Support Requests

### Intel (x86_64) Support
**Priority: LOW** | **Requests: 1** | **Status: Not Planned (No Test Hardware)**

| Requester | Request | Notes |
|-----------|---------|-------|
| Comfortable-Arm4656 (Reddit) | "bad CPU type in executable" | Hackintosh user, Jan 2026 |

**Error:**
```
zsh: bad CPU type in executable: sanebar.app/Contents/macOS/sanebar
```

**Analysis:**
- SaneBar is ARM64-only (Apple Silicon)
- User has Intel x86_64 CPU (Hackintosh)
- Would require Universal Binary build (arm64 + x86_64)

**Cost-Benefit Assessment:**
- **Technical difficulty:** Low (one-line config change: `arch: [arm64, x86_64]`)
- **Testing difficulty:** High (no Intel hardware available)
- **Maintenance burden:** Medium-High (ongoing dual-architecture testing)
- **User base:** Shrinking (Intel Macs phased out since 2020, Hackintosh is unsupported niche)

**Decision:** Not pursuing without Intel test hardware. Community contribution welcome - user could build locally with Claude Code and submit PR if successful.

**Response sent to user:** Invited them to try building with Claude Code on their machine and submit changes if it works
