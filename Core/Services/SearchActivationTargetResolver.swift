import AppKit
import Foundation
import os.log

enum SearchActivationTargetResolver {
    @MainActor
    static func resolveLatestClickTarget(
        for original: RunningApp,
        forceRefresh: Bool,
        logger: Logger
    ) async -> (app: RunningApp, strategy: String) {
        let items = if forceRefresh {
            await AccessibilityService.shared.refreshMenuBarItemsWithPositions()
        } else {
            await AccessibilityService.shared.listMenuBarItemsWithPositions()
        }
        let prefix = "forceRefresh=\(forceRefresh) items=\(items.count)"

        if let exact = items.first(where: { $0.app.uniqueId == original.uniqueId })?.app {
            logger.info("Resolved click target via uniqueId (\(prefix, privacy: .public))")
            return (exact, "\(prefix) method=uniqueId")
        }

        if let menuExtraIdentifier = original.menuExtraIdentifier,
           let match = items.first(where: { $0.app.bundleId == original.bundleId && $0.app.menuExtraIdentifier == menuExtraIdentifier })?.app {
            logger.info("Resolved click target via menuExtra identifier (\(prefix, privacy: .public))")
            return (match, "\(prefix) method=bundle+menuExtraId")
        }

        if let statusItemIndex = original.statusItemIndex,
           let match = items.first(where: { $0.app.bundleId == original.bundleId && $0.app.statusItemIndex == statusItemIndex })?.app {
            logger.info("Resolved click target via status item index (\(prefix, privacy: .public))")
            return (match, "\(prefix) method=bundle+statusItemIndex")
        }

        let sameBundle = items.filter { $0.app.bundleId == original.bundleId }.map(\.app)
        let sameBundleSnapshot = MenuBarRuntimeSnapshot(
            identityPrecision: original.hasPreciseMenuBarIdentity ? .exact : .coarse,
            geometryConfidence: forceRefresh ? .cached : .live,
            visibilityPhase: .expanded,
            browsePhase: .activationInFlight
        )
        if !MenuBarOperationCoordinator.shouldAllowSameBundleActivationFallback(
            snapshot: sameBundleSnapshot,
            sameBundleCount: sameBundle.count
        ) {
            logger.error("Refusing same-bundle activation fallback after precise identity loss (\(prefix, privacy: .public))")
            return (original, "\(prefix) method=preciseIdentityLost")
        }
        if let originalX = original.xPosition,
           let closest = sameBundle.min(by: { abs(($0.xPosition ?? originalX) - originalX) < abs(($1.xPosition ?? originalX) - originalX) }) {
            logger.warning("Resolved click target via closest same-bundle position (\(prefix, privacy: .public))")
            return (closest, "\(prefix) method=closestSameBundleX")
        }
        if let sameBundleFirst = sameBundle.first {
            logger.warning("Resolved click target via first same-bundle fallback (\(prefix, privacy: .public))")
            return (sameBundleFirst, "\(prefix) method=firstSameBundle")
        }

        if let helperHostedAliasMatch = SearchServiceSupport.bestHelperHostedAliasResolutionCandidate(
            for: original,
            candidates: items.map(\.app)
        ) {
            logger.warning("Resolved click target via helper-family fallback (\(prefix, privacy: .public))")
            return (helperHostedAliasMatch, "\(prefix) method=helperFamily")
        }

        logger.error("Resolved click target fell back to original request (\(prefix, privacy: .public))")
        return (original, "\(prefix) method=originalFallback")
    }

    @MainActor
    static func fallbackCenter(
        for app: RunningApp,
        fallbackSource: RunningApp?,
        menuBarScreenFrame: CGRect?,
        logger: Logger
    ) -> CGPoint? {
        let center = SearchServiceSupport.preferredSpatialFallbackCenter(
            primaryXPosition: app.xPosition,
            primaryWidth: app.width,
            fallbackXPosition: fallbackSource?.xPosition,
            fallbackWidth: fallbackSource?.width,
            menuBarScreenFrame: menuBarScreenFrame
        )
        if center == nil, app.xPosition != nil || fallbackSource?.xPosition != nil {
            logger.info("Skipping spatial fallback for \(app.bundleId, privacy: .private): no on-screen fallback center survived target refresh")
        }
        return center
    }

    @MainActor
    static func waitForIconOnScreen(
        app: RunningApp,
        maxWaitMs: Int = 1800,
        logger: Logger
    ) async -> String {
        let intervalMs = 50
        let maxAttempts = maxWaitMs / intervalMs
        var previousX: CGFloat?
        var nilStreak = 0
        let axService = AccessibilityService.shared
        let bundleId = app.bundleId
        let menuExtraId = app.menuExtraIdentifier
        let statusItemIndex = app.statusItemIndex

        for attempt in 1 ... maxAttempts {
            let position: CGPoint? = await Task.detached {
                AccessibilityMenuExtraService.menuBarItemPosition(
                    bundleID: bundleId,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex
                )
            }.value

            if let pos = position {
                nilStreak = 0
                let isOnScreen = NSScreen.screens.contains {
                    $0.frame.insetBy(dx: -2, dy: -2).contains(pos)
                }
                if isOnScreen {
                    if let prev = previousX, abs(prev - pos.x) < 2 {
                        let outcome = "stable after \(attempt * intervalMs)ms at x=\(SearchServiceSupport.diagnosticsNumber(pos.x))"
                        if attempt > 2 {
                            logger.info("Icon on-screen after \(attempt * intervalMs)ms")
                        }
                        return outcome
                    }
                    previousX = pos.x
                }
            } else {
                nilStreak += 1
                if axService.likelyLacksExtrasMenuBar(bundleID: bundleId) {
                    logger.debug("Skipping on-screen wait for \(bundleId, privacy: .private): AXExtrasMenuBar unavailable")
                    return "skipped (AXExtrasMenuBar unavailable)"
                }
                if nilStreak >= 4 {
                    logger.debug("Skipping on-screen wait for \(bundleId, privacy: .private): icon position unavailable")
                    return "skipped (icon position unavailable)"
                }
            }

            try? await Task.sleep(nanoseconds: UInt64(intervalMs) * 1_000_000)
        }
        logger.warning("Icon did not reach stable on-screen position within \(maxWaitMs)ms")
        return "timed out after \(maxWaitMs)ms"
    }
}
