import CoreGraphics

struct SnapshotAlwaysHiddenGeometry {
    let originX: CGFloat?
    let boundaryX: CGFloat?
    let isReliable: Bool
}

extension LayoutSnapshotCommand {
    nonisolated static func normalizedSnapshotAlwaysHiddenGeometry(
        hidingState: HidingState,
        separatorX: CGFloat?,
        alwaysHiddenOriginX: CGFloat?,
        alwaysHiddenBoundaryX: CGFloat?
    ) -> SnapshotAlwaysHiddenGeometry {
        guard hidingState != .hidden else {
            return SnapshotAlwaysHiddenGeometry(originX: nil, boundaryX: nil, isReliable: false)
        }
        guard let separatorX, separatorX.isFinite, separatorX > 0 else {
            return SnapshotAlwaysHiddenGeometry(originX: nil, boundaryX: nil, isReliable: false)
        }

        let boundaryX = SearchService.normalizedAlwaysHiddenBoundary(alwaysHiddenBoundaryX, separatorX: separatorX)
        let originX: CGFloat? = {
            if let alwaysHiddenOriginX,
               alwaysHiddenOriginX.isFinite,
               alwaysHiddenOriginX > 0,
               alwaysHiddenOriginX < separatorX {
                return alwaysHiddenOriginX
            }
            if let boundaryX {
                return max(1, boundaryX - 20)
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
            return SearchService.normalizedAlwaysHiddenBoundary(originX + 20, separatorX: separatorX)
        }()

        return SnapshotAlwaysHiddenGeometry(originX: originX, boundaryX: normalizedBoundaryX, isReliable: true)
    }
}
