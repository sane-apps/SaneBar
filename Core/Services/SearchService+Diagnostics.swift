import AppKit
import Foundation

extension SearchService {
    enum ActivationOrigin: String, Sendable {
        case direct
        case browsePanel
        case automation
    }

    struct ActivationDiagnostics: Sendable {
        var startedAt: String = "never"
        var requestedApp: String = "none"
        var origin: String = ActivationOrigin.direct.rawValue
        var didReveal: Bool = false
        var preferHardwareFirst: Bool = false
        var initialResolution: String = "not-run"
        var initialTarget: String = "none"
        var waitOutcome: String = "not-run"
        var firstAttempt: String = "not-run"
        var retryAttempt: String = "not-run"
        var finalOutcome: String = "not-run"

        func formattedSummary() -> String {
            """
            lastActivation:
              startedAt: \(startedAt)
              requestedApp: \(requestedApp)
              origin: \(origin)
              didReveal: \(didReveal)
              preferHardwareFirst: \(preferHardwareFirst)
              initialResolution: \(initialResolution)
              initialTarget: \(initialTarget)
              waitOutcome: \(waitOutcome)
              firstAttempt: \(firstAttempt)
              retryAttempt: \(retryAttempt)
              finalOutcome: \(finalOutcome)
            """
        }
    }

    nonisolated static func diagnosticsTimestamp(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
    }

    nonisolated static func diagnosticsNumber(_ value: CGFloat?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.1f", value)
    }

    nonisolated static func diagnosticsPoint(_ point: CGPoint?) -> String {
        guard let point else { return "nil" }
        return "x=\(diagnosticsNumber(point.x)) y=\(diagnosticsNumber(point.y))"
    }

    nonisolated static func diagnosticsApp(_ app: RunningApp) -> String {
        "id=\(app.uniqueId) bundle=\(app.bundleId) menuExtra=\(app.menuExtraIdentifier ?? "nil") statusItemIndex=\(app.statusItemIndex.map(String.init) ?? "nil") x=\(diagnosticsNumber(app.xPosition)) width=\(diagnosticsNumber(app.width))"
    }

    nonisolated static func spatialFallbackCenter(
        xPosition: CGFloat?,
        width: CGFloat?,
        menuBarScreenFrame: CGRect?
    ) -> CGPoint? {
        guard let xPosition else { return nil }
        if let menuBarScreenFrame {
            let margin: CGFloat = 6
            let isOffscreen = xPosition < (menuBarScreenFrame.minX - margin) || xPosition > (menuBarScreenFrame.maxX + margin)
            if isOffscreen {
                return nil
            }
        }

        let width = max(1, width ?? 22)
        return CGPoint(x: xPosition + (width / 2), y: 15)
    }

    nonisolated static func preferredSpatialFallbackCenter(
        primaryXPosition: CGFloat?,
        primaryWidth: CGFloat?,
        fallbackXPosition: CGFloat?,
        fallbackWidth: CGFloat?,
        menuBarScreenFrame: CGRect?
    ) -> CGPoint? {
        spatialFallbackCenter(
            xPosition: primaryXPosition,
            width: primaryWidth,
            menuBarScreenFrame: menuBarScreenFrame
        ) ?? spatialFallbackCenter(
            xPosition: fallbackXPosition,
            width: fallbackWidth,
            menuBarScreenFrame: menuBarScreenFrame
        )
    }

    nonisolated static func activationRuntimeSnapshot(
        app: RunningApp,
        origin: ActivationOrigin,
        didReveal: Bool,
        isBrowseSessionActive: Bool
    ) -> MenuBarRuntimeSnapshot {
        let geometryConfidence: MenuBarGeometryConfidence = if didReveal {
            .cached
        } else if let xPosition = app.xPosition {
            xPosition >= 0 ? .live : .stale
        } else {
            .missing
        }

        let browsePhase: MenuBarBrowsePhase = if origin == .browsePanel {
            .activationInFlight
        } else if isBrowseSessionActive {
            .open
        } else {
            .idle
        }

        return MenuBarRuntimeSnapshot(
            identityPrecision: app.hasPreciseMenuBarIdentity ? .exact : .coarse,
            geometryConfidence: geometryConfidence,
            visibilityPhase: didReveal ? .expanded : .hidden,
            browsePhase: browsePhase
        )
    }

    nonisolated static func activationPlan(
        app: RunningApp,
        origin: ActivationOrigin,
        isRightClick: Bool,
        didReveal: Bool,
        isBrowseSessionActive: Bool
    ) -> MenuBarOperationCoordinator.BrowseActivationPlan {
        MenuBarOperationCoordinator.browseActivationPlan(
            snapshot: activationRuntimeSnapshot(
                app: app,
                origin: origin,
                didReveal: didReveal,
                isBrowseSessionActive: isBrowseSessionActive
            ),
            origin: origin,
            isRightClick: isRightClick,
            didReveal: didReveal,
            requestedApp: app
        )
    }

