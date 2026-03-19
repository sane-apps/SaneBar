import AppKit
import Foundation
import os.log

// swiftlint:disable file_length
private let logger = Logger(subsystem: "com.sanebar.app", category: "AppleScriptCommands")
// MARK: - AppleScript Commands
/// Base class for SaneBar AppleScript commands
class SaneBarScriptCommand: NSScriptCommand {
    /// Set AppleScript error when auth blocks the command
    func setAuthBlockedError() {
        scriptErrorNumber = errOSAGeneralError
        scriptErrorString = "Touch ID protection is enabled. Use the SaneBar menu bar icon to authenticate first."
    }
    /// Set AppleScript error when Accessibility permission is missing
    func setAccessibilityError() {
        scriptErrorNumber = errOSAGeneralError
        scriptErrorString = "Accessibility permission is required. Grant SaneBar access in System Settings > Privacy & Security > Accessibility."
    }
    /// Check if Accessibility permission is granted (safe to call from any thread)
    func checkAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }
    /// Check if auth is required (main-thread safe without capturing self)
    func checkAuthRequired() -> Bool {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                MenuBarManager.shared.settings.requireAuthToShowHiddenIcons
            }
        } else {
            DispatchQueue.main.sync {
                MenuBarManager.shared.settings.requireAuthToShowHiddenIcons
            }
        }
    }
    /// Check if hidden items are currently hidden (main-thread safe)
    func checkIsHidden() -> Bool {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                MenuBarManager.shared.hidingService.state == .hidden
            }
        } else {
            DispatchQueue.main.sync {
                MenuBarManager.shared.hidingService.state == .hidden
            }
        }
    }
}

@MainActor
private func runScriptRead<T>(
    timeoutSeconds: TimeInterval = 15.0,
    operation: @escaping @MainActor () async -> T
) -> T? {
    let box = ScriptResultBox<T?>(nil)
    Task { @MainActor in
        box.value = await operation()
    }

    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while box.value == nil, Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    return box.value
}

// MARK: - Toggle Command
@objc(ToggleCommand)
final class ToggleCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // Block if auth is required AND we'd be showing (expanding from hidden)
        // AppleScript can't prompt Touch ID, so we must block entirely
        if checkAuthRequired(), checkIsHidden() {
            setAuthBlockedError()
            return nil
        }
        Task { @MainActor in
            MenuBarManager.shared.toggleHiddenItems()
        }
        return nil
    }
}
// MARK: - Show Command
@objc(ShowCommand)
final class ShowCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // Only block if auth is required AND icons are currently hidden
        // (no need to block if they're already visible)
        if checkAuthRequired(), checkIsHidden() {
            setAuthBlockedError()
            return nil
        }
        Task { @MainActor in
            MenuBarManager.shared.showHiddenItems()
        }
        return nil
    }
}
// MARK: - Hide Command
@objc(HideCommand)
final class HideCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            MenuBarManager.shared.hideHiddenItems()
        }
        return true
    }
}
// MARK: - Browse Panel Commands
@objc(ShowIconPanelCommand)
final class ShowIconPanelCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        if checkAuthRequired(), checkIsHidden() {
            setAuthBlockedError()
            return nil
        }
        Task { @MainActor in
            let manager = MenuBarManager.shared
            _ = await manager.showHiddenItemsNow(trigger: .search)
            SearchWindowController.shared.show(mode: .findIcon)
        }
        return true
    }
}
@objc(ShowSecondMenuBarCommand)
final class ShowSecondMenuBarCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        if checkAuthRequired(), checkIsHidden() {
            setAuthBlockedError()
            return nil
        }
        Task { @MainActor in
            let manager = MenuBarManager.shared
            _ = await manager.showHiddenItemsNow(trigger: .search)
            SearchWindowController.shared.show(mode: .secondMenuBar)
        }
        return true
    }
}
@objc(CloseBrowsePanelCommand)
final class CloseBrowsePanelCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            SearchWindowController.shared.close()
        }
        return true
    }
}

@objc(CaptureBrowsePanelSnapshotCommand)
final class CaptureBrowsePanelSnapshotCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let rawPath = directParameter as? String else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Expected a filesystem path string."
            return nil
        }

        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Expected a filesystem path string."
            return nil
        }

        let didCapture: Bool = if Thread.isMainThread {
            MainActor.assumeIsolated {
                SearchWindowController.shared.captureBrowsePanelSnapshotPNG(to: path)
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    SearchWindowController.shared.captureBrowsePanelSnapshotPNG(to: path)
                }
            }
        }

        guard didCapture else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Browse panel snapshot failed. Make sure the panel is visible first."
            return nil
        }

        return true
    }
}

