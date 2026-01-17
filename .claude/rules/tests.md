# Test File Rules

> Pattern: `**/Tests/**/*.swift`, `**/Specs/**/*.swift`, `**/*Tests.swift`, `**/*Spec.swift`

---

## Requirements

1. **Use Swift Testing** - `import Testing`, `@Test`, `#expect()` - NOT XCTest
2. **No tautologies** - `#expect(true)` or `#expect(x == x)` are useless
3. **Test behavior, not implementation** - What it does, not how
4. **One assertion focus** - Each test verifies one thing
5. **Descriptive test names** - Use `@Test("description")` for clarity

## Swift Testing vs XCTest (ALWAYS use Swift Testing)

| XCTest (DON'T USE) | Swift Testing (USE THIS) |
|--------------------|--------------------------|
| `import XCTest` | `import Testing` |
| `class FooTests: XCTestCase` | `struct FooTests` |
| `func testSomething()` | `@Test func something()` |
| `XCTAssertEqual(a, b)` | `#expect(a == b)` |
| `XCTAssertTrue(x)` | `#expect(x)` |
| `XCTAssertFalse(x)` | `#expect(!x)` |
| `XCTAssertNil(x)` | `#expect(x == nil)` |
| `XCTAssertNotNil(x)` | `#expect(x != nil)` |
| `XCTAssertThrowsError` | `#expect(throws:)` |
| `override func setUp()` | Use helper functions or init |

## Right

```swift
import Testing
@testable import MyApp

struct ParserTests {
    @Test("Parses valid JSON with correct count")
    func parsesValidJSON() throws {
        let result = try parser.parse(validJSON)
        #expect(result.count == 3)
        #expect(result[0].name == "expected")
    }

    @Test("Throws on invalid input")
    func throwsOnInvalidInput() {
        #expect(throws: ParserError.self) {
            try parser.parse(invalidJSON)
        }
    }

    @Test("Handles async operations")
    func asyncOperation() async throws {
        let result = await service.fetch()
        #expect(result.isValid)
    }
}
```

## Wrong

```swift
// DON'T: Using XCTest
import XCTest
class ParserTests: XCTestCase {
    func testParser() {
        XCTAssertTrue(true)  // Tautology
    }
}
```

```swift
// DON'T: Testing too many things
@Test func testEverything() {
    #expect(parser.parse(json) != nil)
    #expect(validator.validate(result))
    #expect(transformer.transform(result).count > 0)
}
```

## Parameterized Tests

```swift
@Test("Validates email formats", arguments: [
    "user@example.com",
    "test.user@domain.org",
    "name+tag@company.io"
])
func validatesEmail(_ email: String) {
    #expect(EmailValidator.isValid(email))
}
```

## Notes

- Swift Testing requires Xcode 16+ / macOS 15+
- Use `@MainActor` for tests touching UI state
- Structs preferred over classes (no inheritance needed)
- `@Test` attribute replaces `test` prefix naming convention
