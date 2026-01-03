# Service Layer Rules

> Pattern: `**/Services/**/*.swift`, `**/*Service.swift`, `**/*Manager.swift`

---

## Requirements

1. **Actor for shared mutable state** - Thread safety built-in
2. **Protocol-first** - Define interface before implementation
3. **Dependency injection** - No singletons, pass dependencies
4. **Typed errors** - Enum errors, not strings or NSError

## Right

```swift
protocol CameraServiceProtocol: Sendable {
    func startCapture() async throws
    func stopCapture() async
}

actor CameraService: CameraServiceProtocol {
    private var session: AVCaptureSession?

    func startCapture() async throws {
        // Actor isolation = thread-safe by default
        session = AVCaptureSession()
        try await configureSession()
    }
}
```

```swift
enum CameraError: Error {
    case permissionDenied
    case deviceNotFound
    case configurationFailed(underlying: Error)
}
```

## Wrong

```swift
// Singleton pattern - hard to test, hidden dependencies
class CameraService {
    static let shared = CameraService()
    private init() {}
}
```

```swift
// String errors - no type safety
func startCapture() throws {
    throw NSError(domain: "Camera", code: 1, userInfo: [
        NSLocalizedDescriptionKey: "Permission denied"
    ])
}
```
