import XCTest
@testable import SaneBar

@MainActor
final class MenuBarSearchDropXCTests: XCTestCase {
    func testSourceResolutionPrefersClassifiedLists() {
        let hiddenApp = RunningApp(
            id: "com.example.tool",
            name: "Tool Hidden",
            icon: nil,
            menuExtraIdentifier: "com.example.tool.item",
            xPosition: nil
        )
        let visibleApp = RunningApp(
            id: "com.example.tool",
            name: "Tool Visible",
            icon: nil,
            statusItemIndex: 0,
            xPosition: 800
        )

        let classified = SearchClassifiedApps(
            visible: [visibleApp],
            hidden: [hiddenApp],
            alwaysHidden: [RunningApp]()
        )

        let resolved = MenuBarSearchView.sourceForDropPayload(hiddenApp.uniqueId, classified: classified)
        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.app.uniqueId, hiddenApp.uniqueId)
        if let zone = resolved?.zone {
            switch zone {
            case .hidden:
                break
            default:
                XCTFail("Expected hidden zone for hidden payload source")
            }
        }
    }

    func testSourceResolutionReturnsNilForUnknownPayload() {
        let classified = SearchClassifiedApps(
            visible: [RunningApp(id: "com.example.one", name: "One", icon: nil)],
            hidden: [RunningApp(id: "com.example.two", name: "Two", icon: nil)],
            alwaysHidden: [RunningApp]()
        )

        let resolved = MenuBarSearchView.sourceForDropPayload("com.unknown.app", classified: classified)
        XCTAssertNil(resolved)
    }

    func testSourceResolutionFallsBackToFilteredAppsWhenCacheMisses() {
        let hiddenApp = RunningApp(
            id: "com.example.hidden",
            name: "Hidden App",
            icon: nil,
            statusItemIndex: 3
        )
        let classified = SearchClassifiedApps(
            visible: [RunningApp](),
            hidden: [RunningApp](),
            alwaysHidden: [RunningApp]()
        )

        let resolved = MenuBarSearchView.sourceForDropPayload(
            hiddenApp.uniqueId,
            classified: classified,
            filteredApps: [hiddenApp],
            mode: .hidden
        )

        XCTAssertNotNil(resolved)
        XCTAssertEqual(resolved?.app.uniqueId, hiddenApp.uniqueId)
        if let zone = resolved?.zone {
            switch zone {
            case .hidden:
                break
            default:
                XCTFail("Expected hidden zone when fallback uses hidden tab context")
            }
        }
    }

    func testSourceResolutionUsesAllModeZoneClassifierOnFallback() {
        let app = RunningApp(
            id: "com.example.all",
            name: "All Mode App",
            icon: nil,
            statusItemIndex: 2
        )
        let classified = SearchClassifiedApps(
            visible: [RunningApp](),
            hidden: [RunningApp](),
            alwaysHidden: [RunningApp]()
        )

        let resolved = MenuBarSearchView.sourceForDropPayload(
            app.uniqueId,
            classified: classified,
            filteredApps: [app],
            mode: .all,
            zoneForAllMode: { _ in .alwaysHidden }
        )

        XCTAssertNotNil(resolved)
        if let zone = resolved?.zone {
            switch zone {
            case .alwaysHidden:
                break
            default:
                XCTFail("Expected zone classifier result for all-mode fallback")
            }
        }
    }

    func testBundleIdExtractionFromPayload() {
        XCTAssertEqual(
            MenuBarSearchView.bundleIDFromPayload("com.apple.controlcenter::statusItem:1"),
            "com.apple.controlcenter"
        )
        XCTAssertEqual(
            MenuBarSearchView.bundleIDFromPayload("com.apple.menuextra.battery"),
            "com.apple.menuextra.battery"
        )
    }

    func testAllTabBoundaryPrefersSeparatorRightEdge() {
        let boundary = MenuBarSearchView.separatorBoundaryForAllTabClassification(
            separatorRightEdgeX: 1205,
            separatorOriginX: 454
        )
        XCTAssertEqual(boundary, 1205)
    }

    func testAllTabBoundaryFallsBackToOrigin() {
        let boundary = MenuBarSearchView.separatorBoundaryForAllTabClassification(
            separatorRightEdgeX: nil,
            separatorOriginX: 1170
        )
        XCTAssertEqual(boundary, 1170)
    }

    func testAllTabClassificationIgnoresAlwaysHiddenSeparatorWhenMisordered() {
        let zone = MenuBarSearchView.classifyAllTabZone(
            midX: 320,
            separatorBoundaryX: 1200,
            alwaysHiddenSeparatorX: 1400
        )

        switch zone {
        case .hidden:
            break
        default:
            XCTFail("Expected hidden when AH separator is not left of main separator")
        }
    }

    func testAllTabClassificationUsesAlwaysHiddenWhenOrdered() {
        let zone = MenuBarSearchView.classifyAllTabZone(
            midX: 180,
            separatorBoundaryX: 1200,
            alwaysHiddenSeparatorX: 250
        )

        switch zone {
        case .alwaysHidden:
            break
        default:
            XCTFail("Expected alwaysHidden when item midpoint is left of AH separator")
        }
    }

    func testVisibleLaneCrowdingHintStaysQuietWhenLaneHasRoom() {
        let visibleApps = [
            RunningApp(
                id: "com.example.one",
                name: "One",
                icon: nil,
                statusItemIndex: 0,
                xPosition: 1200,
                width: 24
            ),
            RunningApp(
                id: "com.example.two",
                name: "Two",
                icon: nil,
                statusItemIndex: 1,
                xPosition: 1240,
                width: 24
            )
        ]
        let movedApp = RunningApp(
            id: "com.example.three",
            name: "Three",
            icon: nil,
            statusItemIndex: 2,
            xPosition: 1280,
            width: 24
        )

        XCTAssertFalse(
            MenuBarSearchView.shouldSuggestSecondMenuBarForVisibleLane(
                visibleApps: visibleApps,
                movedApp: movedApp,
                separatorRightEdgeX: 1100,
                mainLeftEdgeX: 1400
            )
        )
    }

    func testVisibleLaneCrowdingHintTriggersWhenLaneIsNearlyFull() {
        let visibleApps = [
            RunningApp(
                id: "com.example.one",
                name: "One",
                icon: nil,
                statusItemIndex: 0,
                xPosition: 1180,
                width: 28
            ),
            RunningApp(
                id: "com.example.two",
                name: "Two",
                icon: nil,
                statusItemIndex: 1,
                xPosition: 1220,
                width: 28
            ),
            RunningApp(
                id: "com.example.three",
                name: "Three",
                icon: nil,
                statusItemIndex: 2,
                xPosition: 1260,
                width: 28
            ),
            RunningApp(
                id: "com.example.four",
                name: "Four",
                icon: nil,
                statusItemIndex: 3,
                xPosition: 1300,
                width: 28
            )
        ]
        let movedApp = RunningApp(
            id: "com.example.five",
            name: "Five",
            icon: nil,
            statusItemIndex: 4,
            xPosition: 1340,
            width: 28
        )

        XCTAssertTrue(
            MenuBarSearchView.shouldSuggestSecondMenuBarForVisibleLane(
                visibleApps: visibleApps,
                movedApp: movedApp,
                separatorRightEdgeX: 1100,
                mainLeftEdgeX: 1265
            )
        )
    }
}
