import AppKit
import Testing
@testable import SaneBar

@Suite("Bartender Import Fallback Tests")
struct BartenderImportServiceTests {
    private func makePosition(
        bundleId: String,
        name: String = "Item",
        menuExtraId: String? = nil,
        statusItemIndex: Int? = nil
    ) -> AccessibilityService.MenuBarItemPosition {
        let app = RunningApp(
            id: bundleId,
            name: name,
            icon: nil,
            menuExtraIdentifier: menuExtraId,
            statusItemIndex: statusItemIndex,
            xPosition: 100,
            width: 20
        )
        return AccessibilityService.MenuBarItemPosition(app: app, x: 100, width: 20)
    }

    @Test("parseItem trims whitespace and preserves token")
    func parseItemTrimsWhitespace() {
        let parsed = BartenderImportService._test_parseItem("  com.example.app-Item-1 \n")
        #expect(parsed?.raw == "com.example.app-Item-1")
    }

    @Test("resolveBundleIdAndToken prefers longest running bundle match")
    func resolveBundleLongestMatch() {
        let bundles: Set<String> = ["com.example", "com.example.app"]
        let match = BartenderImportService._test_resolveBundleIdAndToken(
            from: "com.example.app-menuExtra",
            availableBundles: bundles
        )

        #expect(match?.bundleId == "com.example.app")
        #expect(match?.token == "menuExtra")
        #expect(match?.matchedRunning == true)
    }

    @Test("resolveBundleIdAndToken marks not running when only raw prefix exists")
    func resolveBundleNotRunning() {
        let bundles: Set<String> = ["com.apple.finder"]
        let match = BartenderImportService._test_resolveBundleIdAndToken(
            from: "com.example.app-Item-2",
            availableBundles: bundles
        )

        #expect(match?.bundleId == "com.example.app")
        #expect(match?.token == "Item-2")
        #expect(match?.matchedRunning == false)
    }

    @Test("parseStatusItemIndex extracts trailing Item-N index")
    func parseStatusIndex() {
        #expect(BartenderImportService._test_parseStatusItemIndex(from: "Battery-Item-12") == 12)
        #expect(BartenderImportService._test_parseStatusItemIndex(from: "Battery-Item-X") == nil)
        #expect(BartenderImportService._test_parseStatusItemIndex(from: nil) == nil)
    }

    @Test("menuExtraIdCandidate resolves menu extra identifiers")
    func menuExtraCandidate() {
        #expect(BartenderImportService._test_menuExtraIdCandidate(from: "com.apple.menuextra.battery") == "com.apple.menuextra.battery")
        #expect(BartenderImportService._test_menuExtraIdCandidate(from: "com.vendor.extra.widget") == "com.vendor.extra.widget")
        #expect(BartenderImportService._test_menuExtraIdCandidate(from: "NoDotsHere") == nil)
    }

    @Test("fallback returns running bundle when AX has no items")
    func fallbackReturnsRunningBundle() {
        let context = BartenderImportService._test_resolutionContext(availableByBundle: [:])
        let result = BartenderImportService._test_fallbackBundleIDForWindowMove(
            raw: "com.obdev.LittleSnitchUIAgent-Item-0",
            context: context,
            runningBundleIDs: ["com.obdev.LittleSnitchUIAgent"]
        )
        #expect(result == "com.obdev.LittleSnitchUIAgent")
    }

    @Test("fallback is suppressed when AX already sees bundle items")
    func fallbackSuppressedWhenAxHasItems() {
        let axItem = makePosition(bundleId: "com.obdev.LittleSnitchUIAgent", name: "Little Snitch")
        let context = BartenderImportService._test_resolutionContext(
            availableByBundle: ["com.obdev.LittleSnitchUIAgent": [axItem]]
        )

        let result = BartenderImportService._test_fallbackBundleIDForWindowMove(
            raw: "com.obdev.LittleSnitchUIAgent-Item-0",
            context: context,
            runningBundleIDs: ["com.obdev.LittleSnitchUIAgent"]
        )
        #expect(result == nil)
    }

    @Test("fallback returns nil when bundle is not running")
    func fallbackNilWhenNotRunning() {
        let context = BartenderImportService._test_resolutionContext(availableByBundle: [:])
        let result = BartenderImportService._test_fallbackBundleIDForWindowMove(
            raw: "com.obdev.LittleSnitchUIAgent-Item-0",
            context: context,
            runningBundleIDs: []
        )
        #expect(result == nil)
    }

    @Test("fallback skips Bartender self entries")
    func fallbackSkipsBartenderOwnItems() {
        let context = BartenderImportService._test_resolutionContext(availableByBundle: [:])
        let result = BartenderImportService._test_fallbackBundleIDForWindowMove(
            raw: "com.surteesstudios.Bartender4-Anything",
            context: context,
            runningBundleIDs: ["com.surteesstudios.Bartender4"]
        )
        #expect(result == nil)
    }
}
