# Marketing Screenshot Automation Process

> Reusable process for capturing professional marketing screenshots across all Sane apps.

## Requirements

```bash
# One-time setup
pip3 install screenshot          # Alex's window capture tool (handles window IDs)
brew install imagemagick         # Image processing
```

## Key Automation Techniques

### 1. Window Capture (NOT coordinate guessing)
```bash
# Alex's tool finds windows by app name + title
/Users/sj/Library/Python/3.13/bin/screenshot AppName -t "Window Title" -s -f output.png
```

### 2. Tab Navigation (AppleScript)
```applescript
click button "TabName" of toolbar 1 of window 1
```

### 3. Scrolling (AppleScript)
```applescript
tell scroll bar 1 of scroll area 1 of group 1 of window 1
    set value to 0.5  -- 0.0=top, 1.0=bottom
end tell
```

### 4. App Control (SaneBar-specific)
```bash
osascript -e 'tell application "SaneBar" to show hidden'
osascript -e 'tell application "SaneBar" to hide items'
```

## Quick Usage

```bash
# List available shots for this app
./Scripts/marketing_screenshots.rb --list

# Capture single screenshot (app window must be open!)
./Scripts/marketing_screenshots.rb --shot settings-advanced

# Capture ALL screenshots
./Scripts/marketing_screenshots.rb
```

## How It Works

1. **Alex's `screenshot` tool** - Automatically finds window by app name + title filter
2. **Shadow included** - Professional look with `-s` flag
3. **ImageMagick polish** - Resize for web, optimize quality
4. **Standardized output** - Saves to `marketing/screenshots/`

## Adding to a New App

1. **Copy the script:**
   ```bash
   cp ~/SaneBar/Scripts/marketing_screenshots.rb ~/YourApp/Scripts/
   ```

2. **Edit the SHOTS hash** to define your app's screenshots:
   ```ruby
   SHOTS = {
     'main-window' => {
       app: 'YourApp',           # App name (as shown in Activity Monitor)
       title: 'Main',            # Window title filter (nil for any)
       filename: 'main.png',     # Output filename
       description: 'Main window'
     },
     # Add more shots...
   }
   ```

3. **Run it:**
   ```bash
   ./Scripts/marketing_screenshots.rb
   ```

## Best Practices

- **Prepare windows first** - Open and position all windows before running
- **Use title filters** - Capture specific tabs/states (e.g., "Advanced" vs "General")
- **Consistent sizing** - Script auto-resizes to max 800px width for web
- **Version control** - Commit screenshots to `marketing/screenshots/`

## Screenshot Definitions

Each shot in `SHOTS` hash:
| Key | Description |
|-----|-------------|
| `app` | Application name (case-sensitive, as in Activity Monitor) |
| `title` | Window title filter (substring match), or `nil` for any window |
| `filename` | Output filename in `marketing/screenshots/` |
| `description` | Human-readable description for `--list` |

## Troubleshooting

**"Failed to capture"**
- Is the app running?
- Is the window visible (not minimized)?
- Check app name matches Activity Monitor exactly

**Wrong window captured**
- Use `-t` title filter to be more specific
- Close other windows from same app

**Quality issues**
- Adjust ImageMagick settings in `polish_screenshot` method
- Use Retina display for higher resolution captures
