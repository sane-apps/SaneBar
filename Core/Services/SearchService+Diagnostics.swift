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

        return merged.sorted { lhs, rhs in
            let lhsX = lhs.xPosition ?? .greatestFiniteMagnitude
            let rhsX = rhs.xPosition ?? .greatestFiniteMagnitude
            if lhsX != rhsX { return lhsX < rhsX }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }
}
