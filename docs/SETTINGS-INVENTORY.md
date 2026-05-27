# SaneBar Settings Inventory (Current)

> Source of truth for current settings UI and labels.
> Last updated: 2026-05-27

## Sidebar Tabs
- `Control`
- `Rules`
- `Appearance`
- `Shortcuts`
- `Health`
- `License`
- `About`

Code: `UI/SettingsView.swift`

---

## Control

### Browse Icons
- `Browse Icons view`: `Icon Panel` / `Second Menu Bar`
- Second Menu Bar row presets and custom row controls
- `Left-click SaneBar icon`: toggle hidden icons or open the selected Browse Icons view

### Startup And Updates
- `Start automatically at login`
- Dock visibility control
- Automatic update check controls
- `Check Now`

### Data And Profiles
- Save, load, delete, and apply profiles
- Export/import settings JSON
- Import from Bartender / Ice
- Reset to defaults

Code: `UI/Settings/GeneralSettingsView.swift`

---

## Rules

### Hiding Behavior
- Automatic hide controls
- Rehide delay controls
- Hide on app change
- External monitor behavior

### Revealing
- Hover reveal
- Scroll reveal
- Drag/rearrange reveal
- Hide app menus during inline reveal

### Automatic Triggers
- Low battery threshold
- App launch triggers
- Schedule triggers
- Wi-Fi triggers
- Focus Mode triggers
- Script trigger path

Code: `UI/Settings/RulesSettingsView.swift`

---

## Appearance

### Menu Bar Icon
- Built-in icon styles
- Custom image

### Divider And Tint
- Divider style
- Extra dividers
- Custom Appearance
- Translucent Background
- Light/Dark tint controls
- Shadow, border, rounded corners, and radius

### Layout
- Reduce space between icons
- Item spacing
- Click area

Code: `UI/Settings/AppearanceSettingsView.swift`

---

## Shortcuts

### Global Hotkeys
- Browse Icons
- Show/Hide icons
- Show icons
- Hide icons
- Open Settings

### Automation
- AppleScript command row
- Copy command controls
- Pro automation command set

Code: `UI/Settings/ShortcutsSettingsView.swift`

---

## Health

### Status And Repair
- Accessibility status
- Menu bar geometry status
- SaneBar item status
- Save Current Layout
- Restore Last Good Layout
- Arrange Now
- Copy Report

Code: `UI/Settings/HealthSettingsView.swift`

---

## License

### Basic And Pro
- Basic/Pro status
- Unlock Pro
- Restore Purchases
- Enter License Key
- Activate
- Deactivate when licensed

Code: shared SaneUI license surface via `UI/SettingsView.swift`

---

## About

### Identity And Trust
- App icon and version
- Source/license links
- Privacy and on-device claims

### Actions
- GitHub
- Licenses
- Report a Bug
- View Issues

Code: shared SaneUI About surface via `UI/Settings/AboutSettingsView.swift`

---

## Browse Window Modes

### Icon Panel
- Modes: `Hidden`, `Visible`, `Always Hidden`, `All`
- Search, category tabs, and icon grid
- Drag reorder and drag between zones

### Second Menu Bar
- Inline row layout under the menu bar
- Search and close controls
- Row visibility follows Control presets
- Drag reorder and drag between zones

Code: `UI/SearchWindow/MenuBarSearchView.swift`, `UI/SearchWindow/SearchWindowController.swift`
