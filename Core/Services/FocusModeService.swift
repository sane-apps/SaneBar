import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "FocusMode")

// MARK: - FocusModeServiceProtocol

/// @mockable
@MainActor
protocol FocusModeServiceProtocol {
    var currentFocusMode: String? { get }
    var isFocusModeActive: Bool { get }
    func configure(menuBarManager: MenuBarManager)
    func startMonitoring()
    func stopMonitoring()
}

// MARK: - FocusModeService

/// Service that monitors macOS Focus Mode changes and triggers menu bar visibility.
///
/// When Focus Mode changes to a mode in the trigger list, the hidden menu bar
/// items are automatically shown. This is useful for workflows like:
/// - Show communication icons when entering "Personal" Focus
/// - Show work apps when "Work" Focus activates
/// - Hide distractions when "Do Not Disturb" is on
///
/// Detection uses a hybrid approach:
/// 1. DistributedNotificationCenter for instant change detection
/// 2. File-based reading for Focus Mode NAME (not just on/off)
@MainActor
final class FocusModeService: NSObject, FocusModeServiceProtocol {

    // MARK: - Properties

    private var isMonitoring = false
    private weak var menuBarManager: MenuBarManager?
    private var monitoringTask: Task<Void, Never>?
    private var lastKnownFocusMode: String?

    /// Path to Focus Mode assertions (manually set modes)
    private let assertionsPath = NSString("~/Library/DoNotDisturb/DB/Assertions.json").expandingTildeInPath

    /// Path to Focus Mode configurations (all mode definitions)
    private let configurationsPath = NSString("~/Library/DoNotDisturb/DB/ModeConfigurations.json").expandingTildeInPath

    /// Current Focus Mode name, or nil if no Focus is active
    var currentFocusMode: String? {
        readCurrentFocusModeName()
    }

    /// Whether any Focus Mode is currently active
    var isFocusModeActive: Bool {
        currentFocusMode != nil
    }

    // MARK: - Configuration

    func configure(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        lastKnownFocusMode = currentFocusMode
        logger.info("Started Focus Mode monitoring. Current mode: \(self.currentFocusMode ?? "none")")

        // Monitor Focus Mode changes via DistributedNotificationCenter
        // This notification fires when Focus status changes system-wide
        monitoringTask = Task { [weak self] in
            let center = DistributedNotificationCenter.default()

            // Listen for DND state changes
            let dndNotifications = center.notifications(named: NSNotification.Name("com.apple.donotdisturb.stateChanged"))

            for await _ in dndNotifications {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.handleFocusModeChange()
                }
            }
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        monitoringTask?.cancel()
        monitoringTask = nil

        isMonitoring = false
        logger.info("Stopped Focus Mode monitoring")
    }

    // MARK: - Private - Focus Detection

    /// Reads the current Focus Mode name from system files.
    /// Returns nil if no Focus is active or files can't be read.
    private func readCurrentFocusModeName() -> String? {
        // Read assertions file to check if Focus is manually set
        guard let assertionsData = FileManager.default.contents(atPath: assertionsPath),
              let assertions = try? JSONSerialization.jsonObject(with: assertionsData) as? [[String: Any]],
              let firstAssertion = assertions.first,
              let details = firstAssertion["assertionDetails"] as? [String: Any],
              let modeIdentifier = details["assertionDetailsModeIdentifier"] as? String else {
            return nil
        }

        // Look up the mode name from configurations
        guard let configData = FileManager.default.contents(atPath: configurationsPath),
              let configurations = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
              let modeConfig = configurations[modeIdentifier] as? [String: Any],
              let mode = modeConfig["mode"] as? [String: Any],
              let modeName = mode["name"] as? String else {
            // Mode identifier exists but can't find name - return identifier as fallback
            logger.debug("Found Focus identifier but couldn't resolve name: \(modeIdentifier)")
            return modeIdentifier
        }

        return modeName
    }

    // MARK: - Private - Change Handling

    private func handleFocusModeChange() {
        guard let manager = menuBarManager else { return }

        // Check if feature is enabled
        guard manager.settings.showOnFocusModeChange else { return }

        let newFocusMode = currentFocusMode

        // Check if Focus actually changed
        guard newFocusMode != lastKnownFocusMode else {
            logger.debug("Focus notification received but mode unchanged")
            return
        }

        let oldMode = lastKnownFocusMode ?? "none"
        let newMode = newFocusMode ?? "none"
        lastKnownFocusMode = newFocusMode

        logger.info("Focus Mode changed: \(oldMode) → \(newMode)")

        // Check if new mode is in trigger list
        let triggerModes = manager.settings.triggerFocusModes

        if let mode = newFocusMode, triggerModes.contains(mode) {
            logger.info("Focus '\(mode)' is in trigger list - showing hidden items")
            manager.showHiddenItems()
        } else if newFocusMode == nil && triggerModes.contains("(Focus Off)") {
            // Special case: trigger when Focus turns OFF
            logger.info("Focus turned off and '(Focus Off)' is in trigger list - showing hidden items")
            manager.showHiddenItems()
        } else {
            logger.debug("Focus '\(newMode)' not in trigger list: \(triggerModes)")
        }
    }

    // MARK: - Utilities

    /// Get list of all configured Focus Modes on this Mac
    func getAvailableFocusModes() -> [String] {
        guard let configData = FileManager.default.contents(atPath: configurationsPath),
              let configurations = try? JSONSerialization.jsonObject(with: configData) as? [String: Any] else {
            return []
        }

        var modes: [String] = []
        for (_, value) in configurations {
            if let modeConfig = value as? [String: Any],
               let mode = modeConfig["mode"] as? [String: Any],
               let name = mode["name"] as? String {
                modes.append(name)
            }
        }

        return modes.sorted()
    }
}
