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
    private let cacheValiditySeconds: TimeInterval = 5.0

    /// Cache for menu bar item owners (apps only, no positions) - used by Find Icon
    private var menuBarOwnersCache: [RunningApp] = []
    private var menuBarOwnersCacheTime: Date = .distantPast

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
        if now.timeIntervalSince(menuBarOwnersCacheTime) < cacheValiditySeconds && !menuBarOwnersCache.isEmpty {
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

        // Map to RunningApp (unique by bundle ID)
        var seenBundleIDs = Set<String>()
        var apps: [RunningApp] = []
        for pid in pids {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier else { continue }
            guard !seenBundleIDs.contains(bundleID) else { continue }
            seenBundleIDs.insert(bundleID)
            apps.append(RunningApp(app: app))
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
        if now.timeIntervalSince(menuBarItemCacheTime) < cacheValiditySeconds && !menuBarItemCache.isEmpty {
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

        // Convert to RunningApps (unique by bundle ID, taking the minimum x position per app)
        var appPositions: [String: (app: RunningApp, x: CGFloat)] = [:]
        for (pid, x) in results {
            guard let app = NSRunningApplication(processIdentifier: pid),
                  let bundleID = app.bundleIdentifier else { continue }

            // Keep the minimum x position for each app (most hidden position)
            if let existing = appPositions[bundleID] {
                if x < existing.x {
                    appPositions[bundleID] = (app: RunningApp(app: app), x: x)
                }
            } else {
                appPositions[bundleID] = (app: RunningApp(app: app), x: x)
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
        logger.debug("Menu bar item caches invalidated")
    }

    /// Pre-warms the menu bar caches in the background.
    /// Call this on app launch so Find Icon opens instantly.
    func prewarmCache() {
        guard isTrusted else {
            logger.debug("Skipping cache prewarm - accessibility not granted")
            return
        }

        Task.detached(priority: .utility) { @MainActor in
            logger.info("Pre-warming menu bar cache...")
            let startTime = Date()

            // Warm both caches
            _ = self.listMenuBarItemOwners()
            _ = self.listMenuBarItemsWithPositions()

            let elapsed = Date().timeIntervalSince(startTime)
            logger.info("Menu bar cache pre-warmed in \(String(format: "%.2f", elapsed))s")
        }
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
}
