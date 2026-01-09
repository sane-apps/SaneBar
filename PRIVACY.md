# Privacy & Permissions

SaneBar is built with privacy as the foundation. This document explains every permission the app requests and exactly what it does with that access.

## The Short Version

- **Zero network requests** - SaneBar never connects to the internet
- **No analytics** - Nothing is tracked or measured
- **No telemetry** - No data leaves your Mac
- **Local storage only** - Settings saved to `~/Library/Preferences/`

---

## Permissions Explained

### Accessibility (Required)

**What it does:** Reads and rearranges menu bar icons.

**Why it's needed:** macOS menu bar icons are controlled by the Accessibility API (`AXUIElement`). SaneBar uses this to:
- Detect which icons are in your menu bar
- Move icons when you Cmd+drag to rearrange them
- Show/hide icon groups

**What it doesn't do:**
- Read window contents of other apps
- Log keystrokes
- Access any data outside the menu bar

**The code:** See `Core/Services/AccessibilityService.swift`

---

### Screen Recording (Optional)

**What it does:** Captures menu bar icon images for display.

**Why it's needed:** When showing hidden icons in the SaneBar drawer, we display icon thumbnails. The Screen Recording permission lets us capture these images.

**What it doesn't do:**
- Record your screen
- Capture window contents
- Save screenshots anywhere

**The code:** See `Core/Services/IconCaptureService.swift`

---

### WiFi Network Name (No Location Required)

**What it does:** Detects when you connect to specific WiFi networks.

**Why it's needed:** The "WiFi Triggers" feature can auto-show hidden icons when you connect to home/work/VPN networks.

**Technical clarification:** SaneBar uses `CoreWLAN` (Apple's WiFi framework), **NOT** `CoreLocation`. This means:
- We read only the network SSID (name)
- No GPS/location data is accessed
- No Location Services permission is required

**What it doesn't do:**
- Track your location
- Access GPS coordinates
- Require Location Services

**The code:** See `Core/Services/NetworkTriggerService.swift`

---

### Launch at Login (Optional)

**What it does:** Starts SaneBar when you log in.

**Why it's needed:** Standard convenience feature for menu bar apps.

**The code:** Uses `SMAppService` (Apple's Login Items API)

---

## Data Storage

All SaneBar data is stored locally:

| Data | Location |
|------|----------|
| Settings | `~/Library/Preferences/com.sanebar.app.plist` |
| Profiles | Same plist file |
| Shortcuts | Managed by KeyboardShortcuts package |

**To completely remove SaneBar data:**
```bash
rm ~/Library/Preferences/com.sanebar.app.plist
rm -rf ~/Library/Application\ Support/SaneBar
```

---

## Network Verification

Want to verify SaneBar makes no network requests? Run this while the app is open:

```bash
# Watch for any network activity from SaneBar
sudo lsof -i -P | grep SaneBar
```

You'll see zero results because SaneBar never opens network connections.

---

## Open Source

SaneBar is fully open source. Every line of code is auditable:
https://github.com/stephanjoseph/SaneBar

If you find any privacy concern, please open an issue.

---

## Contact

Questions about privacy? Open an issue on GitHub or email: [removed-for-privacy]
