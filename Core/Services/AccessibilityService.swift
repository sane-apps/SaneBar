import Foundation
import AppKit
@preconcurrency import ApplicationServices

// MARK: - AccessibilityError

enum AccessibilityError: LocalizedError {
    case notTrusted
    case menuBarNotFound
    case scanFailed(AXError)
    case attributeNotFound(String)

    var errorDescription: String? {
        switch self {
        case .notTrusted:
            return "Accessibility permission not granted"
        case .menuBarNotFound:
            return "Could not find menu bar extras"
        case .scanFailed(let error):
            return "Scan failed with error: \(error.rawValue)"
        case .attributeNotFound(let attr):
            return "Attribute not found: \(attr)"
        }
    }
}

// MARK: - AccessibilityService

/// Service for scanning menu bar items via Accessibility API
@MainActor
final class AccessibilityService: ObservableObject {

    @Published private(set) var isScanning = false
    @Published private(set) var lastScanDate: Date?
    @Published private(set) var lastError: AccessibilityError?

    // MARK: - Permission Checking

    /// Check if the app has accessibility permissions
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Request accessibility permissions (opens System Settings)
    nonisolated func requestPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Menu Bar Scanning

    /// Scan for all menu bar status items
    func scanMenuBarItems() async throws -> [StatusItemModel] {
        guard isTrusted else {
            throw AccessibilityError.notTrusted
        }

        isScanning = true
        defer {
            isScanning = false
            lastScanDate = Date()
        }

        // Get the system-wide accessibility element
        let systemWide = AXUIElementCreateSystemWide()

        // Get the extras menu bar (right side of menu bar with status items)
        var extrasMenuBarValue: CFTypeRef?
        let extrasResult = AXUIElementCopyAttributeValue(
            systemWide,
            "AXExtrasMenuBar" as CFString,
            &extrasMenuBarValue
        )

        guard extrasResult == .success, let extrasMenuBar = extrasMenuBarValue else {
            // Fallback: try to get menu bar via focused app
            return try await scanViaApplications()
        }

        // Get children of the extras menu bar
        return try getStatusItemsFromElement(extrasMenuBar as! AXUIElement)
    }

    // MARK: - Private Helpers

    /// Extract status items from an AX element (menu bar)
    private func getStatusItemsFromElement(_ menuBar: AXUIElement) throws -> [StatusItemModel] {
        var childrenValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            menuBar,
            kAXChildrenAttribute as CFString,
            &childrenValue
        )

        guard result == .success, let children = childrenValue as? [AXUIElement] else {
            throw AccessibilityError.scanFailed(result)
        }

        var items: [StatusItemModel] = []

        for (index, child) in children.enumerated() {
            let item = createStatusItem(from: child, position: index)
            items.append(item)
        }

        return items
    }

    /// Create a StatusItemModel from an AX element
    private func createStatusItem(from element: AXUIElement, position: Int) -> StatusItemModel {
        // Get title
        var titleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleValue)
        let title = titleValue as? String

        // Get description (fallback for title)
        var descValue: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descValue)
        let description = descValue as? String

        // Get PID to determine bundle identifier
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)

        var bundleId: String?
        if pid > 0 {
            if let app = NSRunningApplication(processIdentifier: pid) {
                bundleId = app.bundleIdentifier
            }
        }

        return StatusItemModel(
            bundleIdentifier: bundleId,
            title: title ?? description,
            iconHash: nil, // Icon extraction would require more complex handling
            position: position,
            section: .alwaysVisible,
            isVisible: true
        )
    }

    /// Fallback: scan via running applications
    private func scanViaApplications() async throws -> [StatusItemModel] {
        var items: [StatusItemModel] = []
        let runningApps = NSWorkspace.shared.runningApplications

        // Filter to apps that might have status items
        let statusBarApps = runningApps.filter { app in
            // Apps with activation policy .accessory or .regular might have status items
            app.activationPolicy == .accessory || app.activationPolicy == .regular
        }

        for (index, app) in statusBarApps.prefix(20).enumerated() {
            guard let bundleId = app.bundleIdentifier else { continue }

            // Try to get the app's menu bar element
            let appElement = AXUIElementCreateApplication(app.processIdentifier)

            var menuBarValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(
                appElement,
                kAXExtrasMenuBarAttribute as CFString,
                &menuBarValue
            )

            if result == .success {
                // This app has menu bar extras
                let item = StatusItemModel(
                    bundleIdentifier: bundleId,
                    title: app.localizedName,
                    position: index,
                    section: .alwaysVisible,
                    isVisible: true
                )
                items.append(item)
            }
        }

        return items
    }

    // MARK: - Item Manipulation

    /// Get the AX element for a specific status item (for hiding/showing)
    func elementForItem(_ item: StatusItemModel) async throws -> AXUIElement? {
        guard isTrusted else { throw AccessibilityError.notTrusted }

        let systemWide = AXUIElementCreateSystemWide()

        var extrasMenuBarValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWide,
            "AXExtrasMenuBar" as CFString,
            &extrasMenuBarValue
        )

        guard result == .success, let extrasMenuBar = extrasMenuBarValue as! AXUIElement? else {
            return nil
        }

        var childrenValue: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(
            extrasMenuBar,
            kAXChildrenAttribute as CFString,
            &childrenValue
        )

        guard childResult == .success, let children = childrenValue as? [AXUIElement] else {
            return nil
        }

        // Find matching element by position or composite key
        if item.position < children.count {
            return children[item.position]
        }

        return nil
    }

    /// Get the position of an AX element
    func getPosition(of element: AXUIElement) throws -> CGPoint {
        var positionValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXPositionAttribute as CFString,
            &positionValue
        )

        guard result == .success else {
            throw AccessibilityError.attributeNotFound("AXPosition")
        }

        var point = CGPoint.zero
        if AXValueGetValue(positionValue as! AXValue, .cgPoint, &point) {
            return point
        }

        throw AccessibilityError.attributeNotFound("AXPosition")
    }

    /// Get the size of an AX element
    func getSize(of element: AXUIElement) throws -> CGSize {
        var sizeValue: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSizeAttribute as CFString,
            &sizeValue
        )

        guard result == .success else {
            throw AccessibilityError.attributeNotFound("AXSize")
        }

        var size = CGSize.zero
        if AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) {
            return size
        }

        throw AccessibilityError.attributeNotFound("AXSize")
    }
}
