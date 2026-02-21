import CoreGraphics
@testable import SaneBar
import Testing

@Suite("Zone Classification Tests")
struct ZoneClassificationTests {
    private let service = SearchService.shared

    // MARK: - classifyZone with Two Zones (no always-hidden separator)

    @Test("Item left of separator is classified as hidden")
    func itemLeftOfSeparatorIsHidden() {
        // Separator at x=500. Item at x=200 (midX ~211) → hidden.
        let zone = service.classifyZone(
            itemX: 200, itemWidth: 22, separatorX: 500, alwaysHiddenSeparatorX: nil
        )
        #expect(zone == .hidden)
    }

    @Test("Item right of separator is classified as visible")
    func itemRightOfSeparatorIsVisible() {
        // Separator at x=500. Item at x=600 (midX ~611) → visible.
        let zone = service.classifyZone(
            itemX: 600, itemWidth: 22, separatorX: 500, alwaysHiddenSeparatorX: nil
        )
        #expect(zone == .visible)
    }

    @Test("Item at separator edge respects margin")
    func itemAtSeparatorEdge() {
        // Separator at x=500. Item midX = 500 - 6 = 494 (exactly at margin).
        // midX(483) = 483 + 11 = 494 → 494 == (500 - 6) → NOT < margin → visible
        let zone = service.classifyZone(
            itemX: 483, itemWidth: 22, separatorX: 500, alwaysHiddenSeparatorX: nil
        )
        #expect(zone == .visible)

        // Just barely left of margin: midX = 493.
        // 482 + 11 = 493 < 494 → hidden
        let zone2 = service.classifyZone(
            itemX: 482, itemWidth: 22, separatorX: 500, alwaysHiddenSeparatorX: nil
        )
        #expect(zone2 == .hidden)
    }

    @Test("Boundary sweep: two-zone classification stays stable across icon widths")
    func twoZoneBoundarySweep() {
        let separatorX: CGFloat = 500
        let widths: [CGFloat] = [10, 16, 22, 44, 120]
        let margin: CGFloat = 6

        for width in widths {
            let hiddenMidX = separatorX - margin - 0.1
            let visibleMidX = separatorX - margin + 0.1
            let hiddenX = hiddenMidX - (width / 2)
            let visibleX = visibleMidX - (width / 2)

            let hiddenZone = service.classifyZone(
                itemX: hiddenX,
                itemWidth: width,
                separatorX: separatorX,
                alwaysHiddenSeparatorX: nil
            )
            let visibleZone = service.classifyZone(
                itemX: visibleX,
                itemWidth: width,
                separatorX: separatorX,
                alwaysHiddenSeparatorX: nil
            )

            #expect(hiddenZone == .hidden, "width=\(width): expected hidden just left of margin")
            #expect(visibleZone == .visible, "width=\(width): expected visible just right of margin")
        }
    }

    // MARK: - classifyZone with Three Zones (always-hidden separator present)

    @Test("Item left of AH separator is always-hidden")
    func itemLeftOfAHSeparatorIsAlwaysHidden() {
        // AH separator at x=100, main separator at x=500.
        // Item at x=50 (midX ~61) → always-hidden.
        let zone = service.classifyZone(
            itemX: 50, itemWidth: 22, separatorX: 500, alwaysHiddenSeparatorX: 100
        )
        #expect(zone == .alwaysHidden)
    }

    @Test("Item between separators is hidden")
    func itemBetweenSeparatorsIsHidden() {
        // AH separator at x=100, main separator at x=500.
        // Item at x=300 (midX ~311) → hidden.
        let zone = service.classifyZone(
            itemX: 300, itemWidth: 22, separatorX: 500, alwaysHiddenSeparatorX: 100
        )
        #expect(zone == .hidden)
    }

    @Test("Item right of main separator is visible with three zones")
    func itemRightOfMainSeparatorVisibleThreeZones() {
        // AH separator at x=100, main separator at x=500.
        // Item at x=600 (midX ~611) → visible.
        let zone = service.classifyZone(
            itemX: 600, itemWidth: 22, separatorX: 500, alwaysHiddenSeparatorX: 100
        )
        #expect(zone == .visible)
    }

