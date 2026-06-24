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

    /// A status-item window's TRUE frame can be read live whenever the window is
    /// attached to its screen's menu-bar band, regardless of the item's logical
    /// `length` (a hidden always-hidden separator uses length 10000 to push
    /// *items* off-screen, but its own window may still sit live in the band, and
    /// during an outbound move `showAll()` contracts it back to a small visual
    /// length). Liveness is judged ONLY by screen-relative band membership — never
    /// by length and never by sign. This is the named decision point the
    /// always-hidden live-frame read uses so the redundant `length <= 1000`
    /// short-circuit (which wrongly rejected a live-but-hidden separator) can be
    /// removed without weakening off-screen rejection.
    static func statusItemWindowFrameIsReadableLive(frame: CGRect, screenFrame: CGRect?) -> Bool {
        statusItemFrameLooksLive(frame: frame, screenFrame: screenFrame)
    }

    /// Resolves which screen frame a status-item window's TRUE frame belongs to
    /// when AppKit failed to populate `NSWindow.screen` (it returns nil whenever
    /// the window's frame does not currently intersect a screen rect — common for
    /// a genuinely-hidden separator pushed off the left edge, and for items on an
    /// external display during a topology transition). Without this, the live
    /// readers fed `window.screen?.frame == nil` straight into
    /// `statusItemFrameLooksLive`, which short-circuits to `false`, so a window
    /// with a perfectly live frame in a known screen's band was wrongly classified
    /// non-live → recovery looped on `.stale`/`.missing` anchors forever (#155/
    /// #157/#136 cluster, worst on `isOnExternalMonitor`).
    ///
    /// Off-screen rejection is preserved: a candidate screen is only accepted when
    /// the window's frame actually sits in THAT screen's menu-bar band. A parked
    /// (y=-22) or off-edge (x ≫ maxX) window matches no candidate band and still
    /// resolves to nil → still rejected. This never invents a screen; it only
    /// recovers the screen-relative judgement AppKit dropped.
    static func resolvedScreenFrameForStatusItemWindow(
        windowFrame: CGRect,
        attachedScreenFrame: CGRect?,
        candidateScreenFrames: [CGRect]
    ) -> CGRect? {
        if let attachedScreenFrame { return attachedScreenFrame }
        // Prefer a candidate whose band the window frame genuinely occupies, so
        // the subsequent liveness check is identical to the attached-screen path.
        return candidateScreenFrames.first { candidate in
            statusItemFrameLooksLive(frame: windowFrame, screenFrame: candidate)
        }
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
