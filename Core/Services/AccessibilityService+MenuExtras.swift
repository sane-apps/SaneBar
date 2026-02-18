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
        let roots = menuBarRoots(for: appElement, ownerBundleId: ownerBundleId)
        guard !roots.isEmpty else { return results }
        let items = roots.flatMap { collectMenuBarItems(from: $0) }
        guard !items.isEmpty else { return results }

        for item in items {
            func axString(_ value: CFTypeRef?) -> String? {
                if let s = value as? String { return s }
                if let attributed = value as? NSAttributedString { return attributed.string }
                return nil
            }

            // Get AXIdentifier (e.g., "com.apple.menuextra.wifi"). Some menu extras
            // (notably Siri on some macOS builds) may not provide a canonical identifier.
            var identifierValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifierValue)
            let rawIdentifier = axString(identifierValue)?.trimmingCharacters(in: .whitespacesAndNewlines)

            // Prefer stable, human labels. Title is often more useful than Description.
            var titleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleValue)

            var descValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXDescriptionAttribute as CFString, &descValue)

            let rawLabel = axString(titleValue) ?? axString(descValue) ?? rawIdentifier?.components(separatedBy: ".").last ?? "Unknown"

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

            guard let identifier = canonicalMenuExtraIdentifier(
                ownerBundleId: ownerBundleId,
                rawIdentifier: rawIdentifier,
                rawLabel: rawLabel,
                width: width
            ) else {
                continue
            }

            let virtualApp = RunningApp.menuExtraItem(ownerBundleId: ownerBundleId, name: rawLabel, identifier: identifier, xPosition: xPos, width: width)
            results.append(MenuBarItemPosition(app: virtualApp, x: xPos, width: width))
        }

        return results
    }

    /// Resolve candidate menu bar roots. Prefer AXExtrasMenuBar; allow AXMenuBar fallback
    /// only for known Apple owners where AXExtrasMenuBar is missing on some OS builds.
    private nonisolated static func menuBarRoots(for appElement: AXUIElement, ownerBundleId: String) -> [AXUIElement] {
        var roots: [AXUIElement] = []

        var extrasBar: CFTypeRef?
        let extrasResult = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
        if extrasResult == .success, let extrasBar, let barElement = safeAXUIElement(extrasBar) {
            roots.append(barElement)
        }

        let allowMenuBarFallback = ownerBundleId == "com.apple.systemuiserver" || ownerBundleId == "com.apple.controlcenter"
        if roots.isEmpty, allowMenuBarFallback {
            var menuBar: CFTypeRef?
            let menuBarResult = AXUIElementCopyAttributeValue(appElement, kAXMenuBarAttribute as CFString, &menuBar)
            if menuBarResult == .success, let menuBar, let menuBarElement = safeAXUIElement(menuBar) {
                roots.append(menuBarElement)
            }
        }

        return roots
    }

    /// Collect AXMenuBarItem descendants from a root menu bar element.
    private nonisolated static func collectMenuBarItems(from root: AXUIElement) -> [AXUIElement] {
        var collected: [AXUIElement] = []

        func visit(_ node: AXUIElement) {
            var roleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(node, kAXRoleAttribute as CFString, &roleValue)
            let role = roleValue as? String
            if role == (kAXMenuBarItemRole as String) || role == "AXMenuBarItem" {
                collected.append(node)
                return
            }

            var childrenValue: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(node, kAXChildrenAttribute as CFString, &childrenValue)
            guard result == .success, let children = childrenValue as? [AXUIElement] else { return }
            for child in children {
                visit(child)
            }
        }

        visit(root)
        return collected
    }

    /// Resolve a stable menu-extra identifier for Apple-owned extras.
    /// Falls back to label-based mapping for known items (e.g. Siri) when AXIdentifier is missing.
    internal nonisolated static func canonicalMenuExtraIdentifier(
        ownerBundleId: String,
        rawIdentifier: String?,
        rawLabel: String?,
        width: CGFloat
    ) -> String? {
        let normalizedIdentifier = rawIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLabel = rawLabel?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Non-Apple owners: keep whatever AXIdentifier we have.
        if !ownerBundleId.hasPrefix("com.apple.") {
            guard let normalizedIdentifier, !normalizedIdentifier.isEmpty else { return nil }
            return normalizedIdentifier
        }

        if let normalizedIdentifier, !normalizedIdentifier.isEmpty {
            if normalizedIdentifier.hasPrefix("com.apple.menuextra.") {
                return normalizedIdentifier.lowercased()
            }
            if let mapped = mapKnownAppleMenuExtra(from: normalizedIdentifier) {
                return mapped
            }
        }

        // For Apple owners, only trust label fallback when the item is actually visible.
        guard width > 0 else { return nil }
        if let normalizedLabel, let mapped = mapKnownAppleMenuExtra(from: normalizedLabel) {
            return mapped
        }

        return nil
    }

    private nonisolated static func mapKnownAppleMenuExtra(from raw: String) -> String? {
        let lower = raw.lowercased()
        let compact = lower.replacingOccurrences(
            of: "[^a-z0-9]+",
            with: "",
            options: .regularExpression
        )
        let components = lower
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
        let componentSet = Set(components)

        let aliases: [String: String] = [
            "battery": "com.apple.menuextra.battery",
            "wifi": "com.apple.menuextra.wifi",
            "bluetooth": "com.apple.menuextra.bluetooth",
            "clock": "com.apple.menuextra.clock",
            "airdrop": "com.apple.menuextra.airdrop",
            "focus": "com.apple.menuextra.focusmode",
            "focusmode": "com.apple.menuextra.focusmode",
            "controlcenter": "com.apple.menuextra.controlcenter",
            "display": "com.apple.menuextra.display",
            "sound": "com.apple.menuextra.sound",
            "airplay": "com.apple.menuextra.airplay",
            "nowplaying": "com.apple.menuextra.now-playing",
            "siri": "com.apple.menuextra.siri",
            "spotlight": "com.apple.menuextra.spotlight"
        ]

        for (token, identifier) in aliases {
            if lower == token || compact == token || componentSet.contains(token) {
                return identifier
            }
        }

        return nil
    }
}
