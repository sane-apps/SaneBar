# Privacy & Permissions

> [README](README.md) · [ARCHITECTURE](ARCHITECTURE.md) · [DEVELOPMENT](DEVELOPMENT.md) · [PRIVACY](PRIVACY.md) · [SECURITY](SECURITY.md)

SaneBar is built with privacy as the foundation. This document explains every permission the app requests and exactly what it does with that access.

## The Short Version

- **Your menu bar setup stays on your Mac** - No files, icon names, or menu bar contents are uploaded
- **Privacy-preserving aggregate counts** - We count things like app version, update status, launches, purchase flow, and whether the app opened in Free or Pro
- **No user identifiers** - We do not tie those counts to your identity or sell customer data
- **Local storage only** - Settings saved to `~/Library/Application Support/SaneBar/`
- **Limited network use** - Update checks, license validation, and those simple app counts

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

### Screen Recording

**What it does:** SaneBar does not require Screen Recording permission for normal use.

**Why:** SaneBar's product behavior is driven by the Accessibility API. That is how it detects, hides, shows, and rearranges menu bar items.

**What it doesn't do:**
- Inspect other apps' window contents
- Inspect Zoom video frames
- Inspect network packets

**Repository note:** The repo still contains a narrow ScreenCaptureKit self-snapshot path for SaneBar's own visible settings window during internal snapshot tooling. It is not used to inspect other apps.

**The code:** See `SaneBarApp.swift` and `Core/Services/AppleScriptCommands.swift`

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

## Privacy-Preserving Aggregate Analytics

SaneBar sends a few privacy-preserving aggregate counts so we can see which versions are in use, whether updates are working, and whether the Basic-to-Pro flow is healthy.

These events may include:

- app name
- event name
- app version and build
- macOS version
- distribution channel (`direct`, `app_store`, or `setapp`)
- license tier (`free` or `pro`)
- broad purchase/update lifecycle events such as buy clicked, purchase started/completed, license activated, update available, or update install started
- update target version/build when Sparkle offers or starts installing an update

These events do **not** include:

- your name or email
- license key
- IP address in SaneApps analytics storage
- menu bar contents, icon names, screenshots, or files
- any persistent user identifier
- customer content, clipboard contents, browser history, or app-internal clicked URLs
- data for sale to advertisers or data brokers

Storage is daily aggregate counts only. SaneApps does not store raw per-user histories for these counts.

The sanebar.com website may also use cookie-free aggregate website analytics, such as page views and referrers, to understand whether the website is working. That website analytics is separate from the app and does not identify you.

---

## Network Activity Verification

Want to verify SaneBar's network behavior? Run this while the app is open:

```bash
# Watch for any network activity from SaneBar
sudo lsof -i -P | grep SaneBar
```

You'll only see traffic for update checks, license validation, or simple anonymous app counts.

---

## Transparent Source

SaneBar's source is public and auditable under the PolyForm Shield License:
https://github.com/sane-apps/SaneBar

If you find any privacy concern, please open an issue.

---

## Contact

Questions about privacy? Email hi@saneapps.com. Do not put private file names, paths, screenshots, or customer data in a public issue.
