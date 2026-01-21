# Code Rules Index

SaneBar enforces coding standards via pattern-matched rules. When Claude Code edits a file matching a pattern, the corresponding rule is shown.

---

## Rule Files

| File | Pattern | Purpose |
|------|---------|---------|
| [views.md](views.md) | `**/Views/**/*.swift`, `**/UI/**/*.swift` | SwiftUI views: body limits, no business logic, @Observable |
| [models.md](models.md) | `**/Models/**/*.swift`, `**/*Model.swift` | Data models: value types, Codable, Equatable, Sendable |
| [services.md](services.md) | `**/Services/**/*.swift`, `**/*Service.swift` | Services: actor isolation, protocols, DI, typed errors |
| [tests.md](tests.md) | `**/Tests/**/*.swift` | Tests: Swift Testing (not XCTest), no tautologies |
| [scripts.md](scripts.md) | `**/scripts/**/*.rb` | Ruby scripts: frozen_string_literal, exit codes |
| [hooks.md](hooks.md) | `**/hooks/**/*.rb` | Claude Code hooks: exit 0/1/2, error handling |
| [sanebar-automation.md](sanebar-automation.md) | `**/SaneBar/**` | UI automation: accessibility APIs, AppleScript |

---

## How Rules Work

1. Claude Code checks file path against patterns
2. Matching rules are injected into context
3. Rules override default behavior

---

## Key Standards

### Swift Testing (NOT XCTest)
```swift
import Testing  // NOT XCTest

@Test func something() {
    #expect(result == expected)  // NOT XCTAssertEqual
}
```

### @Observable (NOT @StateObject)
```swift
@Observable class Settings { }  // NOT @StateObject
```

### Actor for Services
```swift
actor CameraService: CameraServiceProtocol { }
```

---

## Adding New Rules

1. Create `rulename.md` in this directory
2. Use YAML frontmatter for pattern matching
3. Follow existing format with Right/Wrong examples
