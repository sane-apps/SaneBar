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
        
        updateService.checkForUpdates()
    }

    /// Sync the user's preference to Sparkle
    func syncUpdateConfiguration() {
        updateService.automaticallyChecksForUpdates = settings.checkForUpdatesAutomatically
    }
}
