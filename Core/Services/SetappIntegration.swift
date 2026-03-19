import Foundation
import os.log

#if SETAPP
    import Setapp
#endif

enum SetappIntegration {
    private static let logger = Logger(subsystem: "com.sanebar.app", category: "Setapp")

    static func showReleaseNotesIfNeeded(delay: TimeInterval = 0) {
        #if SETAPP
            if delay > 0 {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    SetappManager.shared.showReleaseNotesWindowIfNeeded()
                }
            } else {
                SetappManager.shared.showReleaseNotesWindowIfNeeded()
            }
        #endif
    }

    static func showReleaseNotes() {
        #if SETAPP
            SetappManager.shared.showReleaseNotesWindow()
        #endif
    }

    static func reportMenuBarInteraction() {
        #if SETAPP
            SetappManager.shared.reportUsageEvent(.userInteraction)
        #endif
    }

    static func logPurchaseType() {
        #if SETAPP
            SetappManager.shared.requestPurchaseType { result in
                switch result {
                case .success(let purchaseType):
                    switch purchaseType {
                    case .membership:
                        logger.info("Setapp purchase type: membership")
                    case .singleApp:
                        logger.info("Setapp purchase type: single-app")
                    @unknown default:
                        logger.info("Setapp purchase type: unknown")
                    }
                case .failure(let error):
                    logger.error("Failed to fetch Setapp purchase type: \(error.localizedDescription, privacy: .public)")
                }
            }
        #endif
    }
}
