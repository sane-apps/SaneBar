import AppKit
@testable import SaneBar
import SwiftUI
import Testing


struct SearchWindowActivationTests {
    @Test("Search activation rejects unverified clicks for revealed or browse-session flows")
    func searchActivationRequiresObservableReactionForBrowseFlows() {
        #expect(
            SearchServiceSupport.requiresObservableReactionVerification(
                origin: .browsePanel,
                didReveal: true,
                isBrowseSessionActive: false
            )
        )
        #expect(
            SearchServiceSupport.requiresObservableReactionVerification(
                origin: .browsePanel,
                didReveal: false,
                isBrowseSessionActive: true
            )
        )
        #expect(
            !SearchServiceSupport.requiresObservableReactionVerification(
                origin: .direct,
                didReveal: false,
                isBrowseSessionActive: false
            )
        )
        #expect(
            SearchServiceSupport.requiresObservableReactionVerification(
                origin: .browsePanel,
                didReveal: false,
                isBrowseSessionActive: false
            )
        )

        #expect(
            !SearchServiceSupport.acceptsClickResult(
                success: true,
                verification: "unavailable (no comparable AX reaction signals)",
                requireObservableReaction: true
            )
        )
        #expect(
            !SearchServiceSupport.acceptsClickResult(
                success: true,
                verification: "failed (no observable menu/panel reaction)",
                requireObservableReaction: true
            )
        )
        #expect(
            SearchServiceSupport.acceptsClickResult(
                success: true,
                verification: "verified (shownMenu)",
                requireObservableReaction: true
            )
        )
        #expect(
            SearchServiceSupport.acceptsClickResult(
                success: true,
                verification: "unavailable (no comparable AX reaction signals)",
                requireObservableReaction: false
            )
        )
        #expect(
            SearchServiceSupport.shouldForceFreshTargetResolution(
                origin: .browsePanel,
                didReveal: false,
                isBrowseSessionActive: true
            )
        )
        #expect(
            !SearchServiceSupport.shouldAllowImmediateFallbackCenter(
                origin: .browsePanel,
                didReveal: false,
                isBrowseSessionActive: true
            )
        )
        #expect(
            !SearchServiceSupport.shouldAllowImmediateFallbackCenter(
                origin: .browsePanel,
                didReveal: false,
                isBrowseSessionActive: false
            )
        )
        #expect(
            !SearchServiceSupport.shouldUseWorkspaceActivationFallback(
                origin: .browsePanel,
                isRightClick: true
            )
        )
        #expect(
            !SearchServiceSupport.shouldUseWorkspaceActivationFallback(
                origin: .browsePanel,
                isRightClick: false
            )
        )
        #expect(
            SearchServiceSupport.shouldUseWorkspaceActivationFallback(
                origin: .direct,
                isRightClick: true
            )
        )
        #expect(
            !SearchServiceSupport.shouldAllowSameBundleActivationFallback(
                original: RunningApp.menuExtraItem(
                    ownerBundleId: "com.apple.controlcenter",
                    name: "Wi-Fi",
                    identifier: "com.apple.controlcenter.wifi",
                    xPosition: 1500,
                    width: 24
                ),
                sameBundleCount: 2
            )
        )
        #expect(
            SearchServiceSupport.shouldAllowSameBundleActivationFallback(
                original: RunningApp.menuExtraItem(
                    ownerBundleId: "com.apple.controlcenter",
                    name: "Wi-Fi",
                    identifier: "com.apple.controlcenter.wifi",
                    xPosition: 1500,
                    width: 24
                ),
                sameBundleCount: 1
            )
        )
        #expect(
            SearchServiceSupport.shouldAllowSameBundleActivationFallback(
                original: RunningApp(
                    id: "com.apple.controlcenter",
                    name: "Control Center",
                    icon: nil,
                    policy: .accessory,
                    category: .system,
                    xPosition: 1500,
                    width: 24
                ),
                sameBundleCount: 2
            )
        )
        #expect(
            SearchServiceSupport.resolvedAllowImmediateFallbackCenter(
                baseAllowImmediateFallbackCenter: false,
                likelyNoExtrasMenuBar: true,
                fallbackCenterOnScreen: true,
                hasPreciseMenuBarIdentity: true
            )
        )
        #expect(
            !SearchServiceSupport.resolvedAllowImmediateFallbackCenter(
                baseAllowImmediateFallbackCenter: false,
                likelyNoExtrasMenuBar: true,
                fallbackCenterOnScreen: false,
                hasPreciseMenuBarIdentity: true
            )
        )
        #expect(
            SearchServiceSupport.resolvedAllowImmediateFallbackCenter(
                baseAllowImmediateFallbackCenter: false,
                likelyNoExtrasMenuBar: false,
                fallbackCenterOnScreen: true,
                hasPreciseMenuBarIdentity: false
            )
        )
        #expect(
            SearchServiceSupport.shouldUseAlwaysHiddenRevealForActivation(
                appUniqueId: "com.amazon.clouddrive.mac::statusItem:0",
                bundleId: "com.amazon.clouddrive.mac",
                pinnedIds: ["com.amazon.clouddrive.mac::statusItem:0"]
            )
        )
        #expect(
            SearchServiceSupport.shouldUseAlwaysHiddenRevealForActivation(
                appUniqueId: "com.amazon.clouddrive.mac::statusItem:0",
                bundleId: "com.amazon.clouddrive.mac",
                pinnedIds: ["com.amazon.clouddrive.mac"]
            )
        )
        #expect(
            !SearchServiceSupport.shouldUseAlwaysHiddenRevealForActivation(
                appUniqueId: "com.amazon.clouddrive.mac::statusItem:0",
                bundleId: "com.amazon.clouddrive.mac",
                pinnedIds: ["com.example.other"]
            )
        )
        #expect(
            SearchServiceSupport.shouldUseFullRevealForActivation(
                appUniqueId: "com.saneclick.SaneClick::statusItem:0",
                bundleId: "com.saneclick.SaneClick",
                xPosition: -3630,
                origin: .browsePanel,
                pinnedIds: []
            )
        )
        #expect(
            !SearchServiceSupport.shouldUseFullRevealForActivation(
                appUniqueId: "com.saneclick.SaneClick::statusItem:0",
                bundleId: "com.saneclick.SaneClick",
                xPosition: -3630,
                origin: .direct,
                pinnedIds: []
            )
        )
        #expect(
            !SearchServiceSupport.resolvedAllowImmediateFallbackCenter(
                baseAllowImmediateFallbackCenter: false,
                likelyNoExtrasMenuBar: false,
                fallbackCenterOnScreen: true,
                hasPreciseMenuBarIdentity: true
            )
        )
        #expect(
            SearchServiceSupport.shouldAllowFreshHardwareFallbackCenter(
                preferHardwareFirst: true,
                requireObservableReaction: true,
                hasPreciseMenuBarIdentity: true,
                fallbackCenterOnScreen: true
            )
        )
        #expect(
            !SearchServiceSupport.shouldAllowFreshHardwareFallbackCenter(
                preferHardwareFirst: true,
                requireObservableReaction: true,
                hasPreciseMenuBarIdentity: true,
                fallbackCenterOnScreen: false
            )
        )
        #expect(
            SearchServiceSupport.shouldPreferHardwareFirst(
                origin: .browsePanel,
                isRightClick: false,
                app: RunningApp(id: "offscreen.app", name: "Offscreen", icon: nil, xPosition: -4300, width: 24)
            )
        )
        #expect(
            SearchServiceSupport.shouldPreferHardwareFirst(
                origin: .browsePanel,
                isRightClick: false,
                app: RunningApp.menuExtraItem(
                    ownerBundleId: "com.apple.controlcenter",
                    name: "Wi-Fi",
                    identifier: "com.apple.menuextra.wifi",
                    xPosition: 631,
                    width: 24
                )
            )
        )
        #expect(
            SearchServiceSupport.shouldPreferHardwareFirst(
                origin: .browsePanel,
                isRightClick: true,
                app: RunningApp(id: "visible.app", name: "Visible", icon: nil, xPosition: 631, width: 24)
            )
        )
        #expect(
            SearchServiceSupport.shouldUsePinnedAlwaysHiddenFallback(
                hidingState: .hidden,
                isBrowseSessionActive: false
            )
        )
        #expect(
            SearchServiceSupport.shouldUsePinnedAlwaysHiddenFallback(
                hidingState: .expanded,
                isBrowseSessionActive: true
            )
        )
    }

    @Test("Spatial fallback center is suppressed when the cached X is off the hosting menu bar screen")
    func spatialFallbackCenterRejectsOffscreenX() {
        let center = SearchServiceSupport.spatialFallbackCenter(
            xPosition: -1721,
            width: 24,
            menuBarScreenFrame: CGRect(x: 3440, y: 0, width: 1720, height: 1440)
        )

        #expect(center == nil)
    }

    @Test("Spatial fallback center is kept when the cached X is still on the hosting menu bar screen")
    func spatialFallbackCenterKeepsOnScreenX() {
        let center = SearchServiceSupport.spatialFallbackCenter(
            xPosition: 4748,
            width: 24,
            menuBarScreenFrame: CGRect(x: 3440, y: 0, width: 1720, height: 1440)
        )

        #expect(center == CGPoint(x: 4760, y: 15))
    }

    @Test("Browse and reveal flows get a larger click timeout budget for observable reaction verification")
    func clickAttemptTimeoutBudgetExpandsForObservableReaction() {
        #expect(
            SearchServiceSupport.clickAttemptTimeoutMs(
                baseMs: 900,
                requireObservableReaction: false
            ) == 900
        )
        #expect(
            SearchServiceSupport.clickAttemptTimeoutMs(
                baseMs: 900,
                requireObservableReaction: true
            ) == 1800
        )
    }

    @Test("Preferred spatial fallback keeps the last on-screen center when refreshed coordinates drift off-screen")
    func preferredSpatialFallbackCenterUsesOriginalOnScreenXWhenRefreshRegresses() {
        let center = SearchServiceSupport.preferredSpatialFallbackCenter(
            primaryXPosition: -3628,
            primaryWidth: 33,
            fallbackXPosition: 1390,
            fallbackWidth: 33,
            menuBarScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080)
        )

        #expect(center == CGPoint(x: 1406.5, y: 15))
    }

    @Test("Second menu bar diagnostics keep counts and relayout state")
    func secondMenuBarDiagnosticsSummary() {
        let diagnostics = SecondMenuBarDiagnostics(
            showRequestedAt: "2026-03-05T12:34:56.789Z",
            currentMode: "Optional(SaneBar.SearchWindowMode.secondMenuBar)",
            windowVisible: true,
            windowFrame: "x=10.0 y=20.0 w=300.0 h=120.0",
            refreshForced: true,
            visibleCount: 4,
            hiddenCount: 12,
            alwaysHiddenCount: 2,
            relayoutPassCount: 2,
            lastRelayoutAt: "2026-03-05T12:34:57.100Z",
            lastRelayoutReason: "classified-refresh"
        )

        let summary = diagnostics.formattedSummary()

        #expect(summary.contains("windowFrame: x=10.0 y=20.0 w=300.0 h=120.0"))
        #expect(summary.contains("hiddenCount: 12"))
        #expect(summary.contains("relayoutPassCount: 2"))
    }

    @Test("Browse diagnostics report live mode and visibility instead of cached state")
    @MainActor
    func browseDiagnosticsSnapshotReflectsLiveWindowState() {
        let controller = SearchWindowController.shared
        controller.close()

        controller.show(mode: .findIcon)
        let openSummary = controller.diagnosticsSnapshot()
        #expect(openSummary.contains("currentMode: findIcon"))
        #expect(openSummary.contains("windowVisible: true"))

        controller.close()
        let closedSummary = controller.diagnosticsSnapshot()
        #expect(closedSummary.contains("currentMode: findIcon"))
        #expect(closedSummary.contains("windowVisible: false"))

        controller.show(mode: .secondMenuBar)
        let secondMenuSummary = controller.diagnosticsSnapshot()
        #expect(secondMenuSummary.contains("currentMode: secondMenuBar"))
        #expect(secondMenuSummary.contains("windowVisible: true"))

        controller.close()
    }

}
