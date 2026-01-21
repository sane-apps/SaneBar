import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityService.Scanning")

extension AccessibilityService {

    internal struct ScannedStatusItem {
        let pid: pid_t
        let itemIndex: Int?
        let x: CGFloat
        let width: CGFloat
        let axIdentifier: String?
    }
    
    // MARK: - System Wide Search

    /// Best-effort list of apps that currently own a menu bar status item.
    func listMenuBarItemOwners() -> [RunningApp] {
        guard isTrusted else { return [] }

        // Check cache validity - return cached results if still fresh
        let now = Date()
        if now.timeIntervalSince(menuBarOwnersCacheTime) < menuBarOwnersCacheValiditySeconds && !menuBarOwnersCache.isEmpty {
            logger.debug("Returning cached menu bar owners (\(self.menuBarOwnersCache.count) apps)")
            return menuBarOwnersCache
        }

        var pids = Set<pid_t>()

        // Pre-filter: Only scan apps with bundle identifiers
        let candidateApps = NSWorkspace.shared.runningApplications.filter { app in
            guard app.bundleIdentifier != nil else { return false }
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
            return true
        }

        logger.debug("Scanning \(candidateApps.count) apps for menu bar owners")

        // Scan candidate apps for their menu bar extras
        for runningApp in candidateApps {
            let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)

            var extrasBar: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)

