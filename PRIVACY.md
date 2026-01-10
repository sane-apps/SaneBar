# Privacy & Permissions

SaneBar is built with privacy as the foundation. This document explains every permission the app requests and exactly what it does with that access.

## The Short Version

- **No analytics** - Nothing is tracked or measured
- **No telemetry** - No usage data is collected
- **No user identifiers** - We don't know who you are
- **Local storage only** - Settings saved to `~/Library/Application Support/SaneBar/`
- **Optional update check** - Only when YOU click "Check for Updates"

---

## Update Checking - Privacy Commitment

SaneBar includes an optional "Check for Updates" feature. Here's exactly what happens when you use it:

### What We Guarantee

| Promise | How It's Enforced |
|---------|-------------------|
| **No user identifiers** | We send no device ID, UUID, or user token |
| **No cookies** | Ephemeral URLSession with cookies disabled |
| **No tracking** | No analytics, no pixels, no event logging |
| **No personal data** | Just a GET request to a public API |
| **User-initiated only** | Only runs when YOU click the button |
| **Open source** | Every line of code is auditable |

### What Happens Technically

When you click "Check for Updates":
1. SaneBar makes a single GET request to: `https://api.github.com/repos/stephanjoseph/SaneBar/releases/latest`
2. GitHub returns the latest version number
3. SaneBar compares it to your installed version
4. If newer, shows an alert with a link to the release page

**That's it.** No user data. No tracking. No phone home to a SaneBar server.

### What We Cannot Control

**IP Address**: Any network request reveals your IP address to the destination server. This is how the internet fundamentally works. However:
- GitHub is trusted by millions of developers worldwide
- We're using a public API, not a SaneBar-owned server
- GitHub cannot identify you as a SaneBar user specifically
- Users on VPNs have their IP masked

### Automatic Update Checking (Opt-in)

If you enable "Check automatically on launch" in Settings:
- Checks at most once per day (rate limited)
- Only shows an alert if an update is available
- Can be disabled at any time in Settings → About

### The Privacy Promise

```
SaneBar will NEVER:
- Send device identifiers
- Track update check frequency
- Log who checked for updates
- Collect any user data whatsoever
- Phone home to our own analytics server
```

**The code:** See `Core/Services/UpdateService.swift` - fully auditable.

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
| Settings | `~/Library/Application Support/SaneBar/settings.json` |
| Profiles | `~/Library/Application Support/SaneBar/profiles/` |
| Shortcuts | Managed by KeyboardShortcuts package |

**To completely remove SaneBar data:**
```bash
rm -rf ~/Library/Application\ Support/SaneBar
rm ~/Library/Preferences/com.sanebar.app.plist
```

---

## Network Activity Verification

Want to verify SaneBar's network behavior? Run this while the app is open:

```bash
# Watch for any network activity from SaneBar
sudo lsof -i -P | grep SaneBar
```

You'll see zero results unless you're actively checking for updates.

---

## Open Source

SaneBar is fully open source. Every line of code is auditable:
https://github.com/stephanjoseph/SaneBar

If you find any privacy concern, please open an issue.

---

## Contact

Questions about privacy? Open an issue on GitHub or email: stephanjoseph2007@gmail.com