@objc(QueueBrowsePanelSnapshotCommand)
final class QueueBrowsePanelSnapshotCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let rawPath = directParameter as? String else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Expected a filesystem path string."
            return nil
        }

        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Expected a filesystem path string."
            return nil
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            _ = SearchWindowController.shared.captureBrowsePanelSnapshotPNG(to: path)
        }
        return true
    }
}
// MARK: - Thread-Safe Box
/// Thread-safe box for passing values between Task closures and synchronous code.
/// The semaphore provides the synchronization guarantee.
final class ScriptResultBox<T>: @unchecked Sendable {
    var value: T
    init(_ initial: T) { value = initial }
}

enum ScriptIconZone: String {
    case visible
    case hidden
    case alwaysHidden
}

typealias ScriptClassifiedApps = SearchClassifiedApps
typealias ScriptZonedIcon = (app: RunningApp, zone: ScriptIconZone)
struct ScriptIconIdentity: Sendable {
    let uniqueId: String
    let bundleId: String
    let menuExtraIdentifier: String?
    let statusItemIndex: Int?

    init(app: RunningApp) {
        uniqueId = app.uniqueId
        bundleId = app.bundleId
        menuExtraIdentifier = app.menuExtraIdentifier
        statusItemIndex = app.statusItemIndex
    }

    init?(identifier: String) {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        uniqueId = trimmed
        if let range = trimmed.range(of: "::axid:") {
            bundleId = String(trimmed[..<range.lowerBound])
            let menuExtra = String(trimmed[range.upperBound...])
            menuExtraIdentifier = menuExtra.isEmpty ? nil : menuExtra
            statusItemIndex = nil
            return
        }

        if let range = trimmed.range(of: "::statusItem:") {
            bundleId = String(trimmed[..<range.lowerBound])
            let indexString = String(trimmed[range.upperBound...])
            statusItemIndex = Int(indexString)
            menuExtraIdentifier = nil
            return
        }

        bundleId = trimmed
        menuExtraIdentifier = nil
        statusItemIndex = nil
    }

    func matches(_ app: RunningApp) -> Bool {
        if app.uniqueId == uniqueId {
            return true
        }
        if let menuExtraIdentifier,
           app.bundleId == bundleId,
           app.menuExtraIdentifier == menuExtraIdentifier {
            return true
        }
        if let statusItemIndex,
           app.bundleId == bundleId,
           app.statusItemIndex == statusItemIndex {
            return true
        }
        return menuExtraIdentifier == nil && statusItemIndex == nil && app.bundleId == bundleId
    }
}
@MainActor
private func zones(from classified: ScriptClassifiedApps) -> [ScriptZonedIcon] {
    var icons: [ScriptZonedIcon] = []
    icons.reserveCapacity(classified.visible.count + classified.hidden.count + classified.alwaysHidden.count)
    icons += classified.visible.map { ($0, .visible) }
    icons += classified.hidden.map { ($0, .hidden) }
    icons += classified.alwaysHidden.map { ($0, .alwaysHidden) }
    return icons
}
@MainActor
private func currentIconZones() -> [ScriptZonedIcon] {
    var classified: ScriptClassifiedApps = SearchService.shared.cachedClassifiedApps()
    if classified.visible.isEmpty, classified.hidden.isEmpty, classified.alwaysHidden.isEmpty {
        Task { @MainActor in
            _ = await SearchService.shared.refreshClassifiedApps()
        }
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.35))
        classified = SearchService.shared.cachedClassifiedApps()
    }
    return zones(from: classified)
}

func sortedScriptZones(_ zones: [ScriptZonedIcon]) -> [ScriptZonedIcon] {
    zones.sorted { lhs, rhs in
        if lhs.zone.rawValue == rhs.zone.rawValue {
            return (lhs.app.xPosition ?? 0) < (rhs.app.xPosition ?? 0)
        }
        return lhs.zone.rawValue < rhs.zone.rawValue
    }
}

func preferredScriptListingZones(
    cached: [ScriptZonedIcon],
    refreshed: @autoclosure () -> [ScriptZonedIcon]
) -> [ScriptZonedIcon] {
    sortedScriptZones(cached.isEmpty ? refreshed() : cached)
}

@MainActor
private func runScriptMove(timeoutSeconds: TimeInterval = 6.5, operation: @escaping @MainActor () async -> Bool) -> Bool? {
    let box = ScriptResultBox<Bool?>(nil)
    Task { @MainActor in
        box.value = await operation()
    }

    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while box.value == nil, Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return box.value
}

@MainActor
private func refreshedIconZones(timeoutSeconds: TimeInterval = 2.5) -> [ScriptZonedIcon] {
    let result = ScriptResultBox<ScriptClassifiedApps?>(nil)
    Task { @MainActor in
        result.value = await SearchService.shared.refreshClassifiedApps()
    }

    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while result.value == nil, Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    if let classified = result.value {
        return zones(from: classified)
    }

    // If refresh timed out, invalidate AX cache and try once more before
    // falling back to the cached classification snapshot.
    AccessibilityService.shared.invalidateMenuBarItemCache()
    let retryResult = ScriptResultBox<ScriptClassifiedApps?>(nil)
    Task { @MainActor in
        retryResult.value = await SearchService.shared.refreshClassifiedApps()
    }

    let retryDeadline = Date().addingTimeInterval(1.2)
    while retryResult.value == nil, Date() < retryDeadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    if let retryClassified = retryResult.value {
        return zones(from: retryClassified)
    }

    return currentIconZones()
}