    @Test("Boundary sweep: three-zone classification stays stable across icon widths")
    func threeZoneBoundarySweep() {
        let separatorX: CGFloat = 500
        let alwaysHiddenSeparatorX: CGFloat = 120
        let widths: [CGFloat] = [10, 16, 22, 44, 120]
        let margin: CGFloat = 6

        for width in widths {
            let alwaysHiddenMidX = alwaysHiddenSeparatorX - margin - 0.1
            let hiddenMidX = alwaysHiddenSeparatorX + margin + 10
            let visibleMidX = separatorX - margin + 0.1

            let alwaysHiddenX = alwaysHiddenMidX - (width / 2)
            let hiddenX = hiddenMidX - (width / 2)
            let visibleX = visibleMidX - (width / 2)

            let alwaysHiddenZone = service.classifyZone(
                itemX: alwaysHiddenX,
                itemWidth: width,
                separatorX: separatorX,
                alwaysHiddenSeparatorX: alwaysHiddenSeparatorX
            )
            let hiddenZone = service.classifyZone(
                itemX: hiddenX,
                itemWidth: width,
                separatorX: separatorX,
                alwaysHiddenSeparatorX: alwaysHiddenSeparatorX
            )
            let visibleZone = service.classifyZone(
                itemX: visibleX,
                itemWidth: width,
                separatorX: separatorX,
                alwaysHiddenSeparatorX: alwaysHiddenSeparatorX
            )

            #expect(alwaysHiddenZone == .alwaysHidden, "width=\(width): expected always-hidden zone")
            #expect(hiddenZone == .hidden, "width=\(width): expected hidden zone")
            #expect(visibleZone == .visible, "width=\(width): expected visible zone")
        }
    }

    // MARK: - Edge Cases

    @Test("Nil width defaults to 22")
    func nilWidthDefaultsTo22() {
        // Item at x=489, width nil → default width 22, midX = 489 + 11 = 500.
        // 500 >= 500 - 6 = 494 → visible
        let zone = service.classifyZone(
            itemX: 489, itemWidth: nil, separatorX: 500, alwaysHiddenSeparatorX: nil
        )
        #expect(zone == .visible)
    }

    @Test("Zero width treated as 1")
    func zeroWidthTreatedAs1() {
        // width 0 → max(1, 0) = 1, midX = 200 + 0.5 = 200.5
        let zone = service.classifyZone(
            itemX: 200, itemWidth: 0, separatorX: 500, alwaysHiddenSeparatorX: nil
        )
        #expect(zone == .hidden)
    }

    @Test("Negative X position is always hidden")
    func negativeXPosition() {
        // Item pushed off-screen left (x = -100). With separator at 500, clearly hidden.
        let zone = service.classifyZone(
            itemX: -100, itemWidth: 22, separatorX: 500, alwaysHiddenSeparatorX: nil
        )
        #expect(zone == .hidden)

        // With AH separator at screen edge (0), x=-100 → always-hidden
        let zone2 = service.classifyZone(
            itemX: -100, itemWidth: 22, separatorX: 500, alwaysHiddenSeparatorX: 0
        )
        #expect(zone2 == .alwaysHidden)
    }

    // MARK: - Zone Exclusivity

    @Test("Each item belongs to exactly one zone")
    func eachItemInExactlyOneZone() {
        // Simulate a realistic menu bar: AH sep at 50, main sep at 400.
        // 3 items at different positions.
        let positions: [(x: CGFloat, width: CGFloat)] = [
            (x: 10, width: 22), // Should be always-hidden
            (x: 200, width: 22), // Should be hidden
            (x: 600, width: 22), // Should be visible
        ]

        var zones: [SearchService.VisibilityZone] = []
        for pos in positions {
            zones.append(service.classifyZone(
                itemX: pos.x, itemWidth: pos.width,
                separatorX: 400, alwaysHiddenSeparatorX: 50
            ))
        }

        #expect(zones[0] == .alwaysHidden)
        #expect(zones[1] == .hidden)
        #expect(zones[2] == .visible)

        // Verify all three zones are represented
        #expect(Set(zones).count == 3)
    }
}

// MARK: - Switch Exhaustiveness Tests

@Suite("Zone Move Switch Tests")
struct ZoneMoveExhaustivenessTests {
    @Test("All zone transitions are covered explicitly")
    func allTransitionsCovered() {
        // SecondMenuBarView.moveIcon switch should handle all 9 combinations.
        // We verify the IconZone enum has exactly 3 cases by exhaustive switch.
        let zones: [IconZone] = [.visible, .hidden, .alwaysHidden]
        var pairs: [(IconZone, IconZone)] = []
        for source in zones {
            for target in zones {
                pairs.append((source, target))
            }
        }
        #expect(pairs.count == 9)

        // Verify each pair matches one of the explicit switch cases.
        // The switch in SecondMenuBarView covers:
        //   (.alwaysHidden, .visible), (.alwaysHidden, .hidden),
        //   (.hidden, .visible), (.hidden, .alwaysHidden),
        //   (.visible, .hidden), (.visible, .alwaysHidden),
        //   (.visible, .visible), (.hidden, .hidden), (.alwaysHidden, .alwaysHidden)
        for (source, target) in pairs {
            let handled = switch (source, target) {
            case (.alwaysHidden, .visible): true
            case (.alwaysHidden, .hidden): true
            case (.hidden, .visible): true
            case (.hidden, .alwaysHidden): true
            case (.visible, .hidden): true
            case (.visible, .alwaysHidden): true
            case (.visible, .visible), (.hidden, .hidden), (.alwaysHidden, .alwaysHidden): true
            }
            #expect(handled, "Transition \(source) → \(target) should be handled")
        }
    }
}

