import ApplicationServices
import Testing
import AppKit
@testable import SaneBar

@Suite("AccessibilityService — Window Fallback")
struct AccessibilityServiceWindowFallbackTests {
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

    @Test("System-wide fallback candidates stay limited to unresolved fallback owners")
    func testSystemWideFallbackCandidatePIDsStayNarrow() {
        let candidates = AccessibilityService.systemWideFallbackCandidatePIDs(
            axResolvedPIDs: Set([100, 101]),
            knownNoExtrasPIDs: Set([100, 200]),
            windowBackedPIDs: Set([300]),
            topBarHostPIDs: Set([101, 400])
        )

        #expect(candidates == Set([200, 300, 400]))
    }

    @Test("System-wide fallback candidates empty when AX already resolved everything")
    func testSystemWideFallbackCandidatePIDsEmptyWhenResolved() {
        let candidates = AccessibilityService.systemWideFallbackCandidatePIDs(
            axResolvedPIDs: Set([100, 200, 300]),
            knownNoExtrasPIDs: Set([100, 200]),
            windowBackedPIDs: Set([300]),
            topBarHostPIDs: Set([100, 200, 300])
        )

        #expect(candidates.isEmpty)
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
            AccessibilityMenuExtraService.observableReactionDescription(before: before, after: after) == "shownMenu"
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
            AccessibilityMenuExtraService.observableReactionDescription(before: before, after: after) == "focusedWindow"
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
            AccessibilityMenuExtraService.hasComparableReactionSignals(before: before, after: after) == false
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
            AccessibilityMenuExtraService.observableReactionDescription(before: before, after: after) == "windowServerWindowCount 5->15"
        )
        #expect(
            AccessibilityMenuExtraService.hasComparableReactionSignals(before: before, after: after)
        )
    }
}
