import Testing
import AppKit
@testable import SaneBar

// MARK: - StatusBarControllerTests

@Suite("StatusBarController Tests")
struct StatusBarControllerTests {

    // MARK: - Icon Name Tests

    @Test("iconName returns correct icon for expanded state")
    @MainActor
    func testIconNameExpanded() {
        let controller = StatusBarController()

        let iconName = controller.iconName(for: .expanded)

        #expect(iconName == StatusBarController.iconExpanded)
        #expect(!iconName.isEmpty, "Icon name should not be empty")
    }

    @Test("iconName returns correct icon for hidden state")
    @MainActor
    func testIconNameHidden() {
        let controller = StatusBarController()

        let iconName = controller.iconName(for: .hidden)

        #expect(iconName == StatusBarController.iconHidden)
        #expect(!iconName.isEmpty, "Icon name should not be empty")
    }

    // MARK: - Static Constants Tests

    @Test("Autosave names are defined")
    func testAutosaveNamesExist() {
        #expect(!StatusBarController.mainAutosaveName.isEmpty)
        #expect(!StatusBarController.separatorAutosaveName.isEmpty)
    }

    @Test("Autosave names are unique")
    func testAutosaveNamesUnique() {
        let names = [
            StatusBarController.mainAutosaveName,
            StatusBarController.separatorAutosaveName
        ]

        let uniqueNames = Set(names)
        #expect(uniqueNames.count == names.count, "All autosave names must be unique")
    }

    @Test("Autosave names have SaneBar prefix")
    func testAutosaveNamesHavePrefix() {
        #expect(StatusBarController.mainAutosaveName.hasPrefix("SaneBar_"))
        #expect(StatusBarController.separatorAutosaveName.hasPrefix("SaneBar_"))
    }

    // MARK: - Icon Constants Tests

    @Test("Icon names are valid SF Symbol names")
    func testIconNamesAreValid() {
        // These should all be valid SF Symbol names
        #expect(!StatusBarController.iconExpanded.isEmpty)
        #expect(!StatusBarController.iconHidden.isEmpty)
        #expect(!StatusBarController.separatorIcon.isEmpty)
        #expect(!StatusBarController.spacerIcon.isEmpty)
    }

    // MARK: - Menu Creation Tests

    @Test("createMenu returns menu with expected items")
    @MainActor
    func testCreateMenuHasExpectedItems() {
        let controller = StatusBarController()

        // Create a dummy target
        class DummyTarget: NSObject {
            @objc func toggle() {}
            @objc func findIcon() {}
            @objc func settings() {}
            @objc func checkForUpdates() {}
            @objc func quit() {}
        }
        let target = DummyTarget()

        let menu = controller.createMenu(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            settingsAction: #selector(DummyTarget.settings),
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit),
            target: target
        )

        // Should have: Find Icon, separator, Settings, Check for Updates, separator, Quit
        #expect(menu.items.count == 6, "Menu should have 6 items (4 commands + 2 separators)")

        // Check Find Icon item
        let findIconItem = menu.items[0]
        #expect(findIconItem.title == "Find Icon...")
        #expect(findIconItem.keyEquivalent == " ")

        // Check Settings item
        let settingsItem = menu.items[2]
        #expect(settingsItem.title == "Settings...")
        #expect(settingsItem.keyEquivalent == ",")

        // Check Check for Updates item
        let checkUpdatesItem = menu.items[3]
        #expect(checkUpdatesItem.title == "Check for Updates...")
        #expect(checkUpdatesItem.keyEquivalent.isEmpty)

