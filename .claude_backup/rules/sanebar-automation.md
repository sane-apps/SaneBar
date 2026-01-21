# SaneBar UI Automation Rules

> Pattern: `**/SaneBar/**`, `**/scripts/**`

---

## NEVER Guess Coordinates

**WRONG:** Guessing pixel coordinates, using cliclick, manual cropping
**RIGHT:** Use accessibility APIs and AppleScript

---

## SaneBar Window Navigation

### Click Toolbar Tabs
```applescript
tell application "System Events"
    tell process "SaneBar"
        click button "Advanced" of toolbar 1 of window 1
    end tell
end tell
```

Available tabs: `General`, `Shortcuts`, `Advanced`, `About`

### Scroll in Settings
```applescript
tell application "System Events"
    tell process "SaneBar"
        tell scroll area 1 of group 1 of window 1
            tell scroll bar 1
                set value to 0.5  -- 0.0 = top, 1.0 = bottom
            end tell
        end tell
    end tell
end tell
```

---

## SaneBar AppleScript Commands

Control the app directly:
```bash
osascript -e 'tell application "SaneBar" to toggle'       # Toggle hidden/shown
osascript -e 'tell application "SaneBar" to show hidden'  # Reveal hidden icons
osascript -e 'tell application "SaneBar" to hide items'   # Hide icons
```

---

## Screenshot Automation

Use the marketing script:
```bash
./scripts/marketing_screenshots.rb --list   # See available shots
./scripts/marketing_screenshots.rb          # Capture all
./scripts/marketing_screenshots.rb --shot settings-advanced-spacing
```

The script handles:
- Tab navigation
- Scroll positioning
- SaneBar state control (hide/show)
- Window capture with shadows
- Menu bar cropping

---

## Debugging UI Hierarchy

If automation fails, inspect the structure:
```applescript
tell application "System Events"
    tell process "SaneBar"
        return entire contents of window 1
    end tell
end tell
```

---

## Key Learnings (Don't Repeat These Mistakes)

1. **NEVER guess pixel coordinates** - Always use accessibility element paths
2. **SwiftUI scroll areas** need `set value to X` on scroll bar, not scroll actions
3. **Check window name** changes when clicking tabs (e.g., "General" → "Advanced")
4. **SaneBar has AppleScript** - Use it instead of simulating clicks
