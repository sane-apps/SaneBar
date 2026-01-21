# Model File Rules

> Pattern: `**/Models/**/*.swift`, `**/*Model.swift`, `**/Core/**/*.swift`

---

## Requirements

1. **Value types preferred** - Use `struct` over `class` when possible
2. **Codable for persistence** - Models that persist must conform to Codable
3. **Equatable for comparison** - Add Equatable for testability
4. **Sendable for concurrency** - Mark as Sendable if crossing actor boundaries

## Right

```swift
struct VideoProject: Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var createdAt: Date
    var clips: [VideoClip]
}
```

```swift
// Computed properties for derived state
extension VideoProject {
    var totalDuration: CMTime {
        clips.reduce(.zero) { $0 + $1.duration }
    }
}
```

## Wrong

```swift
// Using class when struct would work
class VideoProject {
    var id: UUID  // Should be let
    var name: String
}
```

```swift
// Missing Codable for persistent model
struct Settings {
    var theme: Theme
    // Won't be able to save/load!
}
```
