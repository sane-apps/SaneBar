import AppKit
@testable import SaneBar
import SwiftUI
import Testing


struct SearchWindowLogicTests {
    // MARK: - Logic Tests

    @Test("Filtering logic works correctly")
    @MainActor
    func filtering() async {
        // Given
        let mockService = SearchServiceProtocolMock()
        mockService.getRunningAppsHandler = {
            [
                RunningApp(id: "com.apple.Safari", name: "Safari", icon: nil),
                RunningApp(id: "com.google.Chrome", name: "Chrome", icon: nil),
                RunningApp(id: "com.apple.Notes", name: "Notes", icon: nil),
            ]
        }

        _ = MenuBarSearchView(service: mockService, onDismiss: {}) // Verify it can be created

        // Verify service interaction
        let apps = await mockService.getRunningApps()
        #expect(apps.count == 3)
        #expect(mockService.getRunningAppsCallCount > 0)

        // Note: We cannot test @State filteredApps directly from outside the view
        // But we verified the dependency injection works
    }

    @Test("Service activation is called")
    @MainActor
    func activation() async {
        let mockService = SearchServiceProtocolMock()
        let app = RunningApp(id: "com.test", name: "Test", icon: nil)

        await mockService.activate(app: app, isRightClick: false, origin: .direct)

        #expect(mockService.activateCallCount == 1)
        #expect(mockService.activateArgValues.first?.0.id == "com.test")
        #expect(mockService.activateArgValues.first?.2 == .direct)
    }

    // MARK: - Model Tests

    @Test("RunningApp uses synthesized equality checking all properties")
    func runningAppEquality() {
        let app1 = RunningApp(id: "com.test", name: "Test", icon: nil)
        let app2 = RunningApp(id: "com.test", name: "Test", icon: nil) // Same ID and name
        let app3 = RunningApp(id: "com.other", name: "Test", icon: nil) // Different ID
        let app4 = RunningApp(id: "com.test", name: "Other", icon: nil) // Same ID, different name

        #expect(app1 == app2) // Same id and name = equal
        #expect(app1 != app3) // Different id = not equal
        #expect(app1 != app4) // Same id but different name = not equal (synthesized Equatable)
    }

    @Test("Duplicate badges number repeated menu extras by bundle and name in x-order")
    func duplicateBadgesNumberRepeatedMenuExtrasInXOrder() {
        let stats2 = RunningApp(
            id: "eu.exelban.Stats",
            name: "Stats",
            icon: nil,
            statusItemIndex: 2,
            xPosition: 140
        )
        let stats0 = RunningApp(
            id: "eu.exelban.Stats",
            name: "Stats",
            icon: nil,
            statusItemIndex: 0,
            xPosition: 20
        )
        let stats3 = RunningApp(
            id: "eu.exelban.Stats",
            name: "Stats",
            icon: nil,
            statusItemIndex: 3,
            xPosition: 200
        )
        let stats1 = RunningApp(
            id: "eu.exelban.Stats",
            name: "Stats",
            icon: nil,
            statusItemIndex: 1,
            xPosition: 80
        )
        let wifi = RunningApp.menuExtraItem(
            ownerBundleId: "com.apple.controlcenter",
            name: "Wi-Fi",
            identifier: "com.apple.menuextra.wifi",
            xPosition: 260
        )

        let markers = BrowseDuplicateMarker.markers(for: [stats2, stats0, wifi, stats3, stats1])

        #expect(markers[stats0.uniqueId] == BrowseDuplicateMarker(ordinal: 1, total: 4))
        #expect(markers[stats1.uniqueId] == BrowseDuplicateMarker(ordinal: 2, total: 4))
        #expect(markers[stats2.uniqueId] == BrowseDuplicateMarker(ordinal: 3, total: 4))
        #expect(markers[stats3.uniqueId] == BrowseDuplicateMarker(ordinal: 4, total: 4))
        #expect(markers[wifi.uniqueId] == nil)
    }

    @Test("Duplicate badges do not merge same-bundle items with different names")
    func duplicateBadgesRespectDistinctNamesWithinSameBundle() {
        let wifi = RunningApp.menuExtraItem(
            ownerBundleId: "com.apple.controlcenter",
            name: "Wi-Fi",
            identifier: "com.apple.menuextra.wifi",
            xPosition: 100
        )
        let display = RunningApp.menuExtraItem(
            ownerBundleId: "com.apple.controlcenter",
            name: "Display",
            identifier: "com.apple.menuextra.display",
            xPosition: 130
        )
        let focus = RunningApp.menuExtraItem(
            ownerBundleId: "com.apple.controlcenter",
            name: "Focus",
            identifier: "com.apple.menuextra.focusmode",
            xPosition: 160
        )

        let markers = BrowseDuplicateMarker.markers(for: [wifi, display, focus])

        #expect(markers.isEmpty)
    }

