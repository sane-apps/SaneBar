import Foundation
import Sparkle
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "UpdateService")

/// Wrapper around Sparkle's SPUStandardUpdaterController.
/// Handles app updates securely and privately.
@MainActor
class UpdateService: NSObject, ObservableObject {

    // MARK: - Properties

    private var updaterController: SPUStandardUpdaterController?

    // MARK: - Initialization

    override init() {
        super.init()
        
        // SPUStandardUpdaterController must be retained by the app.
        // startingUpdater: true starts the scheduled checks logic immediately.
        self.updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        
        logger.info("Sparkle updater initialized")
        
        // Privacy check (Sanity check for developers)
        if let profiling = Bundle.main.object(forInfoDictionaryKey: "SUEnableSystemProfiling") as? Bool, profiling == true {
            logger.fault("CRITICAL: SUEnableSystemProfiling is ENABLED. This violates the privacy policy.")
        }
    }

    // MARK: - Public API

    /// Trigger a user-initiated update check.
    /// This shows the Sparkle UI (Standard User Driver).
    func checkForUpdates() {
        logger.info("User triggered check for updates")
        updaterController?.checkForUpdates(nil)
    }
    
    /// Check if updates are handled automatically (just a pass-through property for UI if needed)
    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? false }
        set { updaterController?.updater.automaticallyChecksForUpdates = newValue }
    }
}
