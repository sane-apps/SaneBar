# SaneBar

[![Built with Claude](https://img.shields.io/badge/Built%20with-Claude-blueviolet)](https://claude.ai)
[![Swift](https://img.shields.io/badge/Swift-5.9-orange)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-14%2B-blue)](https://www.apple.com/macos)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

A clean, privacy-focused menu bar manager for macOS. Hide menu bar clutter with a single click.

**Free and open source.**

## The Story

I built this over a long weekend (~20 hours) pair programming with [Claude](https://claude.ai). Wanted a menu bar manager that wasn't $15, didn't phone home, and actually worked on macOS Tahoe. So I made one.

If you're curious about building Mac apps with AI, feel free to poke around the code or reach out. Happy to share what I learned.

## Features

### Core
- **One-click hide/show** - Click the SaneBar icon to toggle hidden items
- **Cmd+drag to organize** - Arrange icons left (always visible) or right (hideable) of the separator
- **Auto-hide** - Hidden items automatically disappear after a configurable delay
- **Spacers** - Add dividers to organize hidden icons into groups

### Keyboard & Automation
- **Global hotkeys** - Configurable shortcuts for all actions
- **Per-icon hotkeys** - Assign keyboard shortcuts to specific menu bar icons
- **Menu bar search** - Quickly find apps and copy their bundle IDs
- **AppleScript support** - Automate via Terminal or other tools

### Smart Triggers
- **Hover to reveal** - Show hidden items when hovering over the menu bar
- **App triggers** - Auto-show hidden items when specific apps launch
- **WiFi triggers** - Auto-show on specific networks (home, work, VPN)
- **Always visible apps** - Keep specific icons visible even when hiding others

### Customization
- **Profiles** - Save and restore different configurations
- **Menu bar appearance** - Customize tint, shadow, and border styling
- **Notch support** - Optimized for MacBook Pro with notch

## Privacy

**100% on-device.** No analytics. No telemetry. No network requests. Everything stays on your Mac.

## Requirements

- macOS 14.0 (Sonoma) or later
- macOS 15.0+ (Sequoia/Tahoe) fully supported

## Installation

### Download

Download the latest release from [Releases](https://github.com/stephanjoseph/SaneBar/releases).

### Build from Source

```bash
# Clone the repository
git clone https://github.com/stephanjoseph/SaneBar.git
cd SaneBar

# Install dependencies
bundle install

# Generate Xcode project and build
./Scripts/SaneMaster.rb verify

# Launch
./Scripts/SaneMaster.rb launch
```

## Usage

### Quick Start

1. **Cmd+drag** menu bar icons to rearrange them
2. Icons **left** of SaneBar icon = always visible
3. Icons **right** of SaneBar icon = can be hidden
4. **Click** SaneBar icon to show/hide

### Keyboard Shortcuts

Configure in Settings > Shortcuts:
- Toggle visibility
- Show hidden items
- Hide items
- Search apps
- Open Settings

### AppleScript

Control SaneBar from Terminal or automation tools:

```bash
osascript -e 'tell app "SaneBar" to toggle'
osascript -e 'tell app "SaneBar" to show hidden'
osascript -e 'tell app "SaneBar" to hide items'
```

## Development

### Prerequisites

- Xcode 16+
- Ruby 3.0+ (for build scripts)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)

### Build & Test

```bash
# Full build + tests
./Scripts/SaneMaster.rb verify

# Kill, build, launch, stream logs
./Scripts/SaneMaster.rb test_mode

# Stream logs
./Scripts/SaneMaster.rb logs --follow
```

### Project Structure

```
SaneBar/
├── Core/
│   ├── MenuBarManager.swift      # Main status bar logic
│   ├── Services/                 # Hiding, shortcuts, triggers, persistence
│   └── Models/                   # Data models (profiles, settings)
├── UI/
│   ├── SettingsView.swift        # Settings window
│   └── SearchWindow/             # Menu bar search UI
├── Tests/                        # Unit tests
└── Scripts/
    └── SaneMaster.rb             # Build automation
```

## macOS Tahoe (26) Notes

SaneBar includes a workaround for the SwiftUI Settings scene issue on macOS Tahoe where `showSettingsWindow:` no longer works for menu bar apps. The fix uses a hidden window technique with activation policy toggling.

## Support

**Totally free to use.** All I ask is you leave a ⭐ on the repo if you find it useful.

Starving artist here - if you really want to help a brother out, donations are always appreciated. God bless!

| Crypto | Address |
|--------|---------|
| **BTC** | `3Go9nJu3dj2qaa4EAYXrTsTf5AnhcrPQke` |
| **SOL** | `FBvU83GUmwEYk3HMwZh3GBorGvrVVWSPb8VLCKeLiWZZ` |
| **ZEC** | `t1PaQ7LSoRDVvXLaQTWmy5tKUAiKxuE9hBN` |

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

- Uses [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) by Sindre Sorhus
- Inspired by [Hidden Bar](https://github.com/dwarvesf/hidden) and other open source menu bar tools
