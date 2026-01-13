import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityService")

// MARK: - Accessibility Prompt Helper

/// Request accessibility with system prompt
/// Uses the string key directly to avoid concurrency issues with kAXTrustedCheckOptionPrompt
private nonisolated func requestAccessibilityWithPrompt() -> Bool {
    // "AXTrustedCheckOptionPrompt" is the string value of kAXTrustedCheckOptionPrompt
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

// MARK: - Permission Change Notification

private extension Notification.Name {
    /// System notification sent when ANY app's accessibility permission changes
    /// Not publicly documented, but reliable. From HIServices.framework
    static let AXPermissionsChanged = Notification.Name(rawValue: "com.apple.accessibility.api")
}

// MARK: - Public Notifications

extension Notification.Name {
    /// Posted when menu bar icons have been moved/reorganized
    static let menuBarIconsDidChange = Notification.Name("com.sanebar.menuBarIconsDidChange")
}

// MARK: - AccessibilityService

/// Service for interacting with other apps' menu bar items via Accessibility API.
///
/// **Apple Best Practice**:
/// - Uses standard `AXUIElement` API.
/// - Does NOT use `CGEvent` cursor hijacking (mouse simulation).
/// - Does NOT use private APIs.
/// - Handles `AXPress` actions to simulate clicks natively.
///
/// **Permission Monitoring**:
/// - Listens for system-wide permission change notifications
/// - Streams permission status changes via AsyncStream
/// - UI can react immediately when user grants permission in System Settings
@MainActor
final class AccessibilityService: ObservableObject {

    // MARK: - Singleton

    static let shared = AccessibilityService()

    // MARK: - Published State

    /// Current permission status - updates reactively when permission changes
    @Published private(set) var isGranted: Bool

    // MARK: - Permission Monitoring

    private var permissionMonitorTask: Task<Void, Never>?
    private var streamContinuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    // MARK: - Menu Bar Item Cache

    /// Cache for menu bar item positions to avoid expensive rescans
    private var menuBarItemCache: [(app: RunningApp, x: CGFloat)] = []
    private var menuBarItemCacheTime: Date = .distantPast
    private let menuBarItemCacheValiditySeconds: TimeInterval = 5.0  // Refresh every 5 seconds for accurate positions

    /// Cache for menu bar item owners (apps only, no positions) - used by Find Icon
    private var menuBarOwnersCache: [RunningApp] = []
    private var menuBarOwnersCacheTime: Date = .distantPast
    private let menuBarOwnersCacheValiditySeconds: TimeInterval = 10.0  // Refresh every 10 seconds for responsive UI

    private var menuBarOwnersRefreshTask: Task<[RunningApp], Never>?
    private var menuBarItemsRefreshTask: Task<[(app: RunningApp, x: CGFloat)], Never>?

    // MARK: - Initialization

    private init() {
        self.isGranted = AXIsProcessTrusted()
        startPermissionMonitoring()
    }

    deinit {
        permissionMonitorTask?.cancel()
        for continuation in streamContinuations.values {
            continuation.finish()
        }
    }

    // MARK: - Permission Streaming

    /// Stream permission status changes. Use this for reactive UI updates.
    /// - Parameter includeInitial: Whether to emit the current status immediately
    /// - Returns: AsyncStream that yields `true` when granted, `false` when revoked
    func permissionStream(includeInitial: Bool = true) -> AsyncStream<Bool> {
        AsyncStream<Bool> { continuation in
            let id = UUID()
            self.streamContinuations[id] = continuation

            if includeInitial {
                continuation.yield(self.isGranted)
            }

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.streamContinuations[id] = nil
                }
            }
        }
    }

    private func startPermissionMonitoring() {
        permissionMonitorTask = Task { [weak self] in
            let notifications = DistributedNotificationCenter.default()
                .notifications(named: .AXPermissionsChanged)

            for await _ in notifications {
                // Small delay - notification fires before status update sometimes
                try? await Task.sleep(for: .milliseconds(250))

                await MainActor.run {
                    self?.checkAndUpdatePermissionStatus()
                }
            }
        }
    }

    private func checkAndUpdatePermissionStatus() {
        let newStatus = AXIsProcessTrusted()
        guard newStatus != isGranted else { return }

        isGranted = newStatus
        logger.info("Accessibility permission changed: \(newStatus ? "GRANTED" : "REVOKED")")

        // Notify all streams
        for continuation in streamContinuations.values {
            continuation.yield(newStatus)
        }
    }

    // MARK: - API Verification

    /// Checks if we have accessibility permissions (legacy - prefer `isGranted` property)
    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Request accessibility permission - shows system prompt if not trusted
    /// Returns true if already trusted, false if user needs to grant permission
    @discardableResult
    func requestAccessibility() -> Bool {
        let trusted = requestAccessibilityWithPrompt()
        if !trusted {
            logger.info("Accessibility not trusted - system prompt shown")
        } else {
            // Update our cached state if already granted
            if !isGranted {
                isGranted = true
                for continuation in streamContinuations.values {
                    continuation.yield(true)
                }
            }
        }
        return trusted
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

        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            logger.warning("App not running: \(bundleID)")
            return false
        }

        return clickSystemWideItem(for: app.processIdentifier)
    }

    // MARK: - Cached Results (Fast)

    func cachedMenuBarItemOwners() -> [RunningApp] {
        menuBarOwnersCache
    }

    func cachedMenuBarItemsWithPositions() -> [(app: RunningApp, x: CGFloat)] {
        menuBarItemCache
    }

    // MARK: - Async Refresh (Non-blocking)

    func refreshMenuBarItemOwners() async -> [RunningApp] {
        guard isTrusted else { return [] }

        let now = Date()
        if now.timeIntervalSince(menuBarOwnersCacheTime) < menuBarOwnersCacheValiditySeconds && !menuBarOwnersCache.isEmpty {
            return menuBarOwnersCache
        }

        if let task = menuBarOwnersRefreshTask {
            return await task.value
        }

        let task = Task<[RunningApp], Never> {
            // Candidate apps list must be gathered on the main thread.
            let candidatePIDs: [pid_t] = NSWorkspace.shared.runningApplications.compactMap { app in
                guard let bundleID = app.bundleIdentifier else { return nil }
                guard bundleID != Bundle.main.bundleIdentifier else { return nil }
                return app.processIdentifier
            }

            let pidsWithExtras = await Task.detached(priority: .utility) {
                Self.scanMenuBarOwnerPIDs(candidatePIDs: candidatePIDs)
            }.value

            var seenIds = Set<String>()
            var apps: [RunningApp] = []
            apps.reserveCapacity(pidsWithExtras.count)
            var controlCenterPID: pid_t?

            for pid in pidsWithExtras {
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
                for item in ccItems {
                    let key = item.app.uniqueId
                    guard !seenIds.contains(key) else { continue }
                    seenIds.insert(key)
                    apps.append(item.app)
                }
            }

            let sortedApps = apps.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
            self.menuBarOwnersCache = sortedApps
            self.menuBarOwnersCacheTime = Date()
            return sortedApps
        }

        menuBarOwnersRefreshTask = task
        let result = await task.value
        menuBarOwnersRefreshTask = nil
        return result
    }

    func refreshMenuBarItemsWithPositions() async -> [(app: RunningApp, x: CGFloat)] {
        guard isTrusted else { return [] }

        let now = Date()
        if now.timeIntervalSince(menuBarItemCacheTime) < menuBarItemCacheValiditySeconds && !menuBarItemCache.isEmpty {
            return menuBarItemCache
        }

        if let task = menuBarItemsRefreshTask {
            return await task.value
        }

        let task = Task<[(app: RunningApp, x: CGFloat)], Never> {
            // Candidate apps list must be gathered on the main thread.
            let candidatePIDs: [pid_t] = NSWorkspace.shared.runningApplications.compactMap { app in
                guard let bundleID = app.bundleIdentifier else { return nil }
                guard bundleID != Bundle.main.bundleIdentifier else { return nil }
                return app.processIdentifier
            }

            let pidMinX = await Task.detached(priority: .utility) {
                Self.scanMenuBarAppMinXPositions(candidatePIDs: candidatePIDs)
            }.value

            var appPositions: [String: (app: RunningApp, x: CGFloat)] = [:]
            var controlCenterPID: pid_t?

            for (pid, x) in pidMinX {
                guard let app = NSRunningApplication(processIdentifier: pid),
                      let bundleID = app.bundleIdentifier else { continue }

                // Special case: Control Center - remember its PID for later expansion
                if bundleID == "com.apple.controlcenter" {
                    controlCenterPID = pid
                    continue  // Don't add the collapsed entry
                }

                if let existing = appPositions[bundleID] {
                    if x < existing.x {
                        appPositions[bundleID] = (app: RunningApp(app: app), x: x)
                    }
                } else {
                    appPositions[bundleID] = (app: RunningApp(app: app), x: x)
                }
            }

            // Expand Control Center into individual items (Battery, WiFi, Clock, etc.)
            if let ccPID = controlCenterPID {
                let ccItems = Self.enumerateControlCenterItems(pid: ccPID)
                for item in ccItems {
                    let key = item.app.uniqueId
                    appPositions[key] = item
                }
            }

            let apps = Array(appPositions.values).sorted { $0.x < $1.x }
            self.menuBarItemCache = apps
            self.menuBarItemCacheTime = Date()
            return apps
        }

        menuBarItemsRefreshTask = task
        let result = await task.value
        menuBarItemsRefreshTask = nil
        return result
    }

    // MARK: - System Wide Search

    /// Best-effort list of apps that currently own a menu bar status item.
    /// This is much closer to "things in the menu bar" than `NSWorkspace.runningApplications`.
    ///
    /// NOTE: We scan running apps for their AXExtrasMenuBar attribute.
    /// OPTIMIZATION: Results cached for 5 seconds. Only scans apps with bundle identifiers.
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
    ///
    /// NOTE: The AXExtrasMenuBar attribute is NOT available on AXSystemWide.
    /// We must get it from individual applications that have menu bar extras.
    /// Each app owns its own status items, so we scan all running apps.
    ///
    /// HOW HIDING WORKS:
    /// - SaneBar hides icons by expanding its delimiter to 10,000px
    /// - This pushes icons to the LEFT of the delimiter off the screen
    /// - Hidden items have NEGATIVE x coordinates (e.g., -4256)
    /// - Visible items have POSITIVE x coordinates (e.g., 1337)
    ///
    /// PERFORMANCE OPTIMIZATION:
    /// - Results are cached for 5 seconds to avoid expensive rescans
    /// - Only apps with bundle identifiers are scanned (skips XPC services, system agents)
    /// - This reduces scan time from minutes to milliseconds on subsequent calls
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
                    appPositions[bundleID] = (app: RunningApp(app: app), x: x)
                }
            } else {
                appPositions[bundleID] = (app: RunningApp(app: app), x: x)
            }
        }

        // Expand Control Center into individual items (Battery, WiFi, Clock, etc.)
        if let ccPID = controlCenterPID {
            let ccItems = Self.enumerateControlCenterItems(pid: ccPID)
            logger.debug("Expanded Control Center into \(ccItems.count) individual items")
            for item in ccItems {
                // Use uniqueId (menuExtraIdentifier) as the key for Control Center items
                let key = item.app.uniqueId
                appPositions[key] = item
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

    /// Invalidates all menu bar caches, forcing a fresh scan on next call.
    /// Call this when you know menu bar items have changed (e.g., after hiding/showing).
    func invalidateMenuBarItemCache() {
        menuBarItemCacheTime = .distantPast
        menuBarOwnersCacheTime = .distantPast
        menuBarOwnersRefreshTask?.cancel()
        menuBarItemsRefreshTask?.cancel()
        menuBarOwnersRefreshTask = nil
        menuBarItemsRefreshTask = nil
        logger.debug("Menu bar item caches invalidated")
    }

    /// Pre-warms the menu bar caches in the background.
    /// Call this on app launch so Find Icon opens instantly.
    func prewarmCache() {
        guard isTrusted else {
            logger.debug("Skipping cache prewarm - accessibility not granted")
            return
        }

        Task.detached(priority: .utility) { [weak self] in
            guard let self else { return }
            logger.info("Pre-warming menu bar cache...")
            let startTime = Date()

            // Warm both caches (off the main thread)
            _ = await self.refreshMenuBarItemOwners()
            _ = await self.refreshMenuBarItemsWithPositions()

            let elapsed = Date().timeIntervalSince(startTime)
            logger.info("Menu bar cache pre-warmed in \(String(format: "%.2f", elapsed))s")
        }
    }

    // MARK: - Control Center Item Enumeration

    /// Enumerates individual Control Center items (Battery, WiFi, Clock, etc.)
    /// Returns virtual RunningApp instances for each item with positions.
    ///
    /// Control Center owns multiple independent menu bar icons under a single bundle ID.
    /// This method extracts each as a separate entry using AXIdentifier and AXDescription.
    private nonisolated static func enumerateControlCenterItems(pid: pid_t) -> [(app: RunningApp, x: CGFloat)] {
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

    private nonisolated static func scanMenuBarOwnerPIDs(candidatePIDs: [pid_t]) -> [pid_t] {
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

    private nonisolated static func scanMenuBarAppMinXPositions(candidatePIDs: [pid_t]) -> [(pid: pid_t, x: CGFloat)] {
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

    private func clickSystemWideItem(for targetPID: pid_t) -> Bool {
        let appElement = AXUIElementCreateApplication(targetPID)

        var extrasBar: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)

        guard result == .success, let bar = extrasBar else {
            logger.debug("App \(targetPID) has no AXExtrasMenuBar")
            return false
        }

        // swiftlint:disable:next force_cast
        let barElement = bar as! AXUIElement
        var children: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)

        guard childResult == .success, let items = children as? [AXUIElement], !items.isEmpty else {
            logger.debug("No items in app's Extras Menu Bar")
            return false
        }

        logger.info("Found \(items.count) status item(s) for PID \(targetPID)")
        return performPress(on: items[0])
    }

    // MARK: - Interaction

    private func performPress(on element: AXUIElement) -> Bool {
        // Try AXPress - the standard action for buttons/menu items
        let error = AXUIElementPerformAction(element, kAXPressAction as CFString)

        if error == .success {
            logger.info("AXPress successful")
            return true
        }

        logger.debug("AXPress failed with error: \(error.rawValue)")

        // Try AXShowMenu as fallback (some apps use this instead)
        var actionNames: CFArray?
        if AXUIElementCopyActionNames(element, &actionNames) == .success,
           let names = actionNames as? [String],
           names.contains("AXShowMenu") {
            let menuError = AXUIElementPerformAction(element, "AXShowMenu" as CFString)
            if menuError == .success {
                logger.info("AXShowMenu successful")
                return true
            }
        }

        return false
    }

    // MARK: - Icon Moving (CGEvent-based)

    /// Move a menu bar icon to visible or hidden position using CGEvent Cmd+drag
    /// - Parameters:
    ///   - bundleID: The bundle ID of the app whose icon to move
    ///   - menuExtraId: For Control Center items, the specific menu extra identifier (e.g., "com.apple.menuextra.battery")
    ///   - toHidden: If true, move LEFT of separator (hidden). If false, move RIGHT (visible).
    ///   - separatorX: The X position of the separator's RIGHT edge
    ///   - mainIconX: The X position of the main SaneBar icon's LEFT edge (visible zone boundary)
    /// - Returns: True if successful
    func moveMenuBarIcon(bundleID: String, menuExtraId: String? = nil, toHidden: Bool, separatorX: CGFloat, mainIconX: CGFloat? = nil) -> Bool {
        logger.error("🔧 moveMenuBarIcon: bundleID=\(bundleID), menuExtraId=\(menuExtraId ?? "nil"), toHidden=\(toHidden), separatorX=\(separatorX), mainIconX=\(mainIconX ?? -1)")

        guard isTrusted else {
            logger.error("🔧 Accessibility permission not granted")
            return false
        }

        // Find the icon's current position
        guard let iconPosition = getMenuBarIconPosition(bundleID: bundleID, menuExtraId: menuExtraId) else {
            logger.error("🔧 Could not find icon position for \(bundleID) (menuExtraId: \(menuExtraId ?? "nil"))")
            return false
        }

        logger.error("🔧 Icon position: x=\(iconPosition.x), width=\(iconPosition.width)")

        // SaneBar menu bar layout:
        // [Apple] [App Menus] ... [HIDDEN ICONS] | SEPARATOR | [VISIBLE ICONS] [SaneBar Icon ≡] [System tray]
        //
        // LEFT of separator (lower X) = HIDDEN
        // RIGHT of separator but LEFT of main SaneBar icon = VISIBLE
        //
        // To HIDE: drag icon to LEFT of separator (targetX < separatorX)
        // To SHOW: drag icon to RIGHT of separator but LEFT of main icon (separatorX < targetX < mainIconX)
        let targetX: CGFloat
        if toHidden {
            // Move to hidden zone - left of separator
            targetX = separatorX - 100
        } else if let mainX = mainIconX {
            // Move to visible zone - between separator and main SaneBar icon
            // Target the midpoint of the visible zone for best placement
            let visibleZoneWidth = mainX - separatorX
            if visibleZoneWidth > 50 {
                // Place icon 30px to the right of separator (near the separator end of visible zone)
                targetX = separatorX + 30
            } else {
                // Very narrow visible zone - place in the middle
                targetX = separatorX + (visibleZoneWidth / 2)
            }
            logger.error("🔧 Visible zone: separator=\(separatorX), mainIcon=\(mainX), width=\(visibleZoneWidth)")
        } else {
            // Fallback if mainIconX not provided - just use separator + 100
            targetX = separatorX + 100
            logger.error("🔧 Warning: mainIconX not provided, using fallback targetX=\(targetX)")
        }

        logger.error("🔧 Target X: \(targetX) (toHidden=\(toHidden), separator=\(separatorX), mainIcon=\(mainIconX ?? -1))")

        // CGEvent uses top-left screen coordinates (Quartz coordinate system)
        // Menu bar is at y=0 to y≈24, middle is around y=12
        let menuBarY: CGFloat = 12

        // The icon's X position from AX API is already in screen coordinates
        let fromPoint = CGPoint(x: iconPosition.x + iconPosition.width / 2, y: menuBarY)
        let toPoint = CGPoint(x: targetX, y: menuBarY)

        logger.error("🔧 CGEvent drag from (\(fromPoint.x), \(fromPoint.y)) to (\(toPoint.x), \(toPoint.y))")

        // Perform Cmd+drag using CGEvent
        return performCmdDrag(from: fromPoint, to: toPoint)
    }

    /// Get the position and size of a menu bar icon
    /// - Parameters:
    ///   - bundleID: The bundle ID of the app
    ///   - menuExtraId: For Control Center items, the specific AXIdentifier to find
    private func getMenuBarIconPosition(bundleID: String, menuExtraId: String? = nil) -> (x: CGFloat, width: CGFloat)? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return nil
        }

        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var extrasBar: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(appElement, "AXExtrasMenuBar" as CFString, &extrasBar)
        guard result == .success, let bar = extrasBar else { return nil }
        guard CFGetTypeID(bar) == AXUIElementGetTypeID() else { return nil }
        // swiftlint:disable:next force_cast
        let barElement = bar as! AXUIElement

        var children: CFTypeRef?
        let childResult = AXUIElementCopyAttributeValue(barElement, kAXChildrenAttribute as CFString, &children)
        guard childResult == .success, let items = children as? [AXUIElement], !items.isEmpty else { return nil }

        // Find the correct item - either by menuExtraId or just take the first one
        var targetItem: AXUIElement?

        if let extraId = menuExtraId {
            // For Control Center items, find the specific one by AXIdentifier
            for item in items {
                var identifierValue: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXIdentifierAttribute as CFString, &identifierValue)
                if let identifier = identifierValue as? String, identifier == extraId {
                    targetItem = item
                    logger.debug("🔧 Found Control Center item with identifier: \(extraId)")
                    break
                }
            }
            if targetItem == nil {
                logger.error("🔧 Could not find Control Center item with identifier: \(extraId)")
                return nil
            }
        } else {
            // For regular apps, take the first item
            targetItem = items[0]
        }

        guard let item = targetItem else { return nil }

        // Get position
        var positionValue: CFTypeRef?
        let posResult = AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &positionValue)
        guard posResult == .success, let posValue = positionValue else { return nil }
        guard CFGetTypeID(posValue) == AXValueGetTypeID() else { return nil }

        var point = CGPoint.zero
        // swiftlint:disable:next force_cast
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &point) else { return nil }

        // Get size
        var sizeValue: CFTypeRef?
        let sizeResult = AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &sizeValue)
        var width: CGFloat = 22  // Default width
        if sizeResult == .success, let sizeVal = sizeValue, CFGetTypeID(sizeVal) == AXValueGetTypeID() {
            var size = CGSize.zero
            // swiftlint:disable:next force_cast
            if AXValueGetValue(sizeVal as! AXValue, .cgSize, &size) {
                width = size.width
            }
        }

        return (x: point.x, width: width)
    }

    /// Perform a Cmd+drag operation using CGEvent (runs on background thread)
    private func performCmdDrag(from: CGPoint, to: CGPoint) -> Bool {
        // Capture current mouse position BEFORE dispatching to background thread
        // NSEvent.mouseLocation uses bottom-left origin, CGEvent uses top-left
        let currentMouseLocation = NSEvent.mouseLocation
        let screenHeight = NSScreen.main?.frame.height ?? 0
        let savedPosition = CGPoint(
            x: currentMouseLocation.x,
            y: screenHeight - currentMouseLocation.y
        )

        // Run CGEvent posting on a background thread to avoid blocking UI
        DispatchQueue.global(qos: .userInitiated).async {
            // Create mouse down event with Cmd modifier
            guard let mouseDown = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDown,
                mouseCursorPosition: from,
                mouseButton: .left
            ) else {
                logger.error("Failed to create mouse down event")
                return
            }
            mouseDown.flags = .maskCommand  // Hold Cmd key

            // Create drag event
            guard let mouseDrag = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseDragged,
                mouseCursorPosition: to,
                mouseButton: .left
            ) else {
                logger.error("Failed to create mouse drag event")
                return
            }
            mouseDrag.flags = .maskCommand

            // Create mouse up event
            guard let mouseUp = CGEvent(
                mouseEventSource: nil,
                mouseType: .leftMouseUp,
                mouseCursorPosition: to,
                mouseButton: .left
            ) else {
                logger.error("Failed to create mouse up event")
                return
            }

            // Post events with minimal delays for reliability
            mouseDown.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.02)

            mouseDrag.post(tap: .cghidEventTap)
            Thread.sleep(forTimeInterval: 0.03)

            mouseUp.post(tap: .cghidEventTap)

            // Restore cursor to original position after a brief delay
            Thread.sleep(forTimeInterval: 0.05)
            CGWarpMouseCursorPosition(savedPosition)

            // Invalidate cache on main thread
            DispatchQueue.main.async {
                self.invalidateMenuBarItemCache()
            }
        }

        return true  // Return immediately, operation happens async
    }
}
