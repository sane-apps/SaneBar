import AppKit

// MARK: - RunningApp Model

/// Represents a running app that might have a menu bar icon
struct RunningApp: Identifiable, Hashable, Sendable {
    enum Policy: String, Codable, Sendable {
        case regular
        case accessory
        case prohibited
        case unknown
    }

    let id: String  // bundleIdentifier
    let name: String
    // NSImage is not Sendable, but we only use it for UI.
    // For strict concurrency, we might wrap it or use @MainActor.
    // Since this is a simple value type for UI, we'll mark it unchecked Sendable for now
    // or better, exclude image from Sendable requirement if possible.
    // However, NSImage IS thread-safe generally.
    let icon: NSImage?
    let policy: Policy

    init(id: String, name: String, icon: NSImage?, policy: Policy = .regular) {
        self.id = id
        self.name = name
        self.icon = icon
        self.policy = policy
    }

    init(app: NSRunningApplication) {
        self.id = app.bundleIdentifier ?? UUID().uuidString
        self.name = app.localizedName ?? "Unknown"
        self.icon = app.icon
        switch app.activationPolicy {
        case .regular:
            self.policy = .regular
        case .accessory:
            self.policy = .accessory
        case .prohibited:
            self.policy = .prohibited
        @unknown default:
            self.policy = .unknown
        }
    }
}
