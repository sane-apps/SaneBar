import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.Updates")

extension MenuBarManager {
    
    // MARK: - Update Checking

    /// Performs the update check and shows appropriate alert
    func performUpdateCheck() async {
        let result = await updateService.checkForUpdates()

        // Update last check time
        settings.lastUpdateCheck = Date()
        saveSettings()

        await MainActor.run {
            showUpdateResult(result)
        }
    }

    func showUpdateResult(_ result: UpdateResult) {
        let alert = NSAlert()

        switch result {
        case .upToDate:
            alert.messageText = "You're up to date!"
            alert.informativeText = "SaneBar is running the latest version."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "OK")

        case .updateAvailable(let version, let releaseURL):
            alert.messageText = "Update Available"
            alert.informativeText = "SaneBar \(version) is available. You're currently running \(currentAppVersion)."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "View Release")
            alert.addButton(withTitle: "Later")

            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(releaseURL)
            }
            return

        case .error(let message):
            alert.messageText = "Update Check Failed"
            alert.informativeText = message
            alert.alertStyle = .warning
            alert.addButton(withTitle: "OK")
        }

        alert.runModal()
    }

    var currentAppVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    /// Check for updates on launch if enabled, with rate limiting (max once per day)
    func checkForUpdatesOnLaunchIfEnabled() {
        guard settings.checkForUpdatesAutomatically else { return }

        // Rate limit: only check once per day
        if let lastCheck = settings.lastUpdateCheck {
            let hoursSinceLastCheck = Date().timeIntervalSince(lastCheck) / 3600
            if hoursSinceLastCheck < 24 {
                logger.debug("Skipping auto update check - last check was \(hoursSinceLastCheck) hours ago")
                return
            }
        }

        logger.info("Auto-checking for updates on launch")
        Task {
            let result = await updateService.checkForUpdates()
            settings.lastUpdateCheck = Date()
            saveSettings()

            // Only show alert if update is available (don't bother user with "up to date")
            if case .updateAvailable = result {
                await MainActor.run {
                    showUpdateResult(result)
                }
            }
        }
    }
}
