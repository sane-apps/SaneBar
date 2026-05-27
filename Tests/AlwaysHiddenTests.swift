import Foundation
@testable import SaneBar
import Testing

// MARK: - AlwaysHiddenTests

@Suite("Always-Hidden Pin Tests")
@MainActor
struct AlwaysHiddenTests {
    // MARK: - parseAlwaysHiddenPin

    @Test("Parses Apple menu extra identifier")
    func parsesMenuExtra() {
        let manager = MenuBarManager.shared
        let pin = manager.alwaysHiddenPinWorkflow.parse("com.apple.menuextra.bluetooth")
        #expect(pin == .menuExtra("com.apple.menuextra.bluetooth"))
    }

    @Test("Parses axId format")
    func parsesAxId() {
        let manager = MenuBarManager.shared
        let pin = manager.alwaysHiddenPinWorkflow.parse("com.spotify.client::axid:NowPlaying")
        #expect(pin == .axId(bundleId: "com.spotify.client", axId: "NowPlaying"))
    }

    @Test("Parses statusItem format")
    func parsesStatusItem() {
        let manager = MenuBarManager.shared
        let pin = manager.alwaysHiddenPinWorkflow.parse("com.1password.1password::statusItem:0")
        #expect(pin == .statusItem(bundleId: "com.1password.1password", index: 0))
    }

    @Test("Parses plain bundle ID")
    func parsesBundleId() {
        let manager = MenuBarManager.shared
        let pin = manager.alwaysHiddenPinWorkflow.parse("com.example.app")
        #expect(pin == .bundleId("com.example.app"))
    }

    @Test("Returns nil for empty string")
    func parsesEmpty() {
        let manager = MenuBarManager.shared
        #expect(manager.alwaysHiddenPinWorkflow.parse("") == nil)
    }

    @Test("Returns nil for whitespace-only string")
    func parsesWhitespace() {
        let manager = MenuBarManager.shared
        #expect(manager.alwaysHiddenPinWorkflow.parse("   ") == nil)
    }

    @Test("Returns nil for malformed axId (missing bundleId)")
    func parsesMalformedAxId() {
        let manager = MenuBarManager.shared
        #expect(manager.alwaysHiddenPinWorkflow.parse("::axid:foo") == nil)
    }

    @Test("Returns nil for malformed axId (missing axId)")
    func parsesMalformedAxIdNoId() {
        let manager = MenuBarManager.shared
        #expect(manager.alwaysHiddenPinWorkflow.parse("com.foo::axid:") == nil)
    }

    @Test("Returns nil for malformed statusItem (non-integer index)")
    func parsesMalformedStatusItem() {
        let manager = MenuBarManager.shared
        #expect(manager.alwaysHiddenPinWorkflow.parse("com.foo::statusItem:abc") == nil)
    }

    // MARK: - isInAlwaysHiddenZone

    @Test("Item left of separator is in always-hidden zone")
    func itemLeftOfSeparator() {
        let manager = MenuBarManager.shared
        let result = manager.alwaysHiddenPinWorkflow.isInZone(itemX: 100, itemWidth: 22, alwaysHiddenSeparatorX: 200)
        #expect(result == true)
    }

    @Test("Item right of separator is NOT in always-hidden zone")
    func itemRightOfSeparator() {
        let manager = MenuBarManager.shared
        let result = manager.alwaysHiddenPinWorkflow.isInZone(itemX: 250, itemWidth: 22, alwaysHiddenSeparatorX: 200)
        #expect(result == false)
    }

    @Test("Item near separator edge (within margin) is NOT in always-hidden zone")
    func itemNearSeparatorEdge() {
        let manager = MenuBarManager.shared
        // itemX=188, width=22 → midX=199, separatorX=200 → midX < (200-6)=194 → false
        let result = manager.alwaysHiddenPinWorkflow.isInZone(itemX: 188, itemWidth: 22, alwaysHiddenSeparatorX: 200)
        #expect(result == false)
    }

