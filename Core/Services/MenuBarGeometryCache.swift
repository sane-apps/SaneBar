import CoreGraphics

@MainActor
final class MenuBarGeometryCache {
    var lastKnownSeparatorX: CGFloat?
    var lastKnownSeparatorRightEdgeX: CGFloat?
    var hasLoggedStaleSeparatorRightEdgeFallback = false
    var lastKnownMainStatusItemX: CGFloat?
    var hasLoggedStaleMainStatusItemFallback = false
    var lastKnownAlwaysHiddenSeparatorX: CGFloat?
    var lastKnownAlwaysHiddenSeparatorRightEdgeX: CGFloat?

    func clearSeparatorGeometry() {
        lastKnownMainStatusItemX = nil
        lastKnownSeparatorX = nil
        lastKnownSeparatorRightEdgeX = nil
        lastKnownAlwaysHiddenSeparatorX = nil
        lastKnownAlwaysHiddenSeparatorRightEdgeX = nil
    }
}
