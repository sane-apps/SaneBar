import AppKit
import CoreGraphics

/// Fingerprint of the current display arrangement. Geometry cached under one
/// arrangement must never be served under another: serving cross-configuration
/// coordinates to recovery/move code is the root of the arrangement-drift
/// issue family (#136, #139, #153).
enum MenuBarDisplayConfiguration {
    @MainActor
    static func currentFingerprint() -> String {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return "no-screens" }
        return screens
            .map { screen in
                let frame = screen.frame
                let number = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? "?"
                return "\(number):\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width))x\(Int(frame.height))"
            }
            .sorted()
            .joined(separator: "|")
    }
}

@MainActor
final class MenuBarGeometryCache {
    struct Entry {
        let value: CGFloat
        let configID: String
    }

    /// Injectable so tests can simulate display-configuration changes.
    var configFingerprintProvider: () -> String = { MenuBarDisplayConfiguration.currentFingerprint() }

    private var separatorXEntry: Entry?
    private var separatorRightEdgeXEntry: Entry?
    private var mainStatusItemXEntry: Entry?
    private var alwaysHiddenSeparatorXEntry: Entry?
    private var alwaysHiddenSeparatorRightEdgeXEntry: Entry?

    var hasLoggedStaleSeparatorRightEdgeFallback = false
    var hasLoggedStaleMainStatusItemFallback = false

    nonisolated static func entryValueIfCurrent(_ entry: Entry?, currentConfigID: String) -> CGFloat? {
        guard let entry, entry.configID == currentConfigID else { return nil }
        return entry.value
    }

    private func read(_ entry: Entry?) -> CGFloat? {
        Self.entryValueIfCurrent(entry, currentConfigID: configFingerprintProvider())
    }

    private func write(_ value: CGFloat?) -> Entry? {
        value.map { Entry(value: $0, configID: configFingerprintProvider()) }
    }

    var lastKnownSeparatorX: CGFloat? {
        get { read(separatorXEntry) }
        set { separatorXEntry = write(newValue) }
    }

    var lastKnownSeparatorRightEdgeX: CGFloat? {
        get { read(separatorRightEdgeXEntry) }
        set { separatorRightEdgeXEntry = write(newValue) }
    }

    var lastKnownMainStatusItemX: CGFloat? {
        get { read(mainStatusItemXEntry) }
        set { mainStatusItemXEntry = write(newValue) }
    }

    var lastKnownAlwaysHiddenSeparatorX: CGFloat? {
        get { read(alwaysHiddenSeparatorXEntry) }
        set { alwaysHiddenSeparatorXEntry = write(newValue) }
    }

    var lastKnownAlwaysHiddenSeparatorRightEdgeX: CGFloat? {
        get { read(alwaysHiddenSeparatorRightEdgeXEntry) }
        set { alwaysHiddenSeparatorRightEdgeXEntry = write(newValue) }
    }

    func clearSeparatorGeometry() {
        mainStatusItemXEntry = nil
        separatorXEntry = nil
        separatorRightEdgeXEntry = nil
        alwaysHiddenSeparatorXEntry = nil
        alwaysHiddenSeparatorRightEdgeXEntry = nil
    }
}
