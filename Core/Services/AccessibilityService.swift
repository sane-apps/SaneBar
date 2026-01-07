import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityService")

// MARK: - AccessibilityService

/// Service for interacting with other apps' menu bar items via Accessibility API.
///
/// **Apple Best Practice**:
/// - Uses standard `AXUIElement` API.
/// - Does NOT use `CGEvent` cursor hijacking (mouse simulation).
/// - Does NOT use private APIs.
/// - Handles `AXPress` actions to simulate clicks natively.
@MainActor
final class AccessibilityService: ObservableObject {

    // MARK: - Singleton

    static let shared = AccessibilityService()

    // MARK: - API Verification

    /// Checks if we have accessibility permissions
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    // MARK: - Actions

    /// Perform a "Virtual Click" on a menu bar item
    /// - Parameter bundleID: The Bundle ID of the target app (e.g., "com.slack.Slack")
    /// - Returns: True if successful, False if not found or failed
    func clickMenuBarItem(for bundleID: String) -> Bool {
        logger.info("Attempting to click menu bar item for: \(bundleID)")

        guard isTrusted else {
            logger.error("Accessibility permission not granted")
            return false
        }

        // 1. Find the running application
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            logger.warning("App not running: \(bundleID)")
            return false
        }

        // 2. Create accessibility element for the app
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        // 3. Find the menu bar extras (status items)
        // Note: Status items are often children of the 'AXExtrasMenuBar' attribute of the Application,
        // OR they are in the System Wide 'AXExtrasMenuBar'.
        // Modern apps (NSStatusItem) often live in the System Wide space.

        if clickSystemWideItem(for: app.processIdentifier) {
            return true
        }

        return false
    }

    // MARK: - System Wide Search

    private func clickSystemWideItem(for targetPID: pid_t) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var extrasMenuBar: CFTypeRef?

        // Get the system menu bar (where status items live)
        let result = AXUIElementCopyAttributeValue(systemWide, kAXExtrasMenuBarAttribute as CFString, &extrasMenuBar)

        guard result == .success, let menuBar = extrasMenuBar else {
            logger.debug("Could not find System Extras Menu Bar")
            return false
        }

        // Safe cast from CFTypeRef
        // swiftlint:disable:next force_cast
        let menuBarElement = menuBar as! AXUIElement
        var children: CFTypeRef?

        // Get all status items
        let childrenResult = AXUIElementCopyAttributeValue(menuBarElement, kAXChildrenAttribute as CFString, &children)

        guard childrenResult == .success, let items = children as? [AXUIElement] else {
            logger.debug("No items in Extras Menu Bar")
            return false
        }

        // Iterate and find the one belonging to our target PID
        for item in items {
            var pid: pid_t = 0
            AXUIElementGetPid(item, &pid)

            if pid == targetPID {
                // Found it! Perform the action.
                logger.info("Found matching status item for PID \(pid)")
                return performPress(on: item)
            }
        }

        logger.warning("Could not find status item for PID \(targetPID) in system bar")
        return false
    }

    // MARK: - Interaction

    private func performPress(on element: AXUIElement) -> Bool {
        // AXPress is the standard action for buttons/menu items
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)

        if error == .success {
            logger.info("AXPress successful")
            return true
        } else {
            logger.error("AXPress failed with error: \(error.rawValue)")
            return false
        }
    }
}
