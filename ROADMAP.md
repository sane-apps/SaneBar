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
| **External Monitor Detection** | ✅ Shipped v1.0.14 | Don't hide icons on external monitors |
| **Per-Display Isolation** | 📋 Planned v1.1.0 | Active-display-only icon reveal logic |
| **Permanently Hidden Zone** | 📋 Planned v1.1.0 | Secondary "Void" spacer for icons that should never show |
| **Composite Rules (AND/OR)** | 📋 Planned | Combine triggers with logic |
| **Migration Tools** | 📋 Planned | Import from Bartender, Ice |
| Intel (x86_64) support | 📌 Backlog | No test hardware |
| Second menu bar row | ❌ Not Planned | macOS limitation |

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
| [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) | Sticky Electron icons and current workarounds |
| [FEATURE_PLAN.md](FEATURE_PLAN.md) | Implementation details, API research, phase planning |
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
| Tint + "Reduce Transparency" fix | Requires full AppKit rewrite of overlay system. Watching for simpler community solutions. |

---

## Deferred: Secondary Panel / Dropdown Bar

**Status:** Researched, deferred to v1.1+ (maybe)

**What users want:** A dropdown panel below the menu bar showing hidden icons (like Bartender/Ice).

**Technical Findings (Jan 2026):**

It's simpler than expected. Ice uses a basic `NSPanel`:

```swift
// Core panel setup - NOT complex
let panel = NSPanel(
    contentRect: .zero,
    styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel, .hudWindow],
    backing: .buffered,
    defer: false
)
panel.level = .floating              // Floats above normal windows
panel.backgroundColor = .clear
panel.isFloatingPanel = true
panel.collectionBehavior = [
    .ignoresCycle,                   // Not in Cmd-Tab
    .moveToActiveSpace,
    .fullScreenAuxiliary
]
panel.animationBehavior = .none      // Instant show/hide
```

**What's involved:**
1. Create `HiddenIconsPanel.swift` (~150 lines)
2. Populate with cached icon grid from AccessibilityService
3. Position below menu bar on show
4. Handle click-to-activate icons
5. Auto-dismiss on click outside or Escape

**Concerns:**
- Adds another UI surface to maintain
- Need to handle multi-monitor positioning
- Click handling complexity (simulating menu bar clicks)
- Edge cases: fullscreen apps, notch positioning, spaces

**Decision:** Not a "skyscraper" but still adds maintenance burden. Defer until demand increases or current approach proves insufficient for power users with 40+ icons.

**Reference:** `jordanbaird/Ice` - `MenuBarSearchPanel.swift`, `IceBarPanel.swift`

