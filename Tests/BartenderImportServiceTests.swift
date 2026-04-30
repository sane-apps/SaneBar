import AppKit
import Testing
@testable import SaneBar

@Suite("Bartender Import Fallback Tests")
struct BartenderImportServiceTests {
    private func projectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

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

    @Test("special all other items hides current items except explicit show entries")
    func specialAllOtherItemsExpandsCurrentMenuBarItems() {
        let visibleItem = makePosition(
            bundleId: "com.example.visible",
            name: "Visible",
            menuExtraId: "com.example.visible.extra"
        )
        let hiddenCandidate = makePosition(
            bundleId: "com.example.hide",
            name: "Hide Me",
            statusItemIndex: 0
        )
        let bartenderItem = makePosition(
            bundleId: "com.surteesstudios.Bartender-setapp",
            name: "Bartender",
            statusItemIndex: 0
        )

        let context = BartenderImportService._test_resolutionContext(
            availableItems: [visibleItem, hiddenCandidate, bartenderItem],
            availableByBundle: [
                "com.example.visible": [visibleItem],
                "com.example.hide": [hiddenCandidate],
                "com.surteesstudios.Bartender-setapp": [bartenderItem],
            ],
            availableByMenuExtraId: [
                "com.example.visible.extra": visibleItem,
            ],
            availableByMenuExtraIdLower: [
                "com.example.visible.extra": visibleItem,
            ]
        )

        let expanded = BartenderImportService._test_resolvedAllOtherItems(
            context: context,
            preservedRawItems: ["com.example.visible-com.example.visible.extra"]
        )

        #expect(expanded.map(\.bundleId) == ["com.example.hide"])
        #expect(expanded.first?.statusItemIndex == 0)
    }

    @Test("special all other items mirrors Bartender 6 default profile shape")
    func specialAllOtherItemsSupportsBartenderSixDefaultShape() {
        let statsItem = makePosition(
            bundleId: "eu.exelban.Stats",
            name: "Stats",
            statusItemIndex: 2
        )
        let batteryItem = makePosition(
            bundleId: "com.apple.controlcenter",
            name: "Battery",
            menuExtraId: "com.apple.controlcenter-Battery"
        )
        let bartenderController = makePosition(
            bundleId: "com.surteesstudios.Bartender-setapp",
            name: "Bartender",
            statusItemIndex: 0
        )

        let context = BartenderImportService._test_resolutionContext(
            availableItems: [statsItem, batteryItem, bartenderController],
            availableByBundle: [
                "eu.exelban.Stats": [statsItem],
                "com.apple.controlcenter": [batteryItem],
                "com.surteesstudios.Bartender-setapp": [bartenderController],
            ]
        )

        let expanded = BartenderImportService._test_resolvedAllOtherItems(
            context: context,
            preservedRawItems: ["com.surteesstudios.Bartender-setapp-statusItem"]
        )

        #expect(Set(expanded.map(\.bundleId)) == ["eu.exelban.Stats", "com.apple.controlcenter"])
    }