            if result == .success {
                // This app has a menu bar extra
                pids.insert(runningApp.processIdentifier)
            }
        }

        // Map to RunningApp (unique by bundle ID or menuExtraIdentifier)
        var seenIds = Set<String>()
        var apps: [RunningApp] = []
        var controlCenterPID: pid_t?
        var systemUIServerPID: pid_t?

        for pid in pids {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier else { continue }

            // Special case: Control Center - remember its PID for later expansion
            if bundleID == "com.apple.controlcenter" {
                controlCenterPID = pid
                continue  // Don't add the collapsed entry
            }

            // Special case: SystemUIServer - it often owns system menu extras like Wi‑Fi
            if bundleID == "com.apple.systemuiserver" {
                systemUIServerPID = pid
                continue  // Don't add the collapsed entry
            }

            guard !seenIds.contains(bundleID) else { continue }
            seenIds.insert(bundleID)
            apps.append(RunningApp(app: app))
        }

        // Expand Control Center into individual items (Battery, WiFi, Clock, etc.)
        if let ccPID = controlCenterPID {
            let ccItems = Self.enumerateControlCenterItems(pid: ccPID)
            logger.debug("Expanded Control Center into \(ccItems.count) individual owners")
            for item in ccItems {
                let key = item.app.uniqueId
                guard !seenIds.contains(key) else { continue }
                seenIds.insert(key)
                apps.append(item.app)
            }
        }

        // Expand SystemUIServer into individual items (Wi‑Fi, Bluetooth, etc.)
        if let suPID = systemUIServerPID {
            let suItems = Self.enumerateMenuExtraItems(pid: suPID, ownerBundleId: "com.apple.systemuiserver")
            logger.debug("Expanded SystemUIServer into \(suItems.count) individual owners")
            for item in suItems {
                let key = item.app.uniqueId
                guard !seenIds.contains(key) else { continue }
                seenIds.insert(key)
                apps.append(item.app)
            }
        }

        let sortedApps = apps.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

        // Update cache
        menuBarOwnersCache = sortedApps
        menuBarOwnersCacheTime = now
        logger.debug("Cached \(sortedApps.count) menu bar owners")

        return sortedApps
    }

    /// Returns menu bar items, with position info.
    func listMenuBarItemsWithPositions() -> [MenuBarItemPosition] {
        guard isTrusted else {
            logger.warning("listMenuBarItemsWithPositions: Not trusted for Accessibility")
            return []
        }

        // Check cache validity - return cached results if still fresh
        let now = Date()
        if now.timeIntervalSince(menuBarItemCacheTime) < menuBarItemCacheValiditySeconds && !menuBarItemCache.isEmpty {
            logger.debug("Returning cached menu bar items (\(self.menuBarItemCache.count) items)")
            return menuBarItemCache
        }

        // Pre-filter: Only scan apps that could have menu bar items
        // Skip processes without bundle identifiers (XPC services, system agents, helpers)
        let candidateApps = NSWorkspace.shared.runningApplications.filter { app in
            // Must have a bundle identifier to be a real app
            guard app.bundleIdentifier != nil else { return false }
            // Skip ourselves
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
            return true
        }

        logger.debug("Scanning \(candidateApps.count) candidate apps (filtered from \(NSWorkspace.shared.runningApplications.count) total)")

        // Scan candidate applications for their menu bar extras
        var results: [ScannedStatusItem] = []

        for runningApp in candidateApps {
            let appElement = AXUIElementCreateApplication(runningApp.processIdentifier)

            // Try to get this app's extras menu bar (status items)
            var extrasBar: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)

            guard result == .success, let bar = extrasBar else { continue }

            // Safe type checking using Core Foundation type IDs
            guard CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
            // swiftlint:disable:next force_cast
            let barElement = bar as! AXUIElement

            var children: CFTypeRef?
            let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)

            guard childResult == .success, let items = children as? [AXUIElement] else { continue }

            func axString(_ value: CFTypeRef?) -> String? {
                if let s = value as? String { return s }
                if let attributed = value as? NSAttributedString { return attributed.string }
                return nil
            }

            let usesPerItemIdentity = items.count > 1

            // Prefer stable AX identifiers when they exist and are unique within this app.
            var identifiersByIndex: [Int: String] = [:]
            if usesPerItemIdentity {
                var identifiers: [String] = []
                identifiers.reserveCapacity(items.count)
                for (index, item) in items.enumerated() {
                    var identifierValue: CFTypeRef?
                    AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifierValue)
                    if let id = axString(identifierValue)?.trimmingCharacters(in: .whitespacesAndNewlines), !id.isEmpty {
                        identifiers.append(id)
                        identifiersByIndex[index] = id
                    }
                }

                // Only use identifiers if we have at least one and they don't collide.
                if !identifiers.isEmpty {
                    let uniqueCount = Set(identifiers).count
                    if uniqueCount != identifiers.count {
                        identifiersByIndex.removeAll(keepingCapacity: true)
                    }
                }
            }

            for (index, item) in items.enumerated() {
                // Get Position
                var positionValue: CFTypeRef?
                let posResult = AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)

                var xPos: CGFloat = 0
                if posResult == .success, let posValue = positionValue {
                    if CFGetTypeID(posValue) == AXValueGetTypeID() {
                        var point = CGPoint.zero
                        // swiftlint:disable:next force_cast
                        if AXValueGetValue(posValue as! AXValue, .cgPoint, &point) {
                            xPos = point.x
                        }
                    }
                }

                // Get Size (Width)
                var sizeValue: CFTypeRef?
                let sizeResult = AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue)

                var width: CGFloat = 0
                if sizeResult == .success, let sValue = sizeValue {
                    if CFGetTypeID(sValue) == AXValueGetTypeID() {
                        var size = CGSize.zero
                        // swiftlint:disable:next force_cast
                        if AXValueGetValue(sValue as! AXValue, .cgSize, &size) {
                            width = size.width
                        }
                    }
                }

                // If the app exposes multiple status items, keep them distinct.
                // Otherwise preserve the legacy identity (bundleId-only).
                let itemIndex: Int? = usesPerItemIdentity ? index : nil
                results.append(
                    ScannedStatusItem(
                        pid: runningApp.processIdentifier,
                        itemIndex: itemIndex,
                        x: xPos,
                        width: width,
                        axIdentifier: identifiersByIndex[index]
                    )
                )
            }
        }

        logger.debug("Scanned candidate apps, found \(results.count) menu bar items")

        // Convert to RunningApps (unique by bundle ID or menuExtraIdentifier)
        var appPositions: [String: MenuBarItemPosition] = [:]
        var controlCenterPID: pid_t?
        var systemUIServerPID: pid_t?

        for scanned in results {
            let pid = scanned.pid
            let itemIndex = scanned.itemIndex
            let axIdentifier = scanned.axIdentifier
            let x = scanned.x
            let width = scanned.width

            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier else { continue }

            // Special case: Control Center - remember its PID for later expansion
            if bundleID == "com.apple.controlcenter" {
                controlCenterPID = pid
                continue  // Don't add the collapsed entry
            }

            // Special case: SystemUIServer - remember its PID for later expansion
            if bundleID == "com.apple.systemuiserver" {
                systemUIServerPID = pid
                continue  // Don't add the collapsed entry
            }

            let appModel = RunningApp(app: app, statusItemIndex: itemIndex, menuExtraIdentifier: axIdentifier, xPosition: x, width: width)
            let key = appModel.uniqueId

            // If we somehow see duplicate keys, keep the more-leftward X (stable sort).
            if let existing = appPositions[key] {
                let newX = min(existing.x, x)
                let newWidth = max(existing.width, width)
                let updatedApp = RunningApp(app: app, statusItemIndex: itemIndex, menuExtraIdentifier: axIdentifier, xPosition: newX, width: newWidth)
                appPositions[key] = MenuBarItemPosition(app: updatedApp, x: newX, width: newWidth)
            } else {
                appPositions[key] = MenuBarItemPosition(app: appModel, x: x, width: width)
            }
        }

        // Expand Control Center into individual items (Battery, WiFi, Clock, etc.)
        if let ccPID = controlCenterPID {
            let ccItems = Self.enumerateControlCenterItems(pid: ccPID)
            logger.debug("Expanded Control Center into \(ccItems.count) individual items")
            for item in ccItems {
                // Use uniqueId (menuExtraIdentifier) as the key for Control Center items
                let key = item.app.uniqueId
                
                // Ensure xPosition and width are preserved in RunningApp
                var appWithProps = item.app
                if appWithProps.xPosition == nil || appWithProps.width == nil {
                    appWithProps = RunningApp(
                        id: item.app.bundleId,
                        name: item.app.name,
                        icon: item.app.icon,
                        policy: item.app.policy,
                        category: item.app.category,
                        menuExtraIdentifier: item.app.menuExtraIdentifier,
                        xPosition: item.x,
                        width: item.width
                    )
                }
                appPositions[key] = MenuBarItemPosition(app: appWithProps, x: item.x, width: item.width)
            }
        }

        // Expand SystemUIServer into individual items (Wi‑Fi, Bluetooth, etc.)
        if let suPID = systemUIServerPID {
            let suItems = Self.enumerateMenuExtraItems(pid: suPID, ownerBundleId: "com.apple.systemuiserver")
            logger.debug("Expanded SystemUIServer into \(suItems.count) individual items")
            for item in suItems {
                let key = item.app.uniqueId

                var appWithProps = item.app
                if appWithProps.xPosition == nil || appWithProps.width == nil {
                    appWithProps = RunningApp(
                        id: item.app.bundleId,
                        name: item.app.name,
                        icon: item.app.icon,
                        policy: item.app.policy,
                        category: item.app.category,
                        menuExtraIdentifier: item.app.menuExtraIdentifier,
                        xPosition: item.x,
                        width: item.width
                    )
                }

                appPositions[key] = MenuBarItemPosition(app: appWithProps, x: item.x, width: item.width)
            }
        }

        let apps = Array(appPositions.values).sorted { $0.x < $1.x }

        // Update cache
        menuBarItemCache = apps
        menuBarItemCacheTime = now

        let hiddenCount = apps.filter { $0.x < 0 }.count
        logger.info("Found \(apps.count) apps with menu bar items (\(hiddenCount) hidden)")

        return apps
    }

    // MARK: - Scanning Helpers

    internal nonisolated static func scanMenuBarOwnerPIDs(candidatePIDs: [pid_t]) -> [pid_t] {
        var pids: [pid_t] = []
        pids.reserveCapacity(candidatePIDs.count)

        for pid in candidatePIDs {
            let appElement = AXUIElementCreateApplication(pid)
            var extrasBar: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
            if result == .success {
                pids.append(pid)
            }
        }

        return pids
    }

    internal nonisolated static func scanMenuBarAppMinXPositions(candidatePIDs: [pid_t]) -> [(pid: pid_t, x: CGFloat)] {
        var results: [(pid: pid_t, x: CGFloat)] = []
        results.reserveCapacity(candidatePIDs.count)

        for pid in candidatePIDs {
            let appElement = AXUIElementCreateApplication(pid)

            var extrasBar: CFTypeRef?
            let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
            guard result == .success, let bar = extrasBar else { continue }
            guard CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
            // swiftlint:disable:next force_cast
            let barElement = bar as! AXUIElement

            var children: CFTypeRef?
            let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)
            guard childResult == .success, let items = children as? [AXUIElement], !items.isEmpty else { continue }

            var minX: CGFloat?
            for item in items {
                var positionValue: CFTypeRef?
                let posResult = AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)

                var xPos: CGFloat = 0

                if posResult == .success, let posValue = positionValue {
                    if CFGetTypeID(posValue) == AXValueGetTypeID() {
                        var point = CGPoint.zero
                        // swiftlint:disable:next force_cast
                        if AXValueGetValue(posValue as! AXValue, .cgPoint, &point) {
                            xPos = point.x
                        }
                    }
                }

                if let existing = minX {
                    if xPos < existing {
                        minX = xPos
                    }
                } else {
                    minX = xPos
                }
            }

            if let minX {
                results.append((pid: pid, x: minX))
            }
        }

        return results
    }
}
