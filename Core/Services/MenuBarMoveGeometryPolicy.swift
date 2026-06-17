import CoreGraphics

enum MenuBarMoveGeometryPolicy {
    static let separatorVisualWidth: CGFloat = 20

    /// Canonical screen-aware liveness: a status-item window is live when it is
    /// attached to a screen and sits in that screen's menu bar band. Sign-based
    /// checks (originX > 0) wrongly classified every frame on a display arranged
    /// left of the primary (negative global X) as stale, and accepted offscreen
    /// parked windows (e.g. y=-22) as live when their X happened to be positive.
    static func statusItemFrameLooksLive(frame: CGRect, screenFrame: CGRect?) -> Bool {
        guard frame.width > 0, frame.width < 1000 else { return false }
        guard let screenFrame else { return false }
        let verticalTolerance: CGFloat = 50
        let horizontalTolerance: CGFloat = 8
        let verticalMatch = abs(screenFrame.maxY - frame.maxY) <= verticalTolerance
        let horizontalOverlap = frame.maxX >= (screenFrame.minX - horizontalTolerance) &&
            frame.minX <= (screenFrame.maxX + horizontalTolerance)
        return verticalMatch && horizontalOverlap
    }

    static func normalizedSeparatorRightEdge(
        cachedRightEdge: CGFloat?,
        cachedOrigin: CGFloat?,
        estimatedRightEdge: CGFloat?,
        mainLeftEdge: CGFloat?
    ) -> CGFloat? {
        var candidate = cachedRightEdge

        // Ordering/normalization is sign-independent: negative global X is
        // legitimate on displays arranged left of the primary.
        if let origin = cachedOrigin, origin.isFinite {
            if candidate == nil || (candidate ?? -.greatestFiniteMagnitude) <= origin || (candidate ?? 0) > (origin + 250) {
                candidate = origin + separatorVisualWidth
            }
        }

        if candidate == nil {
            candidate = estimatedRightEdge
        }

        if let mainLeftEdge, mainLeftEdge.isFinite, let edge = candidate, edge >= mainLeftEdge {
            candidate = mainLeftEdge - 2
        }

        if let origin = cachedOrigin, origin.isFinite, let edge = candidate, edge <= origin {
            candidate = origin + 1
        }

        guard let resolved = candidate, resolved.isFinite else { return nil }
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

        if let origin = cachedOrigin, origin.isFinite {
            if candidate == nil || (candidate ?? -.greatestFiniteMagnitude) <= origin || (candidate ?? 0) > (origin + 250) {
                candidate = origin + separatorVisualWidth
            }
        }

        guard let resolvedSeparatorX = separatorX,
              resolvedSeparatorX.isFinite,
              let boundary = candidate,
              boundary.isFinite
        else {
            return nil
        }

        let maxAllowed = resolvedSeparatorX - max(1, minimumGap)
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
        separatorX: CGFloat,
        visibleBoundaryX: CGFloat?,
        sourceFrameIsOnScreen: Bool,
        hasPreciseIdentity: Bool,
        hasLiveSeparatorAnchor: Bool
    ) -> Bool {
        guard separatorX.isFinite,
              let visibleBoundaryX,
              visibleBoundaryX.isFinite,
              visibleBoundaryX > separatorX
        else {
            return false
        }
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
