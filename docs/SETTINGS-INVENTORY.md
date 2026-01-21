# SaneBar Settings - Complete Inventory

> **AUTHORITATIVE SOURCE** - Read this before making ANY settings UI changes.
> Last updated: 2026-01-12

---

## General Tab

### Section: Startup
| Control | Type | Code Reference |
|---------|------|----------------|
| Open SaneBar when I log in | Toggle | `LaunchAtLogin.Toggle` |
| Show in Dock | Toggle | `settings.showDockIcon` |

### Section: Can't find an icon?
| Control | Type | Code Reference |
|---------|------|----------------|
| Reveal All / Hide All | Button | State-dependent: `hidingState == .hidden` |
| Find Icon… | Button | Opens `SearchWindowController` |

### Section: When I reveal hidden icons…
| Control | Type | Code Reference |
|---------|------|----------------|
| Auto-hide after a few seconds | Toggle | `settings.autoRehide` |
| Wait X seconds | Stepper | `settings.rehideDelay` (1-10) |

### Section: Gestures
| Control | Type | Code Reference |
|---------|------|----------------|
| Reveal when I hover near the top | Toggle | `settings.showOnHover` |
| Delay | Slider | `settings.hoverDelay` (50-500ms) |
| Reveal when I scroll up in menu bar | Toggle | `settings.showOnScroll` |

### Section: How to organize your menu bar
| Control | Type | Notes |
|---------|------|-------|
| DisclosureGroup | Expandable | Contains instructions with SF Symbols |
| - ⌘+drag icons to rearrange | Label | `hand.draw` icon |
| - Icons left of / get hidden | Label | `eye.slash` icon |
| - Icons between / and ≡ stay visible | Label | `eye` icon |
| - The ≡ icon is always visible | Text | |
| - Click ≡ to show/hide | Text | |
| - Notch warning (conditional) | Label | Shows if `hasNotch == true` |

---

## Shortcuts Tab

### Section: Keyboard Shortcuts
| Control | Type | Shortcut Name |
|---------|------|---------------|
| Find any icon | KeyRecorder | `.searchMenuBar` |
| Show/hide icons | KeyRecorder | `.toggleHiddenItems` |
| Show icons | KeyRecorder | `.showHiddenItems` |
| Hide icons | KeyRecorder | `.hideItems` |
| Open settings | KeyRecorder | `.openSettings` |

**Footer:** "Find any icon works for hidden icons AND icons behind the notch. Or Option-click the SaneBar icon."

### Section: Automation
| Control | Type | Value |
|---------|------|-------|
| AppleScript command | Copyable text | `osascript -e 'tell app "SaneBar" to toggle'` |
| Copy button | Button | Copies command to clipboard |

**Footer:** "Commands: toggle, show hidden, hide items"

---

## Advanced Tab

### Section: Privacy
| Control | Type | Code Reference |
|---------|------|----------------|
| Require Touch ID or password to reveal | Toggle | `settings.requireAuthToShowHiddenIcons` |

**Footer:** "You'll need to authenticate before hidden icons appear."

### Section: Automatically show hidden icons
| Control | Type | Code Reference |
|---------|------|----------------|
| When battery is low | Toggle | `settings.showOnLowBattery` |
| When certain apps open | Toggle | `settings.showOnAppLaunch` |
| - App picker | Sheet | Shows when toggle enabled |
| On specific WiFi networks | Toggle | `settings.showOnNetworkChange` |
| - Network names | TextField | Comma-separated |
| - Add current network (SSID) | Button | Shows current SSID |
| When Focus Mode changes | Toggle | `settings.showOnFocusModeChange` |
| - Focus Mode names | List | `settings.triggerFocusModes` |
| - Add current Focus Mode | Button | Shows current active Focus |
| - Add "(Focus Off)" | Button | Trigger when Focus turns off |

### Section: Appearance
| Control | Type | Code Reference |
|---------|------|----------------|
| Custom menu bar style | Toggle | `settings.menuBarAppearance.isEnabled` (master) |
| Use Liquid Glass effect | Toggle | `settings.menuBarAppearance.useLiquidGlass` (macOS 26+) |
| Tint color | ColorPicker | `settings.menuBarAppearance.tintColor` |
| Tint strength | Stepper | `settings.menuBarAppearance.tintOpacity` (5-50%) |
| Add shadow | Toggle | `settings.menuBarAppearance.hasShadow` |
| Add border | Toggle | `settings.menuBarAppearance.hasBorder` |
| Rounded corners | Toggle | `settings.menuBarAppearance.hasRoundedCorners` |
| - Corner size | Stepper | `settings.menuBarAppearance.cornerRadius` (4-16pt) |
| Extra dividers | Stepper | `settings.spacerCount` (0-12) |
| Divider style | Segmented | `settings.spacerStyle` → Line / Dot |
| Divider width | Segmented | `settings.spacerWidth` → Compact / Normal / Wide |

