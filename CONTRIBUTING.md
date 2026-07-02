# Contributing to SaneBar

Thanks for your interest in contributing to SaneBar! This document explains how to get started.

---

## Quick Start

```bash
# Clone the repo
git clone https://github.com/sane-apps/SaneBar.git
cd SaneBar

# Build and run all tests
./Scripts/SaneMaster.rb verify
```

If everything passes, you're ready to contribute! No Ruby gems or other setup
are needed to build and test — the tracked Xcode project builds as-is.

---

## Development Environment

### Requirements

- **Xcode 16+** (needs macOS 15 Sequoia or later to build; the app itself runs on macOS 14.0+)
- **Apple Silicon** (arm64 only)
- **Ruby 3+** for the helper scripts (macOS ships one)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) — only needed when you add or remove source files

### Key Commands

| Command | Purpose |
|---------|---------|
| `./Scripts/SaneMaster.rb verify` | Build + run all tests |
| `./Scripts/SaneMaster.rb test_mode` | Kill → Build → Launch → Stream logs |
| `./Scripts/sanebar_logwatch.sh` | Stream live app logs |

`SaneMaster.rb` falls back to `Scripts/SaneMaster_standalone.rb` (plain
`xcodebuild`) outside the original maintainer's machines — that fallback is
the normal path for contributors. See [DEVELOPMENT.md](DEVELOPMENT.md) for the
full guide, including the project structure and the parts of the codebase
that are fragile on purpose.

---

## Coding Standards

### Swift

- **Swift Testing** framework for tests (`import Testing`, `@Test`, `#expect`) — NOT XCTest
- **@Observable** instead of @StateObject
- **Actors** for services with shared mutable state
- Keep SwiftUI view bodies small; extract subviews rather than nesting deeply

### Adding Files

`project.yml` is the source of truth for the Xcode project; the committed
`.xcodeproj` is a convenience snapshot. CI regenerates the project with
`xcodegen generate` before building, so a file added only through Xcode's GUI
will silently vanish from the CI build. After adding or removing files:

1. Run `xcodegen generate` and commit the regenerated project
2. Follow existing naming patterns:
   - Services: `*Service.swift` in `Core/Services/`
   - Models: `*Model.swift` in `Core/Models/`
   - Views: `*View.swift` in `UI/`

---

## Making Changes

### Before You Start

Heads-up: because SaneBar is community-maintained, **new GitHub issues are
auto-closed by a bot** (with a friendly note explaining why). That's expected.
Put your reproduction, reasoning, and discussion directly in the pull request
description instead — the PR is the record.

### Pull Request Process

1. **Fork** the repository
2. **Create a branch** from `main` (e.g., `feature/my-feature` or `fix/issue-123`)
3. **Make your changes** following the coding standards
4. **Run tests**: `./Scripts/SaneMaster.rb verify`
5. **Submit a PR** with:
   - Clear description of what changed and why
   - Steps to reproduce the bug it fixes (if a bug fix)
   - Screenshots for UI changes

### Commit Messages

Follow conventional commit format:

```
type: short description

Longer explanation if needed.
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

Run tests with `./Scripts/SaneMaster.rb verify`. A test must be able to fail
for the real bug it guards — see the Testing section of
[DEVELOPMENT.md](DEVELOPMENT.md), including what to do when a
`RuntimeGuard*` source-fingerprint test fails after an intentional edit.

---

## Accessibility API Notes

SaneBar uses macOS Accessibility APIs extensively. Key things to know:

- The app requires **Accessibility permission** to function
- Use `AXIsProcessTrusted()` to check permission status
- Verify AX API shapes against Apple's documentation before coding — several
  "obvious" properties don't exist

For deep dives, see [docs/DEBUGGING_MENU_BAR_INTERACTIONS.md](docs/DEBUGGING_MENU_BAR_INTERACTIONS.md).

---

## Documentation

| Document | Purpose |
|----------|---------|
| [README.md](README.md) | User-facing overview |
| [DEVELOPMENT.md](DEVELOPMENT.md) | Build, test, and gotchas |
| [ARCHITECTURE.md](ARCHITECTURE.md) | How the app works internally |

---

## Code of Conduct

This project follows the [Contributor Covenant](CODE_OF_CONDUCT.md). Please be respectful and constructive.

---

## Questions?

Put questions in your pull request description, or email
**hi@saneapps.com**. (New GitHub issues are auto-closed by the sunset bot —
see above.)

Thank you for contributing!

<!-- SANEAPPS_AI_CONTRIB_START -->
## Become a Contributor (Even if You Don't Code)

Are you tired of waiting on the dev to get around to fixing your problem?  
Do you have a great idea that could help everyone in the community, but think you can't do anything about it because you're not a coder?

Good news: you actually can.

Copy and paste this into Claude or Codex, then describe your bug or idea:

```text
I want to contribute to this repo, but I'm not a coder.

Repository:
https://github.com/sane-apps/SaneBar

Bug or idea:
[Describe your bug or idea here in plain English]

Please do this for me:
1) Understand and reproduce the issue (or understand the feature request).
2) Make the smallest safe fix.
3) Open a pull request to https://github.com/sane-apps/SaneBar with a short
   summary of what changed and why in the PR description.
4) Give me the pull request link.

Important:
- Keep it focused on this one issue/idea.
- Do not make unrelated changes.
- Do not open a GitHub issue — new issues are auto-closed; the pull request
  itself is the report.
```

If needed, you can also just email the pull request link to hi@saneapps.com.

Pull requests are reviewed and tested before merge.

If your PR is merged, you get public credit, and the satisfaction of knowing you helped ship a fix for everyone.
<!-- SANEAPPS_AI_CONTRIB_END -->