@MainActor
func zonesForScriptResolution(_ identifier: String) -> [ScriptZonedIcon] {
    let cached = currentIconZones()
    if resolveScriptIcon(identifier, from: cached) != nil {
        return cached
    }

    AccessibilityService.shared.invalidateMenuBarItemCache()
    return refreshedIconZones(timeoutSeconds: 1.2)
}

func shouldPreferFreshZonesForScriptMove(
    identifier: String,
    matchedApp: RunningApp,
    sameBundleCount: Int
) -> Bool {
    if matchedApp.hasPreciseMenuBarIdentity, matchedApp.uniqueId == identifier {
        return true
    }
    if matchedApp.menuExtraIdentifier == identifier {
        return true
    }
    if let statusItemIndex = matchedApp.statusItemIndex,
       identifier == "\(matchedApp.bundleId)::statusItem:\(statusItemIndex)" {
        return true
    }
    return sameBundleCount > 1
}

@MainActor
func zonesForScriptMoveResolution(_ identifier: String) -> [ScriptZonedIcon] {
    let cached = currentIconZones()
    guard let matched = resolveScriptIcon(identifier, from: cached) else {
        AccessibilityService.shared.invalidateMenuBarItemCache()
        return refreshedIconZones(timeoutSeconds: 1.8)
    }

    let sameBundleCount = cached.reduce(into: 0) { count, item in
        if item.app.bundleId == matched.app.bundleId {
            count += 1
        }
    }

    guard shouldPreferFreshZonesForScriptMove(
        identifier: identifier,
        matchedApp: matched.app,
        sameBundleCount: sameBundleCount
    ) else {
        return cached
    }

    AccessibilityService.shared.invalidateMenuBarItemCache()
    let refreshed = refreshedIconZones(timeoutSeconds: 1.8)
    if resolveScriptIcon(identifier, from: refreshed) != nil {
        return refreshed
    }
    return cached
}

func parseIconIdentifier(_ raw: Any?) -> String? {
    guard let iconId = raw as? String else { return nil }
    let trimmed = iconId.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

func scriptErrorIconIdMissing(_ command: NSScriptCommand) {
    command.scriptErrorNumber = errOSAGeneralError
    command.scriptErrorString = "Expected an icon identifier string."
}

func scriptErrorIconNotFound(_ command: NSScriptCommand, iconId: String) {
    command.scriptErrorNumber = errOSAGeneralError
    command.scriptErrorString = "Icon '\(iconId)' not found. Use 'list icon zones' to see available identifiers."
}

func scriptErrorOperationTimedOut(_ command: NSScriptCommand) {
    command.scriptErrorNumber = errOSAGeneralError
    command.scriptErrorString = "Operation timed out. SaneBar may be busy — try again."
}

private func scriptErrorMoveFailed(_ command: NSScriptCommand, iconId: String, target: ScriptIconZone) {
    command.scriptErrorNumber = errOSAGeneralError
    command.scriptErrorString = "Icon '\(iconId)' failed to move to \(target.rawValue)."
}

func scriptIdentifierMatches(_ identifier: String, app: RunningApp) -> Bool {
    if app.uniqueId == identifier || app.bundleId == identifier {
        return true
    }
    if app.menuExtraIdentifier == identifier {
        return true
    }
    if let statusItemIndex = app.statusItemIndex,
       identifier == "\(app.bundleId)::statusItem:\(statusItemIndex)" {
        return true
    }
    return false
}

@MainActor
func resolveScriptIcon(_ identifier: String, from zones: [ScriptZonedIcon]) -> ScriptZonedIcon? {
    if let exact = zones.first(where: { scriptIdentifierMatches(identifier, app: $0.app) }) {
        return exact
    }

    guard let identity = ScriptIconIdentity(identifier: identifier) else { return nil }
    let sameBundle = zones.filter { $0.app.bundleId == identity.bundleId }
    if sameBundle.count == 1 {
        return sameBundle.first
    }

    let coarseFallback = sameBundle.filter { !$0.app.hasPreciseMenuBarIdentity }
    if coarseFallback.count == 1 {
        return coarseFallback.first
    }

    return nil
}

@MainActor
private func waitForScriptZone(
    iconUniqueID: String,
    expected: ScriptIconZone,
    timeoutSeconds: TimeInterval = 12.0,
    pollIntervalSeconds: TimeInterval = 0.25
) -> Bool {
    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while Date() < deadline {
        let zones = refreshedIconZones()
        if let matched = zones.first(where: { $0.app.uniqueId == iconUniqueID }),
           matched.zone == expected {
            return true
        }
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(pollIntervalSeconds))
    }

    // One final strict pass with explicit AX cache invalidation before
    // declaring failure. Some menu-extra relayouts commit late.
    for _ in 0 ..< 3 {
        AccessibilityService.shared.invalidateMenuBarItemCache()
        let zones = refreshedIconZones(timeoutSeconds: 2.0)
        if let matched = zones.first(where: { $0.app.uniqueId == iconUniqueID }),
           matched.zone == expected {
            return true
        }
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.2))
    }

    return false
}