**Footer (macOS 26+):** "Liquid Glass uses macOS Tahoe's new translucent material. Dividers help organize icons."
**Footer (older):** "Dividers help you visually group icons. ⌘+drag to position them."

### Section: System Icon Spacing
| Control | Type | Code Reference |
|---------|------|----------------|
| Tighter menu bar icons | Toggle | Enables spacing controls |
| Icon spacing | Stepper | `settings.menuBarSpacing` (1-10) |
| Click padding | Stepper | `settings.menuBarSelectionPadding` (1-10) |
| Reset to system defaults | Button | Clears both values |

**Footer (enabled):** "⚠️ Logout required to apply. Affects all apps system-wide."
**Footer (disabled):** "Recover icons hidden by the notch! Tighter spacing = more room before icons get cut off."

### Section: App shortcuts (conditional)
> Only shows if `settings.iconHotkeys` is not empty

| Control | Type | Notes |
|---------|------|-------|
| Per-app hotkey list | List | App name + delete button |

**Footer:** "Press Search, pick an app, and assign a key to add more."

### Section: Saved settings
| Control | Type | Notes |
|---------|------|-------|
| Profile list | List | Name, date, Load button, Delete button |
| Save current settings… | Button | Opens alert with name field |

**Footer:** "Save your setup to restore later or share between Macs."

---

## About Tab

### App Identity (centered)
| Element | Type | Notes |
|---------|------|-------|
| App icon | Image | 72x72, `NSApp.applicationIconImage` |
| SaneBar | Title | `.font(.title)` |
| Version X.X.X | Text | From bundle, `.font(.body)` |
| Made by Mr. Sane, USA | Text | `.font(.body)`, tertiary color |

### Updates
| Control | Type | Notes |
|---------|------|-------|
| Check for Updates | Button | `.buttonStyle(.bordered)` |
| Check automatically | Checkbox | `settings.checkForUpdatesAutomatically` |

### Trust Info (non-clickable labels)
| Label | Icon | Notes |
|-------|------|-------|
| 100% Local | `laptopcomputer` | Secondary color, not a button |
| No Analytics | `eye.slash` | Secondary color, not a button |
| Open Source | `lock.open` | Secondary color, not a button |

### Links Row
| Control | Type | Destination |
|---------|------|-------------|
| GitHub | Link button | `https://github.com/sane-apps/SaneBar` |
| Licenses | Button | Opens licenses sheet |
| Support | Button | Opens support sheet (heart icon, crypto addresses) |

### Footer
| Control | Type | Notes |
|---------|------|-------|
| Reset to Defaults | Button | Destructive, plain style, tertiary color |

---

## Image Assets Reference

| Asset | File | Purpose |
|-------|------|---------|
| **Menu Bar Icon** | `menubar-icon.svg` | The ≡ in actual menu bar (monochrome, no background) |
| **App/Dock Icon** | `branding.png` | Dock, marketing, website (blue glowing lines on dark bg) |

**DO NOT CONFUSE THESE** - See Memory entity `SaneBar-Icon-Assets` for details.

---

## Screenshots Needed

| Screenshot | File | Shows |
|------------|------|-------|
| General tab (top) | `settings-general-top.png` | Startup, Can't find icon |
| General tab (bottom) | `settings-general-bottom.png` | Gestures, How to organize |
| General tab (howto expanded) | `settings-general-howto.png` | DisclosureGroup open |
| Shortcuts tab | `shortcuts.png` | All keyboard shortcuts |
| Advanced tab (top) | `settings-advanced-top.png` | Privacy, Auto-show |
| Advanced tab (appearance) | `settings-advanced-appearance.png` | Full appearance section |
| About tab | `settings-about.png` | Full about section |
| Find Icon (hidden) | `find-icon.png` | Hidden tab selected |
| Find Icon (visible) | `find-icon-visible.png` | **NEEDED** |
| Find Icon (all) | `find-icon-all.png` | **NEEDED** |
| Menu bar hidden | `menubar-hidden.png` | Clean state |
| Menu bar revealed | `menubar-revealed.png` | All icons visible |
