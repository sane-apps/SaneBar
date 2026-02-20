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

SaneBar uses the **Sparkle** framework for updates, the industry standard for privacy-focused macOS apps.

### Privacy Configuration

We have explicitly configured Sparkle to maximize privacy:

| Setting | Value | Meaning |
|---------|-------|---------|
| `SUEnableSystemProfiling` | `NO` | **No** system profile (CPU, RAM, OS version) is sent |
| `SUFeedURL` | Cloudflare Pages | Checks a static XML file, not an API |

### What Happens Technically

When SaneBar checks for updates (either automatically or when you click "Check for Updates"):
1. It requests a static file: `https://sanebar.com/appcast.xml`
2. This is a standard HTTP GET request (your IP is visible to Cloudflare, as with any website)
3. **No other data is sent.**

### EdDSA Security

Updates are signed with an **EdDSA signature**. This means:
- Even if the update server is compromised, a malicious update cannot be installed
- Only the developer (holding the private key) can sign valid updates

**The code:** See `Core/Services/UpdateService.swift` and `project.yml` configuration.

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

## 100% Transparent Code

Every line of SaneBar's code is public and auditable:
https://github.com/sane-apps/SaneBar

If you find any privacy concern, please open an issue.

---

## Contact

Questions about privacy? Open an issue on GitHub or email: hi@saneapps.com
