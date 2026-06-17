import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarMoveTargetResolver")

@MainActor
final class MenuBarMoveTargetResolver {
    struct SourceIdentity {
        let bundleID: String
        let menuExtraId: String?
        let statusItemIndex: Int?
        let preferredCenterX: CGFloat?
    }

    private struct AlwaysHiddenTargetReadiness {
        let targets: (separatorX: CGFloat?, visibleBoundaryX: CGFloat?)
        let alwaysHiddenSeparatorIsLive: Bool
        let mainSeparatorIsLive: Bool
    }

    private unowned let manager: MenuBarManager

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    nonisolated private static func hiddenBoundaryIsOrdered(_ boundaryX: CGFloat?, separatorX: CGFloat) -> Bool {
        guard let boundaryX, boundaryX.isFinite, separatorX.isFinite else { return false }
        return boundaryX < separatorX
    }

    nonisolated private static func visibleBoundaryIsOrdered(_ boundaryX: CGFloat?, separatorX: CGFloat) -> Bool {
        guard let boundaryX, boundaryX.isFinite, separatorX.isFinite else { return false }
        return boundaryX > separatorX
    }

    func computeMoveTargets(
        toHidden: Bool,
        separatorOverrideX: CGFloat?
    ) -> (separatorX: CGFloat?, visibleBoundaryX: CGFloat?) {
        if toHidden {
            let separatorX = hiddenMoveSeparatorX(separatorOverrideX: separatorOverrideX)
            let alwaysHiddenBoundaryX = hiddenLaneLeftBoundary(
                separatorX: separatorX,
                separatorOverrideX: separatorOverrideX
            )
            return (separatorX, alwaysHiddenBoundaryX)
        }

        let separatorX = manager.geometryResolver.separatorRightEdgeX()
        let mainLeftEdge = manager.geometryResolver.mainStatusItemLeftEdgeX()
        return (separatorX, mainLeftEdge)
    }

