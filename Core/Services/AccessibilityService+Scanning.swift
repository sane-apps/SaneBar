import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityService.Scanning")

extension AccessibilityService {
    
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

        for pid in pids {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier else { continue }

            // Special case: Control Center - remember its PID for later expansion
            if bundleID == "com.apple.controlcenter" {
                controlCenterPID = pid
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

        let sortedApps = apps.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

        // Update cache
        menuBarOwnersCache = sortedApps
        menuBarOwnersCacheTime = now
        logger.debug("Cached \(sortedApps.count) menu bar owners")

        return sortedApps
    }

    /// Returns menu bar items, with position info.
    func listMenuBarItemsWithPositions() -> [(app: RunningApp, x: CGFloat)] {
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
        var results: [(pid: pid_t, x: CGFloat)] = []

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

                results.append((pid: runningApp.processIdentifier, x: xPos))
            }
        }

        logger.debug("Scanned candidate apps, found \(results.count) menu bar items")

        // Convert to RunningApps (unique by bundle ID or menuExtraIdentifier)
        var appPositions: [String: (app: RunningApp, x: CGFloat)] = [:]
        var controlCenterPID: pid_t?

        for (pid, x) in results {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier else { continue }

            // Special case: Control Center - remember its PID for later expansion
            if bundleID == "com.apple.controlcenter" {
                controlCenterPID = pid
                continue  // Don't add the collapsed entry
            }

            // Keep the minimum x position for each app (most hidden position)
            if let existing = appPositions[bundleID] {
                if x < existing.x {
                    appPositions[bundleID] = (app: RunningApp(app: app, xPosition: x), x: x)
                }
            } else {
                appPositions[bundleID] = (app: RunningApp(app: app, xPosition: x), x: x)
            }
        }

        // Expand Control Center into individual items (Battery, WiFi, Clock, etc.)
        if let ccPID = controlCenterPID {
            let ccItems = Self.enumerateControlCenterItems(pid: ccPID)
            logger.debug("Expanded Control Center into \(ccItems.count) individual items")
            for item in ccItems {
                // Use uniqueId (menuExtraIdentifier) as the key for Control Center items
                let key = item.app.uniqueId
                
                // Ensure xPosition is preserved in RunningApp
                var appWithX = item.app
                if appWithX.xPosition == nil {
                    appWithX = RunningApp(
                        id: item.app.id,
                        name: item.app.name,
                        icon: item.app.icon,
                        policy: item.app.policy,
                        category: item.app.category,
                        menuExtraIdentifier: item.app.menuExtraIdentifier,
                        xPosition: item.x
                    )
                }
                appPositions[key] = (app: appWithX, x: item.x)
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

    // MARK: - Control Center Item Enumeration

    /// Enumerates individual Control Center items (Battery, WiFi, Clock, etc.)
    /// Returns virtual RunningApp instances for each item with positions.
    ///
    /// Control Center owns multiple independent menu bar icons under a single bundle ID.
    /// This method extracts each as a separate entry using AXIdentifier and AXDescription.
    internal nonisolated static func enumerateControlCenterItems(pid: pid_t) -> [(app: RunningApp, x: CGFloat)] {
        var results: [(app: RunningApp, x: CGFloat)] = []

        let appElement = AXUIElementCreateApplication(pid)

        var extrasBar: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
        guard result == .success, let bar = extrasBar else { return results }
        guard CFGetTypeID(bar) == AXUIElementGetTypeID() else { return results }
        // swiftlint:disable:next force_cast
        let barElement = bar as! AXUIElement

        var children: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)
        guard childResult == .success, let items = children as? [AXUIElement] else { return results }

        for item in items {
            // Get AXIdentifier (e.g., "com.apple.menuextra.battery")
            var identifierValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifierValue)
            guard let identifier = identifierValue as? String, !identifier.isEmpty else { continue }

            // Get AXDescription (e.g., "Battery")
            var descValue: CFTypeRef?
            AXUIElementCopyAttributeValue(item, kAXDescriptionAttribute as CFString, &descValue)
            let description = (descValue as? String) ?? identifier.components(separatedBy: ".").last ?? "Unknown"

            // Get position
            var positionValue: CFTypeRef?
            let posResult = AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)
            var xPos: CGFloat = 0
            if posResult == .success, let posValue = positionValue, CFGetTypeID(posValue) == AXValueGetTypeID() {
                var point = CGPoint.zero
                // swiftlint:disable:next force_cast
                if AXValueGetValue(posValue as! AXValue, .cgPoint, &point) {
                    xPos = point.x
                }
            }

            // Create virtual RunningApp for this Control Center item
            let virtualApp = RunningApp.controlCenterItem(name: description, identifier: identifier)
            results.append((app: virtualApp, x: xPos))
        }

        return results
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