    @Test("Item with nil width uses default 22")
    func itemNilWidth() {
        let manager = MenuBarManager.shared
        let result = manager.alwaysHiddenPinWorkflow.isInZone(itemX: 100, itemWidth: nil, alwaysHiddenSeparatorX: 200)
        #expect(result == true)
    }

    // MARK: - Hide-All-Other Rule

    @Test("hide-all-other stored IDs mirror menu bar identity")
    func hideAllOtherStoredIds() {
        #expect(
            MenuBarHideAllOtherWorkflow.storedItemId(
                bundleID: "com.apple.controlcenter",
                menuExtraId: "com.apple.menuextra.battery",
                statusItemIndex: nil
            ) == "com.apple.menuextra.battery"
        )
        #expect(
            MenuBarHideAllOtherWorkflow.storedItemId(
                bundleID: "com.vendor.agent",
                menuExtraId: "AgentAX",
                statusItemIndex: nil
            ) == "com.vendor.agent::axid:AgentAX"
        )
        #expect(
            MenuBarHideAllOtherWorkflow.storedItemId(
                bundleID: "com.vendor.agent",
                menuExtraId: nil,
                statusItemIndex: 1
            ) == "com.vendor.agent::statusItem:1"
        )
    }

    @Test("hide-all-other skips controller and unmovable system items")
    func hideAllOtherSkipRules() {
        #expect(
            MenuBarHideAllOtherWorkflow.shouldSkipItem(
                bundleID: "com.sanebar.app",
                menuExtraId: nil,
                name: "SaneBar"
            )
        )
        #expect(
            MenuBarHideAllOtherWorkflow.shouldSkipItem(
                bundleID: "com.surteesstudios.Bartender-setapp",
                menuExtraId: nil,
                name: "Bartender"
            )
        )
        #expect(
            MenuBarHideAllOtherWorkflow.shouldSkipItem(
                bundleID: "com.apple.controlcenter",
                menuExtraId: "com.apple.menuextra.clock",
                name: "Clock"
            )
        )
        #expect(
            !MenuBarHideAllOtherWorkflow.shouldSkipItem(
                bundleID: "com.example.app",
                menuExtraId: nil,
                name: "Example"
            )
        )
    }

    @Test("hide-all-other allow list seeds from movable visible items")
    func hideAllOtherVisibleIdsSeedsMovableItems() {
        let apps = [
            RunningApp(
                id: "com.apple.controlcenter",
                name: "Wi-Fi",
                icon: nil,
                menuExtraIdentifier: "com.apple.menuextra.wifi",
                xPosition: 500
            ),
            RunningApp(
                id: "com.apple.controlcenter",
                name: "Clock",
                icon: nil,
                menuExtraIdentifier: "com.apple.menuextra.clock",
                xPosition: 540
            ),
            RunningApp(
                id: "com.example.agent",
                name: "Example",
                icon: nil,
                menuExtraIdentifier: "StatusItem",
                xPosition: 560
            ),
            RunningApp(
                id: "com.sanebar.app",
                name: "SaneBar",
                icon: nil,
                xPosition: 580
            ),
        ]

        #expect(
            MenuBarHideAllOtherWorkflow.visibleItemIds(from: apps) == [
                "com.apple.menuextra.wifi",
                "com.example.agent::axid:StatusItem",
            ]
        )
    }

    @Test("hide-all-other detects always-hidden lane before visible replay")
    func hideAllOtherDetectsAlwaysHiddenLaneBeforeVisibleReplay() {
        #expect(
            MenuBarHideAllOtherWorkflow.isAlwaysHiddenZone(
                itemX: 60,
                itemWidth: 22,
                alwaysHiddenBoundaryX: 100
            )
        )
        #expect(
            !MenuBarHideAllOtherWorkflow.isAlwaysHiddenZone(
                itemX: 120,
                itemWidth: 22,
                alwaysHiddenBoundaryX: 100
            )
        )
        #expect(
            !MenuBarHideAllOtherWorkflow.isAlwaysHiddenZone(
                itemX: 60,
                itemWidth: 22,
                alwaysHiddenBoundaryX: nil
            )
        )
    }

    @Test("hide-all-other classifies original zones before expansion")
    func hideAllOtherClassifiesOriginalZonesBeforeExpansion() {
        #expect(
            MenuBarHideAllOtherWorkflow.hideAllOtherZone(
                itemX: 60,
                itemWidth: 22,
                separatorX: 200,
                alwaysHiddenBoundaryX: 100
            ) == .alwaysHidden
        )
        #expect(
            MenuBarHideAllOtherWorkflow.hideAllOtherZone(
                itemX: 140,
                itemWidth: 22,
                separatorX: 200,
                alwaysHiddenBoundaryX: 100
            ) == .hidden
        )
        #expect(
            MenuBarHideAllOtherWorkflow.hideAllOtherZone(
                itemX: 210,
                itemWidth: 22,
                separatorX: 200,
                alwaysHiddenBoundaryX: 100
            ) == .visible
        )
    }

    @Test("hide-all-other replays visible allow-list anchors before hiding violators")
    func hideAllOtherReplaysVisibleAllowListAnchorsBeforeHidingViolators() {
        #expect(
            MenuBarHideAllOtherWorkflow.hideAllOtherMoveNeeded(
                initialZone: .visible,
                shouldShow: false
            )
        )
        #expect(
            MenuBarHideAllOtherWorkflow.hideAllOtherMoveNeeded(
                initialZone: .visible,
                shouldShow: true
            )
        )
        #expect(
            MenuBarHideAllOtherWorkflow.hideAllOtherMoveNeeded(
                initialZone: .hidden,
                shouldShow: true
            )
        )
        #expect(
            MenuBarHideAllOtherWorkflow.hideAllOtherMoveNeeded(
                initialZone: .alwaysHidden,
                shouldShow: true
            )
        )
        #expect(
            !MenuBarHideAllOtherWorkflow.hideAllOtherMoveNeeded(
                initialZone: .hidden,
                shouldShow: false
            )
        )
        #expect(
            !MenuBarHideAllOtherWorkflow.hideAllOtherMoveNeeded(
                initialZone: .alwaysHidden,
                shouldShow: false
            )
        )
    }

    @Test("hide-all-other visible allow-list wins over Always Hidden pin replay")
    func hideAllOtherVisibleAllowListWinsOverAlwaysHiddenPins() {
        let visibleIds: Set<String> = [
            "com.ameba.SwiftBar::statusItem:0",
            "com.apple.menuextra.spotlight",
            "com.example.bundle",
        ]

        #expect(MenuBarAlwaysHiddenPinWorkflow.pinConflictsWithHideAllOtherVisibleAllowList(
            .statusItem(bundleId: "com.ameba.SwiftBar", index: 0),
            visibleIds: visibleIds
        ))
        #expect(MenuBarAlwaysHiddenPinWorkflow.pinConflictsWithHideAllOtherVisibleAllowList(
            .menuExtra("com.apple.menuextra.spotlight"),
            visibleIds: visibleIds
        ))
        #expect(MenuBarAlwaysHiddenPinWorkflow.pinConflictsWithHideAllOtherVisibleAllowList(
            .bundleId("com.example.bundle"),
            visibleIds: visibleIds
        ))
        #expect(!MenuBarAlwaysHiddenPinWorkflow.pinConflictsWithHideAllOtherVisibleAllowList(
            .statusItem(bundleId: "com.other.app", index: 0),
            visibleIds: visibleIds
        ))
    }

    // MARK: - AlwaysHiddenPin.bundleId

    @Test("menuExtra pin has no bundleId")
    func menuExtraBundleId() {
        let pin = MenuBarManager.AlwaysHiddenPin.menuExtra("com.apple.menuextra.clock")
        #expect(pin.bundleId == nil)
    }

    @Test("axId pin has bundleId")
    func axIdBundleId() {
        let pin = MenuBarManager.AlwaysHiddenPin.axId(bundleId: "com.foo", axId: "bar")
        #expect(pin.bundleId == "com.foo")
    }

    @Test("statusItem pin has bundleId")
    func statusItemBundleId() {
        let pin = MenuBarManager.AlwaysHiddenPin.statusItem(bundleId: "com.foo", index: 0)
        #expect(pin.bundleId == "com.foo")
    }

    @Test("bundleId pin has bundleId")
    func bundleIdPinBundleId() {
        let pin = MenuBarManager.AlwaysHiddenPin.bundleId("com.foo")
        #expect(pin.bundleId == "com.foo")
    }

    // MARK: - alwaysHiddenPinnedBundleIds

    @Test("Collects bundle IDs from mixed pin types")
    func pinnedBundleIds() {
        let manager = MenuBarManager.shared
        let original = manager.settings.alwaysHiddenPinnedItemIds
        defer { manager.settings.alwaysHiddenPinnedItemIds = original }

        manager.settings.alwaysHiddenPinnedItemIds = [
            "com.apple.menuextra.bluetooth",
            "com.foo.bar::axid:test",
            "com.baz.qux",
        ]

        let ids = manager.alwaysHiddenPinWorkflow.pinnedBundleIds()
        #expect(ids.contains("com.foo.bar"))
        #expect(ids.contains("com.baz.qux"))
        #expect(!ids.contains("com.apple.menuextra.bluetooth")) // menuExtra has no bundleId
    }

    @Test("unpinAlwaysHidden(bundleID:) removes all matching pin identities")
    func unpinByBundleRemovesMatchingPins() {
        let manager = MenuBarManager.shared
        let original = manager.settings.alwaysHiddenPinnedItemIds
        defer { manager.settings.alwaysHiddenPinnedItemIds = original }

        manager.settings.alwaysHiddenPinnedItemIds = [
            "com.spotify.client",
            "com.spotify.client::axid:NowPlaying",
            "com.spotify.client::statusItem:0",
            "com.apple.menuextra.nowplaying",
            "com.slack.Slack",
        ]

        let changed = manager.alwaysHiddenPinWorkflow.unpin(
            bundleID: "com.spotify.client",
            menuExtraId: "NowPlaying",
            statusItemIndex: 0
        )

        #expect(changed == true)
        #expect(!manager.settings.alwaysHiddenPinnedItemIds.contains("com.spotify.client"))
        #expect(!manager.settings.alwaysHiddenPinnedItemIds.contains("com.spotify.client::axid:NowPlaying"))
        #expect(!manager.settings.alwaysHiddenPinnedItemIds.contains("com.spotify.client::statusItem:0"))
        #expect(manager.settings.alwaysHiddenPinnedItemIds.contains("com.apple.menuextra.nowplaying"))
        #expect(manager.settings.alwaysHiddenPinnedItemIds.contains("com.slack.Slack"))
    }

    @Test("unpinAlwaysHidden(bundleID:) keeps unrelated pins")
    func unpinByBundleKeepsUnrelatedPins() {
        let manager = MenuBarManager.shared
        let original = manager.settings.alwaysHiddenPinnedItemIds
        defer { manager.settings.alwaysHiddenPinnedItemIds = original }

        manager.settings.alwaysHiddenPinnedItemIds = [
            "com.test.alpha",
            "com.test.beta::statusItem:1",
            "com.apple.menuextra.clock",
        ]

        let changed = manager.alwaysHiddenPinWorkflow.unpin(
            bundleID: "com.other.app",
            menuExtraId: "Nope",
            statusItemIndex: 5
        )

        #expect(changed == false)
        #expect(manager.settings.alwaysHiddenPinnedItemIds.count == 3)
        #expect(manager.settings.alwaysHiddenPinnedItemIds.contains("com.test.alpha"))
        #expect(manager.settings.alwaysHiddenPinnedItemIds.contains("com.test.beta::statusItem:1"))
        #expect(manager.settings.alwaysHiddenPinnedItemIds.contains("com.apple.menuextra.clock"))
    }
}