    nonisolated static func requiresObservableReactionVerification(
        origin: ActivationOrigin,
        didReveal: Bool,
        isBrowseSessionActive: Bool
    ) -> Bool {
        didReveal || isBrowseSessionActive || origin == .browsePanel
    }

    nonisolated static func shouldForceFreshTargetResolution(
        origin: ActivationOrigin,
        didReveal: Bool,
        isBrowseSessionActive: Bool
    ) -> Bool {
        didReveal || isBrowseSessionActive || origin == .browsePanel
    }

    nonisolated static func shouldAllowImmediateFallbackCenter(
        origin: ActivationOrigin,
        didReveal: Bool,
        isBrowseSessionActive: Bool
    ) -> Bool {
        !(didReveal || isBrowseSessionActive || origin == .browsePanel)
    }

    nonisolated static func shouldUseWorkspaceActivationFallback(
        origin: ActivationOrigin,
        isRightClick: Bool
    ) -> Bool {
        !(origin == .browsePanel && isRightClick)
    }

    nonisolated static func shouldAllowSameBundleActivationFallback(
        original: RunningApp,
        sameBundleCount: Int
    ) -> Bool {
        MenuBarOperationCoordinator.shouldAllowSameBundleActivationFallback(
            snapshot: MenuBarRuntimeSnapshot(
                identityPrecision: original.hasPreciseMenuBarIdentity ? .exact : .coarse
            ),
            sameBundleCount: sameBundleCount
        )
    }

    nonisolated static func isFallbackCenterOnScreen(_ fallbackCenter: CGPoint?) -> Bool {
        guard let fallbackCenter else { return false }
        return NSScreen.screens.contains { screen in
            screen.frame.insetBy(dx: -2, dy: -2).contains(fallbackCenter)
        }
    }

    nonisolated static func resolvedAllowImmediateFallbackCenter(
        baseAllowImmediateFallbackCenter: Bool,
        likelyNoExtrasMenuBar: Bool,
        fallbackCenterOnScreen: Bool
    ) -> Bool {
        baseAllowImmediateFallbackCenter || (likelyNoExtrasMenuBar && fallbackCenterOnScreen)
    }

    nonisolated static func shouldUsePinnedAlwaysHiddenFallback(
        hidingState: HidingState,
        isBrowseSessionActive: Bool
    ) -> Bool {
        hidingState == .hidden || isBrowseSessionActive
    }

    nonisolated static func acceptsClickResult(
        success: Bool,
        verification: String,
        requireObservableReaction: Bool
    ) -> Bool {
        guard success else { return false }
        guard requireObservableReaction else { return true }
        return verification.hasPrefix("verified")
    }

    nonisolated static func shouldUseRawSpatialFallback(
        allowImmediateFallbackCenter: Bool,
        isPointOnScreen: Bool
    ) -> Bool {
        allowImmediateFallbackCenter && isPointOnScreen
    }

    nonisolated static func shouldWaitForRevealSettle(
        preferHardwareFirst: Bool,
        xPosition: CGFloat?
    ) -> Bool {
        guard preferHardwareFirst else { return true }
        guard let xPosition else { return true }
        return xPosition < 0
    }

    nonisolated static func shouldPreferHardwareFirst(
        origin: ActivationOrigin,
        isRightClick: Bool,
        app: RunningApp
    ) -> Bool {
        if isRightClick {
            return true
        }

        // Browse panel targets are already on-screen and now have observable
        // reaction verification. Prefer AX first there so we do not burn the
        // timeout budget on a failed hardware attempt before trying AXPress.
        if origin == .browsePanel, let xPosition = app.xPosition, xPosition >= 0 {
            return false
        }

        if app.menuExtraIdentifier?.hasPrefix("com.apple.menuextra.") == true {
            return true
        }
        if app.menuExtraIdentifier == nil {
            return true
        }
        return app.bundleId.hasPrefix("com.apple.")
    }

    nonisolated static func clickAttemptTimeoutMs(
        baseMs: Int,
        requireObservableReaction: Bool
    ) -> Int {
        guard requireObservableReaction else { return baseMs }
        return max(baseMs, 1_800)
    }

    nonisolated static func helperHostedAliasFamilyKey(for app: RunningApp) -> String? {
        switch app.bundleId.lowercased() {
        case "at.obdev.littlesnitch",
             "at.obdev.littlesnitch.agent",
             "at.obdev.littlesnitch.daemon",
             "at.obdev.littlesnitch.networkmonitor",
             "com.obdev.littlesnitchuiagent":
            return "little-snitch"
        default:
            return nil
        }
    }

    nonisolated static func helperHostedAliasDisplayKey(for app: RunningApp) -> String? {
        guard let familyKey = helperHostedAliasFamilyKey(for: app) else { return nil }
        let normalizedName = app.name
            .lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        guard !normalizedName.isEmpty else { return nil }
        return "\(familyKey)::\(normalizedName)"
    }