// MARK: - List Icons Command

@objc(ListIconsCommand)
final class ListIconsCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard checkAccessibilityTrusted() else {
            setAccessibilityError()
            return nil
        }

        let apps: [RunningApp]? =
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    runScriptRead(timeoutSeconds: 15.0) {
                        await SearchService.shared.refreshMenuBarApps()
                    }
                }
            } else {
                DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        runScriptRead(timeoutSeconds: 15.0) {
                            await SearchService.shared.refreshMenuBarApps()
                        }
                    }
                }
            }

        guard let apps else {
            scriptErrorOperationTimedOut(self)
            return nil
        }

        let lines = apps.map { app in
            "\(app.uniqueId)\t\(app.name)"
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - List Icon Zones Command

@objc(ListIconZonesCommand)
final class ListIconZonesCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard checkAccessibilityTrusted() else {
            setAccessibilityError()
            return nil
        }

        let zones: [ScriptZonedIcon] = if Thread.isMainThread {
            MainActor.assumeIsolated {
                preferredScriptListingZones(
                    cached: currentIconZones(),
                    refreshed: refreshedIconZones(timeoutSeconds: 1.2)
                )
            }
        } else {
            DispatchQueue.main.sync {
                preferredScriptListingZones(
                    cached: currentIconZones(),
                    refreshed: refreshedIconZones(timeoutSeconds: 1.2)
                )
            }
        }

        let lines = zones.map { item in
            let movable = item.app.isUnmovableSystemItem ? "false" : "true"
            return "\(item.zone.rawValue)\t\(movable)\t\(item.app.bundleId)\t\(item.app.uniqueId)\t\(item.app.name)"
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Layout Snapshot Command

@objc(LayoutSnapshotCommand)
final class LayoutSnapshotCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let json: String
        if Thread.isMainThread {
            json = MainActor.assumeIsolated {
                Self.collectSnapshotJSONOnMain()
            }
        } else {
            json = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    Self.collectSnapshotJSONOnMain()
                }
            }
        }
        return json
    }

    @MainActor
    private static func buildSnapshotPayload(from manager: MenuBarManager) -> [String: Any] {
        let licenseIsPro = LicenseService.shared.isPro
        let alwaysHiddenRequested = manager.settings.alwaysHiddenSectionEnabled
        let alwaysHiddenEffective = MenuBarManager.effectiveAlwaysHiddenSectionEnabled(
            isPro: licenseIsPro,
            alwaysHiddenSectionEnabled: alwaysHiddenRequested
        )
        let mainX = manager.getMainStatusItemLeftEdgeX()
        let separatorX = manager.getSeparatorOriginX()
        let separatorRightEdgeX = manager.getSeparatorRightEdgeX()
        let rawAlwaysHiddenX = manager.getAlwaysHiddenSeparatorOriginX()
        let rawAlwaysHiddenBoundaryX = manager.getAlwaysHiddenSeparatorBoundaryX()
        let alwaysHiddenGeometry = normalizedSnapshotAlwaysHiddenGeometry(
            hidingState: manager.hidingService.state,
            separatorX: separatorX,
            alwaysHiddenOriginX: rawAlwaysHiddenX,
            alwaysHiddenBoundaryX: rawAlwaysHiddenBoundaryX
        )

        let mainWindow = manager.mainStatusItem?.button?.window
        let screenWidth = mainWindow?.screen?.frame.width ?? NSScreen.main?.frame.width
        let notchRightSafeMinX = mainWindow?.screen?.auxiliaryTopRightArea?.minX
            ?? NSScreen.main?.auxiliaryTopRightArea?.minX
        let rightGap: CGFloat? = {
            guard let mainWindow else { return nil }
            guard let rightEdge = mainWindow.screen?.frame.maxX ?? NSScreen.main?.frame.maxX else { return nil }
            return rightEdge - mainWindow.frame.origin.x
        }()

        let separatorBeforeMain: Bool = {
            guard let separatorX, let mainX else { return false }
            return separatorX < mainX
        }()

        let alwaysHiddenBeforeSeparator: Bool = {
            guard alwaysHiddenGeometry.isReliable else { return false }
            guard let alwaysHiddenX = alwaysHiddenGeometry.originX, let separatorX else { return false }
            return alwaysHiddenX < separatorX
        }()

        let mainNearControlCenter = MenuBarManager.isMainNearControlCenter(
            mainX: mainX,
            mainRightGap: rightGap,
            screenWidth: screenWidth,
            notchRightSafeMinX: notchRightSafeMinX
        )

        var payload: [String: Any] = [
            "hidingState": manager.hidingService.state.rawValue,
            "separatorBeforeMain": separatorBeforeMain,
            "alwaysHiddenBeforeSeparator": alwaysHiddenBeforeSeparator,
            "alwaysHiddenGeometryReliable": alwaysHiddenGeometry.isReliable,
            "alwaysHiddenSectionEnabledRequested": alwaysHiddenRequested,
            "alwaysHiddenSectionEnabledEffective": alwaysHiddenEffective,
            "alwaysHiddenSeparatorPresent": manager.alwaysHiddenSeparatorItem != nil,
            "licenseIsPro": licenseIsPro,
            "mainNearControlCenter": mainNearControlCenter,
            // Rehide/debug state to diagnose "stuck expanded" reports quickly.
            "autoRehideEnabled": manager.settings.autoRehide,
            "rehideOnAppChange": manager.settings.rehideOnAppChange,
            "rehideDelay": manager.settings.rehideDelay,
            "findIconRehideDelay": manager.settings.findIconRehideDelay,
            "isRevealPinned": manager.isRevealPinned,
            "isMenuOpen": manager.isMenuOpen,
            "isBrowseVisible": SearchWindowController.shared.isVisible,
            "isBrowseSessionActive": SearchWindowController.shared.isBrowseSessionActive,
            "isMoveInProgress": SearchWindowController.shared.isMoveInProgress,
            "hoverSuspended": manager.hoverService.isSuspended,
            "hoverMouseInMenuBar": manager.hoverService.isMouseInMenuBar,
            "shouldSkipHideForExternalMonitor": manager.shouldSkipHideForExternalMonitor,
            "isOnExternalMonitor": manager.isOnExternalMonitor
        ]
        SearchWindowController.shared.browseWindowPositionSnapshot().forEach { key, value in
            payload[key] = value
        }

        func setOptional(_ key: String, _ value: CGFloat?) {
            payload[key] = value.map(Double.init) ?? NSNull()
        }

        setOptional("mainIconLeftEdgeX", mainX)
        setOptional("separatorOriginX", separatorX)
        setOptional("separatorRightEdgeX", separatorRightEdgeX)
        setOptional("alwaysHiddenSeparatorOriginX", alwaysHiddenGeometry.originX)
        setOptional("alwaysHiddenSeparatorBoundaryX", alwaysHiddenGeometry.boundaryX)
        setOptional("rawAlwaysHiddenSeparatorOriginX", rawAlwaysHiddenX)
        setOptional("rawAlwaysHiddenSeparatorBoundaryX", rawAlwaysHiddenBoundaryX)
        setOptional("screenWidth", screenWidth)
        setOptional("notchRightSafeMinX", notchRightSafeMinX)
        setOptional("mainRightGap", rightGap)
        payload["geometryAvailable"] = (mainX != nil) || (separatorX != nil) || (separatorRightEdgeX != nil)
        return payload
    }

    private static func geometryAvailable(in payload: [String: Any]) -> Bool {
        (payload["geometryAvailable"] as? Bool) == true
    }

    @MainActor
    private static func collectSnapshotJSONOnMain() -> String {
        let manager = MenuBarManager.shared
        let deadline = Date().addingTimeInterval(8.0)
        var payload = buildSnapshotPayload(from: manager)
        var attempts = 1

        while !geometryAvailable(in: payload), Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.25))
            payload = buildSnapshotPayload(from: manager)
            attempts += 1
        }

        payload["snapshotAttempts"] = attempts
        payload["snapshotTimeout"] = !geometryAvailable(in: payload)
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{\"snapshotTimeout\":true}"
    }
}

