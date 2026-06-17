import CoreGraphics

struct SnapshotAlwaysHiddenGeometry {
    let originX: CGFloat?
    let boundaryX: CGFloat?
    let isReliable: Bool
}

extension LayoutSnapshotCommand {
    nonisolated static func resolvedSnapshotMainRightGap(
        referenceScreenRightEdge: CGFloat?,
        liveFrameOriginX: CGFloat?,
        liveFrameWidth: CGFloat?,
        cachedMainX: CGFloat?
    ) -> CGFloat? {
        guard let referenceScreenRightEdge,
              referenceScreenRightEdge.isFinite else {
            return nil
        }

        func plausibleRightGap(from originX: CGFloat) -> CGFloat? {
            guard originX.isFinite else { return nil }
            let gap = referenceScreenRightEdge - originX
            guard gap >= 0, gap < 1000 else { return nil }
            return gap
        }

        if let liveFrameOriginX,
           let liveFrameWidth,
           liveFrameWidth > 0,
           liveFrameWidth < 1000,
           let gap = plausibleRightGap(from: liveFrameOriginX) {
            return gap
        }

        guard let cachedMainX,
              let gap = plausibleRightGap(from: cachedMainX)
        else {
            return nil
        }
        return gap
    }

    nonisolated static func normalizedSnapshotAlwaysHiddenGeometry(
        hidingState: HidingState,
        separatorX: CGFloat?,
        alwaysHiddenOriginX: CGFloat?,
        alwaysHiddenBoundaryX: CGFloat?
    ) -> SnapshotAlwaysHiddenGeometry {
        guard hidingState != .hidden else {
            return SnapshotAlwaysHiddenGeometry(originX: nil, boundaryX: nil, isReliable: false)
        }
        guard let separatorX, separatorX.isFinite else {
            return SnapshotAlwaysHiddenGeometry(originX: nil, boundaryX: nil, isReliable: false)
        }

        let boundaryX = SearchService.normalizedAlwaysHiddenBoundary(alwaysHiddenBoundaryX, separatorX: separatorX)
        let originX: CGFloat? = {
            if let alwaysHiddenOriginX,
               alwaysHiddenOriginX.isFinite,
               alwaysHiddenOriginX < separatorX {
                return alwaysHiddenOriginX
            }
            if let boundaryX {
                return boundaryX - MenuBarMoveGeometryPolicy.separatorVisualWidth
            }
            return nil
        }()

        guard let originX else {
            return SnapshotAlwaysHiddenGeometry(originX: nil, boundaryX: nil, isReliable: false)
        }

        let normalizedBoundaryX: CGFloat? = {
            if let boundaryX {
                return boundaryX
            }
            return SearchService.normalizedAlwaysHiddenBoundary(
                originX + MenuBarMoveGeometryPolicy.separatorVisualWidth,
                separatorX: separatorX
            )
        }()

        return SnapshotAlwaysHiddenGeometry(originX: originX, boundaryX: normalizedBoundaryX, isReliable: true)
    }
}