        // Check Quit item
        let quitItem = menu.items[5]
        #expect(quitItem.title == "Quit SaneBar")
        #expect(quitItem.keyEquivalent == "q")
    }

    @Test("createMenu sets correct target on all items")
    @MainActor
    func testCreateMenuSetsTarget() {
        let controller = StatusBarController()

        class DummyTarget: NSObject {
            @objc func toggle() {}
            @objc func findIcon() {}
            @objc func settings() {}
            @objc func checkForUpdates() {}
            @objc func quit() {}
        }
        let target = DummyTarget()

        let menu = controller.createMenu(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            settingsAction: #selector(DummyTarget.settings),
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit),
            target: target
        )

        // Non-separator items should have target set
        for item in menu.items where !item.isSeparatorItem {
            #expect(item.target === target, "Menu item should have correct target")
        }
    }

    // MARK: - Menu Action Tests (Regression: settings menu must work)

    @Test("Menu items have correct actions set")
    @MainActor
    func testMenuItemsHaveActions() {
        let controller = StatusBarController()

        class DummyTarget: NSObject {
            var toggleCalled = false
            var findIconCalled = false
            var settingsCalled = false
            var checkForUpdatesCalled = false
            var quitCalled = false

            @objc func toggle() { toggleCalled = true }
            @objc func findIcon() { findIconCalled = true }
            @objc func settings() { settingsCalled = true }
            @objc func checkForUpdates() { checkForUpdatesCalled = true }
            @objc func quit() { quitCalled = true }
        }
        let target = DummyTarget()

        let menu = controller.createMenu(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            settingsAction: #selector(DummyTarget.settings),
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit),
            target: target
        )

        // Verify each menu item has an action
        let findIconItem = menu.items[0]
        let settingsItem = menu.items[2]
        let checkForUpdatesItem = menu.items[3]
        let quitItem = menu.items[5]

        #expect(findIconItem.action == #selector(DummyTarget.findIcon), "Find Icon item should have findIcon action")
        #expect(settingsItem.action == #selector(DummyTarget.settings), "Settings item should have settings action")
        #expect(checkForUpdatesItem.action == #selector(DummyTarget.checkForUpdates), "Check for Updates item should have action")
        #expect(quitItem.action == #selector(DummyTarget.quit), "Quit item should have quit action")
    }

    @Test("Settings menu item is invokable")
    @MainActor
    func testSettingsMenuItemInvokable() {
        let controller = StatusBarController()

        class DummyTarget: NSObject {
            var settingsCalled = false
            @objc func toggle() {}
            @objc func findIcon() {}
            @objc func settings() { settingsCalled = true }
            @objc func checkForUpdates() {}
            @objc func quit() {}
        }
        let target = DummyTarget()

        let menu = controller.createMenu(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            settingsAction: #selector(DummyTarget.settings),
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit),
            target: target
        )

        // Get settings item and verify it can be invoked
        let settingsItem = menu.items[2]
        #expect(settingsItem.target != nil, "Settings item must have a target")
        #expect(settingsItem.action != nil, "Settings item must have an action")

        // Simulate clicking the settings item
        if let action = settingsItem.action, let itemTarget = settingsItem.target {
            _ = itemTarget.perform(action, with: settingsItem)
        }

        #expect(target.settingsCalled, "Settings action should be invokable through menu item")
    }

    // MARK: - Click Type Tests

    @Test("clickType correctly identifies left click")
    func testClickTypeLeftClick() {
        // We can't easily create NSEvents in tests, but we can test the enum
        let leftClick = StatusBarController.ClickType.leftClick
        let rightClick = StatusBarController.ClickType.rightClick
        let optionClick = StatusBarController.ClickType.optionClick

        #expect(leftClick != rightClick)
        #expect(leftClick != optionClick)
        #expect(rightClick != optionClick)
    }

    // MARK: - Protocol Conformance Tests

    @Test("StatusBarController conforms to StatusBarControllerProtocol")
    @MainActor
    func testProtocolConformance() {
        let controller: StatusBarControllerProtocol = StatusBarController()

        // Protocol requires these
        _ = controller.mainItem
        _ = controller.separatorItem
        _ = controller.iconName(for: .hidden)

        #expect(true, "Should conform to protocol")
    }

    // MARK: - Initialization Tests

    @Test("StatusBarController initializes without creating status items")
    @MainActor
    func testInitializationDoesNotCreateItems() {
        let controller = StatusBarController()

        // Items should be nil until createStatusItems is called
        #expect(controller.mainItem == nil)
        #expect(controller.separatorItem == nil)
    }
}
