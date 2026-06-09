import AppKit
import Foundation
import os.log

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
    zones(from: SearchService.shared.cachedClassifiedApps())
}

func sortedScriptZones(_ zones: [ScriptZonedIcon]) -> [ScriptZonedIcon] {
    zones.sorted { lhs, rhs in
        if lhs.zone.rawValue == rhs.zone.rawValue {
            return (lhs.app.xPosition ?? 0) < (rhs.app.xPosition ?? 0)
        }
        return lhs.zone.rawValue < rhs.zone.rawValue
    }
}

struct ScriptListingZoneQuality {
    let alwaysHiddenCount: Int
    let preciseIdentityCount: Int
    let totalCount: Int
}

func shouldRefreshScriptListingZones(
    cachedIsEmpty: Bool,
    cacheAge: TimeInterval,
    cacheValiditySeconds: TimeInterval
) -> Bool {
    if cachedIsEmpty {
        return true
    }

    return cacheAge >= cacheValiditySeconds
}

func scriptListingCacheValiditySeconds(
    baseValiditySeconds: TimeInterval,
    minimumValiditySeconds: TimeInterval = 15.0
) -> TimeInterval {
    max(baseValiditySeconds, minimumValiditySeconds)
}

func scriptListingZoneQuality(_ zones: [ScriptZonedIcon]) -> ScriptListingZoneQuality {
    ScriptListingZoneQuality(
        alwaysHiddenCount: zones.filter { $0.zone == .alwaysHidden }.count,
        preciseIdentityCount: zones.filter { $0.app.hasPreciseMenuBarIdentity }.count,
        totalCount: zones.count
    )
}

func shouldPreferRefreshedScriptListingZones(
    cached: [ScriptZonedIcon],
    refreshed: [ScriptZonedIcon]
) -> Bool {
    guard !refreshed.isEmpty else { return false }
    guard !cached.isEmpty else { return true }

    let cachedQuality = scriptListingZoneQuality(cached)
    let refreshedQuality = scriptListingZoneQuality(refreshed)

    if refreshedContainsMovedPreciseScriptZone(cached: cached, refreshed: refreshed) {
        return true
    }

    if refreshedContainsHiddenToAlwaysHiddenScriptArtifact(cached: cached, refreshed: refreshed) {
        return false
    }

    if refreshedQuality.alwaysHiddenCount != cachedQuality.alwaysHiddenCount {
        return refreshedQuality.alwaysHiddenCount > cachedQuality.alwaysHiddenCount
    }

    if refreshedQuality.preciseIdentityCount != cachedQuality.preciseIdentityCount {
        return refreshedQuality.preciseIdentityCount > cachedQuality.preciseIdentityCount
    }

    if refreshedQuality.totalCount != cachedQuality.totalCount {
        return refreshedQuality.totalCount > cachedQuality.totalCount
    }

    return false
}

func refreshedContainsMovedPreciseScriptZone(
    cached: [ScriptZonedIcon],
    refreshed: [ScriptZonedIcon]
) -> Bool {
    for cachedZone in cached where cachedZone.app.hasPreciseMenuBarIdentity {
        if let refreshedZone = refreshed.first(where: { $0.app.uniqueId == cachedZone.app.uniqueId }),
           refreshedZone.zone != cachedZone.zone {
            if cachedZone.zone == .hidden, refreshedZone.zone == .alwaysHidden {
                continue
            }
            return true
        }
    }
    return false
}

func refreshedContainsHiddenToAlwaysHiddenScriptArtifact(
    cached: [ScriptZonedIcon],
    refreshed: [ScriptZonedIcon]
) -> Bool {
    for cachedZone in cached where cachedZone.app.hasPreciseMenuBarIdentity && cachedZone.zone == .hidden {
        if let refreshedZone = refreshed.first(where: { $0.app.uniqueId == cachedZone.app.uniqueId }),
           refreshedZone.zone == .alwaysHidden {
            return true
        }
    }
    return false
}

func preferredScriptListingZones(
    cached: [ScriptZonedIcon],
    refreshed: @autoclosure () -> [ScriptZonedIcon],
    cacheAge: TimeInterval,
    cacheValiditySeconds: TimeInterval
) -> [ScriptZonedIcon] {
    let shouldRefresh = shouldRefreshScriptListingZones(
        cachedIsEmpty: cached.isEmpty,
        cacheAge: cacheAge,
        cacheValiditySeconds: cacheValiditySeconds
    )
    guard shouldRefresh else {
        // Fresh post-move snapshots are intentionally authoritative. Calling the
        // refresher here mutates the AX position cache and can replace a valid
        // shown-state regular Hidden snapshot with hidden-state offscreen geometry.
        return sortedScriptZones(cached)
    }

    // Cold-start cache snapshots can flatten always-hidden lanes into generic
    // hidden rows. Only pay for a refreshed read once the cache is empty or
    // stale; otherwise trust the warmed snapshot and avoid re-scanning on
    // every AppleScript listing call.
    let refreshedZones = refreshed()
    if shouldPreferRefreshedScriptListingZones(cached: cached, refreshed: refreshedZones) {
        return sortedScriptZones(refreshedZones)
    }

    return sortedScriptZones(cached)
}

