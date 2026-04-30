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
        let pin = manager.parseAlwaysHiddenPin("com.apple.menuextra.bluetooth")
        #expect(pin == .menuExtra("com.apple.menuextra.bluetooth"))
    }

    @Test("Parses axId format")
    func parsesAxId() {
        let manager = MenuBarManager.shared
        let pin = manager.parseAlwaysHiddenPin("com.spotify.client::axid:NowPlaying")
        #expect(pin == .axId(bundleId: "com.spotify.client", axId: "NowPlaying"))
    }

    @Test("Parses statusItem format")
    func parsesStatusItem() {
        let manager = MenuBarManager.shared
        let pin = manager.parseAlwaysHiddenPin("com.1password.1password::statusItem:0")
        #expect(pin == .statusItem(bundleId: "com.1password.1password", index: 0))
    }

    @Test("Parses plain bundle ID")
    func parsesBundleId() {
        let manager = MenuBarManager.shared
        let pin = manager.parseAlwaysHiddenPin("com.example.app")
        #expect(pin == .bundleId("com.example.app"))
    }

    @Test("Returns nil for empty string")
    func parsesEmpty() {
        let manager = MenuBarManager.shared
        #expect(manager.parseAlwaysHiddenPin("") == nil)
    }

    @Test("Returns nil for whitespace-only string")
    func parsesWhitespace() {
        let manager = MenuBarManager.shared
        #expect(manager.parseAlwaysHiddenPin("   ") == nil)
    }

    @Test("Returns nil for malformed axId (missing bundleId)")
    func parsesMalformedAxId() {
        let manager = MenuBarManager.shared
        #expect(manager.parseAlwaysHiddenPin("::axid:foo") == nil)
    }

    @Test("Returns nil for malformed axId (missing axId)")
    func parsesMalformedAxIdNoId() {
        let manager = MenuBarManager.shared
        #expect(manager.parseAlwaysHiddenPin("com.foo::axid:") == nil)
    }

    @Test("Returns nil for malformed statusItem (non-integer index)")
    func parsesMalformedStatusItem() {
        let manager = MenuBarManager.shared
        #expect(manager.parseAlwaysHiddenPin("com.foo::statusItem:abc") == nil)
    }

    // MARK: - isInAlwaysHiddenZone

    @Test("Item left of separator is in always-hidden zone")
    func itemLeftOfSeparator() {
        let manager = MenuBarManager.shared
        let result = manager.isInAlwaysHiddenZone(itemX: 100, itemWidth: 22, alwaysHiddenSeparatorX: 200)
        #expect(result == true)
    }

    @Test("Item right of separator is NOT in always-hidden zone")
    func itemRightOfSeparator() {
        let manager = MenuBarManager.shared
        let result = manager.isInAlwaysHiddenZone(itemX: 250, itemWidth: 22, alwaysHiddenSeparatorX: 200)
        #expect(result == false)
    }

    @Test("Item near separator edge (within margin) is NOT in always-hidden zone")
    func itemNearSeparatorEdge() {
        let manager = MenuBarManager.shared
        // itemX=188, width=22 → midX=199, separatorX=200 → midX < (200-6)=194 → false
        let result = manager.isInAlwaysHiddenZone(itemX: 188, itemWidth: 22, alwaysHiddenSeparatorX: 200)
        #expect(result == false)
    }

    @Test("Item with nil width uses default 22")
    func itemNilWidth() {
        let manager = MenuBarManager.shared
        let result = manager.isInAlwaysHiddenZone(itemX: 100, itemWidth: nil, alwaysHiddenSeparatorX: 200)
        #expect(result == true)
    }

    // MARK: - Hide-All-Other Rule

    @Test("hide-all-other stored IDs mirror menu bar identity")
    func hideAllOtherStoredIds() {
        #expect(
            MenuBarManager.hideAllOtherStoredItemId(
                bundleID: "com.apple.controlcenter",
                menuExtraId: "com.apple.menuextra.battery",
                statusItemIndex: nil
            ) == "com.apple.menuextra.battery"
        )
        #expect(
            MenuBarManager.hideAllOtherStoredItemId(
                bundleID: "com.vendor.agent",
                menuExtraId: "AgentAX",
                statusItemIndex: nil
            ) == "com.vendor.agent::axid:AgentAX"
        )
        #expect(
            MenuBarManager.hideAllOtherStoredItemId(
                bundleID: "com.vendor.agent",
                menuExtraId: nil,
                statusItemIndex: 1
            ) == "com.vendor.agent::statusItem:1"
        )
    }

    @Test("hide-all-other skips controller and unmovable system items")
    func hideAllOtherSkipRules() {
        #expect(
            MenuBarManager.hideAllOtherRuleShouldSkipItem(
                bundleID: "com.sanebar.app",
                menuExtraId: nil,
                name: "SaneBar"
            )
        )
        #expect(
            MenuBarManager.hideAllOtherRuleShouldSkipItem(
                bundleID: "com.surteesstudios.Bartender-setapp",
                menuExtraId: nil,
                name: "Bartender"
            )
        )
        #expect(
            MenuBarManager.hideAllOtherRuleShouldSkipItem(
                bundleID: "com.apple.controlcenter",
                menuExtraId: "com.apple.menuextra.clock",
                name: "Clock"
            )
        )
        #expect(
            !MenuBarManager.hideAllOtherRuleShouldSkipItem(
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
            MenuBarManager.hideAllOtherVisibleItemIds(from: apps) == [
                "com.apple.menuextra.wifi",
                "com.example.agent::axid:StatusItem",
            ]
        )
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

        let ids = manager.alwaysHiddenPinnedBundleIds()
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

        let changed = manager.unpinAlwaysHidden(
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

        let changed = manager.unpinAlwaysHidden(
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