    @Test("stored rule IDs mirror RunningApp unique IDs")
    func storedRuleIdsMirrorRunningAppUniqueIds() {
        #expect(
            BartenderImportService._test_storedRuleItemId(
                bundleID: "com.apple.controlcenter",
                menuExtraId: "com.apple.menuextra.wifi",
                statusItemIndex: nil
            ) == "com.apple.menuextra.wifi"
        )
        #expect(
            BartenderImportService._test_storedRuleItemId(
                bundleID: "com.example.app",
                menuExtraId: "StatusItem",
                statusItemIndex: nil
            ) == "com.example.app::axid:StatusItem"
        )
        #expect(
            BartenderImportService._test_storedRuleItemId(
                bundleID: "com.example.app",
                menuExtraId: nil,
                statusItemIndex: 2
            ) == "com.example.app::statusItem:2"
        )
    }

    @Test("preview plan surfaces hide all other rule and skipped controller items")
    func previewPlanSurfacesHideAllOtherRule() {
        let visibleItem = makePosition(
            bundleId: "com.example.visible",
            name: "Visible",
            menuExtraId: "VisibleAX"
        )
        let hiddenItem = makePosition(
            bundleId: "com.example.hidden",
            name: "Hidden",
            statusItemIndex: 0
        )
        let alwaysHiddenItem = makePosition(
            bundleId: "com.example.always",
            name: "Always",
            statusItemIndex: 1
        )
        let bartenderItem = makePosition(
            bundleId: "com.surteesstudios.Bartender-setapp",
            name: "Bartender",
            statusItemIndex: 0
        )
        let sanebarItem = makePosition(
            bundleId: "com.sanebar.app",
            name: "SaneBar",
            statusItemIndex: 0
        )
        let context = BartenderImportService._test_resolutionContext(
            availableItems: [visibleItem, hiddenItem, bartenderItem, sanebarItem],
            availableByBundle: [
                "com.example.visible": [visibleItem],
                "com.example.hidden": [hiddenItem],
                "com.example.always": [alwaysHiddenItem],
                "com.surteesstudios.Bartender-setapp": [bartenderItem],
                "com.sanebar.app": [sanebarItem],
            ]
        )

        let plan = BartenderImportService._test_previewPlan(
            profile: BartenderImportService.Profile(
                hide: ["special.AllOtherItems", "com.surteesstudios.Bartender-setapp-statusItem"],
                show: ["com.example.visible-VisibleAX"],
                alwaysHide: ["com.example.always-Item-1", "com.missing.app-Item-0"]
            ),
            root: [
                "MouseExitDelay": 0.4,
                "ShowAllItemsWhenDragging": true,
            ],
            fileName: "com.surteesstudios.Bartender-setapp.plist",
            context: context
        )

        #expect(plan.sourceKind == .bartender)
        #expect(plan.hideAllOtherItems)
        #expect(plan.showItemIds == ["com.example.visible::axid:VisibleAX"])
        #expect(plan.hideItemIds == ["com.example.hidden::statusItem:0"])
        #expect(plan.alwaysHideItemIds == ["com.example.always::statusItem:1"])
        #expect(plan.missingItemIds == ["com.missing.app-Item-0"])
        #expect(plan.skippedItemIds == ["com.surteesstudios.Bartender-setapp-statusItem"])
        #expect(plan.behavioralSettings.count == 2)
    }

    @Test("import separates Bartender AlwaysHide from regular Hide")
    func importSeparatesAlwaysHideMoves() throws {
        let source = try String(
            contentsOf: projectRootURL().appendingPathComponent("Core/Services/BartenderImportService.swift"),
            encoding: .utf8
        )

        #expect(source.contains("let alwaysHideRaw = profile.alwaysHide"))
        #expect(source.contains("moveIconAlwaysHiddenAndWait("))
        #expect(source.contains("summary.movedAlwaysHidden += 1"))
        #expect(!source.contains("let hideRaw = profile.hide + profile.alwaysHide"))
    }
}

@Suite("Ice Import Settings Tests")
struct IceImportServiceTests {
    @Test("Ice import maps HideApplicationMenus into inline reveal setting")
    func hideApplicationMenusSettingImports() {
        let parsed = IceImportService._test_parseSettings(from: [
            "HideApplicationMenus": false,
            "ShowOnScroll": true,
        ])

        var settings = SaneBarSettings()
        let summary = IceImportService._test_applySettings(&settings, parsed: parsed)

        #expect(settings.hideApplicationMenusOnInlineReveal == false)
        #expect(settings.showOnScroll == true)
        #expect(summary.applied.contains("Hide application menus on inline reveal: off"))
    }

    @Test("Ice import no longer skips HideApplicationMenus when supported")
    func hideApplicationMenusNoLongerSkipped() {
        let parsed = IceImportService._test_parseSettings(from: [
            "HideApplicationMenus": true,
            "Hotkeys": [:],
        ])

        var settings = SaneBarSettings()
        let summary = IceImportService._test_applySettings(
            &settings,
            parsed: parsed,
            iceRoot: [
                "HideApplicationMenus": true,
                "Hotkeys": [:],
            ]
        )

        #expect(settings.hideApplicationMenusOnInlineReveal == true)
        #expect(!summary.skipped.contains("Hide application menus"))
        #expect(summary.skipped.contains("Hotkeys (incompatible format)"))
    }
}