@MainActor
func scriptListingZonesForCommand() -> [ScriptZonedIcon] {
    let cached = currentIconZones()
    let coldStart = cached.isEmpty
    let cacheAge = Date().timeIntervalSince(AccessibilityService.shared.menuBarItemCacheTime)
    let cacheValiditySeconds = scriptListingCacheValiditySeconds(
        baseValiditySeconds: AccessibilityService.shared.menuBarItemCacheValiditySeconds
    )

    let refreshed = preferredScriptListingZones(
        cached: cached,
        refreshed: refreshedIconZones(
            timeoutSeconds: coldStart ? 2.5 : 1.2,
            allowAuthoritativeFallback: coldStart
        ),
        cacheAge: cacheAge,
        cacheValiditySeconds: cacheValiditySeconds
    )
    if !refreshed.isEmpty || !coldStart {
        return refreshed
    }

    return sortedScriptZones(
        refreshedIconZones(timeoutSeconds: 2.5, allowAuthoritativeFallback: true)
    )
}

@MainActor
func authoritativeScriptListingZonesForCommand() -> [ScriptZonedIcon] {
    AccessibilityService.shared.invalidateMenuBarItemPositionsCache()
    let result = ScriptResultBox<ScriptClassifiedApps?>(nil)
    Task { @MainActor in
        result.value = await SearchService.shared.refreshClassifiedApps()
    }

    let deadline = Date().addingTimeInterval(5.0)
    while result.value == nil, Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    if let classified = result.value {
        return sortedScriptZones(zones(from: classified))
    }

    return []
}

@MainActor
func runScriptMove(timeoutSeconds: TimeInterval = 9.0, operation: @escaping @MainActor () async -> Bool) -> Bool? {
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
private func refreshedIconZones(
    timeoutSeconds: TimeInterval = 2.5,
    allowAuthoritativeFallback: Bool = true
) -> [ScriptZonedIcon] {
    let result = ScriptResultBox<ScriptClassifiedApps?>(nil)
    Task { @MainActor in
        result.value = await SearchService.shared.refreshKnownClassifiedApps()
    }

    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while result.value == nil, Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    if let classified = result.value {
        return zones(from: classified)
    }

    let cached = currentIconZones()
    guard allowAuthoritativeFallback else {
        return cached
    }

    // If the lighter known-owner refresh timed out, invalidate AX cache and try
    // once more with the authoritative full inventory refresh before falling
    // back to the cached classification snapshot.
    AccessibilityService.shared.invalidateMenuBarItemPositionsCache()
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

    return cached
}

@MainActor
func freshZonesForScriptMoveVerification(timeoutSeconds: TimeInterval = 2.5) -> [ScriptZonedIcon] {
    AccessibilityService.shared.invalidateMenuBarItemPositionsCache()
    return refreshedIconZones(timeoutSeconds: timeoutSeconds)
}

@MainActor
func zonesForScriptResolution(_ identifier: String) -> [ScriptZonedIcon] {
    let cached = currentIconZones()
    if resolveScriptIcon(identifier, from: cached) != nil {
        return cached
    }

    AccessibilityService.shared.invalidateMenuBarItemPositionsCache()
    return refreshedIconZones(timeoutSeconds: 1.2)
}

func shouldPreferFreshZonesForScriptMove(
    identifier: String,
    matchedApp: RunningApp,
    sameBundleCount: Int,
    cacheIsFresh: Bool
) -> Bool {
    guard cacheIsFresh else {
        return true
    }

    if matchedApp.hasPreciseMenuBarIdentity, matchedApp.uniqueId == identifier {
        return false
    }
    if matchedApp.menuExtraIdentifier == identifier {
        return false
    }
    if let statusItemIndex = matchedApp.statusItemIndex,
       identifier == "\(matchedApp.bundleId)::statusItem:\(statusItemIndex)" {
        return false
    }
    return sameBundleCount > 1
}

@MainActor
func zonesForScriptMoveResolution(_ identifier: String) -> [ScriptZonedIcon] {
    let cached = currentIconZones()
    let cacheAge = Date().timeIntervalSince(AccessibilityService.shared.menuBarItemCacheTime)
    let cacheIsFresh = cacheAge < AccessibilityService.shared.menuBarItemCacheValiditySeconds
    guard let matched = resolveScriptIcon(identifier, from: cached) else {
        AccessibilityService.shared.invalidateMenuBarItemPositionsCache()
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
        sameBundleCount: sameBundleCount,
        cacheIsFresh: cacheIsFresh
    ) else {
        return cached
    }

    AccessibilityService.shared.invalidateMenuBarItemPositionsCache()
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

func scriptErrorMoveFailed(_ command: NSScriptCommand, iconId: String, target: ScriptIconZone) {
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
