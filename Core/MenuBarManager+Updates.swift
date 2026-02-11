import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.Updates")

extension MenuBarManager {
    // MARK: - Update Checking

    /// Trigger the update check (User initiated)
    @objc func userDidClickCheckForUpdates() {
        logger.info("User requested update check")

        // Update last check time for record keeping
        settings.lastUpdateCheck = Date()
        saveSettings()

        // Activate the app so Sparkle's update window appears in front.
        // Menu bar apps (LSUIElement) don't auto-activate, so without this
        // the update window hides behind other apps (#54).
        NSApp.activate()

        updateService.checkForUpdates()
    }

    /// Sync the user's preference to Sparkle
    func syncUpdateConfiguration() {
        updateService.automaticallyChecksForUpdates = settings.checkForUpdatesAutomatically
    }
}
