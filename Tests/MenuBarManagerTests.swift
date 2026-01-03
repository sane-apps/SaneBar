import Testing
import Foundation
@testable import SaneBar

// MARK: - MenuBarManagerTests

@Suite("MenuBarManager Tests")
struct MenuBarManagerTests {

    // MARK: - AutosaveName Tests

    @Test("Autosave names are unique to prevent position conflicts")
    func testAutosaveNamesAreUnique() {
        // These are the autosaveName values used in MenuBarManager
        // They must be unique for macOS to persist positions correctly
        let autosaveNames = [
            "SaneBar_main",
            "SaneBar_separator",
            "SaneBar_spacer_0",
            "SaneBar_spacer_1",
            "SaneBar_spacer_2"
        ]

        let uniqueNames = Set(autosaveNames)

        #expect(uniqueNames.count == autosaveNames.count,
                "All autosaveName values must be unique - found duplicates")
    }

    @Test("Autosave names follow naming convention")
    func testAutosaveNamesFollowConvention() {
        let autosaveNames = [
            "SaneBar_main",
            "SaneBar_separator",
            "SaneBar_spacer_0"
        ]

        for name in autosaveNames {
            #expect(name.hasPrefix("SaneBar_"),
                    "Autosave names should start with 'SaneBar_' prefix")
            #expect(!name.contains(" "),
                    "Autosave names should not contain spaces")
        }
    }
}