    nonisolated static func isSyntheticThirdPartyMenuExtraIdentity(_ app: RunningApp) -> Bool {
        guard let menuExtraIdentifier = app.menuExtraIdentifier?.lowercased() else { return false }
        guard !menuExtraIdentifier.hasPrefix("com.apple.menuextra.") else { return false }
        return menuExtraIdentifier.contains(".menuextra.")
    }

    nonisolated static func helperHostedAliasBundlePriority(_ bundleID: String) -> Int {
        switch bundleID.lowercased() {
        case "at.obdev.littlesnitch.agent":
            return 0
        case "at.obdev.littlesnitch.networkmonitor":
            return 1
        case "at.obdev.littlesnitch.daemon":
            return 2
        case "at.obdev.littlesnitch":
            return 3
        case "com.obdev.littlesnitchuiagent":
            return 4
        default:
            return 10
        }
    }

    nonisolated static func isLikelyDeepHiddenX(_ xPosition: CGFloat?) -> Bool {
        guard let xPosition else { return false }
        return abs(xPosition) >= 2_000
    }

    nonisolated static func bestHelperHostedAliasRepresentative(
        from candidates: [RunningApp]
    ) -> RunningApp? {
        candidates.min { lhs, rhs in
            let lhsDeepHidden = isLikelyDeepHiddenX(lhs.xPosition)
            let rhsDeepHidden = isLikelyDeepHiddenX(rhs.xPosition)
            if lhsDeepHidden != rhsDeepHidden { return !lhsDeepHidden && rhsDeepHidden }

            let lhsPriority = helperHostedAliasBundlePriority(lhs.bundleId)
            let rhsPriority = helperHostedAliasBundlePriority(rhs.bundleId)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }

            let lhsSynthetic = isSyntheticThirdPartyMenuExtraIdentity(lhs)
            let rhsSynthetic = isSyntheticThirdPartyMenuExtraIdentity(rhs)
            if lhsSynthetic != rhsSynthetic { return !lhsSynthetic && rhsSynthetic }

            let lhsX = lhs.xPosition ?? -.greatestFiniteMagnitude
            let rhsX = rhs.xPosition ?? -.greatestFiniteMagnitude
            if lhsX != rhsX { return lhsX > rhsX }

            return lhs.uniqueId.localizedCompare(rhs.uniqueId) == .orderedAscending
        }
    }

    nonisolated static func collapseHelperHostedAliasDuplicates(
        _ apps: [RunningApp]
    ) -> [RunningApp] {
        var kept: [RunningApp] = []
        var aliasBuckets: [String: [RunningApp]] = [:]

        for app in apps {
            if let aliasKey = helperHostedAliasDisplayKey(for: app) {
                aliasBuckets[aliasKey, default: []].append(app)
            } else {
                kept.append(app)
            }
        }

        for bucket in aliasBuckets.values {
            if let best = bestHelperHostedAliasRepresentative(from: bucket) {
                kept.append(best)
            }
        }

        return kept
    }

    nonisolated static func bestHelperHostedAliasResolutionCandidate(
        for original: RunningApp,
        candidates: [RunningApp]
    ) -> RunningApp? {
        guard let aliasKey = helperHostedAliasDisplayKey(for: original) else { return nil }

        let familyMatches = candidates.filter { helperHostedAliasDisplayKey(for: $0) == aliasKey }
        guard !familyMatches.isEmpty else { return nil }

        let originalX = original.xPosition
        return familyMatches.min { lhs, rhs in
            let lhsPriority = helperHostedAliasBundlePriority(lhs.bundleId)
            let rhsPriority = helperHostedAliasBundlePriority(rhs.bundleId)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }

            let lhsSynthetic = isSyntheticThirdPartyMenuExtraIdentity(lhs)
            let rhsSynthetic = isSyntheticThirdPartyMenuExtraIdentity(rhs)
            if lhsSynthetic != rhsSynthetic { return !lhsSynthetic && rhsSynthetic }

            if let originalX {
                let lhsDistance = abs((lhs.xPosition ?? originalX) - originalX)
                let rhsDistance = abs((rhs.xPosition ?? originalX) - originalX)
                if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            }

            return lhs.uniqueId.localizedCompare(rhs.uniqueId) == .orderedAscending
        }
    }

    @MainActor
    static func mergedDiscoverableApps(positioned: [RunningApp], owners: [RunningApp]) -> [RunningApp] {
        var merged = positioned
        var seenIDs = Set(positioned.map(\.uniqueId))
        let positionedBundles = Set(positioned.map(\.bundleId))

        for owner in owners {
            if seenIDs.contains(owner.uniqueId) { continue }
            if owner.menuExtraIdentifier == nil,
               owner.statusItemIndex == nil,
               positionedBundles.contains(owner.bundleId) {
                continue
            }

            seenIDs.insert(owner.uniqueId)
            merged.append(owner)
        }

        merged = collapseHelperHostedAliasDuplicates(merged)

        return merged.sorted { lhs, rhs in
            let lhsX = lhs.xPosition ?? .greatestFiniteMagnitude
            let rhsX = rhs.xPosition ?? .greatestFiniteMagnitude
            if lhsX != rhsX { return lhsX < rhsX }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }
}
