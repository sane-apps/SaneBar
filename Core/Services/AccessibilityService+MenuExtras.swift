import AppKit
import ApplicationServices
import os.log

extension AccessibilityService {

    // MARK: - Control Center & Menu Extra Enumeration

    /// Enumerates individual Control Center items (Battery, WiFi, Clock, etc.)
    /// Returns virtual RunningApp instances for each item with positions.
    ///
    /// Control Center owns multiple independent menu bar icons under a single bundle ID.
    /// This method extracts each as a separate entry using AXIdentifier and AXDescription.
    internal nonisolated static func enumerateControlCenterItems(pid: pid_t) -> [MenuBarItemPosition] {
        enumerateMenuExtraItems(pid: pid, ownerBundleId: "com.apple.controlcenter")
    }

    /// Enumerates individual system menu extra items owned by a single process (e.g. Control Center, SystemUIServer).
    /// Returns virtual RunningApp instances for each item with positions.
    internal nonisolated static func enumerateMenuExtraItems(pid: pid_t, ownerBundleId: String) -> [MenuBarItemPosition] {
        var results: [MenuBarItemPosition] = []

        let appElement = AXUIElementCreateApplication(pid)

        var extrasBar: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
        guard result == .success, let bar = extrasBar else { return results }
        guard let barElement = safeAXUIElement(bar) else { return results }

        var children: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)
        guard childResult == .success, let items = children as? [AXUIElement] else { return results }

        for item in items {
            func axString(_ value: CFTypeRef?) -> String? {
                if let s = value as? String { return s }
                if let attributed = value as? NSAttributedString { return attributed.string }
                return nil
            }

            // Get AXIdentifier (e.g., "com.apple.menuextra.wifi"). If it doesn't exist, it's usually not a user-facing item.
            var identifierValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifierValue)
            guard let rawIdentifier = axString(identifierValue)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawIdentifier.isEmpty else {
                continue
            }

            // SystemUIServer/Control Center can expose internal children; only keep real menu extras.
            if ownerBundleId.hasPrefix("com.apple."), !rawIdentifier.hasPrefix("com.apple.menuextra.") {
                continue
            }

            let identifier = rawIdentifier

            // Prefer stable, human labels. Title is often more useful than Description.
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleValue)

            var descValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXDescriptionAttribute as CFString, &descValue)

            let rawLabel = axString(titleValue) ?? axString(descValue) ?? identifier.components(separatedBy: ".").last ?? "Unknown"

            // Get position
            var positionValue: CFTypeRef?
            let posResult = AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)
            var xPos: CGFloat = 0
            if posResult == .success, let posValue = positionValue,
               let axPosValue = safeAXValue(posValue) {
                var point = CGPoint.zero
                if AXValueGetValue(axPosValue, .cgPoint, &point) {
                    xPos = point.x
                }
            }

            // Get Size (Width)
            var sizeValue: CFTypeRef?
            let sizeResult = AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue)
            var width: CGFloat = 0
            if sizeResult == .success, let sValue = sizeValue,
               let axSizeValue = safeAXValue(sValue) {
                var size = CGSize.zero
                if AXValueGetValue(axSizeValue, .cgSize, &size) {
                    width = size.width
                }
            }

            let virtualApp = RunningApp.menuExtraItem(ownerBundleId: ownerBundleId, name: rawLabel, identifier: identifier, xPosition: xPos, width: width)
            results.append(MenuBarItemPosition(app: virtualApp, x: xPos, width: width))
        }

        return results
    }
}
