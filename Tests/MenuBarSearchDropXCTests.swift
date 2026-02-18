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

        let classified = (
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
        let classified = (
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
        let classified = (
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
        let classified = (
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
}
