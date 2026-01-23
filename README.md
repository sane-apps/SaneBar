# SaneBar

[![License: MIT](https://img.shields.io/github/license/sane-apps/SaneBar)](LICENSE)
[![Release](https://img.shields.io/github/v/release/sane-apps/SaneBar)](https://github.com/sane-apps/SaneBar/releases)
[![macOS 15+](https://img.shields.io/badge/macOS-15%2B-blue)](https://github.com/sane-apps/SaneBar/releases)
[![Privacy: 100% On-Device](https://img.shields.io/badge/Privacy-100%25%20On--Device-success)](PRIVACY.md)
[![Built with Claude](https://img.shields.io/badge/Built%20with-Claude-blueviolet)](https://claude.ai)

**The privacy-first menu bar manager for macOS.** Native, lightweight, and scriptable.

Hide clutter. Lock sensitive icons behind Touch ID. Find any app instantly.

[![SaneBar Demo - Hide Icons & Lock with Touch ID](https://img.youtube.com/vi/I6U3APV-998/maxresdefault.jpg)](https://www.youtube.com/watch?v=I6U3APV-998)

![SaneBar Find Hidden Icon](docs/images/find-icon.png)

### Icons Revealed
![Menu bar with all icons revealed](docs/images/menubar-revealed.png)

### Icons Hidden
![Clean menu bar with icons hidden](docs/images/menubar-hidden.png)

---

## Download

SaneBar is open source. You are welcome to clone the repo and build it yourself for free. If you'd like to support development and get a ready-to-use, notarized version, you can purchase the DMG for $5 at **[sanebar.com](https://sanebar.com)**.

**Note:** Homebrew is not supported. All software updates are delivered directly through the app.

**Requirements:** macOS 15 Sequoia or later

---

## How It Works

1. **Click** the SaneBar icon to show/hide your menu bar icons
2. **⌘+drag** icons to choose which ones hide
3. **Option-click** the SaneBar icon to open Power Search
4. That's it!

Icons to the **left** of the Separator (`|`) = can be hidden  
Icons to the **right** of the Separator (`|`) = always visible

---

## Features

### Privacy First
- **🔒 Secure Reveal** — The *only* menu bar manager that locks hidden icons behind **system authentication** (password prompt). Protect sensitive apps like crypto wallets, messaging tools, and VPNs.
- **100% On-Device** — No analytics. No telemetry. No network requests. Everything stays on your Mac.

![Privacy Settings](docs/images/settings-general.png)

### Power Search
- **Find Hidden Icon** — Search and click any menu bar app, even if hidden behind the Notch
- **Keyboard Navigation** — Arrow keys to navigate, Enter to select, Escape to close
- **Virtual Click** — Activate menu bar items without seeing them
- **Per-Icon Hotkeys** — Global shortcuts for your most-used menu bar apps

### Automation Ready
- **AppleScript Support** — Full scripting integration for Shortcuts and automation workflows
- **Smart Triggers** — Auto-show on Focus Mode, WiFi network, app launch, or low battery
- **Profiles** — Save different setups for work, home, or presentations

![Rules and Automation](docs/images/settings-rules.png)

### Core
- **One-click hide/show** — Toggle visibility with a single click or hotkey (default: ⌘\)
- **⌘+drag to organize** — Choose which icons hide and which stay visible
- **Auto-hide** — Icons disappear after a configurable delay

### Gestures
- **Hover to reveal** — Move your cursor to the top of the screen to show hidden icons
- **Scroll to reveal** — Two-finger scroll in the menu bar area
- **Directional scroll** — Scroll up to show, scroll down to hide (optional)
- **Click to toggle** — Left-click in menu bar toggles visibility (optional)
- **⌘+drag reveal** — All icons appear while rearranging so you can organize freely

### Customization
- **Liquid Glass** — Beautiful translucent styling on macOS 26 Tahoe
- **Bar Styling** — Tint, shadow, borders, and rounded corners (all macOS versions)

![Appearance Settings](docs/images/settings-appearance.png)

Works perfectly on Macs with Notch. **100% private** — no network requests, no analytics, no account.

---

## Power User Features

### 🔍 Find Hidden Icon
Quickly find and activate any menu bar app without lifting your hands from the keyboard.
1. **Option-click** the SaneBar icon, or use the menu **Find Icon…** (default hotkey: ⌘⇧Space)
2. Type an app name and press **Return**
3. SaneBar will reveal hidden icons and **virtually click** the app's menu bar item
4. After a configurable delay (default 15 seconds), icons automatically hide again

This works even if the icon is physically hidden behind the Notch or off-screen!

### ⌨️ Per-Icon Hotkeys
Assign a specific global hotkey to any menu bar app.
1. Open **Find Icon…** window
2. Select an app from the list
3. Click the **Record Shortcut** box in the footer
4. Press your desired key combination
5. Now, pressing that hotkey will instantly show hidden items and open that app's menu

### 🎨 Bar Styling
Customize the look of your menu bar panel.
- Go to **Settings → Appearance**
- Enable "Custom Appearance"
- On macOS 26 Tahoe: Enable **Translucent Background** for the native Liquid Glass look
- On older macOS: Adjust **Tint Color**, **Opacity**, **Shadow**, **Border**, and **Rounded Corners**

### 💾 Profiles
Save different menu bar configurations for different contexts (e.g., "Work", "Gaming", "Presentation").
- Go to **Settings → General → Saved Profiles**
- Click **Save as Profile…**
- Restore any profile with a single click

---

## The Notch & 50+ Apps

**Worried about losing icons behind the Notch?**

If you have 50+ apps, macOS might hide some of them behind the camera housing (the "Notch") or off-screen. SaneBar handles this gracefully:

1. **Hiding**: SaneBar pushes unused icons safely off-screen so your menu bar looks clean
2. **Safety Lock**: If SaneBar itself would get pushed off-screen, it refuses to hide to ensure you never lose control
3. **Find Hidden Icon**: Can't see an icon because it's behind the Notch? Open **Find Icon…**, type the app name and hit Enter. SaneBar will find it and click it for you, even if it's invisible
4. **Tighter Icon Spacing**: Reduce system-wide menu bar spacing to fit more icons. Go to **Settings → Appearance** and enable "Reduce space between icons" (requires logout)

---

## Configuration

All settings are in the **Settings** window (click SaneBar icon → Settings, or press ⌘,).

| Tab | What's there |
|-----|--------------|
| **General** | Launch at login, show in Dock, security (authentication lock), software updates, saved profiles |
| **Rules** | Auto-hide behavior, revealing gestures (hover, scroll), automatic triggers (battery, apps, Wi-Fi) |
| **Appearance** | Divider style, menu bar styling (tint, opacity, shadow, border, corners), icon spacing |
| **Shortcuts** | Global keyboard shortcuts, AppleScript commands |
| **Experimental** | Beta features being tested, easy bug reporting |
| **About** | Version info, privacy badge, licenses, support, report issue |

### Revealing Gestures (Settings → Rules)
- **Hover near top** — Show hidden icons when you move cursor to the top of the screen
- **Scroll up** — Two-finger scroll up in the menu bar reveals hidden icons

### Automatic Triggers (Settings → Rules)
- **Low Battery** — Auto-show when battery drops below threshold
- **App Launch** — Show when specific apps start
- **Wi-Fi Change** — Show on specific networks (click "Add current network")
- **Focus Mode** — Show when macOS Focus Mode changes (Work, Personal, etc.)

### Icon Spacing (Settings → Appearance)

Reduce the spacing between **all** menu bar icons system-wide to fit more icons before they get hidden by the notch.

- **Enable**: Toggle "Reduce space between icons" in Appearance Settings
- **Defaults**: Ships with notch-friendly values (spacing=4, padding=4)
- **Logout required**: macOS reads these settings at login, so you must log out and back in for changes to take effect
- **Reversible**: Disable the toggle and log out to restore default spacing

---

## Privacy

**Your data stays on your Mac.** SaneBar makes zero network requests. No analytics. No telemetry. No account.

![100% On-Device](docs/images/settings-about.png)

[Full privacy details](PRIVACY.md)

---

## Support

Free to use! If SaneBar helps you, star this repo.

### Donations

| | Address |
|---|---------|
| **BTC** | `3Go9nJu3dj2qaa4EAYXrTsTf5AnhcrPQke` |
| **SOL** | `FBvU83GUmwEYk3HMwZh3GBorGvrVVWSPb8VLCKeLiWZZ` |
| **ZEC** | `t1PaQ7LSoRDVvXLaQTWmy5tKUAiKxuE9hBN` |

---

## For Developers

<details>
<summary>Build from source</summary>

### Requirements
- macOS 15.0+ (Sequoia or later)
- Xcode 16+
- Ruby 3.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Build

```bash
git clone https://github.com/sane-apps/SaneBar.git
cd SaneBar
bundle install
./scripts/SaneMaster.rb verify
./scripts/SaneMaster.rb launch
```

### Project Structure

```
SaneBar/
├── Core/                   # Business logic
│   ├── Services/           # AccessibilityService, HoverService, etc.
│   ├── Controllers/        # StatusBarController, SettingsController
│   └── Models/             # Data models
├── UI/                     # SwiftUI views
│   ├── Settings/           # Modular settings tabs
│   └── SearchWindow/       # Find Hidden Icon UI
├── Tests/                  # 241 unit tests with mocks
├── scripts/                # Build automation (SaneMaster.rb)
└── project.yml             # XcodeGen configuration
```

</details>

<details>
<summary>AppleScript automation</summary>

```bash
# Toggle hidden items
osascript -e 'tell app "SaneBar" to toggle'

# Show hidden items
osascript -e 'tell app "SaneBar" to show hidden'

# Hide items
osascript -e 'tell app "SaneBar" to hide items'
```

</details>

<details>
<summary>The story</summary>

Built pair programming with [Claude](https://claude.ai). Wanted a menu bar manager that wasn't $15, didn't phone home, and actually worked on macOS Tahoe with Liquid Glass.

</details>

<details>
<summary>Documentation for contributors</summary>

| Document | Purpose |
|----------|---------|
| [CONTRIBUTING.md](CONTRIBUTING.md) | How to contribute |
| [SECURITY.md](SECURITY.md) | Security policy and reporting |
| [CHANGELOG.md](CHANGELOG.md) | Version history |
| [ROADMAP.md](ROADMAP.md) | Feature status overview |
| [BUG_TRACKING.md](BUG_TRACKING.md) | Bug reports with GitHub links |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Development rules and SOP |

</details>

---

## License

MIT — see [LICENSE](LICENSE)