// MARK: - Hide Icon Command

@objc(HideIconCommand)
final class HideIconCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let iconId = directParameter as? String else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Expected an icon identifier string."
            return false
        }

        let trimmedId = iconId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Icon identifier cannot be empty."
            return false
        }

        guard checkAccessibilityTrusted() else {
            setAccessibilityError()
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ScriptResultBox(false)
        let completed = ScriptResultBox(false)

        Task { @MainActor in
            let manager = MenuBarManager.shared

            // Find the icon in current menu bar items
            let items = await AccessibilityService.shared.listMenuBarItemsWithPositions()
            let match = items.first { item in
                item.app.uniqueId == trimmedId || item.app.bundleId == trimmedId
            }

            if let match {
                manager.pinAlwaysHidden(app: match.app)
                manager.saveSettings()
                // Trigger enforcement to physically move the icon
                await manager.enforceAlwaysHiddenPinnedItems(reason: "AppleScript hide icon")
                box.value = true
            }

            completed.value = true
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10.0)

        guard completed.value else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Operation timed out. SaneBar may be busy — try again."
            return false
        }

        if !box.value {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Icon '\(trimmedId)' not found. Use 'list icons' to see available identifiers."
        }

        return box.value
    }
}

// MARK: - Show Icon Command

@objc(ShowIconCommand)
final class ShowIconCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let iconId = directParameter as? String else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Expected an icon identifier string."
            return false
        }

        let trimmedId = iconId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Icon identifier cannot be empty."
            return false
        }

        guard checkAccessibilityTrusted() else {
            setAccessibilityError()
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ScriptResultBox(false)

        Task { @MainActor in
            let manager = MenuBarManager.shared

            // Check if this ID is currently pinned
            let pinnedIds = manager.settings.alwaysHiddenPinnedItemIds
            let matchedPin = pinnedIds.first { pinId in
                pinId == trimmedId || pinId.hasPrefix(trimmedId)
            }

            if let matchedPin {
                // Remove the pin
                manager.settings.alwaysHiddenPinnedItemIds = pinnedIds.filter { $0 != matchedPin }
                manager.saveSettings()

                // Move the icon to the visible zone
                let items = await AccessibilityService.shared.listMenuBarItemsWithPositions()
                if let match = items.first(where: { $0.app.uniqueId == matchedPin || $0.app.bundleId == trimmedId }) {
                    _ = await manager.moveIconAndWait(
                        bundleID: match.app.bundleId,
                        menuExtraId: match.app.menuExtraIdentifier,
                        statusItemIndex: match.app.statusItemIndex,
                        preferredCenterX: match.app.preferredCenterX,
                        toHidden: false
                    )
                }
                box.value = true
            }

            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10.0)

        if !box.value {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Icon '\(trimmedId)' is not in the always-hidden section."
        }

        return box.value
    }
}

