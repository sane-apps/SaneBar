import XCTest
@testable import SaneBar

final class SecondMenuBarDropXCTests: XCTestCase {
    func testSourceResolutionFindsVisibleApp() {
        let app = RunningApp(id: "com.example.visible", name: "Visible", icon: nil)
        let source = SecondMenuBarDropResolver.sourceForDragID(
            app.uniqueId,
            visible: [app],
            hidden: [],
            alwaysHidden: []
        )
        XCTAssertNotNil(source)
        XCTAssertEqual(source?.app.uniqueId, app.uniqueId)
        if let zone = source?.zone {
            switch zone {
            case .visible:
                break
            default:
                XCTFail("Expected visible zone")
            }
        }
    }

    func testSourceResolutionFindsHiddenApp() {
        let app = RunningApp(id: "com.example.hidden", name: "Hidden", icon: nil)
        let source = SecondMenuBarDropResolver.sourceForDragID(
            app.uniqueId,
            visible: [],
            hidden: [app],
            alwaysHidden: []
        )
        XCTAssertNotNil(source)
        if let zone = source?.zone {
            switch zone {
            case .hidden:
                break
            default:
                XCTFail("Expected hidden zone")
            }
        }
    }

    func testSourceResolutionFindsAlwaysHiddenApp() {
        let app = RunningApp(id: "com.example.alwaysHidden", name: "AlwaysHidden", icon: nil)
        let source = SecondMenuBarDropResolver.sourceForDragID(
            app.uniqueId,
            visible: [],
            hidden: [],
            alwaysHidden: [app]
        )
        XCTAssertNotNil(source)
        if let zone = source?.zone {
            switch zone {
            case .alwaysHidden:
                break
            default:
                XCTFail("Expected always hidden zone")
            }
        }
    }

    func testSourceResolutionReturnsNilForUnknownID() {
        let source = SecondMenuBarDropResolver.sourceForDragID(
            "com.unknown",
            visible: [RunningApp(id: "com.example.visible", name: "Visible", icon: nil)],
            hidden: [RunningApp(id: "com.example.hidden", name: "Hidden", icon: nil)],
            alwaysHidden: [RunningApp(id: "com.example.alwaysHidden", name: "AlwaysHidden", icon: nil)]
        )
        XCTAssertNil(source)
    }

    func testVisibleZoneAlwaysShownWhenSettingEnabled() {
        XCTAssertTrue(
            SecondMenuBarLayout.shouldShowVisibleZone(
                includeVisibleIcons: true,
                hiddenCount: 0,
                alwaysHiddenCount: 0
            )
        )
    }

    func testVisibleZoneShownAsDropTargetWhenSettingDisabledButHiddenItemsExist() {
        XCTAssertTrue(
            SecondMenuBarLayout.shouldShowVisibleZone(
                includeVisibleIcons: false,
                hiddenCount: 2,
                alwaysHiddenCount: 0
            )
        )
    }

    func testVisibleZoneShownAsDropTargetWhenSettingDisabledButAlwaysHiddenItemsExist() {
        XCTAssertTrue(
            SecondMenuBarLayout.shouldShowVisibleZone(
                includeVisibleIcons: false,
                hiddenCount: 0,
                alwaysHiddenCount: 1
            )
        )
    }

    func testVisibleZoneHiddenWhenSettingDisabledAndNoMovableHiddenItems() {
        XCTAssertFalse(
            SecondMenuBarLayout.shouldShowVisibleZone(
                includeVisibleIcons: false,
                hiddenCount: 0,
                alwaysHiddenCount: 0
            )
        )
    }
}
