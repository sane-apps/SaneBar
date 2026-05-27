import AppKit
import os.log

private let accessibilityScanningLogger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityMenuBarScanningService")

@MainActor
final class AccessibilityMenuBarScanningService {
    typealias MenuBarItemPosition = AccessibilityService.MenuBarItemPosition
    typealias SystemWideHitSample = AccessibilitySystemWideMenuBarScanner.SystemWideHitSample
    typealias SystemWideMenuBarSegment = AccessibilitySystemWideMenuBarScanner.SystemWideMenuBarSegment

    private unowned let accessibilityService: AccessibilityService

    init(accessibilityService: AccessibilityService) {
        self.accessibilityService = accessibilityService
    }

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
        AccessibilityMenuExtraService.canonicalMenuExtraIdentifier(
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

    internal nonisolated static func scannedStatusItemIndex(
        itemCount: Int,
        itemIndex: Int,
        axIdentifier: String?
    ) -> Int? {
        let hasIdentifier = axIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if itemCount > 1 || !hasIdentifier {
            return itemIndex
        }
        return nil
    }

    // MARK: - System Wide Search

    /// Best-effort list of apps that currently own a menu bar status item.
    func listMenuBarItemOwners() async -> [RunningApp] {
        guard accessibilityService.isTrusted else { return [] }

        // Check cache validity - return cached results if still fresh
        let now = Date()
        if now.timeIntervalSince(accessibilityService.menuBarOwnersCacheTime) < accessibilityService.menuBarOwnersCacheValiditySeconds && !accessibilityService.menuBarOwnersCache.isEmpty {
            accessibilityScanningLogger.debug("Returning cached menu bar owners (\(self.accessibilityService.menuBarOwnersCache.count) apps)")
            return accessibilityService.menuBarOwnersCache
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

        accessibilityScanningLogger.debug("Scanning \(candidateApps.count) apps for menu bar owners")

        // Scan candidate apps for their menu bar extras in parallel
        let axDiscoveredPIDs = await withTaskGroup(of: pid_t?.self) { group in
            for runningApp in candidateApps {
                group.addTask {
                    autoreleasepool { () -> pid_t? in
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
            }
            var pidsSet = Set<pid_t>()
            for await pid in group {
                if let pid = pid {
                    pidsSet.insert(pid)
                }
            }
            return pidsSet
        }

        let windowBackedItems = AccessibilityMenuBarWindowFallbackPolicy.windowBackedMenuBarItems(
            candidatePIDs: Set(candidateApps.map(\.processIdentifier))
        )
        let windowBackedPIDs = Set(windowBackedItems.map(\.pid))
        let topBarHostPIDs = AccessibilityMenuBarWindowFallbackPolicy.topBarHostPIDs(candidatePIDs: Set(candidateApps.map(\.processIdentifier)))
        let discoveredPIDs = axDiscoveredPIDs.union(windowBackedPIDs)
        let windowFramesByPID = AccessibilityMenuBarWindowFallbackPolicy.representativeWindowBackedFramesByPID(windowBackedItems)
        if !windowBackedPIDs.isEmpty || !topBarHostPIDs.isEmpty {
            accessibilityScanningLogger.debug("WindowServer fallback found \(windowBackedPIDs.count) compact owner candidate(s), \(topBarHostPIDs.count) top-bar host candidate(s)")
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
                accessibilityService.markExtrasMenuBarUnavailable(bundleID: bundleID)
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

            let fallbackItems = AccessibilityMenuExtraService.enumerateMenuExtraItems(
                pid: pid,
                ownerBundleId: bundleID,
                allowThirdPartyMenuBarFallback: true
            )
            guard AccessibilityMenuBarWindowFallbackPolicy.shouldIncludeThirdPartyTopBarOwner(
                bundleID: bundleID,
                fallbackItemsCount: fallbackItems.count
            ) else { continue }

            if !fallbackItems.isEmpty {
                accessibilityScanningLogger.info(
                    "Top-bar host owner fallback accepted precise items bundle=\(bundleID, privacy: .public) pid=\(pid, privacy: .public) items=\(fallbackItems.count, privacy: .public)"
                )
                for item in fallbackItems where !seenIds.contains(item.app.uniqueId) {
                    seenIds.insert(item.app.uniqueId)
                    apps.append(item.app)
                }
                continue
            }

            accessibilityScanningLogger.info("Top-bar host owner fallback candidate bundle=\(bundleID, privacy: .public) pid=\(pid, privacy: .public)")
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
            let ccItems = AccessibilityMenuExtraService.enumerateControlCenterItems(pid: ccPID)
            accessibilityScanningLogger.debug("Expanded Control Center into \(ccItems.count) individual owners")
            for item in ccItems {
                let key = item.app.uniqueId
                guard !seenIds.contains(key) else { continue }
                seenIds.insert(key)
                apps.append(item.app)
            }
        }

        // Expand SystemUIServer into individual items (Wi‑Fi, Bluetooth, etc.)
        if let suPID = systemUIServerPID {
            let suItems = AccessibilityMenuExtraService.enumerateMenuExtraItems(pid: suPID, ownerBundleId: "com.apple.systemuiserver")
            accessibilityScanningLogger.debug("Expanded SystemUIServer into \(suItems.count) individual owners")
            for item in suItems {
                let key = item.app.uniqueId
                guard !seenIds.contains(key) else { continue }
                seenIds.insert(key)
                apps.append(item.app)
            }
        }

        let sortedApps = apps.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

        // Update cache
        accessibilityService.menuBarOwnersCache = sortedApps
        accessibilityService.menuBarOwnersCacheTime = now
        accessibilityScanningLogger.debug("Cached \(sortedApps.count) menu bar owners")

        return sortedApps
    }

    /// Returns menu bar items, with position info.
    func listMenuBarItemsWithPositions() async -> [MenuBarItemPosition] {
        guard accessibilityService.isTrusted else {
            accessibilityScanningLogger.warning("listMenuBarItemsWithPositions: Not trusted for Accessibility")
            return []
        }

        // Check cache validity - return cached results if still fresh
        let now = Date()
        if now.timeIntervalSince(accessibilityService.menuBarItemCacheTime) < accessibilityService.menuBarItemCacheValiditySeconds && !accessibilityService.menuBarItemCache.isEmpty {
            accessibilityScanningLogger.debug("Returning cached menu bar items (\(self.accessibilityService.menuBarItemCache.count) items)")
            return accessibilityService.menuBarItemCache
        }

        let apps = await scanMenuBarItemsWithPositions(
            candidateApps: filteredMenuBarCandidateApps(),
            includeSystemWideFallback: true
        )
        accessibilityService.menuBarItemCache = apps
        accessibilityService.menuBarItemCacheTime = now
        return apps
    }

    func listKnownMenuBarItemsWithPositions(owners: [RunningApp]) async -> [MenuBarItemPosition] {
        guard accessibilityService.isTrusted else {
            accessibilityScanningLogger.warning("listKnownMenuBarItemsWithPositions: Not trusted for Accessibility")
            return []
        }

        let now = Date()
        let apps = await scanKnownMenuBarItemsWithPositions(owners: owners)
        accessibilityService.menuBarItemCache = apps
        accessibilityService.menuBarItemCacheTime = now
        return apps
    }

    func scopedMenuBarItemsWithPositions(for owners: [RunningApp]) async -> [MenuBarItemPosition] {
        guard accessibilityService.isTrusted else {
            accessibilityScanningLogger.warning("scopedMenuBarItemsWithPositions: Not trusted for Accessibility")
            return []
        }

        return await scanKnownMenuBarItemsWithPositions(owners: owners)
    }

    // MARK: - Scanning Helpers

    private func filteredMenuBarCandidateApps() -> [NSRunningApplication] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            guard app.processIdentifier != selfPID else { return false }
            if let bundleID = app.bundleIdentifier,
               bundleID == Bundle.main.bundleIdentifier {
                return false
            }
            return true
        }
    }

    private func knownMenuBarCandidateApps(from owners: [RunningApp]) -> [NSRunningApplication] {
        let selfPID = ProcessInfo.processInfo.processIdentifier
        var seenPIDs = Set<pid_t>()
        var apps: [NSRunningApplication] = []

        for owner in owners {
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: owner.bundleId).first else {
                continue
            }
            guard app.processIdentifier != selfPID else { continue }
            guard seenPIDs.insert(app.processIdentifier).inserted else { continue }
            apps.append(app)
        }

        return apps
    }

    private func scanKnownMenuBarItemsWithPositions(owners: [RunningApp]) async -> [MenuBarItemPosition] {
        await scanMenuBarItemsWithPositions(
            candidateApps: knownMenuBarCandidateApps(from: owners),
            includeSystemWideFallback: false
        )
    }

    private func scanMenuBarItemsWithPositions(
        candidateApps: [NSRunningApplication],
        includeSystemWideFallback: Bool
    ) async -> [MenuBarItemPosition] {
        guard !candidateApps.isEmpty else {
            accessibilityScanningLogger.debug("No candidate apps available for menu bar item scan")
            return []
        }

        accessibilityScanningLogger.debug(
            "Scanning \(candidateApps.count) candidate apps for menu bar positions (systemWideFallback=\(includeSystemWideFallback, privacy: .public))"
        )

        let results: [ScannedStatusItem] = await withTaskGroup(of: [ScannedStatusItem].self) { group in
            for runningApp in candidateApps {
                group.addTask {
                    autoreleasepool { () -> [ScannedStatusItem] in
                        let pid = runningApp.processIdentifier
                    let appElement = AXUIElementCreateApplication(pid)

                    var extrasBar: CFTypeRef?
                    let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
                    guard result == .success, let bar = extrasBar else { return [] }
                    guard let barElement = safeAXUIElement(bar) else { return [] }

                    var children: CFTypeRef?
                    let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)
                    guard childResult == .success, let items = children as? [AXUIElement] else { return [] }

                    func axString(_ value: CFTypeRef?) -> String? {
                        if let s = value as? String { return s }
                        if let attributed = value as? NSAttributedString { return attributed.string }
                        return nil
                    }

                    var localResults: [ScannedStatusItem] = []

                    var identifiersByIndex: [Int: String] = [:]
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

                    if items.count > 1, !identifiers.isEmpty {
                        let uniqueCount = Set(identifiers).count
                        if uniqueCount != identifiers.count {
                            identifiersByIndex.removeAll(keepingCapacity: true)
                        }
                    }

                    for (index, item) in items.enumerated() {
                        var titleValue: CFTypeRef?
                        AXUIElementCopyAttributeValue(item, kAXTitleAttribute as CFString, &titleValue)
                        let rawTitle = axString(titleValue)?.trimmingCharacters(in: .whitespacesAndNewlines)

                        var descValue: CFTypeRef?
                        AXUIElementCopyAttributeValue(item, kAXDescriptionAttribute as CFString, &descValue)
                        let rawDescription = axString(descValue)?.trimmingCharacters(in: .whitespacesAndNewlines)

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

                        let itemIndex = Self.scannedStatusItemIndex(
                            itemCount: items.count,
                            itemIndex: index,
                            axIdentifier: identifiersByIndex[index]
                        )
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
            }

            var allResults: [ScannedStatusItem] = []
            for await groupResults in group {
                allResults.append(contentsOf: groupResults)
            }
            return allResults
        }

        let axResolvedPIDs = Set(results.map(\.pid))
        let candidatePIDs = Set(candidateApps.map(\.processIdentifier))
        let knownNoExtrasPIDs = Set(candidateApps.compactMap { app -> pid_t? in
            guard let bundleID = Self.resolvedBundleIdentifier(for: app),
                  accessibilityService.likelyLacksExtrasMenuBar(bundleID: bundleID) else {
                return nil
            }
            return app.processIdentifier
        })
        let windowBackedItems = AccessibilityMenuBarWindowFallbackPolicy.windowBackedMenuBarItems(candidatePIDs: candidatePIDs)
        let windowBackedPIDs = Set(windowBackedItems.map(\.pid))
        let topBarHostPIDs = AccessibilityMenuBarWindowFallbackPolicy.topBarHostPIDs(candidatePIDs: candidatePIDs)
        let systemWideItems: [MenuBarItemPosition]
        if includeSystemWideFallback {
            let systemWideCandidatePIDs = AccessibilityMenuBarWindowFallbackPolicy.systemWideFallbackCandidatePIDs(
                axResolvedPIDs: axResolvedPIDs,
                knownNoExtrasPIDs: knownNoExtrasPIDs,
                windowBackedPIDs: windowBackedPIDs,
                topBarHostPIDs: topBarHostPIDs
            )
            let totalScreenWidth = NSScreen.screens.reduce(CGFloat(0)) { partial, screen in
                partial + screen.frame.width
            }
            let systemWideSampleStep = AccessibilitySystemWideMenuBarScanner.recommendedSystemWideSampleStep(
                candidateCount: systemWideCandidatePIDs.count,
                totalScreenWidth: totalScreenWidth
            )
            systemWideItems = systemWideCandidatePIDs.isEmpty
                ? []
                : AccessibilitySystemWideMenuBarScanner.systemWideVisibleMenuBarItems(
                    candidatePIDs: systemWideCandidatePIDs,
                    sampleStep: systemWideSampleStep
                )
        } else {
            systemWideItems = []
        }

        accessibilityScanningLogger.debug("Scanned candidate apps in parallel, found \(results.count) menu bar items")

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

            if bundleID == "com.apple.controlcenter" {
                controlCenterPID = pid
                continue
            }

            if bundleID == "com.apple.systemuiserver" {
                systemUIServerPID = pid
                continue
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
            let key = appModel.uniqueId

            if let existing = appPositions[key] {
                let newX = min(existing.x, x)
                let newWidth = max(existing.width, width)
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

            let fallbackItems = AccessibilityMenuExtraService.enumerateMenuExtraItems(
                pid: pid,
                ownerBundleId: bundleID,
                allowThirdPartyMenuBarFallback: true
            )
            accessibilityScanningLogger.debug("Top-bar host AXMenuBar fallback bundle=\(bundleID, privacy: .public) pid=\(pid, privacy: .public) items=\(fallbackItems.count, privacy: .public)")
            guard AccessibilityMenuBarWindowFallbackPolicy.shouldIncludeThirdPartyTopBarOwner(
                bundleID: bundleID,
                fallbackItemsCount: fallbackItems.count
            ) else { continue }

            if fallbackItems.isEmpty {
                accessibilityService.markExtrasMenuBarUnavailable(bundleID: bundleID)
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

            accessibilityService.markExtrasMenuBarUnavailable(bundleID: bundleID)

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
            AccessibilityMenuBarWindowFallbackPolicy.mergeSystemWideMenuBarItem(item, into: &appPositions)
        }

        if controlCenterPID == nil {
            controlCenterPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.controlcenter").first?.processIdentifier
        }
        if systemUIServerPID == nil {
            systemUIServerPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.systemuiserver").first?.processIdentifier
        }

        if let ccPID = controlCenterPID {
            let ccItems = AccessibilityMenuExtraService.enumerateControlCenterItems(pid: ccPID)
            accessibilityScanningLogger.debug("Expanded Control Center into \(ccItems.count) individual items")
            for item in ccItems {
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

        if let suPID = systemUIServerPID {
            let suItems = AccessibilityMenuExtraService.enumerateMenuExtraItems(pid: suPID, ownerBundleId: "com.apple.systemuiserver")
            accessibilityScanningLogger.debug("Expanded SystemUIServer into \(suItems.count) individual items")
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
        let hiddenCount = apps.filter { $0.x < 0 }.count
        accessibilityScanningLogger.debug("Found \(apps.count) apps with menu bar items (\(hiddenCount) hidden)")
        return apps
    }

}