// MARK: - Move Icon Commands

/// Shared move-icon implementation for AppleScript commands.
class MoveIconScriptCommand: SaneBarScriptCommand {
    var targetZone: ScriptIconZone { .visible }
    var reasonLabel: String { "AppleScript move icon" }

    override func performDefaultImplementation() -> Any? {
        guard let trimmedId = parseIconIdentifier(directParameter) else {
            scriptErrorIconIdMissing(self)
            return false
        }

        guard checkAccessibilityTrusted() else {
            setAccessibilityError()
            return false
        }
        let targetZone = self.targetZone
        var errorCode: String?
        var skipZoneWait = false
        var movedUniqueID: String?
        let started: Bool = if Thread.isMainThread {
            MainActor.assumeIsolated {
                let manager = MenuBarManager.shared
                let startZones = zonesForScriptMoveResolution(trimmedId)
                guard let source = resolveScriptIcon(trimmedId, from: startZones) else {
                    errorCode = "notFound"
                    return false
                }
                let icon = source.app
                movedUniqueID = icon.uniqueId
                let sourceZone = source.zone
                logger.info(
                    "AppleScript move request id=\(trimmedId, privacy: .private) sourceZone=\(sourceZone.rawValue, privacy: .public) targetZone=\(targetZone.rawValue, privacy: .public)"
                )
                if sourceZone == targetZone {
                    if targetZone == .alwaysHidden {
                        if !manager.settings.alwaysHiddenSectionEnabled {
                            manager.settings.alwaysHiddenSectionEnabled = true
                        }
                        manager.pinAlwaysHidden(app: icon)
                        manager.saveSettings()
                    }
                    skipZoneWait = true
                    return true
                }

                switch targetZone {
                case .alwaysHidden:
                    if !manager.settings.alwaysHiddenSectionEnabled {
                        manager.settings.alwaysHiddenSectionEnabled = true
                    }
                    manager.pinAlwaysHidden(app: icon)
                    manager.saveSettings()
                    let moved = runScriptMove {
                        await manager.moveIconAlwaysHiddenAndWait(
                            bundleID: icon.bundleId,
                            menuExtraId: icon.menuExtraIdentifier,
                            statusItemIndex: icon.statusItemIndex,
                            preferredCenterX: icon.preferredCenterX,
                            toAlwaysHidden: true
                        )
                    }
                    guard let moved else {
                        _ = manager.unpinAlwaysHidden(
                            bundleID: icon.bundleId,
                            menuExtraId: icon.menuExtraIdentifier,
                            statusItemIndex: icon.statusItemIndex
                        ) || (!icon.bundleId.hasPrefix("com.apple.controlcenter") &&
                            manager.unpinAlwaysHidden(bundleID: icon.bundleId))
                        manager.saveSettings()
                        errorCode = "timedOut"
                        return false
                    }
                    if !moved {
                        _ = manager.unpinAlwaysHidden(
                            bundleID: icon.bundleId,
                            menuExtraId: icon.menuExtraIdentifier,
                            statusItemIndex: icon.statusItemIndex
                        ) || (!icon.bundleId.hasPrefix("com.apple.controlcenter") &&
                            manager.unpinAlwaysHidden(bundleID: icon.bundleId))
                        manager.saveSettings()
                    }
                    return moved

                case .hidden:
                    switch sourceZone {
                    case .alwaysHidden:
                        let removedPin = manager.unpinAlwaysHidden(
                            bundleID: icon.bundleId,
                            menuExtraId: icon.menuExtraIdentifier,
                            statusItemIndex: icon.statusItemIndex
                        ) || (!icon.bundleId.hasPrefix("com.apple.controlcenter") &&
                            manager.unpinAlwaysHidden(bundleID: icon.bundleId))
                        if removedPin {
                            manager.saveSettings()
                        }
                        let moved = runScriptMove {
                            await manager.moveIconFromAlwaysHiddenToHiddenAndWait(
                                bundleID: icon.bundleId,
                                menuExtraId: icon.menuExtraIdentifier,
                                statusItemIndex: icon.statusItemIndex,
                                preferredCenterX: icon.preferredCenterX
                            )
                        }
                        guard let moved else {
                            errorCode = "timedOut"
                            return false
                        }
                        return moved
                    case .visible:
                        let moved = runScriptMove {
                            await manager.moveIconAndWait(
                                bundleID: icon.bundleId,
                                menuExtraId: icon.menuExtraIdentifier,
                                statusItemIndex: icon.statusItemIndex,
                                preferredCenterX: icon.preferredCenterX,
                                toHidden: true
                            )
                        }
                        guard let moved else {
                            errorCode = "timedOut"
                            return false
                        }
                        return moved
                    case .hidden:
                        return true
                    }

                case .visible:
                    switch sourceZone {
                    case .alwaysHidden:
                        let removedPin = manager.unpinAlwaysHidden(
                            bundleID: icon.bundleId,
                            menuExtraId: icon.menuExtraIdentifier,
                            statusItemIndex: icon.statusItemIndex
                        ) || (!icon.bundleId.hasPrefix("com.apple.controlcenter") &&
                            manager.unpinAlwaysHidden(bundleID: icon.bundleId))
                        if removedPin {
                            manager.saveSettings()
                        }
                        let moved = runScriptMove {
                            await manager.moveIconAlwaysHiddenAndWait(
                                bundleID: icon.bundleId,
                                menuExtraId: icon.menuExtraIdentifier,
                                statusItemIndex: icon.statusItemIndex,
                                preferredCenterX: icon.preferredCenterX,
                                toAlwaysHidden: false
                            )
                        }
                        guard let moved else {
                            errorCode = "timedOut"
                            return false
                        }
                        return moved
                    case .hidden:
                        let moved = runScriptMove {
                            await manager.moveIconAndWait(
                                bundleID: icon.bundleId,
                                menuExtraId: icon.menuExtraIdentifier,
                                statusItemIndex: icon.statusItemIndex,
                                preferredCenterX: icon.preferredCenterX,
                                toHidden: false
                            )
                        }
                        guard let moved else {
                            errorCode = "timedOut"
                            return false
                        }
                        return moved
                    case .visible:
                        return true
                    }
                }
            }
        } else {
            DispatchQueue.main.sync {
                let manager = MenuBarManager.shared
                let startZones = zonesForScriptMoveResolution(trimmedId)
                guard let source = resolveScriptIcon(trimmedId, from: startZones) else {
                    errorCode = "notFound"
                    return false
                }

                let icon = source.app
                movedUniqueID = icon.uniqueId
                let sourceZone = source.zone
                logger.info(
                    "AppleScript move request id=\(trimmedId, privacy: .private) sourceZone=\(sourceZone.rawValue, privacy: .public) targetZone=\(targetZone.rawValue, privacy: .public)"
                )

                if sourceZone == targetZone {
                    if targetZone == .alwaysHidden {
                        if !manager.settings.alwaysHiddenSectionEnabled {
                            manager.settings.alwaysHiddenSectionEnabled = true
                        }
                        manager.pinAlwaysHidden(app: icon)
                        manager.saveSettings()
                    }
                    skipZoneWait = true
                    return true
                }

                switch targetZone {
                case .alwaysHidden:
                    if !manager.settings.alwaysHiddenSectionEnabled {
                        manager.settings.alwaysHiddenSectionEnabled = true
                    }
                    manager.pinAlwaysHidden(app: icon)
                    manager.saveSettings()
                    let moved = runScriptMove {
                        await manager.moveIconAlwaysHiddenAndWait(
                            bundleID: icon.bundleId,
                            menuExtraId: icon.menuExtraIdentifier,
                            statusItemIndex: icon.statusItemIndex,
                            preferredCenterX: icon.preferredCenterX,
                            toAlwaysHidden: true
                        )
                    }
                    guard let moved else {
                        _ = manager.unpinAlwaysHidden(
                            bundleID: icon.bundleId,
                            menuExtraId: icon.menuExtraIdentifier,
                            statusItemIndex: icon.statusItemIndex
                        ) || (!icon.bundleId.hasPrefix("com.apple.controlcenter") &&
                            manager.unpinAlwaysHidden(bundleID: icon.bundleId))
                        manager.saveSettings()
                        errorCode = "timedOut"
                        return false
                    }
                    if !moved {
                        _ = manager.unpinAlwaysHidden(
                            bundleID: icon.bundleId,
                            menuExtraId: icon.menuExtraIdentifier,
                            statusItemIndex: icon.statusItemIndex
                        ) || (!icon.bundleId.hasPrefix("com.apple.controlcenter") &&
                            manager.unpinAlwaysHidden(bundleID: icon.bundleId))
                        manager.saveSettings()
                    }
                    return moved

                case .hidden:
                    switch sourceZone {
                    case .alwaysHidden:
                        let removedPin = manager.unpinAlwaysHidden(
                            bundleID: icon.bundleId,
                            menuExtraId: icon.menuExtraIdentifier,
                            statusItemIndex: icon.statusItemIndex
                        ) || (!icon.bundleId.hasPrefix("com.apple.controlcenter") &&
                            manager.unpinAlwaysHidden(bundleID: icon.bundleId))
                        if removedPin {
                            manager.saveSettings()
                        }
                        let moved = runScriptMove {
                            await manager.moveIconFromAlwaysHiddenToHiddenAndWait(
                                bundleID: icon.bundleId,
                                menuExtraId: icon.menuExtraIdentifier,
                                statusItemIndex: icon.statusItemIndex,
                                preferredCenterX: icon.preferredCenterX
                            )
                        }
                        guard let moved else {
                            errorCode = "timedOut"
                            return false
                        }
                        return moved
                    case .visible:
                        let moved = runScriptMove {
                            await manager.moveIconAndWait(
                                bundleID: icon.bundleId,
                                menuExtraId: icon.menuExtraIdentifier,
                                statusItemIndex: icon.statusItemIndex,
                                preferredCenterX: icon.preferredCenterX,
                                toHidden: true
                            )
                        }
                        guard let moved else {
                            errorCode = "timedOut"
                            return false
                        }
                        return moved
                    case .hidden:
                        return true
                    }

                case .visible:
                    switch sourceZone {
                    case .alwaysHidden:
                        let removedPin = manager.unpinAlwaysHidden(
                            bundleID: icon.bundleId,
                            menuExtraId: icon.menuExtraIdentifier,
                            statusItemIndex: icon.statusItemIndex
                        ) || (!icon.bundleId.hasPrefix("com.apple.controlcenter") &&
                            manager.unpinAlwaysHidden(bundleID: icon.bundleId))
                        if removedPin {
                            manager.saveSettings()
                        }
                        let moved = runScriptMove {
                            await manager.moveIconAlwaysHiddenAndWait(
                                bundleID: icon.bundleId,
                                menuExtraId: icon.menuExtraIdentifier,
                                statusItemIndex: icon.statusItemIndex,
                                preferredCenterX: icon.preferredCenterX,
                                toAlwaysHidden: false
                            )
                        }
                        guard let moved else {
                            errorCode = "timedOut"
                            return false
                        }
                        return moved
                    case .hidden:
                        let moved = runScriptMove {
                            await manager.moveIconAndWait(
                                bundleID: icon.bundleId,
                                menuExtraId: icon.menuExtraIdentifier,
                                statusItemIndex: icon.statusItemIndex,
                                preferredCenterX: icon.preferredCenterX,
                                toHidden: false
                            )
                        }
                        guard let moved else {
                            errorCode = "timedOut"
                            return false
                        }
                        return moved
                    case .visible:
                        return true
                    }
                }
            }
        }

        guard started else {
            if errorCode == "notFound" {
                scriptErrorIconNotFound(self, iconId: trimmedId)
            } else if errorCode == "timedOut" {
                scriptErrorOperationTimedOut(self)
            } else {
                scriptErrorMoveFailed(self, iconId: trimmedId, target: targetZone)
            }
            return false
        }

        if skipZoneWait {
            return true
        }

        guard let movedUniqueID else {
            scriptErrorMoveFailed(self, iconId: trimmedId, target: targetZone)
            return false
        }

        let settled: Bool = if Thread.isMainThread {
            MainActor.assumeIsolated {
                waitForScriptZone(iconUniqueID: movedUniqueID, expected: targetZone, timeoutSeconds: 4.0)
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    waitForScriptZone(iconUniqueID: movedUniqueID, expected: targetZone, timeoutSeconds: 4.0)
                }
            }
        }

        guard settled else {
            scriptErrorMoveFailed(self, iconId: trimmedId, target: targetZone)
            return false
        }

        return true
    }
}

@objc(MoveIconToHiddenCommand)
final class MoveIconToHiddenCommand: MoveIconScriptCommand {
    override var targetZone: ScriptIconZone { .hidden }
    override var reasonLabel: String { "AppleScript move icon to hidden" }
}

@objc(MoveIconToVisibleCommand)
final class MoveIconToVisibleCommand: MoveIconScriptCommand {
    override var targetZone: ScriptIconZone { .visible }
    override var reasonLabel: String { "AppleScript move icon to visible" }
}

@objc(MoveIconToAlwaysHiddenCommand)
final class MoveIconToAlwaysHiddenCommand: MoveIconScriptCommand {
    override var targetZone: ScriptIconZone { .alwaysHidden }
    override var reasonLabel: String { "AppleScript move icon to always hidden" }
}

// swiftlint:enable file_length
