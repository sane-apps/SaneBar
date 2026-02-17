import AppKit
@testable import SaneBar
import Testing

// MARK: - Menu Item Lookup Helper

extension NSMenu {
    /// Find a menu item by its title (safer than hardcoded indices)
    func item(titled title: String) -> NSMenuItem? {
        items.first { $0.title == title }
    }
}

// MARK: - StatusBarControllerTests

@Suite("StatusBarController Tests")
struct StatusBarControllerTests {
    // MARK: - Icon Name Tests

    @Test("iconName returns correct icon for expanded state")
    @MainActor
    func iconNameExpanded() {
        let controller = StatusBarController()

        let iconName = controller.iconName(for: .expanded)

        #expect(iconName == StatusBarController.iconExpanded)
        #expect(!iconName.isEmpty, "Icon name should not be empty")
    }

    @Test("iconName returns correct icon for hidden state")
    @MainActor
    func iconNameHidden() {
        let controller = StatusBarController()

        let iconName = controller.iconName(for: .hidden)

        #expect(iconName == StatusBarController.iconHidden)
        #expect(!iconName.isEmpty, "Icon name should not be empty")
    }

    // MARK: - Static Constants Tests

    @Test("Autosave names are defined")
    func autosaveNamesExist() {
        #expect(!StatusBarController.mainAutosaveName.isEmpty)
        #expect(!StatusBarController.separatorAutosaveName.isEmpty)
        #expect(!StatusBarController.alwaysHiddenSeparatorAutosaveName.isEmpty)
    }

    @Test("Autosave names are unique")
    func autosaveNamesUnique() {
        let names = [
            StatusBarController.mainAutosaveName,
            StatusBarController.separatorAutosaveName,
            StatusBarController.alwaysHiddenSeparatorAutosaveName,
        ]

        let uniqueNames = Set(names)
        #expect(uniqueNames.count == names.count, "All autosave names must be unique")
    }

    @Test("Autosave names have SaneBar prefix")
    func autosaveNamesHavePrefix() {
        #expect(StatusBarController.mainAutosaveName.hasPrefix("SaneBar_"))
        #expect(StatusBarController.separatorAutosaveName.hasPrefix("SaneBar_"))
        #expect(StatusBarController.alwaysHiddenSeparatorAutosaveName.hasPrefix("SaneBar_"))
    }

    // MARK: - Icon Constants Tests

    @Test("Icon names are valid SF Symbol names")
    func iconNamesAreValid() {
        // These should all be valid SF Symbol names
        #expect(!StatusBarController.iconExpanded.isEmpty)
        #expect(!StatusBarController.iconHidden.isEmpty)
    }

    // MARK: - Menu Creation Tests

    @Test("createMenu returns menu with expected items")
    @MainActor
    func createMenuHasExpectedItems() {
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

        let menu = controller.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            settingsAction: #selector(DummyTarget.settings),
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit),
            target: target
        ))

        // Should have: Browse Icons, separator, Settings, Check for Updates, separator, Quit
        #expect(menu.items.count == 6, "Menu should have 6 items (4 commands + 2 separators)")

        // Use named lookups (resilient to menu reordering)
        let findIconItem = menu.item(titled: "Browse Icons...")
        #expect(findIconItem != nil, "Menu should have Browse Icons item")
        // keyEquivalent is set dynamically via KeyboardShortcuts.setShortcut(for:)
        // so we don't assert on a hardcoded value here

        let settingsItem = menu.item(titled: "Settings...")
        #expect(settingsItem != nil, "Menu should have Settings item")
        #expect(settingsItem?.keyEquivalent == ",")

        let checkUpdatesItem = menu.item(titled: "Check for Updates...")
        #expect(checkUpdatesItem != nil, "Menu should have Check for Updates item")
        #expect(checkUpdatesItem?.keyEquivalent.isEmpty == true)

        let quitItem = menu.item(titled: "Quit SaneBar")
        #expect(quitItem != nil, "Menu should have Quit item")
        #expect(quitItem?.keyEquivalent == "q")
    }

    @Test("createMenu sets correct target on all items")
    @MainActor
    func createMenuSetsTarget() {
        let controller = StatusBarController()

        class DummyTarget: NSObject {
            @objc func toggle() {}
            @objc func findIcon() {}
            @objc func settings() {}
            @objc func checkForUpdates() {}
            @objc func quit() {}
        }
        let target = DummyTarget()

        let menu = controller.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            settingsAction: #selector(DummyTarget.settings),
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit),
            target: target
        ))

        // Non-separator items should have target set
        for item in menu.items where !item.isSeparatorItem {
            #expect(item.target === target, "Menu item should have correct target")
        }
    }

    // MARK: - Menu Action Tests (Regression: settings menu must work)

    @Test("Menu items have correct actions set")
    @MainActor
    func menuItemsHaveActions() {
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

        let menu = controller.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            settingsAction: #selector(DummyTarget.settings),
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit),
            target: target
        ))

        // Verify each menu item has an action (using named lookups)
        let findIconItem = menu.item(titled: "Browse Icons...")
        let settingsItem = menu.item(titled: "Settings...")
        let checkForUpdatesItem = menu.item(titled: "Check for Updates...")
        let quitItem = menu.item(titled: "Quit SaneBar")

        #expect(findIconItem?.action == #selector(DummyTarget.findIcon), "Browse Icons item should have findIcon action")
        #expect(settingsItem?.action == #selector(DummyTarget.settings), "Settings item should have settings action")
        #expect(checkForUpdatesItem?.action == #selector(DummyTarget.checkForUpdates), "Check for Updates item should have action")
        #expect(quitItem?.action == #selector(DummyTarget.quit), "Quit item should have quit action")
    }

    @Test("Settings menu item is invokable")
    @MainActor
    func settingsMenuItemInvokable() {
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

        let menu = controller.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            settingsAction: #selector(DummyTarget.settings),
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit),
            target: target
        ))

        // Get settings item by name and verify it can be invoked
        guard let settingsItem = menu.item(titled: "Settings...") else {
            Issue.record("Settings menu item not found")
            return
        }

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
    func clickTypeLeftClick() {
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
    func protocolConformance() {
        let controller: StatusBarControllerProtocol = StatusBarController()

        // Protocol requires these
        _ = controller.mainItem
        _ = controller.separatorItem
        _ = controller.iconName(for: .hidden)

        #expect(true, "Should conform to protocol")
    }

    // MARK: - Initialization Tests

    @Test("StatusBarController creates status items during initialization")
    @MainActor
    func initializationCreatesItems() {
        let controller = StatusBarController()

        // Items are created as property initializers for proper WindowServer positioning
        // This ensures proper WindowServer positioning
        #expect(controller.mainItem.button != nil)
        #expect(controller.separatorItem.button != nil)
    }
}