    func resolveMoveTargetsWithRetries(
        toHidden: Bool,
        sourceIdentity: SourceIdentity,
        separatorOverrideX: CGFloat?,
        maxAttempts: Int = 20
    ) async -> (separatorX: CGFloat?, visibleBoundaryX: CGFloat?) {
        if toHidden {
            await manager.geometryResolver.warmSeparatorPositionCache(maxAttempts: 16)
            await manager.geometryResolver.warmAlwaysHiddenSeparatorPositionCache(maxAttempts: 16)
        }

        var lastTargets: (separatorX: CGFloat?, visibleBoundaryX: CGFloat?) = (nil, nil)

        for attempt in 1 ... maxAttempts {
            let targets = computeMoveTargets(toHidden: toHidden, separatorOverrideX: separatorOverrideX)
            let liveSeparatorReady = separatorOverrideX != nil || manager.geometryResolver.currentLiveSeparatorFrame() != nil
            let sourceFrameIsOnScreen = !toHidden && sourceFrameIsOnScreenForMove(sourceIdentity)
            lastTargets = targets

            if let separatorX = targets.separatorX, separatorX.isFinite {
                let hiddenLaneBoundaryReady = !toHidden ||
                    separatorOverrideX != nil ||
                    !regularHiddenMoveRequiresAlwaysHiddenBoundary() ||
                    Self.hiddenBoundaryIsOrdered(targets.visibleBoundaryX, separatorX: separatorX)
                let visibleBoundaryReady = toHidden || Self.visibleBoundaryIsOrdered(
                    targets.visibleBoundaryX,
                    separatorX: separatorX
                )
                if hiddenLaneBoundaryReady, visibleBoundaryReady {
                    let canUseCachedVisibleTarget = !toHidden && MenuBarMoveGeometryPolicy.shouldAcceptCachedVisibleMoveTargetWithoutLiveSeparator(
                        separatorX: separatorX,
                        visibleBoundaryX: targets.visibleBoundaryX,
                        sourceFrameIsOnScreen: sourceFrameIsOnScreen,
                        hasPreciseIdentity: MenuBarMoveGeometryPolicy.hasPreciseMoveIdentity(
                            menuExtraId: sourceIdentity.menuExtraId,
                            statusItemIndex: sourceIdentity.statusItemIndex
                        ),
                        hasLiveSeparatorAnchor: liveSeparatorReady
                    )

                    if liveSeparatorReady || canUseCachedVisibleTarget {
                        if attempt > 1 {
                            logger.info("Resolved separator target after \(attempt * 50)ms")
                        }
                        if canUseCachedVisibleTarget {
                            logger.info("Accepting cached visible move target because source icon is already on-screen with a precise identity")
                        }
                        return targets
                    }

                    if attempt == 1 || attempt % 5 == 0 {
                        logger.debug("Cached separator target available after \(attempt * 50)ms but live frame is still stale")
                        logger.debug("Waiting for live separator frame or an on-screen precise source icon before accepting cached move target")
                        if toHidden, !hiddenLaneBoundaryReady {
                            logger.debug("Waiting for always-hidden boundary before accepting regular hidden move target")
                        }
                    }
                }
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        let requiresHiddenLaneBoundary = toHidden &&
            separatorOverrideX == nil &&
            regularHiddenMoveRequiresAlwaysHiddenBoundary()
        if requiresHiddenLaneBoundary {
            guard let separatorX = lastTargets.separatorX,
                  Self.hiddenBoundaryIsOrdered(lastTargets.visibleBoundaryX, separatorX: separatorX)
            else {
                logger.error("Regular hidden move target resolution failed without separator or always-hidden boundary")
                return (nil, nil)
            }
        }
        if !toHidden, manager.geometryResolver.currentLiveSeparatorFrame() == nil {
            logger.error("Visible move target resolution failed without live separator geometry")
            return (nil, nil)
        }
        return lastTargets
    }

    func regularHiddenMoveRequiresAlwaysHiddenBoundary() -> Bool {
        MenuBarActionWorkflow.effectiveAlwaysHiddenSectionEnabled(
            isPro: LicenseService.shared.isPro,
            alwaysHiddenSectionEnabled: manager.settings.alwaysHiddenSectionEnabled
        ) && manager.alwaysHiddenSeparatorItem != nil
    }

    func resolveAlwaysHiddenMoveTargetsWithRetries(
        toAlwaysHidden: Bool,
        maxAttempts: Int = 20
    ) async -> (separatorX: CGFloat?, visibleBoundaryX: CGFloat?) {
        for attempt in 1 ... maxAttempts {
            let readiness = alwaysHiddenTargetReadiness(toAlwaysHidden: toAlwaysHidden)

            if let separatorX = readiness.targets.separatorX,
               separatorX.isFinite,
               toAlwaysHidden || Self.visibleBoundaryIsOrdered(
                   readiness.targets.visibleBoundaryX,
                   separatorX: separatorX
               ) {
                let liveGeometryReady = toAlwaysHidden
                    ? readiness.alwaysHiddenSeparatorIsLive
                    : readiness.alwaysHiddenSeparatorIsLive && readiness.mainSeparatorIsLive
                if liveGeometryReady {
                    if attempt > 1 {
                        logger.info("Resolved always-hidden move targets after \(attempt * 50)ms")
                    }
                    return readiness.targets
                }

                if attempt == 1 || attempt % 5 == 0 {
                    logger.debug("Waiting for live always-hidden separator geometry before move target acceptance")
                }
            }

            try? await Task.sleep(for: .milliseconds(50))
        }

        logger.error("Always-hidden move target resolution failed without live separator geometry")
        return (nil, nil)
    }

    func verifyVisibleMoveWithFreshGeometry(
        identity: SourceIdentity,
        staleSeparatorX: CGFloat,
        allowsGeometryRecheck: Bool
    ) async -> Bool {
        guard allowsGeometryRecheck else { return false }
        guard staleSeparatorX.isFinite else { return false }

        guard let staleFrame = AccessibilityMenuExtraService.getMenuBarIconFrame(
            bundleID: identity.bundleID,
            menuExtraId: identity.menuExtraId,
            statusItemIndex: identity.statusItemIndex,
            preferredCenterX: identity.preferredCenterX
        ) else {
            return false
        }

        try? await Task.sleep(for: .milliseconds(120))
        await manager.geometryResolver.warmSeparatorPositionCache(maxAttempts: 16)

        guard let freshSeparatorX = manager.geometryResolver.separatorRightEdgeX(),
              freshSeparatorX.isFinite
        else {
            return false
        }
        guard let freshVisibleBoundaryX = manager.geometryResolver.mainStatusItemLeftEdgeX(),
              Self.visibleBoundaryIsOrdered(freshVisibleBoundaryX, separatorX: freshSeparatorX)
        else {
            return false
        }
        guard let refreshedFrame = AccessibilityMenuExtraService.getMenuBarIconFrame(
            bundleID: identity.bundleID,
            menuExtraId: identity.menuExtraId,
            statusItemIndex: identity.statusItemIndex,
            preferredCenterX: identity.preferredCenterX
        ) else {
            return false
        }

        guard AccessibilityService.shouldAcceptVisibleMoveAfterFreshGeometryRecheck(
            staleSeparatorX: staleSeparatorX,
            staleFrame: staleFrame,
            freshSeparatorX: freshSeparatorX,
            freshVisibleBoundaryX: freshVisibleBoundaryX,
            refreshedFrame: refreshedFrame
        ) else {
            return false
        }

        logger.info(
            "Visible move accepted after fresh geometry recheck (staleSeparatorX=\(staleSeparatorX, privacy: .public), freshSeparatorX=\(freshSeparatorX, privacy: .public), freshVisibleBoundaryX=\(freshVisibleBoundaryX, privacy: .public), afterMidX=\(refreshedFrame.midX, privacy: .public))"
        )
        return true
    }

    private func hiddenMoveSeparatorX(separatorOverrideX: CGFloat?) -> CGFloat? {
        if let separatorOverrideX {
            return separatorOverrideX
        }

        let origin = manager.geometryResolver.separatorOriginX()
        let derivedFromRightEdge: CGFloat? = {
            guard let rightEdge = manager.geometryResolver.separatorRightEdgeX(), rightEdge.isFinite else { return nil }
            return rightEdge - MenuBarMoveGeometryPolicy.separatorVisualWidth
        }()

        if let origin, let derivedFromRightEdge {
            if origin + 40 < derivedFromRightEdge {
                logger.warning(
                    "Hidden move target corrected from stale origin \(origin) to right-edge-derived \(derivedFromRightEdge)"
                )
                return derivedFromRightEdge
            }
            return origin
        }

        return origin ?? derivedFromRightEdge
    }

    private func alwaysHiddenTargetReadiness(toAlwaysHidden: Bool) -> AlwaysHiddenTargetReadiness {
        if toAlwaysHidden {
            let liveBoundaryX = manager.geometryResolver.currentLiveAlwaysHiddenSeparatorBoundaryX()
            return AlwaysHiddenTargetReadiness(
                targets: (liveBoundaryX, nil),
                alwaysHiddenSeparatorIsLive: liveBoundaryX != nil,
                mainSeparatorIsLive: liveBoundaryX != nil
            )
        }

        return AlwaysHiddenTargetReadiness(
            targets: (manager.geometryResolver.separatorRightEdgeX(), manager.geometryResolver.mainStatusItemLeftEdgeX()),
            alwaysHiddenSeparatorIsLive: manager.geometryResolver.currentLiveAlwaysHiddenSeparatorFrame() != nil,
            mainSeparatorIsLive: manager.geometryResolver.currentLiveSeparatorFrame() != nil
        )
    }

    private func hiddenLaneLeftBoundary(
        separatorX: CGFloat?,
        separatorOverrideX: CGFloat?
    ) -> CGFloat? {
        guard separatorOverrideX == nil,
              let separatorX,
              let candidateBoundaryX = manager.geometryResolver.alwaysHiddenSeparatorBoundaryX(),
              separatorX.isFinite,
              candidateBoundaryX.isFinite
        else {
            return nil
        }

        if candidateBoundaryX < (separatorX - 4) {
            logger.info("AH separator boundary for hidden target: \(candidateBoundaryX)")
            return candidateBoundaryX
        }

        logger.warning(
            "Ignoring AH boundary >= separator during hidden move target resolution (ah=\(candidateBoundaryX), sep=\(separatorX))"
        )
        return nil
    }

    private func sourceFrameIsOnScreenForMove(_ identity: SourceIdentity) -> Bool {
        guard let frame = AccessibilityMenuExtraService.getMenuBarIconFrame(
            bundleID: identity.bundleID,
            menuExtraId: identity.menuExtraId,
            statusItemIndex: identity.statusItemIndex,
            preferredCenterX: identity.preferredCenterX
        ) else {
            return false
        }

        let center = CGPoint(x: frame.midX, y: frame.midY)
        return AccessibilityService.isAccessibilityPointOnAnyScreen(
            center,
            screenFrames: NSScreen.screens.map(\.frame)
        )
    }
}
