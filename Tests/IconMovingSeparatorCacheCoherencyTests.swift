import Foundation
@testable import SaneBar
import Testing

@Suite("Icon Moving — Separator Cache Coherency")
struct IconMovingSeparatorCacheCoherencyTests {
    @Test("Screen-aware liveness accepts frames in the menu bar band of their screen")
    func screenAwareLivenessAcceptsMenuBarBandFrames() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let frame = CGRect(x: 1537, y: 1093, width: 83, height: 24)
        #expect(MenuBarMoveGeometryPolicy.statusItemFrameLooksLive(frame: frame, screenFrame: screen))
    }

    @Test("Screen-aware liveness accepts negative-X frames on a left-arranged display")
    func screenAwareLivenessAcceptsNegativeXOnLeftDisplay() {
        // External display arranged left of the primary: global X is negative.
        let leftScreen = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        let frame = CGRect(x: -1100, y: 1416, width: 36, height: 24)
        #expect(MenuBarMoveGeometryPolicy.statusItemFrameLooksLive(frame: frame, screenFrame: leftScreen))
    }

    @Test("Screen-aware liveness rejects offscreen-parked and detached frames")
    func screenAwareLivenessRejectsParkedAndDetachedFrames() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        // The #152 signature: window parked at the bottom-left, positive X or not.
        let parked = CGRect(x: 10, y: -22, width: 36, height: 24)
        #expect(MenuBarMoveGeometryPolicy.statusItemFrameLooksLive(frame: parked, screenFrame: screen) == false)
        // Detached window (no screen) is never live.
        let live = CGRect(x: 1537, y: 1093, width: 83, height: 24)
        #expect(MenuBarMoveGeometryPolicy.statusItemFrameLooksLive(frame: live, screenFrame: nil) == false)
        // Blocking-sized separator is never live.
        let blocking = CGRect(x: 100, y: 1093, width: 5002, height: 24)
        #expect(MenuBarMoveGeometryPolicy.statusItemFrameLooksLive(frame: blocking, screenFrame: screen) == false)
        // Frame from another display's coordinates does not overlap this screen.
        let crossScreen = CGRect(x: 4000, y: 1093, width: 36, height: 24)
        #expect(MenuBarMoveGeometryPolicy.statusItemFrameLooksLive(frame: crossScreen, screenFrame: screen) == false)
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
            separatorX: 1662,
            visibleBoundaryX: 1699,
            sourceFrameIsOnScreen: true,
            hasPreciseIdentity: true,
            hasLiveSeparatorAnchor: true
        )
        #expect(allowed)
    }

    @Test("Visible cached move target is allowed with ordered negative coordinates")
    func acceptsCachedVisibleMoveTargetWithOrderedNegativeCoordinates() {
        let allowed = MenuBarMoveGeometryPolicy.shouldAcceptCachedVisibleMoveTargetWithoutLiveSeparator(
            separatorX: -600,
            visibleBoundaryX: -560,
            sourceFrameIsOnScreen: true,
            hasPreciseIdentity: true,
            hasLiveSeparatorAnchor: true
        )
        #expect(allowed)
    }

    @Test("Visible cached move target stays blocked while separator anchor is estimated")
    func rejectsCachedVisibleMoveTargetWithoutLiveSeparatorAnchor() {
        let allowed = MenuBarMoveGeometryPolicy.shouldAcceptCachedVisibleMoveTargetWithoutLiveSeparator(
            separatorX: 1662,
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
            separatorX: 1662,
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
            separatorX: 1662,
            visibleBoundaryX: 1699,
            sourceFrameIsOnScreen: false,
            hasPreciseIdentity: true,
            hasLiveSeparatorAnchor: true
        )
        #expect(allowed == false)
    }

    @Test("Visible cached move target rejects unordered negative coordinates")
    func rejectsCachedVisibleMoveTargetWithUnorderedNegativeCoordinates() {
        let allowed = MenuBarMoveGeometryPolicy.shouldAcceptCachedVisibleMoveTargetWithoutLiveSeparator(
            separatorX: -600,
            visibleBoundaryX: -620,
            sourceFrameIsOnScreen: true,
            hasPreciseIdentity: true,
            hasLiveSeparatorAnchor: true
        )
        #expect(allowed == false)
    }

    @Test("Layout snapshot preserves negative-coordinate main gap and always-hidden ordering")
    func layoutSnapshotPreservesNegativeCoordinateGeometry() {
        #expect(
            LayoutSnapshotCommand.resolvedSnapshotMainRightGap(
                referenceScreenRightEdge: 0,
                liveFrameOriginX: -120,
                liveFrameWidth: 24,
                cachedMainX: nil
            ) == 120
        )

        let geometry = LayoutSnapshotCommand.normalizedSnapshotAlwaysHiddenGeometry(
            hidingState: .expanded,
            separatorX: -600,
            alwaysHiddenOriginX: -1100,
            alwaysHiddenBoundaryX: -1080
        )
        #expect(geometry.isReliable)
        #expect(geometry.originX == -1100)
        #expect(geometry.boundaryX == -1080)
    }
}
