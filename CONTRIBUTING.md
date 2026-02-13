# Contributing to SaneBar

Thanks for your interest in contributing to SaneBar! This document explains how to get started.

---

## Quick Start

```bash
# Clone the repo
git clone https://github.com/sane-apps/SaneBar.git
cd SaneBar

# Install dependencies
bundle install

# Generate Xcode project and verify build
./scripts/SaneMaster.rb verify
```

If everything passes, you're ready to contribute!

---

## Development Environment

### Requirements

- **macOS 15.0+** (Sequoia or later)
- **Xcode 16+**
- **Ruby 3.0+** (for build scripts)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) - installed via `bundle install`

### Key Commands

| Command | Purpose |
|---------|---------|
| `./scripts/SaneMaster.rb verify` | Build + run all tests |
| `./scripts/SaneMaster.rb test_mode` | Kill → Build → Launch → Stream logs |
| `./scripts/SaneMaster.rb logs --follow` | Stream live app logs |

> **Important**: Always use `SaneMaster.rb` instead of raw `xcodebuild`. It handles XcodeGen, signing, and other project-specific configuration.

---

## Project Structure

```
SaneBar/
├── Core/                   # Business logic
│   ├── Services/           # AccessibilityService, HoverService, etc.
│   ├── Controllers/        # StatusBarController, SettingsController
│   └── Models/             # Data models
├── UI/                     # SwiftUI views
│   ├── Settings/           # Settings tabs
│   └── SearchWindow/       # Find Icon UI
├── Tests/                  # Unit tests (Swift Testing framework)
├── scripts/                # Build automation
└── project.yml             # XcodeGen configuration
```

---

## Coding Standards

### Swift

- **Swift 5.9+** features encouraged
- **@Observable** instead of @StateObject
- **Swift Testing** framework (`import Testing`, `@Test`, `#expect`) — NOT XCTest
- **Actors** for services with shared mutable state
- Keep SwiftUI view bodies under 50 lines

### File Organization

When creating new files:

1. Run `xcodegen generate` after adding files (or use `./scripts/SaneMaster.rb verify`)
2. Follow existing naming patterns:
   - Services: `*Service.swift` in `Core/Services/`
   - Models: `*Model.swift` in `Core/Models/`
   - Views: `*View.swift` in `UI/`

For detailed coding rules, see [.claude/rules/README.md](.claude/rules/README.md).

---

## Making Changes

### Before You Start

1. Check [GitHub Issues](https://github.com/sane-apps/SaneBar/issues) for existing discussions
2. For significant changes, open an issue first to discuss the approach

### Pull Request Process

1. **Fork** the repository
2. **Create a branch** from `main` (e.g., `feature/my-feature` or `fix/issue-123`)
3. **Make your changes** following the coding standards
4. **Run tests**: `./scripts/SaneMaster.rb verify`
5. **Submit a PR** with:
   - Clear description of what changed and why
   - Reference to any related issues
   - Screenshots for UI changes

### Commit Messages

Follow conventional commit format:

```
type: short description

Longer explanation if needed.

Fixes #123
```

Types: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`

---

## Testing

SaneBar uses **Swift Testing** (not XCTest):

```swift
import Testing
@testable import SaneBar

@Test("Hiding service toggles state correctly")
func hidesAndShows() async {
    let service = HidingService()
    #expect(service.isHidden == false)

    await service.hide()
    #expect(service.isHidden == true)
}
```

Run tests:
```bash
./scripts/SaneMaster.rb verify
```

---

## Accessibility API Notes

SaneBar uses macOS Accessibility APIs extensively. Key things to know:

- The app requires **Accessibility permission** to function
- Use `AXIsProcessTrusted()` to check permission status
- Always verify API existence: `./scripts/SaneMaster.rb verify_api <symbol> <framework>`

For deep dives, see [docs/DEBUGGING_MENU_BAR_INTERACTIONS.md](docs/DEBUGGING_MENU_BAR_INTERACTIONS.md).

---

## Documentation

| Document | Purpose |
|----------|---------|
| [README.md](README.md) | User-facing overview |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Full development SOP |
| [GitHub Issues](https://github.com/sane-apps/SaneBar/issues) | Bug reports and tracking |

---

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Please be respectful and constructive.

---

## Questions?

- Open a [GitHub Issue](https://github.com/sane-apps/SaneBar/issues)
- Check existing [Discussions](https://github.com/sane-apps/SaneBar/discussions) (if enabled)

Thank you for contributing!
