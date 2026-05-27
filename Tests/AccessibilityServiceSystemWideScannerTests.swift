import ApplicationServices
import Testing
import AppKit
@testable import SaneBar

@Suite("AccessibilityService — System-Wide Scanner")
struct AccessibilityServiceSystemWideScannerTests {
    @Test("System-wide hit samples collapse into contiguous menu-extra segments")
    func testSystemWideMenuBarSegmentsCollapseContiguousSamples() {
        let samples = [
            AccessibilitySystemWideMenuBarScanner.SystemWideHitSample(
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
            AccessibilitySystemWideMenuBarScanner.SystemWideHitSample(
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
            AccessibilitySystemWideMenuBarScanner.SystemWideHitSample(
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

        let segments = AccessibilitySystemWideMenuBarScanner.systemWideMenuBarSegments(from: samples, sampleStep: 4)

        #expect(segments.count == 2)
        #expect(segments[0].startX == 100)
        #expect(segments[0].endX == 104)
        #expect(segments[1].startX == 120)
    }

    @Test("System-wide scan step uses the lighter default on typical single-screen layouts")
    func testRecommendedSystemWideSampleStepForTypicalLayout() {
        #expect(
            AccessibilitySystemWideMenuBarScanner.recommendedSystemWideSampleStep(
                candidateCount: 2,
                totalScreenWidth: 1728
            ) == 6
        )
    }

    @Test("System-wide scan step widens further on very wide layouts")
    func testRecommendedSystemWideSampleStepForVeryWideLayout() {
        #expect(
            AccessibilitySystemWideMenuBarScanner.recommendedSystemWideSampleStep(
                candidateCount: 8,
                totalScreenWidth: 3200
            ) == 8
        )
    }

    @Test("System-wide resolver synthesizes third-party identifier from label")
    func testResolvedSystemWideMenuBarItemsUseThirdPartyLabelFallback() {
        let segments = [
            AccessibilitySystemWideMenuBarScanner.SystemWideMenuBarSegment(
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

        let items = AccessibilitySystemWideMenuBarScanner.resolvedSystemWideMenuBarItems(from: segments, sampleStep: 4)

        #expect(items.count == 1)
        #expect(items[0].app.bundleId == "at.obdev.littlesnitch.networkmonitor")
        #expect(items[0].app.menuExtraIdentifier == "at.obdev.littlesnitch.networkmonitor.menuextra.little-snitch")
        #expect(items[0].x == 1600)
        #expect(items[0].width == 24)
    }

    @Test("System-wide resolver falls back to bundle identity for single unlabeled third-party item")
    func testResolvedSystemWideMenuBarItemsFallbackToBundleIdentity() {
        let segments = [
            AccessibilitySystemWideMenuBarScanner.SystemWideMenuBarSegment(
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

        let items = AccessibilitySystemWideMenuBarScanner.resolvedSystemWideMenuBarItems(from: segments, sampleStep: 4)

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
