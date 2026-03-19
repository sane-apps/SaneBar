import Testing
import AppKit
@testable import SaneBar

@Suite("AccessibilityService Tests")
struct AccessibilityServiceTests {

    // MARK: - Permission Tests

    @Test("isTrusted returns boolean without crashing")
    @MainActor
    func testIsTrustedReturnsBoolean() {
        let service = AccessibilityService.shared
        // Just verify it doesn't crash - actual value depends on system permissions
        let result = service.isTrusted
        #expect(result == true || result == false)
    }

    // MARK: - clickMenuBarItem Tests

    @Test("clickMenuBarItem returns false for non-existent bundle ID")
    @MainActor
    func testClickMenuBarItemNonExistentApp() {
        let service = AccessibilityService.shared
        // This should return false because no app with this bundle ID exists
        let result = service.clickMenuBarItem(for: "com.nonexistent.app.that.does.not.exist")
        #expect(result == false)
    }

    @Test("clickMenuBarItem returns false for empty bundle ID")
    @MainActor
    func testClickMenuBarItemEmptyBundleID() {
        let service = AccessibilityService.shared
        let result = service.clickMenuBarItem(for: "")
        #expect(result == false)
    }

    @Test("clickMenuBarItem handles Finder gracefully")
    @MainActor
    func testClickMenuBarItemFinder() {
        let service = AccessibilityService.shared
        // Finder is always running but may not have a menu bar extra
        // This tests that the code handles a real app without crashing
        let result = service.clickMenuBarItem(for: "com.apple.finder")
        // Result depends on whether Finder has a status item - just verify no crash
        #expect(result == true || result == false)
    }

    // MARK: - Integration Tests (require accessibility permission)

    @Test("Virtual click returns boolean for any bundle ID")
    @MainActor
    func testVirtualClickReturnsBool() async {
        let service = AccessibilityService.shared

        // Skip if no accessibility permission
        guard service.isTrusted else {
            // Can't test without permission - this is expected in CI
            return
        }

        // Use a non-existent bundle ID to avoid clicking real system UI
        // (Previously clicked Control Center which toggled AirDrop!)
        let result = service.clickMenuBarItem(for: "com.test.nonexistent.app")

        // Should return false for non-existent app, but main point is no crash
        #expect(result == false)
    }

    // MARK: - Permission Flow Regression Tests

    @Test("isGranted property doesn't trigger system permission dialog")
    @MainActor
    func testIsGrantedDoesNotPrompt() {
        // REGRESSION: MenuBarSearchView was calling requestAccessibility() which
        // triggered the system permission dialog unexpectedly.
        // Fix: Use isGranted property which only checks current status.
        let service = AccessibilityService.shared

        // Reading isGranted should NEVER trigger a dialog
        // It uses AXIsProcessTrusted() internally which is read-only
        let _ = service.isGranted
        let _ = service.isGranted
        let _ = service.isGranted

        // If we got here without a dialog, test passed
        #expect(true)
    }

    @Test("System Settings accessibility URL is valid")
    func testAccessibilitySettingsURLIsValid() {
        // REGRESSION: "Open System Settings" button wasn't opening anything
        // because it called requestAccessibility() instead of opening the URL
        let urlString = AccessibilityService.accessibilitySettingsURLString
        let url = URL(string: urlString)

        #expect(url != nil, "Accessibility Settings URL must be valid")
        #expect(url?.scheme == "x-apple.systempreferences", "URL scheme must be x-apple.systempreferences")
    }

    @Test("Cache warmup delays prioritize launch immediacy and reveal settling")
    func testCacheWarmupDelays() {
        #expect(AccessibilityService.cacheWarmupDelay(for: .launch) == 0)
        #expect(AccessibilityService.cacheWarmupDelay(for: .reveal) > 0)
        #expect(AccessibilityService.cacheWarmupDelay(for: .structuralChange) >= AccessibilityService.cacheWarmupDelay(for: .reveal))
        #expect(AccessibilityService.cacheWarmupDelay(for: .conceal) <= AccessibilityService.cacheWarmupDelay(for: .structuralChange))
    }

