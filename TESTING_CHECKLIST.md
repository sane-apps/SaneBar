# SaneBar User Testing Checklist

Manual testing checklist for SaneBar app verification.

## Initial Launch

- [ ] App launches without crashing
- [ ] Menu bar icon appears (SaneBar icon in menu bar)
- [ ] Clicking icon opens Settings window

## Permission Flow

- [ ] First launch shows accessibility permission request
- [ ] "Open System Settings" button opens correct pane
- [ ] After granting permission, app detects it automatically
- [ ] Status updates from "Not Granted" to "Granted"

## Menu Bar Scanning

- [ ] Click "Refresh" scans menu bar items
- [ ] All visible third-party status items are discovered
- [ ] Item icons are displayed correctly
- [ ] Item names are readable (app name or bundle ID)
- [ ] Success message appears briefly after scan

## Item Management (Items Tab)

- [ ] Items are grouped by section (Always Visible, Hidden, Collapsed)
- [ ] Search filters items by name
- [ ] Search filters items by bundle identifier
- [ ] Clear search button works
- [ ] Section picker changes item section
- [ ] Changes persist after app restart

## Keyboard Shortcuts (Shortcuts Tab)

- [ ] Toggle Hidden Items shortcut can be set
- [ ] Show Hidden Items shortcut can be set
- [ ] Hide Items shortcut can be set
- [ ] Open Settings shortcut can be set
- [ ] Shortcuts work system-wide when app is in background
- [ ] Shortcut conflicts are detected

## Behavior Settings (Behavior Tab)

- [ ] Auto-hide toggle enables/disables feature
- [ ] Rehide delay slider adjusts timing (1-10 seconds)
- [ ] Show on hover toggle enables/disables hover-to-expand
- [ ] Hover delay slider adjusts timing (0.1-1.0 seconds)
- [ ] Analytics toggle enables/disables usage tracking
- [ ] Smart suggestions toggle enables/disables recommendations

## Profiles (Profiles Tab)

- [ ] Default profile exists on first launch
- [ ] Add Profile creates new profile
- [ ] Profile name can be edited
- [ ] Activate button switches active profile
- [ ] Delete button removes profile (with confirmation)
- [ ] Cannot delete last profile
- [ ] Time-based toggle enables schedule settings
- [ ] Start/End time pickers work
- [ ] Day selector toggles individual days
- [ ] Weekdays preset selects Mon-Fri
- [ ] Weekends preset selects Sat-Sun
- [ ] Every Day preset selects all days
- [ ] Capture Current Layout saves item sections

## Usage Analytics (Usage Tab)

- [ ] Total Items count is accurate
- [ ] Total Clicks count tracks interactions
- [ ] Items Used count shows non-zero click items
- [ ] Most Used Items list shows top 10
- [ ] Progress bars reflect relative usage
- [ ] Click percentages are calculated correctly

## Smart Suggestions

- [ ] Suggestions appear based on usage patterns
- [ ] "Hide" suggestions for rarely-used visible items
- [ ] "Show" suggestions for frequently-used hidden items
- [ ] Apply button implements suggestion
- [ ] Dismiss button removes suggestion
- [ ] Disabled state shows when suggestions are off

## Hover Expand (if enabled)

- [ ] Hovering over menu bar shows hidden items
- [ ] Moving mouse away hides items (after delay)
- [ ] Hover region is at top of screen only
- [ ] Delay respects settings value

## Search Window (Cmd+Shift+Space or custom)

- [ ] Keyboard shortcut opens search window
- [ ] Search window appears centered on screen
- [ ] Typing filters menu bar items
- [ ] Selecting item performs action
- [ ] Escape key closes window
- [ ] Clicking outside closes window

## Import/Export

- [ ] Export button saves .json file
- [ ] Import button loads .json file
- [ ] Imported configuration applies correctly
- [ ] Invalid file shows error

## Edge Cases

- [ ] App handles no menu bar items gracefully
- [ ] App handles permission denied gracefully
- [ ] App survives macOS restart
- [ ] App survives sleep/wake cycle
- [ ] App doesn't leak memory over time

## Known Limitations

- System status items (Control Center, Spotlight, Siri) are not controllable
- Some apps use non-standard menu bar implementations
- Accessibility API may not return all items on first scan
- Drag reordering requires accessibility permission

---

## Test Hardware

- **Model**: ___________________
- **macOS Version**: ___________________
- **RAM**: ___________________

## Tester

- **Name**: ___________________
- **Date**: ___________________

## Notes

(Add any bugs, issues, or suggestions here)

