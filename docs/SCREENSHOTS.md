# SaneBar Screenshot & Asset Catalog

> **Last Updated:** 2026-01-12
> **Maintained by:** Claude Code sessions

This document catalogs all marketing screenshots and assets for SaneBar. Keep this updated when adding or modifying screenshots.

---

## Quick Reference

| Icon | Meaning |
|------|---------|
| `/` | Separator (divides hidden from visible icons) |
| `line.3.horizontal.decrease` | SaneBar icon (three decreasing lines - ALWAYS visible) |

**Key Concept:** Icons LEFT of `/` get hidden. Icons BETWEEN `/` and SaneBar stay visible. The SaneBar icon is ALWAYS visible.

---

## Branding Assets

| File | Description | Notes |
|------|-------------|-------|
| `docs/images/branding.png` | Glowing logo graphic | Marketing hero image |
| `docs/images/menubar-icon.svg` | Official SF Symbol SVG | `line.3.horizontal.decrease` - USE THIS for web demos |

### Official Icon SVG
```svg
<svg viewBox="0 0 24 24" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
    <rect x="2" y="5" width="20" height="2" rx="1"/>
    <rect x="4" y="11" width="16" height="2" rx="1"/>
    <rect x="6" y="17" width="12" height="2" rx="1"/>
</svg>
```

---

## Menu Bar States

| File | State | Description |
|------|-------|-------------|
| `docs/images/menubar-hidden.png` | Hidden | Only SaneBar icon visible, all others hidden |
| `docs/images/menubar-revealed.png` | Revealed | All icons visible |

---

## Settings Screenshots

### General Tab
| File | Section | Contents |
|------|---------|----------|
| `settings-general-top.png` | Top | Startup, Can't find an icon?, Auto-hide |
| `settings-general-bottom.png` | Middle | Gestures section |
| `settings-general-howto.png` | Bottom | "How to organize your menu bar" expanded |

**Sections in General:**
1. Startup - Launch at login, Show in Dock
2. Can't find an icon? - Reveal All / Find Icon buttons
3. When I reveal hidden icons... - Auto-hide toggle + delay
4. Gestures - Hover reveal, Scroll reveal
5. How to organize your menu bar - Instructions with `/` and icon

### Shortcuts Tab
| File | Contents |
|------|----------|
| `shortcuts.png` | Full tab - 5 keyboard shortcuts + Automation section |

**Shortcuts:**
- Find any icon (default: ⌥⌘Space)
- Show/hide icons
- Show icons
- Hide icons
- Open settings

### Advanced Tab
| File | Section | Contents |
|------|---------|----------|
| `settings-advanced-top.png` | Top | Privacy, Auto-show triggers |
| `settings-advanced-appearance.png` | Middle | Full Appearance section |
| `spacing.png` | Bottom | System Icon Spacing, Saved Settings |

**Sections in Advanced:**
1. Privacy - Touch ID / password requirement
2. Automatically show hidden icons - Battery, Apps, WiFi triggers
3. Appearance - Custom style, Liquid Glass, tint, shadow, border, corners, dividers
4. System Icon Spacing - **UNIQUE FEATURE** - tighter spacing recovers notch-hidden icons
5. App shortcuts (conditional) - Per-app hotkeys
6. Saved settings - Profile management

### About Tab
| File | Contents |
|------|----------|
| `about.png` | Full tab - Version, Privacy statement, Updates, Links, Reset |

---

## Feature Screenshots

### Find Icon Window
| File | Filter State | Description |
|------|--------------|-------------|
| `find-icon.png` | Hidden | Shows hidden icons only |
| `find-icon-visible.png` | Visible | Shows visible icons only |
| `find-icon-all.png` | All | Shows all icons |
| `find-icon-rightclick.png` | Right-click | Hotkey assignment menu |

**Find Icon Elements:**
- Filter pills: Hidden (yellow when active) / Visible / All
- Category tabs: All, Productivity, Social, Utilities, System, + Custom
- Icon grid with app icons
- Footer: count + "Right-click an icon for hotkeys"

### Touch ID / Privacy
| File | Description |
|------|-------------|
| `touchid-prompt.png` | System auth dialog when revealing hidden icons |

---

## Context Menu
| File | Description |
|------|-------------|
| `assets/menu.png` | Right-click menu: Find Icon, Settings, Check for Updates, Quit |

---

## Missing / TODO

- [ ] `find-icon-visible.png` - Visible filter state
- [ ] `find-icon-all.png` - All filter state
- [ ] `find-icon-rightclick.png` - Right-click hotkey menu
- [ ] `find-icon-search.png` - Search active state (optional)

---

## File Naming Convention

```
{feature}-{state/section}.png

Examples:
- settings-general-top.png
- settings-advanced-appearance.png
- find-icon-visible.png
- menubar-hidden.png
```

---

## Usage in Website

The website (`docs/index.html`) uses these assets for:
1. Hero demo - Interactive CSS-based demo
2. Feature screenshots - Static images
3. Icon - `menubar-icon.svg` for inline icon display

When updating screenshots, also check if `docs/index.html` references them.
