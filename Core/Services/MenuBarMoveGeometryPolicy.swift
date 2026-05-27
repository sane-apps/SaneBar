import CoreGraphics

enum MenuBarMoveGeometryPolicy {
    static let separatorVisualWidth: CGFloat = 20

    static func separatorFrameLooksLive(originX: CGFloat, width: CGFloat) -> Bool {
        originX > 0 && width > 0 && width < 1000
    }

    static func mainStatusItemFrameLooksLive(originX: CGFloat, width: CGFloat) -> Bool {
        originX > 0 && width > 0 && width < 1000
    }

    static func normalizedSeparatorRightEdge(
        cachedRightEdge: CGFloat?,
        cachedOrigin: CGFloat?,
        estimatedRightEdge: CGFloat?,
        mainLeftEdge: CGFloat?
    ) -> CGFloat? {
        var candidate = cachedRightEdge

        if let origin = cachedOrigin, origin > 0 {
            if candidate == nil || (candidate ?? 0) <= origin || (candidate ?? 0) > (origin + 250) {
                candidate = origin + separatorVisualWidth
            }
        }

        if candidate == nil {
            candidate = estimatedRightEdge
        }

        if let mainLeftEdge, mainLeftEdge > 0, let edge = candidate, edge >= mainLeftEdge {
            candidate = max(1, mainLeftEdge - 2)
        }

        if let origin = cachedOrigin, origin > 0, let edge = candidate, edge <= origin {
            candidate = origin + 1
        }

        guard let resolved = candidate, resolved > 0 else { return nil }
        return resolved
    }

    static func estimatedMainStatusItemLeftEdge(
        separatorIsPresentInVisualMode: Bool,
        separatorRightEdge: CGFloat?,
        separatorOrigin: CGFloat?
    ) -> CGFloat? {
        guard separatorIsPresentInVisualMode else { return nil }
        return normalizedSeparatorRightEdge(
            cachedRightEdge: separatorRightEdge,
            cachedOrigin: separatorOrigin,
            estimatedRightEdge: nil,
            mainLeftEdge: nil
        )
    }

    static func normalizedAlwaysHiddenBoundary(
        cachedRightEdge: CGFloat?,
        cachedOrigin: CGFloat?,
        separatorX: CGFloat?,
        minimumGap: CGFloat = 8
    ) -> CGFloat? {
        var candidate = cachedRightEdge

        if let origin = cachedOrigin, origin > 0 {
            if candidate == nil || (candidate ?? 0) <= origin || (candidate ?? 0) > (origin + 250) {
                candidate = origin + separatorVisualWidth
            }
        }

        guard let resolvedSeparatorX = separatorX,
              resolvedSeparatorX.isFinite,
              resolvedSeparatorX > 0,
              let boundary = candidate,
              boundary.isFinite,
              boundary > 0
        else {
            return nil
        }

        let maxAllowed = resolvedSeparatorX - max(1, minimumGap)
        guard maxAllowed > 0 else { return nil }
        guard boundary < maxAllowed else { return nil }
        return boundary
    }

    static func hasPreciseMoveIdentity(
        menuExtraId: String?,
        statusItemIndex: Int?
    ) -> Bool {
        if let menuExtraId, !menuExtraId.isEmpty {
            return true
        }
        if let statusItemIndex, statusItemIndex >= 0 {
            return true
        }
        return false
    }

    static func shouldAcceptCachedVisibleMoveTargetWithoutLiveSeparator(
        visibleBoundaryX: CGFloat?,
        sourceFrameIsOnScreen: Bool,
        hasPreciseIdentity: Bool,
        hasLiveSeparatorAnchor: Bool
    ) -> Bool {
        guard let visibleBoundaryX, visibleBoundaryX > 0 else { return false }
        guard sourceFrameIsOnScreen else { return false }
        return hasPreciseIdentity && hasLiveSeparatorAnchor
    }

    static func shouldBlockWideIconHiddenMove(
        iconWidth: CGFloat,
        hiddenLaneWidth: CGFloat
    ) -> Bool {
        guard iconWidth.isFinite, hiddenLaneWidth.isFinite else { return false }
        guard iconWidth > 0, hiddenLaneWidth > 0 else { return false }

        let wideIconThreshold: CGFloat = 120
        guard iconWidth >= wideIconThreshold else { return false }

        let lanePadding: CGFloat = 18
        return hiddenLaneWidth < (iconWidth + lanePadding)
    }
}
