import CoreGraphics
import Foundation
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

    @Test("Always-hidden boundary sanitizer keeps valid left-side boundary")
    func alwaysHiddenBoundarySanitizerAcceptsValidBoundary() {
        let normalized = SearchService.normalizedAlwaysHiddenBoundary(240, separatorX: 500)
        #expect(normalized == 240)
    }

    @Test("Always-hidden boundary sanitizer rejects inverted boundary")
    func alwaysHiddenBoundarySanitizerRejectsInvertedBoundary() {
        // Candidate on the wrong side of the main separator must be dropped.
        let normalized = SearchService.normalizedAlwaysHiddenBoundary(520, separatorX: 500)
        #expect(normalized == nil)
    }

    @Test("Always-hidden boundary sanitizer enforces minimum gap from separator")
    func alwaysHiddenBoundarySanitizerEnforcesMinimumGap() {
        // 494 is within the default 8pt guard band of separatorX=500.
        let normalized = SearchService.normalizedAlwaysHiddenBoundary(494, separatorX: 500)
        #expect(normalized == nil)
    }

    @Test("Always-hidden boundary sanitizer accepts negative global coordinates")
    func alwaysHiddenBoundarySanitizerAcceptsNegativeGlobalCoordinates() {
        // External display arranged left of the primary: both separator X values can be negative.
        let normalized = SearchService.normalizedAlwaysHiddenBoundary(-1080, separatorX: -600)
        #expect(normalized == -1080)
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
    private func projectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func source(_ relativePath: String) throws -> String {
        try String(
            contentsOf: projectRootURL().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func secondMenuBarSource() throws -> String {
        try [
            "UI/SearchWindow/SecondMenuBarView.swift",
            "UI/SearchWindow/SecondMenuBarSupport.swift",
            "UI/SearchWindow/SecondMenuBarPanelIconTile.swift"
        ]
        .map(source)
        .joined(separator: "\n")
    }

    private func functionBody(_ marker: String, in source: String) throws -> Substring {
        let start = try #require(source.range(of: marker))
        let openBrace = try #require(source[start.lowerBound...].firstIndex(of: "{"))
        var depth = 0
        var index = openBrace
        var closeBrace: String.Index?

        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    closeBrace = index
                    index = source.endIndex
                    continue
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        let closingBrace = try #require(closeBrace)
        return source[start.lowerBound...closingBrace]
    }

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

    @Test("Shared zone move request mapper covers every customer move transition")
    func sharedZoneMoveRequestMapperCoversEveryCustomerMoveTransition() {
        let enabledCases: [(BrowseAppZone, BrowseAppZone, MenuBarZoneMoveRequest?)] = [
            (.visible, .hidden, .visibleToHidden),
            (.hidden, .visible, .hiddenToVisible),
            (.visible, .alwaysHidden, .visibleToAlwaysHidden),
            (.hidden, .alwaysHidden, .hiddenToAlwaysHidden),
            (.alwaysHidden, .visible, .alwaysHiddenToVisible),
            (.alwaysHidden, .hidden, .alwaysHiddenToHidden),
            (.visible, .visible, nil),
            (.hidden, .hidden, nil),
            (.alwaysHidden, .alwaysHidden, nil)
        ]

        for (source, target, expected) in enabledCases {
            #expect(BrowsePanelMoveQueue.zoneMoveRequest(
                from: source,
                to: target,
                isAlwaysHiddenEnabled: true
            ) == expected)
        }

        #expect(BrowsePanelMoveQueue.zoneMoveRequest(
            from: .visible,
            to: .alwaysHidden,
            isAlwaysHiddenEnabled: false
        ) == nil)
        #expect(BrowsePanelMoveQueue.zoneMoveRequest(
            from: .hidden,
            to: .alwaysHidden,
            isAlwaysHiddenEnabled: false
        ) == nil)
    }

    @Test("Customer UI move entry points all route through deferred queue path")
    func customerUIMoveEntryPointsAllRouteThroughDeferredQueuePath() throws {
        let browseNavigation = try source("UI/SearchWindow/MenuBarSearchView+Navigation.swift")
        let browseQueue = try source("UI/SearchWindow/BrowsePanelMoveQueue.swift")
        let browseGrid = try source("UI/SearchWindow/BrowseAppGridView.swift")
        let browseToolbar = try source("UI/SearchWindow/BrowsePanelToolbarViews.swift")
        let secondMenuBar = try source("UI/SearchWindow/SecondMenuBarView.swift")
        let secondMenuBarTile = try source("UI/SearchWindow/SecondMenuBarPanelIconTile.swift")
        let searchWindowUISources = try [
            "UI/SearchWindow/MenuBarSearchView+Navigation.swift",
            "UI/SearchWindow/BrowsePanelMoveQueue.swift",
            "UI/SearchWindow/SecondMenuBarView.swift"
        ].map(source).joined(separator: "\n")

        #expect(browseGrid.contains("onToggleHidden: isPro ? makeToggleHiddenAction(app)"))
        #expect(browseGrid.contains("onMoveToAlwaysHidden: isPro ? makeMoveToAlwaysHiddenAction(app)"))
        #expect(browseGrid.contains("onMoveToHidden: isPro ? makeMoveToHiddenAction(app)"))
        #expect(browseToolbar.contains("handleZoneDrop(payloads, segmentMode)"))

        let toggleAction = try functionBody("func makeToggleHiddenAction", in: browseNavigation)
        let moveToHiddenAction = try functionBody("func makeMoveToHiddenAction", in: browseNavigation)
        let moveToAlwaysHiddenAction = try functionBody("func makeMoveToAlwaysHiddenAction", in: browseNavigation)
        let browseZoneDrop = try functionBody("func handleZoneDrop", in: browseNavigation)
        let browseGridDrop = try functionBody("func handleGridReorderDrop", in: browseNavigation)
        let browseDeferredMove = try functionBody("static func queueMoveAfterDrop", in: browseQueue)
        let browseDeferredReorder = try functionBody("static func queueReorderAfterDrop", in: browseQueue)

        #expect(toggleAction.contains("queueMoveAfterDrop"))
        #expect(moveToHiddenAction.contains("queueMoveAfterDrop"))
        #expect(moveToAlwaysHiddenAction.contains("queueMoveAfterDrop"))
        #expect(browseZoneDrop.contains("return queueMoveAfterDrop(sourceApp, from: sourceZone, to: .visible)"))
        #expect(browseZoneDrop.contains("return queueMoveAfterDrop(sourceApp, from: sourceZone, to: .hidden)"))
        #expect(browseZoneDrop.contains("return queueMoveAfterDrop(sourceApp, from: sourceZone, to: .alwaysHidden)"))
        #expect(browseGridDrop.contains("return queueReorderAfterDrop(sourceApp, targetApp: targetApp)"))
        #expect(browseDeferredMove.contains("await Task.yield()"))
        #expect(browseDeferredMove.contains("queueZoneMoveAfterDrop"))
        #expect(browseDeferredReorder.contains("await Task.yield()"))

        #expect(secondMenuBarTile.contains("onMoveToVisible"))
        #expect(secondMenuBarTile.contains("onMoveToHidden"))
        #expect(secondMenuBarTile.contains("onMoveToAlwaysHidden"))

        let makeSecondMenuBarTile = try functionBody("private func makeTile", in: secondMenuBar)
        let secondMenuBarMoveIcon = try functionBody("private func moveIcon", in: secondMenuBar)
        let secondMenuBarRequest = try functionBody("private func zoneMoveRequest", in: secondMenuBar)
        let secondMenuBarDeferredMove = try functionBody("private func queueMoveAfterDrop", in: secondMenuBar)
        let secondMenuBarZoneDrop = try functionBody("private func handleZoneDrop", in: secondMenuBar)
        let secondMenuBarTileDrop = try functionBody("private func handleTileDrop", in: secondMenuBar)
        let secondMenuBarReorder = try functionBody("private func handleReorderDrop", in: secondMenuBar)

        #expect(makeSecondMenuBarTile.contains("_ = moveIcon(app, from: zone, to: .visible)"))
        #expect(makeSecondMenuBarTile.contains("_ = moveIcon(app, from: zone, to: .hidden)"))
        #expect(makeSecondMenuBarTile.contains("_ = moveIcon(app, from: zone, to: .alwaysHidden)"))
        #expect(secondMenuBarMoveIcon.contains("return queueMoveAfterDrop(app, from: source, to: target)"))
        #expect(secondMenuBarRequest.contains("BrowsePanelMoveQueue.zoneMoveRequest"))
        #expect(secondMenuBarRequest.contains("BrowseAppZone(source)"))
        #expect(secondMenuBarRequest.contains("BrowseAppZone(target)"))
        #expect(secondMenuBarDeferredMove.contains("await Task.yield()"))
        #expect(secondMenuBarDeferredMove.contains("queueZoneMoveAfterDrop"))
        #expect(secondMenuBarZoneDrop.contains("return queueMoveAfterDrop(source.app, from: source.zone, to: targetZone)"))
        #expect(secondMenuBarTileDrop.contains("return queueMoveAfterDrop(source.app, from: source.zone, to: targetZone)"))
        #expect(secondMenuBarTileDrop.contains("return handleReorderDrop(payloads, targetApp: targetApp)"))
        #expect(secondMenuBarReorder.contains("await Task.yield()"))
        #expect(secondMenuBarReorder.contains("queueReorderIcon("))

        #expect(!searchWindowUISources.contains("moveQueueWorkflow.queueZoneMove(\n"))
        #expect(!searchWindowUISources.contains("func queueMove("))
    }

    @Test("Browse views wait on queued move tasks instead of fixed delays")
    func browseViewsWaitOnQueuedMoveTasksInsteadOfGuessingWithDelays() throws {
        let iconPanelSource = try source("UI/SearchWindow/BrowsePanelMoveQueue.swift")
        let secondMenuBarSource = try secondMenuBarSource()
        let queueSource = try source("Core/Services/MenuBarMoveQueueWorkflow.swift")
        let verifierSource = try source("Core/Services/MenuBarMoveVerifier.swift")
        let taskSource = try source("Core/Services/MenuBarMoveTaskCoordinator.swift")

        #expect(queueSource.contains("MenuBarZoneMoveRequest"))
        #expect(queueSource.contains("func queueZoneMove("))
        #expect(queueSource.contains("func queueZoneMoveAfterDrop("))
        #expect(queueSource.contains("prepareAlwaysHiddenMoveQueueAfterDrop"))
        #expect(queueSource.contains("ensureAlwaysHiddenSeparatorReadyAfterDrop"))
        #expect(queueSource.contains("try? await Task.sleep(for: .milliseconds(50))"))
        #expect(taskSource.contains("enum QueuedAlwaysHiddenMutation"))
        #expect(taskSource.contains("optimisticAlwaysHiddenMutation"))
        #expect(verifierSource.contains("classifyItemsForMoveVerification"))
        #expect(taskSource.contains("applyQueuedAlwaysHiddenMutation(optimisticAlwaysHiddenMutation)"))
        #expect(taskSource.contains("lastManualZoneMoveSettledAt"))

        #expect(iconPanelSource.contains("queueZoneMoveAfterDrop("))
        #expect(iconPanelSource.contains("physicalMoveOrigin: .explicitUserAction"))
        #expect(iconPanelSource.contains("guard let request = zoneMoveRequest("))
        #expect(iconPanelSource.contains("let moved = await task.value"))
        #expect(iconPanelSource.contains("queueMoveAfterDrop"))
        #expect(iconPanelSource.contains("queueReorderAfterDrop"))
        #expect(iconPanelSource.contains("await Task.yield()"))
        #expect(!iconPanelSource.contains("moveQueueWorkflow.queueZoneMove(\n"))
        #expect(!iconPanelSource.contains("pinAlwaysHidden(app: app)"))
        #expect(!iconPanelSource.contains("unpinAlwaysHidden(app: app)"))

        #expect(secondMenuBarSource.contains("queueZoneMoveAfterDrop("))
        #expect(secondMenuBarSource.contains("queueReorderIcon("))
        #expect(secondMenuBarSource.contains("physicalMoveOrigin: .explicitUserAction"))
        #expect(secondMenuBarSource.contains("guard let request = zoneMoveRequest("))
        #expect(secondMenuBarSource.contains("let moved = await task.value"))
        #expect(secondMenuBarSource.contains("applySuccessfulMovePresentation"))
        #expect(secondMenuBarSource.contains("queueMoveAfterDrop"))
        #expect(secondMenuBarSource.contains("await Task.yield()"))
        #expect(!secondMenuBarSource.contains("moveQueueWorkflow.queueZoneMove(\n"))
        #expect(!secondMenuBarSource.contains("pinAlwaysHidden(app: app)"))
        #expect(!secondMenuBarSource.contains("unpinAlwaysHidden(app: app)"))
        #expect(!secondMenuBarSource.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.3)"))
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
        let result = manager.alwaysHiddenPinWorkflow.isInZone(itemX: 30, itemWidth: 22, alwaysHiddenSeparatorX: 100)
        #expect(result == true)
    }

    @Test("Item clearly outside AH zone detected correctly")
    @MainActor
    func itemOutsideAHZone() {
        let manager = MenuBarManager.shared
        // Item at x=200, width=22 → midX=211. AH separator at x=100.
        // midX(211) < (100 - 6.6 = 93.4) → false → NOT in AH zone
        let result = manager.alwaysHiddenPinWorkflow.isInZone(itemX: 200, itemWidth: 22, alwaysHiddenSeparatorX: 100)
        #expect(result == false)
    }

    @Test("Item at AH separator edge respects margin")
    @MainActor
    func itemAtAHEdge() {
        let manager = MenuBarManager.shared
        // Item at x=80, width=22 → midX=91. AH separator at x=100. margin=6.6
        // midX(91) < (100 - 6.6 = 93.4) → true → in AH zone
        let inZone = manager.alwaysHiddenPinWorkflow.isInZone(itemX: 80, itemWidth: 22, alwaysHiddenSeparatorX: 100)
        #expect(inZone == true)

        // Item at x=90, width=22 → midX=101. 101 < 93.4 → false → NOT in AH zone
        let outsideZone = manager.alwaysHiddenPinWorkflow.isInZone(itemX: 90, itemWidth: 22, alwaysHiddenSeparatorX: 100)
        #expect(outsideZone == false)
    }

    @Test("Nil width defaults to 22")
    @MainActor
    func nilWidthDefaultsInAHCheck() {
        let manager = MenuBarManager.shared
        // width nil → max(1, 22) = 22, midX = 30 + 11 = 41. margin = max(4, 22*0.3) = 6.6
        let result = manager.alwaysHiddenPinWorkflow.isInZone(itemX: 30, itemWidth: nil, alwaysHiddenSeparatorX: 100)
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

        manager.alwaysHiddenPinWorkflow.pin(app: app)
        #expect(!manager.settings.alwaysHiddenPinnedItemIds.isEmpty)

        manager.alwaysHiddenPinWorkflow.unpin(app: app)
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

        manager.alwaysHiddenPinWorkflow.pin(app: app)
        let countAfterFirst = manager.settings.alwaysHiddenPinnedItemIds.count

        manager.alwaysHiddenPinWorkflow.pin(app: app)
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
