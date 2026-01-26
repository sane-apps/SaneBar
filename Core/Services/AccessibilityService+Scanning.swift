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
    func listMenuBarItemOwners() async -> [RunningApp] {
        guard isTrusted else { return [] }

        // Check cache validity - return cached results if still fresh
        let now = Date()
        if now.timeIntervalSince(menuBarOwnersCacheTime) < menuBarOwnersCacheValiditySeconds && !menuBarOwnersCache.isEmpty {
            logger.debug("Returning cached menu bar owners (\(self.menuBarOwnersCache.count) apps)")
            return menuBarOwnersCache
        }

        // Pre-filter: Only scan apps with bundle identifiers
        let candidateApps = NSWorkspace.shared.runningApplications.filter { app in
            guard app.bundleIdentifier != nil else { return false }
            guard app.bundleIdentifier != Bundle.main.bundleIdentifier else { return false }
            return true
        }

        logger.debug("Scanning \(candidateApps.count) apps for menu bar owners")

        // Scan candidate apps for their menu bar extras in parallel
        let discoveredPIDs = await withTaskGroup(of: pid_t?.self) { group in
            for runningApp in candidateApps {
                group.addTask {
                    let pid = runningApp.processIdentifier
                    let appElement = AXUIElementCreateApplication(pid)

                    var extrasBar: CFTypeRef?
                    let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)

                    if result == .success {
                        return pid
                    }
                    return nil
                }
            }

            var pidsSet = Set<pid_t>()
            for await pid in group {
                if let pid = pid {
                    pidsSet.insert(pid)
                }
            }
            return pidsSet
        }

        // Map to RunningApp (unique by bundle ID or menuExtraIdentifier)
        var seenIds = Set<String>()
        var apps: [RunningApp] = []
        var controlCenterPID: pid_t?
        var systemUIServerPID: pid_t?

        for pid in discoveredPIDs {
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
    func listMenuBarItemsWithPositions() async -> [MenuBarItemPosition] {
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

        // Scan candidate applications for their menu bar extras in parallel
        let results: [ScannedStatusItem] = await withTaskGroup(of: [ScannedStatusItem].self) { group in
            for runningApp in candidateApps {
                group.addTask {
                    let pid = runningApp.processIdentifier
                    let appElement = AXUIElementCreateApplication(pid)

                    // Try to get this app's extras menu bar (status items)
                    var extrasBar: CFTypeRef?
                    let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)

                    guard result == .success, let bar = extrasBar else { return [] }

                    // Safe type checking using Core Foundation type IDs
                    guard let barElement = safeAXUIElement(bar) else { return [] }

                    var children: CFTypeRef?
                    let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)

                    guard childResult == .success, let items = children as? [AXUIElement] else { return [] }

                    func axString(_ value: CFTypeRef?) -> String? {
                        if let s = value as? String { return s }
                        if let attributed = value as? NSAttributedString { return attributed.string }
                        return nil
                    }

                    let usesPerItemIdentity = items.count > 1
                    var localResults: [ScannedStatusItem] = []

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

                        // If the app exposes multiple status items, keep them distinct.
                        let itemIndex: Int? = usesPerItemIdentity ? index : nil
                        localResults.append(
                            ScannedStatusItem(
                                pid: pid,
                                itemIndex: itemIndex,
                                x: xPos,
                                width: width,
                                axIdentifier: identifiersByIndex[index]
                            )
                        )
                    }
                    return localResults
                }
            }

            var allResults: [ScannedStatusItem] = []
            for await groupResults in group {
                allResults.append(contentsOf: groupResults)
            }
            return allResults
        }

        logger.debug("Scanned candidate apps in parallel, found \(results.count) menu bar items")

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
            // Skip thumbnail pre-calculation - let UI render lazily for faster scanning with 50+ apps
            let key = appModel.uniqueId

            // If we somehow see duplicate keys, keep the more-leftward X (stable sort).
            if let existing = appPositions[key] {
                let newX = min(existing.x, x)
                let newWidth = max(existing.width, width)
                // Use the new position
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

    internal nonisolated static func scanMenuBarOwnerPIDs(candidatePIDs: [pid_t]) async -> [pid_t] {
        await withTaskGroup(of: pid_t?.self) { group in
            for pid in candidatePIDs {
                group.addTask {
                    let appElement = AXUIElementCreateApplication(pid)
                    var extrasBar: CFTypeRef?
                    let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
                    if result == .success {
                        return pid
                    }
                    return nil
                }
            }

            var pids: [pid_t] = []
            pids.reserveCapacity(candidatePIDs.count)
            for await pid in group {
                if let pid = pid {
                    pids.append(pid)
                }
            }
            return pids
        }
    }

    internal nonisolated static func scanMenuBarAppMinXPositions(candidatePIDs: [pid_t]) async -> [(pid: pid_t, x: CGFloat)] {
        await withTaskGroup(of: (pid: pid_t, x: CGFloat)?.self) { group in
            for pid in candidatePIDs {
                group.addTask {
                    let appElement = AXUIElementCreateApplication(pid)

                    var extrasBar: CFTypeRef?
                    let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
                    guard result == .success, let bar = extrasBar else { return nil }
                    guard let barElement = safeAXUIElement(bar) else { return nil }

                    var children: CFTypeRef?
                    let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)
                    guard childResult == .success, let items = children as? [AXUIElement], !items.isEmpty else { return nil }

                    var minX: CGFloat?
                    for item in items {
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

                        if let existing = minX {
                            if xPos < existing {
                                minX = xPos
                            }
                        } else {
                            minX = xPos
                        }
                    }

                    if let minX {
                        return (pid: pid, x: minX)
                    }
                    return nil
                }
            }

            var results: [(pid: pid_t, x: CGFloat)] = []
            results.reserveCapacity(candidatePIDs.count)
            for await result in group {
                if let result = result {
                    results.append(result)
                }
            }
            return results
        }
    }
}
