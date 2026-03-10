import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityService.Scanning")

extension AccessibilityService {
    private nonisolated static let knownThirdPartyTopBarFallbackBundles: [String] = [
        "com.obdev.LittleSnitchUIAgent",
        "at.obdev.littlesnitch",
        "at.obdev.littlesnitch.agent",
        "at.obdev.littlesnitch.daemon",
        "at.obdev.littlesnitch.networkmonitor"
    ]

    internal struct ScannedStatusItem {
        let pid: pid_t
        let itemIndex: Int?
        let x: CGFloat
        let width: CGFloat
        let axIdentifier: String?
        let rawTitle: String?
        let rawDescription: String?
    }

    internal struct WindowBackedStatusItem: Equatable, Sendable {
        let pid: pid_t
        let frame: CGRect
        let fallbackIndex: Int?
    }

    internal nonisolated static func resolvedBundleIdentifier(for app: NSRunningApplication) -> String? {
        if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
            return bundleID
        }

        if let bundleURL = app.bundleURL,
           let bundleID = Bundle(url: bundleURL)?.bundleIdentifier,
           !bundleID.isEmpty {
            return bundleID
        }

        if var candidateURL = app.executableURL?.deletingLastPathComponent() {
            while candidateURL.path != "/" {
                if candidateURL.pathExtension == "app",
                   let bundleID = Bundle(url: candidateURL)?.bundleIdentifier,
                   !bundleID.isEmpty {
                    return bundleID
                }
                candidateURL.deleteLastPathComponent()
            }
        }

