import AppKit
import ApplicationServices
import os.log

private let menuExtrasLogger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityService.MenuExtras")

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
    internal nonisolated static func enumerateMenuExtraItems(
        pid: pid_t,
        ownerBundleId: String,
        allowThirdPartyMenuBarFallback: Bool = false
    ) -> [MenuBarItemPosition] {
        var results: [MenuBarItemPosition] = []

        let appElement = AXUIElementCreateApplication(pid)
        let roots = menuBarRoots(
            for: appElement,
            ownerBundleId: ownerBundleId,
            allowThirdPartyMenuBarFallback: allowThirdPartyMenuBarFallback
        )
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

            var subroleValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXSubroleAttribute as CFString, &subroleValue)

            let rawLabel = axString(titleValue) ?? axString(descValue) ?? rawIdentifier?.components(separatedBy: ".").last ?? "Unknown"
            let rawSubrole = axString(subroleValue)?.trimmingCharacters(in: .whitespacesAndNewlines)

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

            if allowThirdPartyMenuBarFallback,
               !ownerBundleId.hasPrefix("com.apple."),
               !shouldAcceptThirdPartyTopBarFallbackItem(
                   rawIdentifier: rawIdentifier,
                   rawSubrole: rawSubrole
               ) {
                continue
            }

            guard let identifier = canonicalMenuExtraIdentifier(
                ownerBundleId: ownerBundleId,
                rawIdentifier: rawIdentifier,
                rawLabel: rawLabel,
                width: width,
                allowThirdPartyLabelFallback: allowThirdPartyMenuBarFallback
            ) else {
                continue
            }

            let virtualApp = RunningApp.menuExtraItem(ownerBundleId: ownerBundleId, name: rawLabel, identifier: identifier, xPosition: xPos, width: width)
            results.append(MenuBarItemPosition(app: virtualApp, x: xPos, width: width))
        }

        return results
    }

    internal nonisolated static func shouldAcceptThirdPartyTopBarFallbackItem(
        rawIdentifier: String?,
        rawSubrole: String?
    ) -> Bool {
        let normalizedSubrole = rawSubrole?.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedSubrole == "AXMenuExtra" {
            return true
        }

        guard let normalizedIdentifier = rawIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalizedIdentifier.isEmpty else {
            return false
        }

        if normalizedIdentifier.hasPrefix("_NS:") {
            return false
        }

        if bundleIdentifierFallback(fromAXIdentifier: normalizedIdentifier) != nil {
            return true
        }

        guard !normalizedIdentifier.contains(" "),
              normalizedIdentifier.contains(".") else {
            return false
        }

        return normalizedIdentifier.range(
            of: "^[A-Za-z0-9._:-]+$",
            options: .regularExpression
        ) != nil
    }

    /// Resolve candidate menu bar roots. Prefer AXExtrasMenuBar; allow AXMenuBar fallback
    /// only for known Apple owners where AXExtrasMenuBar is missing on some OS builds.
    private nonisolated static func menuBarRoots(
        for appElement: AXUIElement,
        ownerBundleId: String,
        allowThirdPartyMenuBarFallback: Bool
    ) -> [AXUIElement] {
        var roots: [AXUIElement] = []

        var extrasBar: CFTypeRef?
        let extrasResult = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
        if extrasResult == .success, let extrasBar, let barElement = safeAXUIElement(extrasBar) {
            roots.append(barElement)
        }

        let allowMenuBarFallback =
            ownerBundleId == "com.apple.systemuiserver" ||
            ownerBundleId == "com.apple.controlcenter" ||
            allowThirdPartyMenuBarFallback
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
        width: CGFloat,
        allowThirdPartyLabelFallback: Bool = false
    ) -> String? {
        let normalizedIdentifier = rawIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedLabel = rawLabel?.trimmingCharacters(in: .whitespacesAndNewlines)

        // Non-Apple owners: keep whatever AXIdentifier we have.
        if !ownerBundleId.hasPrefix("com.apple.") {
            if let normalizedIdentifier, !normalizedIdentifier.isEmpty {
                return normalizedIdentifier
            }

            guard allowThirdPartyLabelFallback, width > 0,
                  let normalizedLabel else { return nil }

            let slug = normalizedLabel
                .lowercased()
                .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
            guard !slug.isEmpty else { return nil }
            return "\(ownerBundleId).menuextra.\(slug)"
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

    // MARK: - Status Item Targeting & Verification Helpers

    nonisolated func captureStatusItemReactionSnapshot(
        item: AXUIElement,
        appElement: AXUIElement
    ) -> StatusItemReactionSnapshot {
        StatusItemReactionSnapshot(
            shownMenuPresent: shownMenuPresence(item: item, appElement: appElement),
            focusedWindowPresent: focusedWindowPresence(appElement),
            windowCount: appWindowCount(appElement),
            windowServerWindowCount: appWindowServerCount(appElement),
            expanded: boolAttribute(kAXExpandedAttribute as CFString, on: item),
            selected: boolAttribute(kAXSelectedAttribute as CFString, on: item)
        )
    }

    nonisolated func shownMenuPresence(
        item: AXUIElement,
        appElement: AXUIElement
    ) -> Bool? {
        let itemShownMenu = elementPresenceAttribute(kAXShownMenuUIElementAttribute as CFString, on: item)
        let appShownMenu = elementPresenceAttribute(kAXShownMenuUIElementAttribute as CFString, on: appElement)

        switch (itemShownMenu, appShownMenu) {
        case (.some(let value), _):
            return value
        case (.none, .some(let value)):
            return value
        case (.none, .none):
            return nil
        }
    }

    nonisolated func focusedWindowPresence(_ appElement: AXUIElement) -> Bool? {
        elementPresenceAttribute(kAXFocusedWindowAttribute as CFString, on: appElement)
    }

    nonisolated func appWindowCount(_ appElement: AXUIElement) -> Int? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &value)
        switch error {
        case .success:
            return (value as? [Any])?.count ?? 0
        case .noValue:
            return 0
        default:
            return nil
        }
    }

    nonisolated func appWindowServerCount(_ appElement: AXUIElement) -> Int? {
        var pid: pid_t = 0
        guard AXUIElementGetPid(appElement, &pid) == .success, pid > 0 else {
            return nil
        }

        guard let infos = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        return infos.filter { info in
            (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid
        }.count
    }

    nonisolated func elementPresenceAttribute(_ attribute: CFString, on element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        switch error {
        case .success:
            return value != nil
        case .noValue:
            return false
        default:
            return nil
        }
    }

    nonisolated func boolAttribute(_ attribute: CFString, on element: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        let error = AXUIElementCopyAttributeValue(element, attribute, &value)
        switch error {
        case .success:
            if let boolValue = value as? Bool {
                return boolValue
            }
            if let numberValue = value as? NSNumber {
                return numberValue.boolValue
            }
            return nil
        case .noValue:
            return false
        default:
            return nil
        }
    }

    nonisolated static func hasComparableReactionSignals(
        before: StatusItemReactionSnapshot,
        after: StatusItemReactionSnapshot
    ) -> Bool {
        (before.shownMenuPresent != nil && after.shownMenuPresent != nil) ||
            (before.focusedWindowPresent != nil && after.focusedWindowPresent != nil) ||
            (before.windowCount != nil && after.windowCount != nil) ||
            (before.windowServerWindowCount != nil && after.windowServerWindowCount != nil) ||
            (before.expanded != nil && after.expanded != nil) ||
            (before.selected != nil && after.selected != nil)
    }

    nonisolated static func observableReactionDescription(
        before: StatusItemReactionSnapshot,
        after: StatusItemReactionSnapshot
    ) -> String? {
        if before.shownMenuPresent == false, after.shownMenuPresent == true {
            return "shownMenu"
        }
        if before.focusedWindowPresent == false, after.focusedWindowPresent == true {
            return "focusedWindow"
        }
        if let beforeWindowCount = before.windowCount,
           let afterWindowCount = after.windowCount,
           afterWindowCount > beforeWindowCount {
            return "windowCount \(beforeWindowCount)->\(afterWindowCount)"
        }
        if let beforeWindowServerWindowCount = before.windowServerWindowCount,
           let afterWindowServerWindowCount = after.windowServerWindowCount,
           afterWindowServerWindowCount > beforeWindowServerWindowCount {
            return "windowServerWindowCount \(beforeWindowServerWindowCount)->\(afterWindowServerWindowCount)"
        }
        if before.expanded != true, after.expanded == true {
            return "expanded"
        }
        if before.selected != true, after.selected == true {
            return "selected"
        }
        return nil
    }

    /// Lightweight position query for polling loops (e.g. `waitForIconOnScreen`).
    /// Returns the center point of the icon's AX frame, or nil if unavailable.
    nonisolated func menuBarItemPosition(bundleID: String, menuExtraId: String? = nil, statusItemIndex: Int? = nil) -> CGPoint? {
        guard let frame = getMenuBarIconFrame(bundleID: bundleID, menuExtraId: menuExtraId, statusItemIndex: statusItemIndex) else {
            return nil
        }
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    nonisolated func getMenuBarIconFrame(
        bundleID: String,
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil,
        preferredCenterX: CGFloat? = nil
    ) -> CGRect? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            menuExtrasLogger.error("🔧 getMenuBarIconFrame: App not found for bundleID: \(bundleID, privacy: .private)")
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var extrasBar: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
        guard result == .success, let bar = extrasBar else {
            menuExtrasLogger.error("🔧 getMenuBarIconFrame: App \(bundleID, privacy: .private) has no AXExtrasMenuBar (Error: \(result.rawValue))")
            return nil
        }
        guard let barElement = safeAXUIElement(bar) else { return nil }

        var children: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)
        guard childResult == .success, let items = children as? [AXUIElement], !items.isEmpty else {
            menuExtrasLogger.error("🔧 getMenuBarIconFrame: No items found in AXExtrasMenuBar for \(bundleID, privacy: .private)")
            return nil
        }

        let targetItem = resolvedTargetStatusItem(
            from: items,
            bundleID: bundleID,
            menuExtraId: menuExtraId,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX
        )

        guard let item = targetItem else { return nil }
        return frameForStatusItem(item)
    }

    nonisolated func frameForStatusItem(_ item: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        let posResult = AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)
        guard posResult == .success, let posValue = positionValue else { return nil }
        guard CFGetTypeID(posValue) == AXValueGetTypeID() else { return nil }

        var origin = CGPoint.zero
        guard let axPosValue = safeAXValue(posValue),
              AXValueGetValue(axPosValue, .cgPoint, &origin) else { return nil }

        var sizeValue: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue)
        var size = CGSize(width: 22, height: 22)
        if sizeResult == .success, let sizeVal = sizeValue, let axSizeVal = safeAXValue(sizeVal) {
            var s = CGSize.zero
            if AXValueGetValue(axSizeVal, .cgSize, &s) {
                size = CGSize(width: max(1, s.width), height: max(1, s.height))
            }
        }

        return CGRect(origin: origin, size: size)
    }

    nonisolated func resolvedTargetStatusItem(
        from items: [AXUIElement],
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?,
        preferredCenterX: CGFloat?
    ) -> AXUIElement? {
        if let extraId = menuExtraId {
            for item in items {
                var identifierValue: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifierValue)
                if let identifier = identifierValue as? String, identifier == extraId {
                    return item
                }
            }
            menuExtrasLogger.error("🔧 Could not find status item with identifier: \(extraId, privacy: .private)")
            if items.count == 1 {
                menuExtrasLogger.info("🔧 Single status item available for \(bundleID, privacy: .private); using it after identifier miss")
                return items[0]
            }
            guard Self.shouldContinueStatusItemResolutionAfterIdentifierMiss(
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            ) else {
                return nil
            }
            menuExtrasLogger.info("🔧 Falling back to positional status item resolution for \(bundleID, privacy: .private)")
        }

        guard items.count > 1 else { return items.first }
        guard let preferredCenterX else {
            if let statusItemIndex, items.indices.contains(statusItemIndex) {
                return items[statusItemIndex]
            }
            menuExtrasLogger.warning("🔧 getMenuBarIconFrame: App has \(items.count) status items but no menuExtraId/statusItemIndex/preferredCenterX — using first item (may be wrong)")
            return items[0]
        }

        let candidates = items.enumerated().compactMap { index, item -> (index: Int, midX: CGFloat)? in
            guard let frame = frameForStatusItem(item) else { return nil }
            return (index, frame.midX)
        }

        guard !candidates.isEmpty else {
            menuExtrasLogger.warning("🔧 getMenuBarIconFrame: App has \(items.count) status items but none had a readable frame for nearest-match selection")
            return items[0]
        }

        let candidateMidXs = candidates.map(\.midX)
        guard let bestCandidateIndex = Self.resolvedStatusItemIndex(
            midXs: candidateMidXs,
            statusItemIndex: statusItemIndex,
            preferredCenterX: preferredCenterX
        ) else {
            return items[0]
        }

        let resolvedIndex = candidates[bestCandidateIndex].index
        menuExtrasLogger.info("🔧 Resolved nearest status item for \(bundleID, privacy: .private) at index \(resolvedIndex, privacy: .public)")
        return items[resolvedIndex]
    }

    internal nonisolated static func shouldContinueStatusItemResolutionAfterIdentifierMiss(
        statusItemIndex: Int?,
        preferredCenterX: CGFloat?
    ) -> Bool {
        statusItemIndex != nil || preferredCenterX != nil
    }

    nonisolated static func resolvedStatusItemIndex(
        midXs: [CGFloat],
        statusItemIndex: Int?,
        preferredCenterX: CGFloat?,
        hintTolerance: CGFloat = 18
    ) -> Int? {
        guard !midXs.isEmpty else { return nil }

        if let statusItemIndex, midXs.indices.contains(statusItemIndex) {
            guard let preferredCenterX else {
                return statusItemIndex
            }

            let hintedMidX = midXs[statusItemIndex]
            if abs(hintedMidX - preferredCenterX) <= hintTolerance {
                return statusItemIndex
            }
        }

        return preferredStatusItemIndex(midXs: midXs, preferredCenterX: preferredCenterX)
    }

    nonisolated static func preferredStatusItemIndex(midXs: [CGFloat], preferredCenterX: CGFloat?) -> Int? {
        guard !midXs.isEmpty else { return nil }
        guard let preferredCenterX else { return 0 }
        return midXs.enumerated().min { lhs, rhs in
            let lhsDistance = abs(lhs.element - preferredCenterX)
            let rhsDistance = abs(rhs.element - preferredCenterX)
            if lhsDistance == rhsDistance {
                return lhs.offset < rhs.offset
            }
            return lhsDistance < rhsDistance
        }?.offset
    }

    nonisolated func getMenuBarIconFrameOnScreen(
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?,
        preferredCenterX: CGFloat? = nil,
        attempts: Int = 20,
        interval: TimeInterval = 0.05
    ) -> CGRect? {
        for attempt in 1 ... attempts {
            guard let frame = getMenuBarIconFrame(
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex,
                preferredCenterX: preferredCenterX
            ) else {
                return nil
            }

            let center = CGPoint(x: frame.midX, y: frame.midY)
            let isOnScreen = NSScreen.screens.contains { $0.frame.insetBy(dx: -2, dy: -2).contains(center) }

            if isOnScreen {
                Thread.sleep(forTimeInterval: 0.08)
                if let recheck = getMenuBarIconFrame(
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    preferredCenterX: preferredCenterX
                ),
                   abs(recheck.origin.x - frame.origin.x) < 2 {
                    return recheck
                }
                menuExtrasLogger.debug("getMenuBarIconFrameOnScreen: position unstable (attempt \(attempt))")
                continue
            }

            menuExtrasLogger.debug("getMenuBarIconFrameOnScreen: frame off-screen (attempt \(attempt), x=\(frame.origin.x, privacy: .public), y=\(frame.origin.y, privacy: .public))")
            Thread.sleep(forTimeInterval: interval)
        }
        return nil
    }
}
