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

    private func makeContext(
        classified: SearchClassifiedApps,
        pinnedIds: Set<String> = [],
        allApps: [RunningApp],
        separatorRightEdgeX: CGFloat? = nil,
        separatorOriginX: CGFloat? = nil,
        alwaysHiddenBoundaryX: CGFloat? = nil,
        alwaysHiddenOriginX: CGFloat? = nil
    ) -> BrowsePanelZoneClassifier.AllTabContext {
        BrowsePanelZoneClassifier.AllTabContext(
            classified: classified,
            pinnedIds: pinnedIds,
            allApps: allApps,
            separatorRightEdgeX: separatorRightEdgeX,
            separatorOriginX: separatorOriginX,
            alwaysHiddenBoundaryX: alwaysHiddenBoundaryX,
            alwaysHiddenOriginX: alwaysHiddenOriginX
        )
    }

    @Test("Prefers cached Hidden classification over stale/absent geometry")
    func cachedHiddenWinsOverGeometry() {
        let target = makeApp("com.test.hidden")
        let classified = SearchClassifiedApps(visible: [], hidden: [target], alwaysHidden: [])
        // Geometry unavailable (nil) → the pre-fix path returned .visible.
        let zone = BrowsePanelZoneClassifier.zoneForAllTab(
            app: target,
            context: makeContext(classified: classified, allApps: [target])
        )
        #expect(zone == .hidden)
    }

    @Test("Prefers cached Always-Hidden classification over stale/absent geometry")
    func cachedAlwaysHiddenWinsOverGeometry() {
        let target = makeApp("com.test.ah")
        let classified = SearchClassifiedApps(visible: [], hidden: [], alwaysHidden: [target])
        let zone = BrowsePanelZoneClassifier.zoneForAllTab(
            app: target,
            context: makeContext(classified: classified, allApps: [target])
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
            context: makeContext(
                classified: classified,
                allApps: [target],
                separatorRightEdgeX: 1000,
                separatorOriginX: 980,
                alwaysHiddenBoundaryX: 500,
                alwaysHiddenOriginX: 480
            )
        )
        #expect(zone == .visible)
    }

    @Test("Falls back to geometry default when the app is absent from the cache")
    func fallsBackToGeometryWhenUncached() {
        let target = makeApp("com.test.uncached")
        let empty = SearchClassifiedApps(visible: [], hidden: [], alwaysHidden: [])
        let zone = BrowsePanelZoneClassifier.zoneForAllTab(
            app: target,
            context: makeContext(classified: empty, allApps: [target])
        )
        // No cache hit, no geometry, no position → documented default.
        #expect(zone == .visible)
    }

    @Test("Bundle-level pin does not classify same-bundle precise siblings as Always Hidden")
    func bundlePinDoesNotPromoteSharedBundleSiblingInAllTab() {
        let pinned = RunningApp(
            id: "com.sanebar.fixture",
            name: "SBF-A",
            icon: nil,
            statusItemIndex: 0,
            xPosition: nil,
            width: 20
        )
        let sibling = RunningApp(
            id: "com.sanebar.fixture",
            name: "SBF-B",
            icon: nil,
            statusItemIndex: 1,
            xPosition: nil,
            width: 20
        )
        let empty = SearchClassifiedApps(visible: [], hidden: [], alwaysHidden: [])

        let zone = BrowsePanelZoneClassifier.zoneForAllTab(
            app: sibling,
            context: makeContext(
                classified: empty,
                pinnedIds: [pinned.bundleId],
                allApps: [pinned, sibling]
            )
        )

        #expect(zone == .visible)
    }
}
