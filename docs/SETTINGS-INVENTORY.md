# SaneBar Settings Inventory (Current)

> Source of truth for current settings UI and labels.
> Last updated: 2026-02-25

## Sidebar Tabs
- `General`
- `Rules`
- `Appearance`
- `Shortcuts`
- `Help`

Code: `UI/SettingsView.swift`

---

## General

### Browse Icons
- `Browse Icons view`: `Icon Panel` / `Second Menu Bar`
- `Visible rows` presets (Pro + Second Menu Bar only):
  - `Minimal` (Hidden)
  - `Balanced` (Hidden + Visible)
  - `Power` (Hidden + Visible + Always Hidden)
- `Customize rows` (Power preset only):
  - `Include visible icons`
  - `Include always-hidden icons`
- `Left-click SaneBar icon`:
  - `Toggle Hidden`
  - `Open Icon Panel` or `Open Second Menu Bar` (dynamic label)
- Tip text: right-click opens app menu

### Security
- `Touch ID to unlock hidden icons` (Pro)

### Startup
- `Start automatically at login`
- `Show app in Dock`

### Software Updates
- `Check for updates automatically`
- `Check Now`

### Saved Profiles (Pro)
- Save current settings as profile
- Load/delete saved profiles

### Data (Pro)
- Export/import settings JSON
- Import from Bartender / Ice

### Pro License
- Status: `Free` or `Pro`
- Free: `Unlock Pro`, `Enter Key`
- Pro: licensed email, `Deactivate License`

### Maintenance
- `Reset to Defaults…`

Code: `UI/Settings/GeneralSettingsView.swift`

---

## Rules

### Hiding Behavior
- `Hide icons automatically`
- Pro customizations:
  - `Wait before hiding`
  - `Wait after Browse Icons`
  - `Hide when app changes`
  - `Always show on external monitors`

### Revealing
- `Show when mouse hovers top edge`
- `Show when scrolling on menu bar`
- Pro: gesture behavior (`Show only` / `Show and Hide`)
- `Show when rearranging icons`

### Automatic Triggers (Pro)
- Low battery threshold
- Specific app launch trigger list
- Schedule (days + start/end)
- Wi-Fi trigger list
- Focus Mode trigger list
- Script trigger path

Code: `UI/Settings/RulesSettingsView.swift`

---

## Appearance

### Menu Bar Icon
- Built-in icon styles + custom image (Pro)

### Divider Style
- Primary divider style
- Pro: extra dividers + extra divider style

### Menu Bar Style (Pro)
- `Custom Appearance`
- `Translucent Background` (when supported)
- Light/Dark tint + intensity
- Shadow / Border / Rounded corners
- Corner radius control

### Menu Bar Layout (Pro)
- `Reduce space between icons`
- Item spacing + click area
- logout reminder

Code: `UI/Settings/AppearanceSettingsView.swift`

---

## Shortcuts

### Global Hotkeys
- Browse Icons
- Show/Hide icons
- Show icons (Pro)
- Hide icons (Pro)
- Open Settings (Pro)

### Automation
- AppleScript command row + copy
- Pro automation command set

Code: `UI/Settings/ShortcutsSettingsView.swift`

---

## Help

### Identity + Trust
- App icon, version
- `Made with ❤️ in 🇺🇸 · 100% On-Device · No Analytics`

### Actions
- GitHub
- Licenses
- Donate
- Report a Bug
- View Issues
- Questions

### Popovers
- Third-party license text
- Donation/support panel
- Feedback form

Code: `UI/Settings/AboutSettingsView.swift`

---

## Browse Window Modes

### Icon Panel
- Modes: `Hidden`, `Visible`, `Always Hidden` (if enabled), `All`
- Search + category tabs + icon grid
- Drag reorder and drag between zones

### Second Menu Bar
- Inline row layout under menu bar
- Search + close button
- Row visibility depends on General preset/toggles
- Drag reorder and drag between zones

Code: `UI/SearchWindow/MenuBarSearchView.swift`, `UI/SearchWindow/SearchWindowController.swift`