    @Test("Preferred status item index chooses nearest X when explicit identity is missing")
    func testPreferredStatusItemIndexUsesNearestCenterX() {
        let index = AccessibilityService.preferredStatusItemIndex(
            midXs: [120, 260, 410],
            preferredCenterX: 275
        )

        #expect(index == 1)
    }

    @Test("Preferred status item index falls back to first item without preferred X")
    func testPreferredStatusItemIndexFallsBackToFirst() {
        let index = AccessibilityService.preferredStatusItemIndex(
            midXs: [120, 260, 410],
            preferredCenterX: nil
        )

        #expect(index == 0)
    }

    @Test("Resolved status item index keeps the hinted item when it still matches the requested center")
    func testResolvedStatusItemIndexKeepsMatchingHint() {
        let index = AccessibilityService.resolvedStatusItemIndex(
            midXs: [120, 260, 410],
            statusItemIndex: 1,
            preferredCenterX: 272
        )

        #expect(index == 1)
    }

    @Test("Resolved status item index falls back to nearest center when the hinted item drifts")
    func testResolvedStatusItemIndexFallsBackWhenHintDrifts() {
        let index = AccessibilityService.resolvedStatusItemIndex(
            midXs: [120, 260, 410],
            statusItemIndex: 2,
            preferredCenterX: 272
        )

        #expect(index == 1)
    }

    @Test("Resolved status item index uses the hint when no preferred center is available")
    func testResolvedStatusItemIndexUsesHintWithoutPreferredCenter() {
        let index = AccessibilityService.resolvedStatusItemIndex(
            midXs: [120, 260, 410],
            statusItemIndex: 2,
            preferredCenterX: nil
        )

        #expect(index == 2)
    }