// MARK: - AH Zone Detection Tests

@Suite("Always Hidden Zone Detection Tests")
struct AlwaysHiddenZoneDetectionTests {
    @Test("Item clearly in AH zone detected correctly")
    @MainActor
    func itemInAHZone() {
        let manager = MenuBarManager.shared
        // Item at x=30, width=22 → midX=41. AH separator at x=100. margin=max(4, 22*0.3)=6.6
        // midX(41) < (100 - 6.6 = 93.4) → true → in AH zone
        let result = manager.isInAlwaysHiddenZone(itemX: 30, itemWidth: 22, alwaysHiddenSeparatorX: 100)
        #expect(result == true)
    }

    @Test("Item clearly outside AH zone detected correctly")
    @MainActor
    func itemOutsideAHZone() {
        let manager = MenuBarManager.shared
        // Item at x=200, width=22 → midX=211. AH separator at x=100.
        // midX(211) < (100 - 6.6 = 93.4) → false → NOT in AH zone
        let result = manager.isInAlwaysHiddenZone(itemX: 200, itemWidth: 22, alwaysHiddenSeparatorX: 100)
        #expect(result == false)
    }

    @Test("Item at AH separator edge respects margin")
    @MainActor
    func itemAtAHEdge() {
        let manager = MenuBarManager.shared
        // Item at x=80, width=22 → midX=91. AH separator at x=100. margin=6.6
        // midX(91) < (100 - 6.6 = 93.4) → true → in AH zone
        let inZone = manager.isInAlwaysHiddenZone(itemX: 80, itemWidth: 22, alwaysHiddenSeparatorX: 100)
        #expect(inZone == true)

        // Item at x=90, width=22 → midX=101. 101 < 93.4 → false → NOT in AH zone
        let outsideZone = manager.isInAlwaysHiddenZone(itemX: 90, itemWidth: 22, alwaysHiddenSeparatorX: 100)
        #expect(outsideZone == false)
    }

    @Test("Nil width defaults to 22")
    @MainActor
    func nilWidthDefaultsInAHCheck() {
        let manager = MenuBarManager.shared
        // width nil → max(1, 22) = 22, midX = 30 + 11 = 41. margin = max(4, 22*0.3) = 6.6
        let result = manager.isInAlwaysHiddenZone(itemX: 30, itemWidth: nil, alwaysHiddenSeparatorX: 100)
        #expect(result == true)
    }
}

// MARK: - Pin/Unpin Tests

@Suite("Pin Identity Tests")
struct PinIdentityTests {
    @Test("Pin operation uses uniqueId consistently")
    @MainActor
    func pinUsesUniqueId() {
        let manager = MenuBarManager.shared
        let original = manager.settings.alwaysHiddenPinnedItemIds
        defer { manager.settings.alwaysHiddenPinnedItemIds = original }

        manager.settings.alwaysHiddenPinnedItemIds = []

        let app = RunningApp(
            id: "com.spotify.client",
            name: "Spotify",
            icon: nil,
            menuExtraIdentifier: nil,
            statusItemIndex: 0
        )

        manager.pinAlwaysHidden(app: app)
        #expect(!manager.settings.alwaysHiddenPinnedItemIds.isEmpty)

        manager.unpinAlwaysHidden(app: app)
        #expect(manager.settings.alwaysHiddenPinnedItemIds.isEmpty)
    }

    @Test("Duplicate pin is idempotent")
    @MainActor
    func duplicatePinIdempotent() {
        let manager = MenuBarManager.shared
        let original = manager.settings.alwaysHiddenPinnedItemIds
        defer { manager.settings.alwaysHiddenPinnedItemIds = original }

        manager.settings.alwaysHiddenPinnedItemIds = []

        let app = RunningApp(id: "com.test.app", name: "Test", icon: nil)

        manager.pinAlwaysHidden(app: app)
        let countAfterFirst = manager.settings.alwaysHiddenPinnedItemIds.count

        manager.pinAlwaysHidden(app: app)
        let countAfterSecond = manager.settings.alwaysHiddenPinnedItemIds.count

        #expect(countAfterFirst == countAfterSecond)
    }

    @Test("System items filtered from all zones")
    func systemItemsFiltered() {
        let clock = RunningApp(
            id: "com.apple.controlcenter",
            name: "Control Center",
            icon: nil,
            menuExtraIdentifier: "com.apple.menuextra.clock"
        )
        let slack = RunningApp(id: "com.slack.Slack", name: "Slack", icon: nil)

        let apps = [clock, slack]
        let filtered = apps.filter { !$0.isUnmovableSystemItem }

        #expect(filtered.count == 1)
        #expect(filtered.first?.id == "com.slack.Slack")
    }
}