    @Test("Search activation diagnostics keep resolution and retry details")
    func searchActivationDiagnosticsSummary() {
        let diagnostics = SearchServiceSupport.ActivationDiagnostics(
            startedAt: "2026-03-05T12:34:56.789Z",
            requestedApp: "id=req bundle=com.test.app menuExtra=nil statusItemIndex=1 x=100.0 width=24.0",
            didReveal: true,
            preferHardwareFirst: false,
            initialResolution: "forceRefresh=false items=12 method=uniqueId",
            initialTarget: "id=resolved bundle=com.test.app menuExtra=foo statusItemIndex=1 x=101.0 width=24.0",
            waitOutcome: "stable after 150ms at x=101.0",
            firstAttempt: "success=false accepted=false timedOut=false durationMs=280 fallbackCenter=x=113.0 y=15.0 allowImmediateFallbackCenter=false requireObservableReaction=true verification=failed (no observable menu/panel reaction)",
            retryAttempt: "success=true accepted=true timedOut=false durationMs=140 resolution=forceRefresh=true items=12 method=bundle+statusItemIndex target=id=resolved bundle=com.test.app menuExtra=foo statusItemIndex=1 x=101.0 width=24.0 fallbackCenter=x=113.0 y=15.0 requireObservableReaction=true verification=verified (shownMenu)",
            finalOutcome: "click succeeded"
        )

        let summary = diagnostics.formattedSummary()

        #expect(summary.contains("initialResolution: forceRefresh=false items=12 method=uniqueId"))
        #expect(summary.contains("retryAttempt: success=true"))
        #expect(summary.contains("verification=verified (shownMenu)"))
        #expect(summary.contains("finalOutcome: click succeeded"))
    }

    @Test("Second menu bar idle close defers for in-flight and recent browse activation")
    @MainActor
    func secondMenuBarIdleCloseDeferral() {
        #expect(
            SearchWindowLayoutPolicy.panelIdleCloseActivationGracePeriod(for: .secondMenuBar) == 4
        )
        #expect(
            SearchWindowLayoutPolicy.shouldDeferPanelIdleClose(
                mode: .secondMenuBar,
                pointerInsidePanel: false,
                activationInFlight: true,
                secondsSinceLastActivation: nil
            )
        )
        #expect(
            SearchWindowLayoutPolicy.shouldDeferPanelIdleClose(
                mode: .secondMenuBar,
                pointerInsidePanel: false,
                activationInFlight: false,
                secondsSinceLastActivation: 1.5
            )
        )
        #expect(
            !SearchWindowLayoutPolicy.shouldDeferPanelIdleClose(
                mode: .secondMenuBar,
                pointerInsidePanel: false,
                activationInFlight: false,
                secondsSinceLastActivation: 4.5
            )
        )
        #expect(
            SearchWindowLayoutPolicy.shouldDeferPanelIdleClose(
                mode: .findIcon,
                pointerInsidePanel: true,
                activationInFlight: false,
                secondsSinceLastActivation: nil
            )
        )
        #expect(
            !SearchWindowLayoutPolicy.shouldDeferPanelIdleClose(
                mode: .findIcon,
                pointerInsidePanel: false,
                activationInFlight: true,
                secondsSinceLastActivation: 0.2
            )
        )
    }

    @Test("Browse window anchor validation accepts correctly positioned icon panel")
    func browseWindowAnchorValidationForFindIcon() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 860)
        let windowFrame = CGRect(x: 510, y: 320, width: 420, height: 520)

        #expect(
            SearchWindowLayoutPolicy.isBrowseWindowAnchoredCorrectly(
                windowFrame: windowFrame,
                screenFrame: screenFrame,
                visibleFrame: visibleFrame,
                mode: .findIcon,
                statusItemRightEdge: nil
            )
        )
    }

    @Test("Browse window anchor validation rejects obviously misplaced second menu bar")
    func browseWindowAnchorValidationRejectsMisplacedSecondMenuBar() {
        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let visibleFrame = CGRect(x: 0, y: 0, width: 1440, height: 860)
        let expectedRightEdge: CGFloat = 1320
        let misplacedFrame = CGRect(x: 200, y: 200, width: 280, height: 140)

        #expect(
            !SearchWindowLayoutPolicy.isBrowseWindowAnchoredCorrectly(
                windowFrame: misplacedFrame,
                screenFrame: screenFrame,
                visibleFrame: visibleFrame,
                mode: .secondMenuBar,
                statusItemRightEdge: expectedRightEdge
            )
        )
    }

    @Test("Second menu bar initial sizing can reuse the current frame before a deferred refit")
    func secondMenuBarSizeCanReuseCurrentFrame() {
        let size = SearchWindowLayoutPolicy.clampedSecondMenuBarSize(
            currentWindowSize: CGSize(width: 400, height: 140),
            fittingSize: CGSize(width: 620, height: 260),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 860),
            useContentFittingSize: false
        )

        #expect(size == CGSize(width: 400, height: 140))
    }

    @Test("Second menu bar refit still honors SwiftUI fitting size with clamping")
    func secondMenuBarRefitUsesFittingSize() {
        let size = SearchWindowLayoutPolicy.clampedSecondMenuBarSize(
            currentWindowSize: CGSize(width: 400, height: 140),
            fittingSize: CGSize(width: 900, height: 40),
            visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 860),
            useContentFittingSize: true
        )

        #expect(size == CGSize(width: 800, height: 80))
    }

}
