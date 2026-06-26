import CoreGraphics
@testable import SaneBar
import Testing

/// Regression coverage for the All-tab zone classifier used to build the
/// right-click move menu. The SaneClip bug (#move-classification): a genuinely
/// Hidden item was misclassified as Always Hidden because `appZone` recomputed
/// from separator geometry that is stale/off-screen, diverging from the
/// authoritative cached classification. `zoneForAllTab` must prefer the cache.
struct BrowsePanelZoneClassifierTests {
    private func makeApp(_ id: String, xPosition: CGFloat? = nil) -> RunningApp {
        RunningApp(id: id, name: id, icon: nil, menuExtraIdentifier: nil, xPosition: xPosition, width: 20)
    }

    @Test("Prefers cached Hidden classification over stale/absent geometry")
    func cachedHiddenWinsOverGeometry() {
        let target = makeApp("com.test.hidden")
        let classified = SearchClassifiedApps(visible: [], hidden: [target], alwaysHidden: [])
        // Geometry unavailable (nil) → the pre-fix path returned .visible.
        let zone = BrowsePanelZoneClassifier.zoneForAllTab(
            app: target,
            classified: classified,
            pinnedIds: [],
            separatorRightEdgeX: nil,
            separatorOriginX: nil,
            alwaysHiddenBoundaryX: nil,
            alwaysHiddenOriginX: nil
        )
        #expect(zone == .hidden)
    }

    @Test("Prefers cached Always-Hidden classification over stale/absent geometry")
    func cachedAlwaysHiddenWinsOverGeometry() {
        let target = makeApp("com.test.ah")
        let classified = SearchClassifiedApps(visible: [], hidden: [], alwaysHidden: [target])
        let zone = BrowsePanelZoneClassifier.zoneForAllTab(
            app: target,
            classified: classified,
            pinnedIds: [],
            separatorRightEdgeX: nil,
            separatorOriginX: nil,
            alwaysHiddenBoundaryX: nil,
            alwaysHiddenOriginX: nil
        )
        #expect(zone == .alwaysHidden)
    }

    @Test("Cached Visible classification wins even when geometry would say Always Hidden")
    func cachedVisibleWinsOverGeometryAlwaysHidden() {
        // SaneClip-shape: genuinely Visible item whose midX sits left of a stale
        // always-hidden boundary. The cache must override the geometry verdict.
        let target = makeApp("com.test.visible", xPosition: 100)
        let classified = SearchClassifiedApps(visible: [target], hidden: [], alwaysHidden: [])
        let zone = BrowsePanelZoneClassifier.zoneForAllTab(
            app: target,
            classified: classified,
            pinnedIds: [],
            separatorRightEdgeX: 1000,
            separatorOriginX: 980,
            alwaysHiddenBoundaryX: 500,
            alwaysHiddenOriginX: 480
        )
        #expect(zone == .visible)
    }

    @Test("Falls back to geometry default when the app is absent from the cache")
    func fallsBackToGeometryWhenUncached() {
        let target = makeApp("com.test.uncached")
        let empty = SearchClassifiedApps(visible: [], hidden: [], alwaysHidden: [])
        let zone = BrowsePanelZoneClassifier.zoneForAllTab(
            app: target,
            classified: empty,
            pinnedIds: [],
            separatorRightEdgeX: nil,
            separatorOriginX: nil,
            alwaysHiddenBoundaryX: nil,
            alwaysHiddenOriginX: nil
        )
        // No cache hit, no geometry, no position → documented default.
        #expect(zone == .visible)
    }
}
