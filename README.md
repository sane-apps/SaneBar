# SaneBar

[![License: MIT](https://img.shields.io/github/license/stephanjoseph/SaneBar)](LICENSE)
[![Release](https://img.shields.io/github/v/release/stephanjoseph/SaneBar)](https://github.com/stephanjoseph/SaneBar/releases)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)](https://github.com/stephanjoseph/SaneBar/releases)
[![Built with Claude](https://img.shields.io/badge/Built%20with-Claude-blueviolet)](https://claude.ai)

**Clean up your Mac's menu bar in one click.**

Free. Private. No account needed.

| Before | After |
|--------|-------|
| ![Cluttered menu bar](assets/screenshot-1.png) | ![Clean menu bar](assets/screenshot-2.png) |

---

## Download

**[Download SaneBar v1.0.0](https://github.com/stephanjoseph/SaneBar/releases/download/v1.0.0/SaneBar-1.0.0.dmg)** (macOS 14+)

Or via Homebrew: `brew install --cask sanebar` *(coming soon - help approval by starring this repo!)*

---

## How It Works

1. **Click** the SaneBar icon to show/hide your menu bar icons
2. **Cmd+drag** icons to choose which ones hide
3. That's it!

Icons to the **left** of SaneBar = always visible
Icons to the **right** of SaneBar = can be hidden

---

## Features

- **One-click hide/show** - Click to toggle visibility
- **Hover to reveal** - Show icons when you mouse over the menu bar
- **Auto-hide** - Icons disappear after a configurable delay
- **Keyboard shortcuts** - Global hotkeys for everything
- **WiFi triggers** - Auto-show icons on specific networks
- **Profiles** - Save different setups for work/home

Works great on MacBook Pro with notch.

---

## Configuration

All settings are in the **Settings** window (click SaneBar icon > Settings, or use your configured shortcut).

| Tab | What's there |
|-----|--------------|
| **General** | Launch at login, auto-hide delay |
| **Shortcuts** | Global keyboard shortcuts, AppleScript commands |
| **Advanced** | Profiles, always-visible apps, triggers, appearance |
| **About** | Version info, privacy badge, licenses |

**Smart Triggers** (Settings > Advanced > Automation):
- **Hover**: Show hidden icons when you mouse over the menu bar area
- **Low Battery**: Auto-show when battery drops below threshold
- **App Launch**: Show when specific apps start (enter bundle IDs)
- **WiFi Networks**: Show on specific networks (enter SSIDs or click "Add current network")

---

## Privacy

**Your data stays on your Mac.** SaneBar makes zero network requests. No analytics. No telemetry. No account.

![100% On-Device](assets/settings-about.png)

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
- macOS 14.0+
- Xcode 16+
- Ruby 3.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Build

```bash
git clone https://github.com/stephanjoseph/SaneBar.git
cd SaneBar
bundle install
./Scripts/SaneMaster.rb verify
./Scripts/SaneMaster.rb launch
```

### Project Structure

```
SaneBar/                    # Repository root
├── Core/                   # Business logic, services, managers
├── UI/                     # SwiftUI views
├── SaneBar/                # App target (entry point, resources)
├── Resources/              # Assets, icons
├── Tests/                  # Unit tests
├── Scripts/                # Build automation (SaneMaster.rb)
└── project.yml             # XcodeGen configuration
```

</details>

<details>
<summary>AppleScript automation</summary>

```bash
osascript -e 'tell app "SaneBar" to toggle'
osascript -e 'tell app "SaneBar" to show hidden'
osascript -e 'tell app "SaneBar" to hide items'
```

</details>

<details>
<summary>The story</summary>

Built over a weekend pair programming with [Claude](https://claude.ai). Wanted a menu bar manager that wasn't $15, didn't phone home, and actually worked on macOS Tahoe.

</details>

---

## License

MIT - see [LICENSE](LICENSE)
