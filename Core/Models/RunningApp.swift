import AppKit

// MARK: - RunningApp Model

/// Represents a running app that might have a menu bar icon
struct RunningApp: Identifiable, Hashable, Sendable {
    let id: String  // bundleIdentifier
    let name: String
    // NSImage is not Sendable, but we only use it for UI.
    // For strict concurrency, we might wrap it or use @MainActor.
    // Since this is a simple value type for UI, we'll mark it unchecked Sendable for now
    // or better, exclude image from Sendable requirement if possible.
    // However, NSImage IS thread-safe generally.
    let icon: NSImage?

    init(id: String, name: String, icon: NSImage?) {
        self.id = id
        self.name = name
        self.icon = icon
    }

    init(app: NSRunningApplication) {
        self.id = app.bundleIdentifier ?? UUID().uuidString
        self.name = app.localizedName ?? "Unknown"
        self.icon = app.icon
    }
}
