# SaneBar Roadmap

> High-level feature status. For details, see linked documents.

---

## Feature Status Overview

| Feature | Status | Details |
|---------|--------|---------|
| Hide/Show menu bar icons | ✅ Shipped v1.0.0 | Core functionality |
| AppleScript support | ✅ Shipped v1.0.0 | `tell app "SaneBar" to toggle` |
| Per-icon keyboard shortcuts | ✅ Shipped v1.0.0 | Settings → Shortcuts |
| Show on hover | ✅ Shipped v1.0.0 | Settings → Rules → Revealing |
| Show on scroll (up/down) | ✅ Shipped v1.0.9 | Added "Both Ways" scroll support |
| **"Click to Show"** | ✅ Shipped v1.0.9 | New gesture trigger |
| **Find Icon Overhaul** | ✅ Shipped v1.0.9 | Instant loading + Search Auto-focus |
| Menu bar spacing control | ✅ Shipped v1.0.3 | Settings → Advanced |
| Visual zones (dividers) | ✅ Shipped v1.0.3 | Settings → Advanced |
| Find Icon search | ✅ Shipped v1.0.3 | Option-click or ⌘⇧Space |
| Sparkle auto-updates | ✅ Shipped v1.0.6 | Automatic update checks |
| **Automatic Triggers** | ✅ Shipped v1.0.6 | Battery, App Launch, Wi-Fi network |
| **Focus Mode Binding** | ✅ Shipped v1.0.7 | Show icons when Focus Mode changes |
| **External Monitor Detection** | ✅ Shipped v1.0.15 | Keep icons visible on external monitors |
| **Directional Scroll** | ✅ Shipped v1.0.15 | Scroll up to show, scroll down to hide |
| **Gesture Toggle** | ✅ Shipped v1.0.15 | Click/scroll toggles visibility |
| **Hide on App Change** | ✅ Shipped v1.0.15 | Auto-hide when switching apps |
| **Show When Rearranging** | ✅ Shipped v1.0.15 | Reveal all icons during ⌘+drag |
| **Ice Migration Tool** | 📋 Planned v1.1.0 | Import from Ice (open source, easy) |
| **Bartender Migration Tool** | ✅ Shipped | Import from Bartender (Settings → General → Import Bartender) |
| **Permanently Hidden Zone** | 🧪 Beta (Experimental) | Optional always-hidden section (Settings → Experimental) + per-icon pinning in Find Icon |
| **Reveal All Toggle** | 📋 Planned | Reveal All ↔ Hide All two-way toggle + override auto-hide |
| **Composite Rules (AND/OR)** | 📋 Planned | Combine triggers with logic |
| **Icon Groups** | ✅ Shipped | Categorize icons, filter in Find Icon (custom groups + drag-and-drop) |
| **Reduce Transparency Support** | ✅ Shipped | Tint renders correctly when Reduce Transparency is enabled |
| Intel (x86_64) support | ❌ Not Planned | No test hardware, shrinking user base |
| Second menu bar row | ❌ Impossible | macOS has one menu bar row - we can't add another |

### Automatic Triggers

SaneBar already supports automatic show/hide based on:

| Trigger | Description | Location |
|---------|-------------|----------|
| 🔋 Low Battery | Show icons when battery is low | Settings → Rules |
| 📱 App Launch | Show when specific apps open | Settings → Rules |
| 📶 Wi-Fi Network | Show when connecting to specific networks | Settings → Rules |
| 🎯 Focus Mode | Show when macOS Focus Mode changes | Settings → Rules |
| 🖱️ Hover | Show when mouse hovers menu bar | Settings → Rules |
| ⬆️ Scroll | Show when scrolling on menu bar | Settings → Rules |
| 🖱️ Click | Show when clicking on menu bar | Settings → Rules |

---

## Detailed Documentation

| Document | Purpose |
|----------|---------|
| [GitHub Issues](https://github.com/sane-apps/SaneBar/issues) | Implementation details and tracking |
| [marketing/feature-requests.md](marketing/feature-requests.md) | User requests, priority assessment, testimonials |
| [CHANGELOG.md](CHANGELOG.md) | Version history |

---

## How to Request Features

1. **GitHub Issue**: https://github.com/sane-apps/SaneBar/issues/new
2. **Reddit**: r/macapps or r/MacOS threads
3. **Include**: What you want, why you need it, how many others might benefit

---

## Decision Criteria

Features are evaluated on:
1. **User impact**: How many people does this help?
2. **Alignment**: Does it fit SaneBar's "clean menu bar" vision?
3. **Complexity**: Engineering effort vs. benefit
4. **Risk**: Could it break existing functionality?

---

## Not Planned (with reasons)

| Request | Reason |
|---------|--------|
| Intel/Hackintosh support | No test hardware, shrinking user base |
| "Reveal to front" positioning | Edge case for notch overlay apps, high complexity |
| Icon click-through | High complexity, cursor hijacking risk |

---

## Completed: Second Menu Bar

**Status:** Shipped in v1.0.19 (Feb 2026)

**What users wanted:** A second bar below the menu bar showing hidden icons (like Ice's "Ice Bar").

**Implementation:** Reused `SearchWindowController` with a mode switch. `NSPanel` with `.nonactivatingPanel` + `.statusBar` level, positioned flush below menu bar. Right-click context menus for zone management.

- **Enable:** Settings → General → Hiding → "Show hidden icons in second menu bar"
- **Behavior:** When enabled, clicking the SaneBar icon shows the second menu bar AND expands the real delimiter (so Cmd+drag still works)
- **File:** `UI/SearchWindow/SecondMenuBarView.swift`, `SearchWindowController.swift` (mode-aware)
