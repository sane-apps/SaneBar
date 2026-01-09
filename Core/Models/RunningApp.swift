import AppKit

// MARK: - RunningApp Model

/// Represents a running app that might have a menu bar icon
/// Note: @unchecked Sendable because NSImage is thread-safe but not marked Sendable
struct RunningApp: Identifiable, Hashable, @unchecked Sendable {
    enum Policy: String, Codable, Sendable {
        case regular
        case accessory
        case prohibited
        case unknown
    }

    let id: String  // bundleIdentifier
    let name: String
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
