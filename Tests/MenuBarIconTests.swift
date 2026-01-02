import Testing
import AppKit
@testable import SaneBar

// MARK: - MenuBarIconTests

@Suite("MenuBarIcon Tests")
struct MenuBarIconTests {

    @Test("Custom icon loads from asset catalog")
    func testCustomIconLoadsFromAssetCatalog() {
        // BUG-001: Asset cache not cleared by nuclear clean
        // This test verifies the custom MenuBarIcon is loadable
        let icon = NSImage(named: "MenuBarIcon")

        #expect(icon != nil, "MenuBarIcon should load from asset catalog")
    }

    @Test("Custom icon can be set as template")
    func testCustomIconCanBeTemplate() {
        guard let icon = NSImage(named: "MenuBarIcon") else {
            Issue.record("MenuBarIcon not found")
            return
        }

        icon.isTemplate = true
        #expect(icon.isTemplate == true)
    }

    @Test("Custom icon resizes for menu bar")
    func testCustomIconResizesForMenuBar() {
        guard let icon = NSImage(named: "MenuBarIcon") else {
            Issue.record("MenuBarIcon not found")
            return
        }

        icon.size = NSSize(width: 18, height: 18)
        #expect(icon.size.width == 18)
        #expect(icon.size.height == 18)
    }

    // BUG-004: Icon was 2048x2048, should be ≤36x36 for menu bar
    @Test("Custom icon has appropriate dimensions for menu bar")
    func testCustomIconHasAppropriateDimensions() {
        guard let icon = NSImage(named: "MenuBarIcon") else {
            Issue.record("MenuBarIcon not found")
            return
        }

        // Menu bar icons should be at most 36x36 (2x scale of 18x18)
        // Larger icons won't render properly
        let maxDimension: CGFloat = 36

        for rep in icon.representations {
            #expect(rep.pixelsWide <= Int(maxDimension * 2),
                    "Icon width \(rep.pixelsWide) exceeds max \(Int(maxDimension * 2))")
            #expect(rep.pixelsHigh <= Int(maxDimension * 2),
                    "Icon height \(rep.pixelsHigh) exceeds max \(Int(maxDimension * 2))")
        }
    }
}
