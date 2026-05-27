import Foundation
@testable import SaneBar
import Testing

@Suite("Icon Moving — Separator Cache Coherency")
struct IconMovingSeparatorCacheCoherencyTests {
    @Test("Accepts live separator frame when origin is on-screen and width is visual size")
    func acceptsLiveSeparatorFrame() {
        #expect(MenuBarMoveGeometryPolicy.separatorFrameLooksLive(originX: 1537, width: 83))
    }

    @Test("Rejects stale separator frame when off-screen or blocking sized")
    func rejectsStaleSeparatorFrame() {
        #expect(MenuBarMoveGeometryPolicy.separatorFrameLooksLive(originX: -3527, width: 36) == false)
        #expect(MenuBarMoveGeometryPolicy.separatorFrameLooksLive(originX: 1537, width: 5002) == false)
    }

    @Test("Repairs stale right-edge cache from origin cache")
    func repairsStaleRightEdgeFromOrigin() {
        let resolved = MenuBarMoveGeometryPolicy.normalizedSeparatorRightEdge(
            cachedRightEdge: 454,
            cachedOrigin: 1168,
            estimatedRightEdge: nil,
            mainLeftEdge: 1386
        )
        #expect(resolved == 1188)
    }

    @Test("Clamps right-edge cache left of main icon boundary")
    func clampsRightEdgeToMainBoundary() {
        let resolved = MenuBarMoveGeometryPolicy.normalizedSeparatorRightEdge(
            cachedRightEdge: 1450,
            cachedOrigin: 1200,
            estimatedRightEdge: nil,
            mainLeftEdge: 1386
        )
        #expect(resolved == 1384)
    }

    @Test("Falls back to estimated edge when caches are missing")
    func fallsBackToEstimatedEdge() {
        let resolved = MenuBarMoveGeometryPolicy.normalizedSeparatorRightEdge(
            cachedRightEdge: nil,
            cachedOrigin: nil,
            estimatedRightEdge: 1190,
            mainLeftEdge: 1386
        )
        #expect(resolved == 1190)
    }

    @Test("Repairs inverted edge cache to one point right of origin")
    func repairsInvertedEdge() {
        let resolved = MenuBarMoveGeometryPolicy.normalizedSeparatorRightEdge(
            cachedRightEdge: 1000,
            cachedOrigin: 1168,
            estimatedRightEdge: nil,
            mainLeftEdge: 1386
        )
        #expect(resolved == 1188)
    }

    @Test("Clamps live separator edge left of main icon boundary")
    func clampsLiveSeparatorEdgeLeftOfMainIcon() {
        let resolved = MenuBarMoveGeometryPolicy.normalizedSeparatorRightEdge(
            cachedRightEdge: 1699,
            cachedOrigin: 1663,
            estimatedRightEdge: nil,
            mainLeftEdge: 1699
        )
        #expect(resolved == 1697)
    }

    @Test("Repairs always-hidden boundary from origin cache")
    func repairsAlwaysHiddenBoundaryFromOrigin() {
        let resolved = MenuBarMoveGeometryPolicy.normalizedAlwaysHiddenBoundary(
            cachedRightEdge: 1920,
            cachedOrigin: 1357,
            separatorX: 1662
        )
        #expect(resolved == 1377)
    }

    @Test("Rejects always-hidden boundary on or right of separator")
    func rejectsInvalidAlwaysHiddenBoundary() {
        let resolved = MenuBarMoveGeometryPolicy.normalizedAlwaysHiddenBoundary(
            cachedRightEdge: 1890,
            cachedOrigin: nil,
            separatorX: 1662
        )
        #expect(resolved == nil)
    }

    @Test("Visible cached move target is allowed when source is on-screen and identity is precise")
    func acceptsCachedVisibleMoveTargetForPreciseOnScreenSource() {
        let allowed = MenuBarMoveGeometryPolicy.shouldAcceptCachedVisibleMoveTargetWithoutLiveSeparator(
            visibleBoundaryX: 1699,
            sourceFrameIsOnScreen: true,
            hasPreciseIdentity: true,
            hasLiveSeparatorAnchor: true
        )
        #expect(allowed)
    }

    @Test("Visible cached move target stays blocked while separator anchor is estimated")
    func rejectsCachedVisibleMoveTargetWithoutLiveSeparatorAnchor() {
        let allowed = MenuBarMoveGeometryPolicy.shouldAcceptCachedVisibleMoveTargetWithoutLiveSeparator(
            visibleBoundaryX: 1699,
            sourceFrameIsOnScreen: true,
            hasPreciseIdentity: true,
            hasLiveSeparatorAnchor: false
        )
        #expect(allowed == false)
    }

    @Test("Visible cached move target stays blocked for coarse source identity")
    func rejectsCachedVisibleMoveTargetForCoarseIdentity() {
        let allowed = MenuBarMoveGeometryPolicy.shouldAcceptCachedVisibleMoveTargetWithoutLiveSeparator(
            visibleBoundaryX: 1699,
            sourceFrameIsOnScreen: true,
            hasPreciseIdentity: false,
            hasLiveSeparatorAnchor: true
        )
        #expect(allowed == false)
    }

    @Test("Visible cached move target stays blocked while source is still off-screen")
    func rejectsCachedVisibleMoveTargetForOffScreenSource() {
        let allowed = MenuBarMoveGeometryPolicy.shouldAcceptCachedVisibleMoveTargetWithoutLiveSeparator(
            visibleBoundaryX: 1699,
            sourceFrameIsOnScreen: false,
            hasPreciseIdentity: true,
            hasLiveSeparatorAnchor: true
        )
        #expect(allowed == false)
    }
}