        return nil
    }

    internal nonisolated static func bundleIdentifierFallback(fromAXIdentifier axIdentifier: String?) -> String? {
        guard let raw = axIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }

        // Apple menu-extra identifiers identify the menu extra, not the owning app process.
        if raw.hasPrefix("com.apple.menuextra.") {
            return nil
        }

        // Common third-party shape: com.vendor.App-Item-0
        if let range = raw.range(of: "-Item-", options: .backwards) {
            let candidate = String(raw[..<range.lowerBound])
            if isLikelyBundleIdentifier(candidate) {
                return candidate
            }
        }

        if isLikelyBundleIdentifier(raw) {
            return raw
        }

        return nil
    }

    internal nonisolated static func resolvedScannedMenuExtraIdentifier(
        ownerBundleId: String,
        axIdentifier: String?,
        rawTitle: String?,
        rawDescription: String?,
        width: CGFloat
    ) -> String? {
        canonicalMenuExtraIdentifier(
            ownerBundleId: ownerBundleId,
            rawIdentifier: axIdentifier,
            rawLabel: rawTitle ?? rawDescription,
            width: width
        )
    }

    private nonisolated static func isLikelyBundleIdentifier(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !trimmed.contains(" ") else { return false }
        guard trimmed.contains(".") else { return false }
        return trimmed.range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil
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

        let selfPID = ProcessInfo.processInfo.processIdentifier
        // Pre-filter: scan everything except ourselves. Some menu extras run from
        // helper processes where bundleIdentifier is temporarily nil.
        let candidateApps = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != selfPID else { return false }
            if let bundleID = app.bundleIdentifier,
               bundleID == Bundle.main.bundleIdentifier {
                return false
            }
            return true
        }

        logger.debug("Scanning \(candidateApps.count) apps for menu bar owners")

        // Scan candidate apps for their menu bar extras in parallel
        let axDiscoveredPIDs = await withTaskGroup(of: pid_t?.self) { group in
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

        let windowBackedItems = Self.windowBackedMenuBarItems(
            candidatePIDs: Set(candidateApps.map(\.processIdentifier))
        )
        let windowBackedPIDs = Set(windowBackedItems.map(\.pid))
        let topBarHostPIDs = Self.topBarHostPIDs(candidatePIDs: Set(candidateApps.map(\.processIdentifier)))
        let discoveredPIDs = axDiscoveredPIDs.union(windowBackedPIDs)
        let windowFramesByPID = Self.representativeWindowBackedFramesByPID(windowBackedItems)
        if !windowBackedPIDs.isEmpty || !topBarHostPIDs.isEmpty {
            logger.debug("WindowServer fallback found \(windowBackedPIDs.count) compact owner candidate(s), \(topBarHostPIDs.count) top-bar host candidate(s)")
        }

        // Map to RunningApp (unique by bundle ID or menuExtraIdentifier)
        var seenIds = Set<String>()
        var apps: [RunningApp] = []
        var controlCenterPID: pid_t?
        var systemUIServerPID: pid_t?

        for pid in discoveredPIDs {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = Self.resolvedBundleIdentifier(for: app) else { continue }

            let windowOnly = windowBackedPIDs.contains(pid) && !axDiscoveredPIDs.contains(pid)
            if windowOnly {
                markExtrasMenuBarUnavailable(bundleID: bundleID)
            }

            let fallbackFrame = windowFramesByPID[pid]

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
            apps.append(
                RunningApp(
                    app: app,
                    resolvedBundleId: bundleID,
                    xPosition: fallbackFrame?.origin.x,
                    width: fallbackFrame?.width
                )
            )
        }

        for pid in topBarHostPIDs.subtracting(discoveredPIDs) {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = Self.resolvedBundleIdentifier(for: app) else { continue }

            let fallbackItems = Self.enumerateMenuExtraItems(
                pid: pid,
                ownerBundleId: bundleID,
                allowThirdPartyMenuBarFallback: true
            )
            guard Self.shouldIncludeThirdPartyTopBarOwner(
                bundleID: bundleID,
                fallbackItemsCount: fallbackItems.count
            ) else { continue }

            if !fallbackItems.isEmpty {
                logger.info(
                    "Top-bar host owner fallback accepted precise items bundle=\(bundleID, privacy: .public) pid=\(pid, privacy: .public) items=\(fallbackItems.count, privacy: .public)"
                )
                for item in fallbackItems where !seenIds.contains(item.app.uniqueId) {
                    seenIds.insert(item.app.uniqueId)
                    apps.append(item.app)
                }
                continue
            }

            logger.info("Top-bar host owner fallback candidate bundle=\(bundleID, privacy: .public) pid=\(pid, privacy: .public)")
            guard !seenIds.contains(bundleID) else { continue }
            seenIds.insert(bundleID)
            apps.append(RunningApp(app: app, resolvedBundleId: bundleID))
        }

        // Some macOS builds expose system extras through AXMenuBar instead of AXExtrasMenuBar.
        // Ensure we still attempt targeted expansion for these owners.
        if controlCenterPID == nil {
            controlCenterPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first?.processIdentifier
        }
        if systemUIServerPID == nil {
            systemUIServerPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemuiserver").first?.processIdentifier
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

        let selfPID = ProcessInfo.processInfo.processIdentifier
        // Pre-filter: scan everything except ourselves. Some menu extras run from
        // helper processes where bundleIdentifier is temporarily nil.
        let candidateApps = NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != selfPID else { return false }
            if let bundleID = app.bundleIdentifier,
               bundleID == Bundle.main.bundleIdentifier {
                return false
            }
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
                        var titleValue: CFTypeRef?
                        AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleValue)
                        let rawTitle = axString(titleValue)?.trimmingCharacters(in: .whitespacesAndNewlines)

                        var descValue: CFTypeRef?
                        AXUIElementCopyAttributeValue(item, kAXDescriptionAttribute as CFString, &descValue)
                        let rawDescription = axString(descValue)?.trimmingCharacters(in: .whitespacesAndNewlines)

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
                                axIdentifier: identifiersByIndex[index],
                                rawTitle: rawTitle,
                                rawDescription: rawDescription
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

        let axResolvedPIDs = Set(results.map(\.pid))
        let windowBackedItems = Self.windowBackedMenuBarItems(
            candidatePIDs: Set(candidateApps.map(\.processIdentifier))
        )
        let systemWideItems = Self.systemWideVisibleMenuBarItems(
            candidatePIDs: Set(candidateApps.map(\.processIdentifier))
        )
        let topBarHostPIDs = Self.topBarHostPIDs(candidatePIDs: Set(candidateApps.map(\.processIdentifier)))

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

            guard let app = NSRunningApplication(processIdentifier: pid) else { continue }
            guard let bundleID = Self.resolvedBundleIdentifier(for: app)
                ?? Self.bundleIdentifierFallback(fromAXIdentifier: axIdentifier) else { continue }

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

            let appModel = RunningApp(
                app: app,
                resolvedBundleId: bundleID,
                statusItemIndex: itemIndex,
                menuExtraIdentifier: Self.resolvedScannedMenuExtraIdentifier(
                    ownerBundleId: bundleID,
                    axIdentifier: axIdentifier,
                    rawTitle: scanned.rawTitle,
                    rawDescription: scanned.rawDescription,
                    width: width
                ),
                xPosition: x,
                width: width
            )
            // Skip thumbnail pre-calculation - let UI render lazily for faster scanning with 50+ apps
            let key = appModel.uniqueId

            // If we somehow see duplicate keys, keep the more-leftward X (stable sort).
            if let existing = appPositions[key] {
                let newX = min(existing.x, x)
                let newWidth = max(existing.width, width)
                // Use the new position
                let updatedApp = RunningApp(
                    app: app,
                    resolvedBundleId: bundleID,
                    statusItemIndex: itemIndex,
                    menuExtraIdentifier: Self.resolvedScannedMenuExtraIdentifier(
                        ownerBundleId: bundleID,
                        axIdentifier: axIdentifier,
                        rawTitle: scanned.rawTitle,
                        rawDescription: scanned.rawDescription,
                        width: newWidth
                    ),
                    xPosition: newX,
                    width: newWidth
                )
                appPositions[key] = MenuBarItemPosition(app: updatedApp, x: newX, width: newWidth)
            } else {
                appPositions[key] = MenuBarItemPosition(app: appModel, x: x, width: width)
            }
        }

        for pid in topBarHostPIDs.subtracting(axResolvedPIDs) {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = Self.resolvedBundleIdentifier(for: app) else { continue }

            if bundleID == "com.apple.controlcenter" {
                controlCenterPID = pid
                continue
            }

            if bundleID == "com.apple.systemuiserver" {
                systemUIServerPID = pid
                continue
            }

            let fallbackItems = Self.enumerateMenuExtraItems(
                pid: pid,
                ownerBundleId: bundleID,
                allowThirdPartyMenuBarFallback: true
            )
            logger.info("Top-bar host AXMenuBar fallback bundle=\(bundleID, privacy: .public) pid=\(pid, privacy: .public) items=\(fallbackItems.count, privacy: .public)")
            guard Self.shouldIncludeThirdPartyTopBarOwner(
                bundleID: bundleID,
                fallbackItemsCount: fallbackItems.count
            ) else { continue }

            if fallbackItems.isEmpty {
                markExtrasMenuBarUnavailable(bundleID: bundleID)
                continue
            }
            for item in fallbackItems {
                appPositions[item.app.uniqueId] = item
            }
        }

        for windowBacked in windowBackedItems where !axResolvedPIDs.contains(windowBacked.pid) {
            guard let app = NSRunningApplication(processIdentifier: windowBacked.pid),
                  let bundleID = Self.resolvedBundleIdentifier(for: app) else { continue }

            if bundleID == "com.apple.controlcenter" {
                controlCenterPID = windowBacked.pid
                continue
            }

            if bundleID == "com.apple.systemuiserver" {
                systemUIServerPID = windowBacked.pid
                continue
            }

            markExtrasMenuBarUnavailable(bundleID: bundleID)

            let appModel = RunningApp(
                app: app,
                resolvedBundleId: bundleID,
                statusItemIndex: windowBacked.fallbackIndex,
                xPosition: windowBacked.frame.origin.x,
                width: windowBacked.frame.width
            )
            appPositions[appModel.uniqueId] = MenuBarItemPosition(
                app: appModel,
                x: windowBacked.frame.origin.x,
                width: windowBacked.frame.width
            )
        }

        for item in systemWideItems {
            Self.mergeSystemWideMenuBarItem(item, into: &appPositions)
        }

        // Some macOS builds expose system extras through AXMenuBar instead of AXExtrasMenuBar.
        // Ensure we still attempt targeted expansion for these owners.
        if controlCenterPID == nil {
            controlCenterPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first?.processIdentifier
        }
        if systemUIServerPID == nil {
            systemUIServerPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemuiserver").first?.processIdentifier
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

    internal nonisolated static func windowBackedMenuBarItems(candidatePIDs: Set<pid_t>) -> [WindowBackedStatusItem] {
        guard !candidatePIDs.isEmpty,
              let infos = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        return windowBackedMenuBarItems(fromWindowInfos: infos, candidatePIDs: candidatePIDs)
    }

    internal nonisolated static func topBarHostPIDs(candidatePIDs: Set<pid_t>) -> Set<pid_t> {
        guard !candidatePIDs.isEmpty,
              let infos = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]
        else {
            return []
        }

        let minimumWidth = (NSScreen.screens.map(\.frame.width).max() ?? 0) * 0.7
        return topBarHostPIDs(
            fromWindowInfos: infos,
            candidatePIDs: candidatePIDs,
            minimumWidth: minimumWidth
        )
    }

    internal nonisolated static func mergeSystemWideMenuBarItem(
        _ item: MenuBarItemPosition,
        into appPositions: inout [String: MenuBarItemPosition]
    ) {
        let key = item.app.uniqueId
        if appPositions[key] != nil {
            return
        }

        if item.app.menuExtraIdentifier == nil {
            // Bundle-level fallback items are discovery-only. If the same bundle
            // already has a more precise AX or WindowServer match, prefer that.
            if appPositions.values.contains(where: { $0.app.bundleId == item.app.bundleId }) {
                return
            }

            appPositions[key] = item
            return
        }

        // Precise menu-extra identities should replace coarse owner-only fallbacks
        // for the same bundle so we do not render duplicate entries.
        let coarseKeys = appPositions.compactMap { candidate -> String? in
            guard candidate.value.app.bundleId == item.app.bundleId,
                  candidate.value.app.menuExtraIdentifier == nil else {
                return nil
            }
            return candidate.key
        }
        for coarseKey in coarseKeys {
            appPositions.removeValue(forKey: coarseKey)
        }

        appPositions[key] = item
    }

    internal nonisolated static func windowBackedMenuBarItems(
        fromWindowInfos infos: [[String: Any]],
        candidatePIDs: Set<pid_t>
    ) -> [WindowBackedStatusItem] {
        guard !candidatePIDs.isEmpty else { return [] }

        func number(_ value: Any?) -> CGFloat? {
            switch value {
            case let number as NSNumber:
                return CGFloat(truncating: number)
            case let value as CGFloat:
                return value
            case let value as Double:
                return value
            case let value as Int:
                return CGFloat(value)
            default:
                return nil
            }
        }

        var framesByPID: [pid_t: [CGRect]] = [:]

        for info in infos {
            guard let ownerPIDValue = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let ownerPID = pid_t(ownerPIDValue.intValue)
            guard candidatePIDs.contains(ownerPID) else { continue }

            guard let layerValue = info[kCGWindowLayer as String] as? NSNumber else { continue }
            let layer = layerValue.intValue
            guard layer == 24 || layer == 25 else { continue }

            if let alphaValue = info[kCGWindowAlpha as String] as? NSNumber,
               alphaValue.doubleValue <= 0 {
                continue
            }

            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let x = number(bounds["X"]),
                  let y = number(bounds["Y"]),
                  let width = number(bounds["Width"]),
                  let height = number(bounds["Height"]) else {
                continue
            }

            guard width > 0, height > 0 else { continue }
            guard height <= 60 else { continue }
            guard width <= 500 else { continue }

            let frame = CGRect(x: x, y: y, width: width, height: height)
            framesByPID[ownerPID, default: []].append(frame)
        }

        return framesByPID
            .sorted { $0.key < $1.key }
            .flatMap { pid, frames in
                let orderedFrames = frames.sorted {
                    if $0.midX == $1.midX {
                        return $0.width < $1.width
                    }
                    return $0.midX < $1.midX
                }
                let shouldAssignFallbackIndex = orderedFrames.count > 1
                return orderedFrames.enumerated().map { index, frame in
                    WindowBackedStatusItem(
                        pid: pid,
                        frame: frame,
                        fallbackIndex: shouldAssignFallbackIndex ? index : nil
                    )
                }
            }
    }

    internal nonisolated static func representativeWindowBackedFramesByPID(
        _ items: [WindowBackedStatusItem]
    ) -> [pid_t: CGRect] {
        items.reduce(into: [pid_t: CGRect]()) { partial, item in
            if let existing = partial[item.pid] {
                if item.frame.midX > existing.midX {
                    partial[item.pid] = item.frame
                }
            } else {
                partial[item.pid] = item.frame
            }
        }
    }

    internal nonisolated static func topBarHostPIDs(
        fromWindowInfos infos: [[String: Any]],
        candidatePIDs: Set<pid_t>,
        minimumWidth: CGFloat
    ) -> Set<pid_t> {
        guard !candidatePIDs.isEmpty else { return [] }

        func number(_ value: Any?) -> CGFloat? {
            switch value {
            case let number as NSNumber:
                return CGFloat(truncating: number)
            case let value as CGFloat:
                return value
            case let value as Double:
                return value
            case let value as Int:
                return CGFloat(value)
            default:
                return nil
            }
        }

        var matches = Set<pid_t>()

        for info in infos {
            guard let ownerPIDValue = info[kCGWindowOwnerPID as String] as? NSNumber else { continue }
            let ownerPID = pid_t(ownerPIDValue.intValue)
            guard candidatePIDs.contains(ownerPID) else { continue }

            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let y = number(bounds["Y"]),
                  let width = number(bounds["Width"]),
                  let height = number(bounds["Height"]) else {
                continue
            }

            guard y <= 1 else { continue }
            guard height >= 20, height <= 40 else { continue }
            guard width >= minimumWidth else { continue }
            matches.insert(ownerPID)
        }

        return matches
    }

    internal nonisolated static func scanMenuBarOwnerPIDs(candidatePIDs: [pid_t]) async -> [pid_t] {
        let axPIDs = await withTaskGroup(of: pid_t?.self) { group in
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

        let windowBackedPIDs = Set(windowBackedMenuBarItems(candidatePIDs: Set(candidatePIDs)).map(\.pid))
        let topBarPIDs = Set(
            topBarHostPIDs(candidatePIDs: Set(candidatePIDs)).compactMap { pid -> pid_t? in
                guard let app = NSRunningApplication(processIdentifier: pid),
                      let bundleID = resolvedBundleIdentifier(for: app) else {
                    return nil
                }

                let fallbackItems = enumerateMenuExtraItems(
                    pid: pid,
                    ownerBundleId: bundleID,
                    allowThirdPartyMenuBarFallback: true
                )
                guard shouldIncludeThirdPartyTopBarOwner(
                    bundleID: bundleID,
                    fallbackItemsCount: fallbackItems.count
                ) else {
                    return nil
                }
                return pid
            }
        )
        return Array(Set(axPIDs).union(windowBackedPIDs).union(topBarPIDs))
    }

    internal nonisolated static func shouldAllowThirdPartyTopBarFallback(bundleID: String) -> Bool {
        knownThirdPartyTopBarFallbackBundles.contains { bundleID == $0 || bundleID.hasPrefix($0 + ".") }
    }

    internal nonisolated static func shouldIncludeThirdPartyTopBarOwner(
        bundleID: String,
        fallbackItemsCount: Int
    ) -> Bool {
        fallbackItemsCount > 0 || shouldAllowThirdPartyTopBarFallback(bundleID: bundleID)
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
// swiftlint:enable file_length