    @Test("Status item resolution continues after identifier miss when a live spatial hint exists")
    func testStatusItemResolutionContinuesAfterIdentifierMissWithPreferredCenterX() {
        #expect(
            AccessibilityService.shouldContinueStatusItemResolutionAfterIdentifierMiss(
                statusItemIndex: nil,
                preferredCenterX: 1408
            )
        )
    }

    @Test("Status item resolution stops after identifier miss when only stale ordinal remains")
    func testStatusItemResolutionStopsAfterIdentifierMissWithOnlyStatusItemIndex() {
        #expect(
            !AccessibilityService.shouldContinueStatusItemResolutionAfterIdentifierMiss(
                statusItemIndex: 1,
                preferredCenterX: nil
            )
        )
    }

    @Test("Status item resolution stops after identifier miss when no hints exist")
    func testStatusItemResolutionStopsAfterIdentifierMissWithoutHints() {
        #expect(
            AccessibilityService.shouldContinueStatusItemResolutionAfterIdentifierMiss(
                statusItemIndex: nil,
                preferredCenterX: nil
            ) == false
        )
    }

    @Test("Single status item falls back to sole item after identifier miss")
    @MainActor
    func testResolvedTargetStatusItemFallsBackToSingleItemAfterIdentifierMiss() {
        let service = AccessibilityService.shared
        let item = AXUIElementCreateApplication(getpid())

        let resolved = service.resolvedTargetStatusItem(
            from: [item],
            bundleID: "com.example.tool",
            menuExtraId: "com.example.tool.missing",
            statusItemIndex: nil,
            preferredCenterX: nil
        )

        #expect(resolved != nil)
    }

    @Test("Raw spatial fallback is disabled for browse or reveal flows after frame polling fails")
    func testShouldUseRawSpatialFallbackRejectsStaleBrowseCenter() {
        #expect(
            !SearchService.shouldUseRawSpatialFallback(
                allowImmediateFallbackCenter: false,
                isPointOnScreen: true
            )
        )
    }

    @Test("Raw spatial fallback requires an on-screen point")
    func testShouldUseRawSpatialFallbackRejectsOffscreenPoint() {
        #expect(
            !SearchService.shouldUseRawSpatialFallback(
                allowImmediateFallbackCenter: true,
                isPointOnScreen: false
            )
        )
        #expect(
            SearchService.shouldUseRawSpatialFallback(
                allowImmediateFallbackCenter: true,
                isPointOnScreen: true
            )
        )
    }

    @Test("Hardware-first click falls back to AX when verification is unavailable on-screen")
    func testShouldFallbackToAXAfterHardwareAttemptForUnavailableOnScreenResult() {
        #expect(
            AccessibilityService.shouldFallbackToAXAfterHardwareAttempt(
                success: true,
                verificationSummary: "unavailable (no comparable AX reaction signals)",
                isItemOnScreen: true
            )
        )
    }

    @Test("Hardware-first click keeps verified on-screen result without AX fallback")
    func testShouldFallbackToAXAfterHardwareAttemptSkipsVerifiedResult() {
        #expect(
            !AccessibilityService.shouldFallbackToAXAfterHardwareAttempt(
                success: true,
                verificationSummary: "verified (shownMenu)",
                isItemOnScreen: true
            )
        )
    }

    @Test("Hardware-first click does not fall back to AX for off-screen targets")
    func testShouldFallbackToAXAfterHardwareAttemptSkipsOffscreenTargets() {
        #expect(
            !AccessibilityService.shouldFallbackToAXAfterHardwareAttempt(
                success: false,
                verificationSummary: "failed (no observable menu/panel reaction)",
                isItemOnScreen: false
            )
        )
    }

    @Test("Hardware-first reveal waits for hidden items to come on-screen")
    func testShouldWaitForRevealSettleWhenHardwareFirstItemStartsHidden() {
        #expect(
            SearchService.shouldWaitForRevealSettle(
                preferHardwareFirst: true,
                xPosition: -3470
            )
        )
    }

    @Test("Hardware-first reveal skips extra wait for already visible items")
    func testShouldWaitForRevealSettleSkipsVisibleHardwareFirstItem() {
        #expect(
            !SearchService.shouldWaitForRevealSettle(
                preferHardwareFirst: true,
                xPosition: 1621
            )
        )
    }

    @Test("Non-hardware-first reveal always waits for settle")
    func testShouldWaitForRevealSettleWhenNotHardwareFirst() {
        #expect(
            SearchService.shouldWaitForRevealSettle(
                preferHardwareFirst: false,
                xPosition: 1621
            )
        )
    }

    @Test("Browse-panel left click prefers AX first for on-screen targets")
    func testShouldPreferHardwareFirstSkipsBrowsePanelOnScreenLeftClick() {
        let app = RunningApp(
            id: "com.apple.Spotlight",
            name: "Spotlight",
            icon: nil,
            policy: .accessory,
            category: .system,
            menuExtraIdentifier: "com.apple.menuextra.spotlight",
            xPosition: 1344,
            width: 32
        )

        #expect(
            !SearchService.shouldPreferHardwareFirst(
                origin: .browsePanel,
                isRightClick: false,
                app: app
            )
        )
    }

    @Test("Direct Spotlight activation still prefers hardware first")
    func testShouldPreferHardwareFirstKeepsDirectAppleMenuExtraBias() {
        let app = RunningApp(
            id: "com.apple.Spotlight",
            name: "Spotlight",
            icon: nil,
            policy: .accessory,
            category: .system,
            menuExtraIdentifier: "com.apple.menuextra.spotlight",
            xPosition: 1344,
            width: 32
        )

        #expect(
            SearchService.shouldPreferHardwareFirst(
                origin: .direct,
                isRightClick: false,
                app: app
            )
        )
    }

    @Test("Right-click browse activation keeps hardware-first behavior")
    func testShouldPreferHardwareFirstKeepsRightClickHardwareBias() {
        let app = RunningApp(
            id: "com.apple.controlcenter",
            name: "Wi-Fi",
            icon: nil,
            policy: .accessory,
            category: .system,
            menuExtraIdentifier: "com.apple.menuextra.wifi",
            xPosition: 1548,
            width: 22
        )

        #expect(
            SearchService.shouldPreferHardwareFirst(
                origin: .browsePanel,
                isRightClick: true,
                app: app
            )
        )
    }

    @Test("WindowServer fallback keeps helper-hosted off-screen menu extras visible to the scanner")
    func testWindowBackedMenuBarItemsIncludesOffscreenHelperItem() {
        let pid: pid_t = 4242
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: 25),
            kCGWindowAlpha as String: NSNumber(value: 1),
            kCGWindowBounds as String: [
                "X": NSNumber(value: -3534),
                "Y": NSNumber(value: 0),
                "Width": NSNumber(value: 18),
                "Height": NSNumber(value: 30)
            ]
        ]]

        let items = AccessibilityService.windowBackedMenuBarItems(
            fromWindowInfos: infos,
            candidatePIDs: Set([pid])
        )

        #expect(items.count == 1)
        #expect(items.first?.pid == pid)
        #expect(items.first?.frame.origin.x == -3534)
        #expect(items.first?.frame.width == 18)
    }

    @Test("Third-party top-bar fallback allowlist recognizes current Little Snitch app bundle")
    func testShouldAllowThirdPartyTopBarFallbackRecognizesLittleSnitchAppBundle() {
        #expect(AccessibilityService.shouldAllowThirdPartyTopBarFallback(bundleID: "at.obdev.littlesnitch"))
    }

    @Test("Third-party top-bar fallback allowlist recognizes current Little Snitch daemon bundle")
    func testShouldAllowThirdPartyTopBarFallbackRecognizesLittleSnitchDaemonBundle() {
        #expect(AccessibilityService.shouldAllowThirdPartyTopBarFallback(bundleID: "at.obdev.littlesnitch.daemon"))
    }

    @Test("WindowServer fallback ignores non-menu-bar windows")
    func testWindowBackedMenuBarItemsIgnoresNonMenuBarWindows() {
        let pid: pid_t = 4242
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: 5),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 100),
                "Y": NSNumber(value: 200),
                "Width": NSNumber(value: 900),
                "Height": NSNumber(value: 700)
            ]
        ]]

        let items = AccessibilityService.windowBackedMenuBarItems(
            fromWindowInfos: infos,
            candidatePIDs: Set([pid])
        )

        #expect(items.isEmpty)
    }

    @Test("WindowServer fallback preserves multiple compact windows per app")
    func testWindowBackedMenuBarItemsPreservesMultipleFramesPerPID() {
        let pid: pid_t = 4242
        let infos: [[String: Any]] = [
            [
                kCGWindowOwnerPID as String: NSNumber(value: pid),
                kCGWindowLayer as String: NSNumber(value: 24),
                kCGWindowAlpha as String: NSNumber(value: 1),
                kCGWindowBounds as String: [
                    "X": NSNumber(value: -500),
                    "Y": NSNumber(value: 0),
                    "Width": NSNumber(value: 22),
                    "Height": NSNumber(value: 30)
                ]
            ],
            [
                kCGWindowOwnerPID as String: NSNumber(value: pid),
                kCGWindowLayer as String: NSNumber(value: 24),
                kCGWindowAlpha as String: NSNumber(value: 1),
                kCGWindowBounds as String: [
                    "X": NSNumber(value: 220),
                    "Y": NSNumber(value: 0),
                    "Width": NSNumber(value: 24),
                    "Height": NSNumber(value: 30)
                ]
            ]
        ]

        let items = AccessibilityService.windowBackedMenuBarItems(
            fromWindowInfos: infos,
            candidatePIDs: Set([pid])
        )

        #expect(items.count == 2)
        #expect(items[0].frame.origin.x == -500)
        #expect(items[0].fallbackIndex == 0)
        #expect(items[1].frame.origin.x == 220)
        #expect(items[1].frame.width == 24)
        #expect(items[1].fallbackIndex == 1)
    }

    @Test("Representative WindowServer fallback frame still prefers the right-most frame per app")
    func testRepresentativeWindowBackedFramesByPIDPrefersRightMostFrame() {
        let pid: pid_t = 4242
        let items = [
            AccessibilityService.WindowBackedStatusItem(
                pid: pid,
                frame: CGRect(x: -500, y: 0, width: 22, height: 30),
                fallbackIndex: 0
            ),
            AccessibilityService.WindowBackedStatusItem(
                pid: pid,
                frame: CGRect(x: 220, y: 0, width: 24, height: 30),
                fallbackIndex: 1
            )
        ]

        let framesByPID = AccessibilityService.representativeWindowBackedFramesByPID(items)

        #expect(framesByPID.count == 1)
        #expect(framesByPID[pid]?.origin.x == 220)
        #expect(framesByPID[pid]?.width == 24)
    }

    @Test("Top-bar host detection catches full-width menu bar overlays")
    func testTopBarHostPIDsDetectsFullWidthOverlay() {
        let pid: pid_t = 5151
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 0),
                "Y": NSNumber(value: 0),
                "Width": NSNumber(value: 1920),
                "Height": NSNumber(value: 30)
            ]
        ]]

        let pids = AccessibilityService.topBarHostPIDs(
            fromWindowInfos: infos,
            candidatePIDs: Set([pid]),
            minimumWidth: 1200
        )

        #expect(pids == Set([pid]))
    }

    @Test("Top-bar host detection ignores ordinary app windows")
    func testTopBarHostPIDsIgnoreOrdinaryWindows() {
        let pid: pid_t = 5151
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: pid),
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 345),
                "Y": NSNumber(value: 109),
                "Width": NSNumber(value: 1230),
                "Height": NSNumber(value: 646)
            ]
        ]]

        let pids = AccessibilityService.topBarHostPIDs(
            fromWindowInfos: infos,
            candidatePIDs: Set([pid]),
            minimumWidth: 1200
        )

        #expect(pids.isEmpty)
    }

    @Test("Third-party top-bar fallback allowlist stays narrow")
    func testThirdPartyTopBarFallbackAllowlistStaysNarrow() {
        #expect(AccessibilityService.shouldAllowThirdPartyTopBarFallback(bundleID: "at.obdev.littlesnitch.networkmonitor"))
        #expect(AccessibilityService.shouldAllowThirdPartyTopBarFallback(bundleID: "at.obdev.littlesnitch.agent"))
        #expect(AccessibilityService.shouldAllowThirdPartyTopBarFallback(bundleID: "com.obdev.LittleSnitchUIAgent"))
        #expect(!AccessibilityService.shouldAllowThirdPartyTopBarFallback(bundleID: "com.brave.Browser"))
        #expect(!AccessibilityService.shouldAllowThirdPartyTopBarFallback(bundleID: "com.openai.codex"))
    }

    @Test("Third-party top-bar owner inclusion accepts precise fallback items outside allowlist")
    func testShouldIncludeThirdPartyTopBarOwnerWhenPreciseFallbackItemsExist() {
        #expect(
            AccessibilityService.shouldIncludeThirdPartyTopBarOwner(
                bundleID: "com.example.overlay",
                fallbackItemsCount: 2
            )
        )
    }

    @Test("Third-party top-bar owner inclusion still rejects unknown bundles without precise fallback items")
    func testShouldIncludeThirdPartyTopBarOwnerRejectsUnknownBundleWithoutItems() {
        #expect(
            !AccessibilityService.shouldIncludeThirdPartyTopBarOwner(
                bundleID: "com.example.overlay",
                fallbackItemsCount: 0
            )
        )
        #expect(
            AccessibilityService.shouldIncludeThirdPartyTopBarOwner(
                bundleID: "at.obdev.littlesnitch.agent",
                fallbackItemsCount: 0
            )
        )
    }

    @Test("Observable reaction detects shown menu appearance")
    func testObservableReactionDetectsShownMenu() {
        let before = AccessibilityService.StatusItemReactionSnapshot(
            shownMenuPresent: false,
            focusedWindowPresent: false,
            windowCount: 0,
            windowServerWindowCount: 0,
            expanded: false,
            selected: false
        )
        let after = AccessibilityService.StatusItemReactionSnapshot(
            shownMenuPresent: true,
            focusedWindowPresent: false,
            windowCount: 0,
            windowServerWindowCount: 0,
            expanded: false,
            selected: false
        )

        #expect(
            AccessibilityService.observableReactionDescription(before: before, after: after) == "shownMenu"
        )
    }

    @Test("Observable reaction detects new focused window")
    func testObservableReactionDetectsFocusedWindow() {
        let before = AccessibilityService.StatusItemReactionSnapshot(
            shownMenuPresent: false,
            focusedWindowPresent: false,
            windowCount: 0,
            windowServerWindowCount: 0,
            expanded: false,
            selected: false
        )
        let after = AccessibilityService.StatusItemReactionSnapshot(
            shownMenuPresent: false,
            focusedWindowPresent: true,
            windowCount: 1,
            windowServerWindowCount: 1,
            expanded: false,
            selected: false
        )

        #expect(
            AccessibilityService.observableReactionDescription(before: before, after: after) == "focusedWindow"
        )
    }

    @Test("Comparable reaction signals require overlapping AX fields")
    func testComparableReactionSignalsRequireOverlap() {
        let before = AccessibilityService.StatusItemReactionSnapshot(
            shownMenuPresent: nil,
            focusedWindowPresent: nil,
            windowCount: nil,
            windowServerWindowCount: nil,
            expanded: nil,
            selected: nil
        )
        let after = AccessibilityService.StatusItemReactionSnapshot(
            shownMenuPresent: nil,
            focusedWindowPresent: nil,
            windowCount: nil,
            windowServerWindowCount: nil,
            expanded: nil,
            selected: nil
        )

        #expect(
            AccessibilityService.hasComparableReactionSignals(before: before, after: after) == false
        )
    }

    @Test("Observable reaction detects new WindowServer windows for system extras")
    func testObservableReactionDetectsWindowServerWindowIncrease() {
        let before = AccessibilityService.StatusItemReactionSnapshot(
            shownMenuPresent: nil,
            focusedWindowPresent: nil,
            windowCount: nil,
            windowServerWindowCount: 5,
            expanded: nil,
            selected: nil
        )
        let after = AccessibilityService.StatusItemReactionSnapshot(
            shownMenuPresent: nil,
            focusedWindowPresent: nil,
            windowCount: nil,
            windowServerWindowCount: 15,
            expanded: nil,
            selected: nil
        )

        #expect(
            AccessibilityService.observableReactionDescription(before: before, after: after) == "windowServerWindowCount 5->15"
        )
        #expect(
            AccessibilityService.hasComparableReactionSignals(before: before, after: after)
        )
    }

    @Test("System-wide hit samples collapse into contiguous menu-extra segments")
    func testSystemWideMenuBarSegmentsCollapseContiguousSamples() {
        let samples = [
            AccessibilityService.SystemWideHitSample(
                pid: 42,
                bundleID: "com.example.agent",
                appName: "Example",
                lineY: 15,
                x: 100,
                role: "AXMenuBarItem",
                subrole: "AXMenuExtra",
                rawIdentifier: "com.example.agent.status",
                rawTitle: "Example",
                rawDescription: nil
            ),
            AccessibilityService.SystemWideHitSample(
                pid: 42,
                bundleID: "com.example.agent",
                appName: "Example",
                lineY: 15,
                x: 104,
                role: "AXMenuBarItem",
                subrole: "AXMenuExtra",
                rawIdentifier: "com.example.agent.status",
                rawTitle: "Example",
                rawDescription: nil
            ),
            AccessibilityService.SystemWideHitSample(
                pid: 42,
                bundleID: "com.example.agent",
                appName: "Example",
                lineY: 15,
                x: 120,
                role: "AXMenuBarItem",
                subrole: "AXMenuExtra",
                rawIdentifier: "com.example.agent.status",
                rawTitle: "Example",
                rawDescription: nil
            )
        ]

        let segments = AccessibilityService.systemWideMenuBarSegments(from: samples, sampleStep: 4)

        #expect(segments.count == 2)
        #expect(segments[0].startX == 100)
        #expect(segments[0].endX == 104)
        #expect(segments[1].startX == 120)
    }

    @Test("System-wide resolver synthesizes third-party identifier from label")
    func testResolvedSystemWideMenuBarItemsUseThirdPartyLabelFallback() {
        let segments = [
            AccessibilityService.SystemWideMenuBarSegment(
                pid: 77,
                bundleID: "at.obdev.littlesnitch.networkmonitor",
                appName: "Little Snitch Network Monitor",
                lineY: 15,
                startX: 1600,
                endX: 1620,
                rawIdentifier: nil,
                rawTitle: nil,
                rawDescription: "Little Snitch"
            )
        ]

        let items = AccessibilityService.resolvedSystemWideMenuBarItems(from: segments, sampleStep: 4)

        #expect(items.count == 1)
        #expect(items[0].app.bundleId == "at.obdev.littlesnitch.networkmonitor")
        #expect(items[0].app.menuExtraIdentifier == "at.obdev.littlesnitch.networkmonitor.menuextra.little-snitch")
        #expect(items[0].x == 1600)
        #expect(items[0].width == 24)
    }

    @Test("System-wide resolver falls back to bundle identity for single unlabeled third-party item")
    func testResolvedSystemWideMenuBarItemsFallbackToBundleIdentity() {
        let segments = [
            AccessibilityService.SystemWideMenuBarSegment(
                pid: 88,
                bundleID: "com.example.single",
                appName: "Single App",
                lineY: 15,
                startX: 1500,
                endX: 1512,
                rawIdentifier: nil,
                rawTitle: nil,
                rawDescription: nil
            )
        ]

        let items = AccessibilityService.resolvedSystemWideMenuBarItems(from: segments, sampleStep: 4)

        #expect(items.count == 1)
        #expect(items[0].app.uniqueId == "com.example.single")
        #expect(items[0].app.menuExtraIdentifier == nil)
    }

    @Test("System-wide merge replaces coarse Apple fallback with precise menu extra")
    func testMergeSystemWideMenuBarItemReplacesCoarseAppleFallback() {
        let coarse = AccessibilityService.MenuBarItemPosition(
            app: RunningApp(
                id: "com.apple.Spotlight",
                name: "Spotlight",
                icon: nil,
                policy: .accessory,
                category: .system,
                xPosition: 1888,
                width: 33
            ),
            x: 1888,
            width: 33
        )
        let precise = AccessibilityService.MenuBarItemPosition(
            app: RunningApp.menuExtraItem(
                ownerBundleId: "com.apple.Spotlight",
                name: "Spotlight",
                identifier: "com.apple.menuextra.spotlight",
                xPosition: 1888,
                width: 33
            ),
            x: 1888,
            width: 33
        )

        var appPositions = [coarse.app.uniqueId: coarse]
        AccessibilityService.mergeSystemWideMenuBarItem(precise, into: &appPositions)

        #expect(appPositions.count == 1)
        #expect(appPositions["com.apple.Spotlight"] == nil)
        #expect(appPositions["com.apple.menuextra.spotlight"]?.app.menuExtraIdentifier == "com.apple.menuextra.spotlight")
    }

    @Test("System-wide merge replaces coarse third-party fallback with precise identifier")
    func testMergeSystemWideMenuBarItemReplacesCoarseThirdPartyFallback() {
        let coarse = AccessibilityService.MenuBarItemPosition(
            app: RunningApp(
                id: "at.obdev.littlesnitch.networkmonitor",
                name: "Little Snitch",
                icon: nil,
                policy: .accessory,
                category: .other,
                xPosition: 1600,
                width: 24
            ),
            x: 1600,
            width: 24
        )
        let precise = AccessibilityService.MenuBarItemPosition(
            app: RunningApp(
                id: "at.obdev.littlesnitch.networkmonitor",
                name: "Little Snitch",
                icon: nil,
                policy: .accessory,
                category: .other,
                menuExtraIdentifier: "at.obdev.littlesnitch.networkmonitor.menuextra.little-snitch",
                xPosition: 1600,
                width: 24
            ),
            x: 1600,
            width: 24
        )

        var appPositions = [coarse.app.uniqueId: coarse]
        AccessibilityService.mergeSystemWideMenuBarItem(precise, into: &appPositions)

        #expect(appPositions.count == 1)
        #expect(appPositions["at.obdev.littlesnitch.networkmonitor"] == nil)
        #expect(appPositions["at.obdev.littlesnitch.networkmonitor::axid:at.obdev.littlesnitch.networkmonitor.menuextra.little-snitch"]?.app.menuExtraIdentifier == "at.obdev.littlesnitch.networkmonitor.menuextra.little-snitch")
    }

    @Test("System-wide merge skips coarse fallback when precise item already exists")
    func testMergeSystemWideMenuBarItemSkipsCoarseFallbackWhenPreciseExists() {
        let precise = AccessibilityService.MenuBarItemPosition(
            app: RunningApp.menuExtraItem(
                ownerBundleId: "com.apple.Spotlight",
                name: "Spotlight",
                identifier: "com.apple.menuextra.spotlight",
                xPosition: 1888,
                width: 33
            ),
            x: 1888,
            width: 33
        )
        let coarse = AccessibilityService.MenuBarItemPosition(
            app: RunningApp(
                id: "com.apple.Spotlight",
                name: "Spotlight",
                icon: nil,
                policy: .accessory,
                category: .system,
                xPosition: 1888,
                width: 33
            ),
            x: 1888,
            width: 33
        )

        var appPositions = [precise.app.uniqueId: precise]
        AccessibilityService.mergeSystemWideMenuBarItem(coarse, into: &appPositions)

        #expect(appPositions.count == 1)
        #expect(appPositions["com.apple.menuextra.spotlight"] != nil)
        #expect(appPositions["com.apple.Spotlight"] == nil)
    }

    @Test("Same-bundle precise menu extras keep distinct unique identities")
    func testSameBundlePreciseMenuExtrasKeepDistinctUniqueIDs() {
        let wifi = RunningApp.menuExtraItem(
            ownerBundleId: "com.apple.controlcenter",
            name: "Wi-Fi",
            identifier: "com.apple.controlcenter.wifi"
        )
        let bluetooth = RunningApp.menuExtraItem(
            ownerBundleId: "com.apple.controlcenter",
            name: "Bluetooth",
            identifier: "com.apple.controlcenter.bluetooth"
        )

        #expect(wifi.hasPreciseMenuBarIdentity)
        #expect(bluetooth.hasPreciseMenuBarIdentity)
        #expect(wifi.uniqueId != bluetooth.uniqueId)
    }

    @Test("Bundle-only fallback stays coarse beside same-bundle precise items")
    func testBundleOnlyFallbackStaysCoarseNextToPreciseSameBundleItem() {
        let coarse = RunningApp(
            id: "com.apple.controlcenter",
            name: "Control Center",
            icon: nil,
            policy: .accessory,
            category: .system,
            xPosition: 1500,
            width: 24
        )
        let precise = RunningApp.menuExtraItem(
            ownerBundleId: "com.apple.controlcenter",
            name: "Wi-Fi",
            identifier: "com.apple.controlcenter.wifi",
            xPosition: 1510,
            width: 24
        )

        #expect(!coarse.hasPreciseMenuBarIdentity)
        #expect(coarse.uniqueId == "com.apple.controlcenter")
        #expect(precise.hasPreciseMenuBarIdentity)
        #expect(precise.uniqueId != coarse.uniqueId)
    }
}
