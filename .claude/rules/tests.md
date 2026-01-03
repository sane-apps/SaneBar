# Test File Rules

> Pattern: `**/Tests/**/*.swift`, `**/Specs/**/*.swift`, `**/*Tests.swift`, `**/*Spec.swift`

---

## Requirements

1. **Use Swift Testing** - `#expect()` not `XCTAssert`
2. **No tautologies** - `#expect(true)` or `#expect(x == x)` are useless
3. **Test behavior, not implementation** - What it does, not how
4. **One assertion focus** - Each test verifies one thing

## Right

```swift
@Test func parsesValidJSON() throws {
    let result = try parser.parse(validJSON)
    #expect(result.count == 3)
    #expect(result[0].name == "expected")
}
```

```swift
@Test func throwsOnInvalidInput() {
    #expect(throws: ParserError.self) {
        try parser.parse(invalidJSON)
    }
}
```

## Wrong

```swift
@Test func testParser() {
    #expect(true)  // Tautology - tests nothing
}
```

```swift
@Test func testEverything() {
    // Tests parse, validate, transform, save - too many concerns
    #expect(parser.parse(json) != nil)
    #expect(validator.validate(result))
    #expect(transformer.transform(result).count > 0)
}
```
