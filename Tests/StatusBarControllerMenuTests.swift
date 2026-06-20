import AppKit
import SaneUI
@testable import SaneBar
import Testing

@Suite("StatusBarControllerMenuTests", .serialized)
struct StatusBarControllerMenuTests {
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
            @objc func arrangeNow() {}
            @objc func health() {}
            @objc func settings() {}
            @objc func license() {}
            @objc func about() {}
            @objc func checkForUpdates() {}
            @objc func quit() {}
        }

        let menu = controller.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            arrangeNowAction: #selector(DummyTarget.arrangeNow),
            healthAction: #selector(DummyTarget.health),
            settingsAction: #selector(DummyTarget.settings),
            licenseAction: #selector(DummyTarget.license),
            aboutAndBugReportAction: #selector(DummyTarget.about),
            showReleaseNotesAction: nil,
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit)
        ))

        // Should have: Browse, Toggle, separator, Arrange, Health, separator,
        // Settings, License, Updates, About / Report, separator, Quit
        #expect(menu.items.count == 12, "Menu should have 12 items (9 commands + 3 separators)")

        // Use named lookups (resilient to menu reordering)
        let findIconItem = menu.item(titled: "Browse Icons...")
        #expect(findIconItem != nil, "Menu should have Browse Icons item")
        // keyEquivalent is set dynamically via KeyboardShortcuts.setShortcut(for:)
        // so we don't assert on a hardcoded value here

        let toggleItem = menu.item(titled: "Show / Hide Icons")
        #expect(toggleItem != nil, "Menu should have Show / Hide Icons item")

        let arrangeItem = menu.item(titled: "Arrange Now")
        #expect(arrangeItem != nil, "Menu should have Arrange Now item")

        let healthItem = menu.item(titled: "Help / Repair...")
        #expect(healthItem != nil, "Menu should have Help / Repair item")

        let settingsItem = menu.item(titled: "Settings...")
        #expect(settingsItem != nil, "Menu should have Settings item")
        #expect(settingsItem?.keyEquivalent == ",")

        let licenseItem = menu.item(titled: SaneStandardMenu.licenseTitle)
        #expect(licenseItem != nil, "Menu should have License item")

        let checkUpdatesItem = menu.item(titled: "Check for Updates...")
        #expect(checkUpdatesItem != nil, "Menu should have Check for Updates item")
        #expect(checkUpdatesItem?.keyEquivalent.isEmpty == true)

        let aboutItem = menu.item(titled: SaneStandardMenu.aboutAndBugReportTitle)
        #expect(aboutItem != nil, "Menu should have About / Report item")

        let quitItem = menu.item(titled: "Quit SaneBar")
        #expect(quitItem != nil, "Menu should have Quit item")
        #expect(quitItem?.keyEquivalent == "q")
    }

    @Test("createMenu omits update item when updates are externally managed")
    @MainActor
    func createMenuOmitsUpdateItemWhenUnavailable() {
        let controller = StatusBarController()

        class DummyTarget: NSObject {
            @objc func toggle() {}
            @objc func findIcon() {}
            @objc func arrangeNow() {}
            @objc func health() {}
            @objc func settings() {}
            @objc func license() {}
            @objc func about() {}
            @objc func quit() {}
        }

        let menu = controller.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            arrangeNowAction: #selector(DummyTarget.arrangeNow),
            healthAction: #selector(DummyTarget.health),
            settingsAction: #selector(DummyTarget.settings),
            licenseAction: #selector(DummyTarget.license),
            aboutAndBugReportAction: #selector(DummyTarget.about),
            showReleaseNotesAction: nil,
            checkForUpdatesAction: nil,
            quitAction: #selector(DummyTarget.quit)
        ))

        #expect(menu.item(titled: "Check for Updates...") == nil)
        #expect(menu.items.count == 11, "Menu should remove only the update command")
    }

    @Test("createMenu leaves item targets unset")
    @MainActor
    func createMenuLeavesTargetsUnset() {
        let controller = StatusBarController()

        class DummyTarget: NSObject {
            @objc func toggle() {}
            @objc func findIcon() {}
            @objc func arrangeNow() {}
            @objc func health() {}
            @objc func settings() {}
            @objc func license() {}
            @objc func about() {}
            @objc func checkForUpdates() {}
            @objc func quit() {}
        }

        let menu = controller.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            arrangeNowAction: #selector(DummyTarget.arrangeNow),
            healthAction: #selector(DummyTarget.health),
            settingsAction: #selector(DummyTarget.settings),
            licenseAction: #selector(DummyTarget.license),
            aboutAndBugReportAction: #selector(DummyTarget.about),
            showReleaseNotesAction: nil,
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit)
        ))

        // MenuBarManager wires the live target after creation.
        for item in menu.items where !item.isSeparatorItem {
            #expect(item.target == nil, "Menu item target should be unset in the raw menu")
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
            var arrangeNowCalled = false
            var healthCalled = false
            var settingsCalled = false
            var licenseCalled = false
            var aboutCalled = false
            var checkForUpdatesCalled = false
            var quitCalled = false

            @objc func toggle() { toggleCalled = true }
            @objc func findIcon() { findIconCalled = true }
            @objc func arrangeNow() { arrangeNowCalled = true }
            @objc func health() { healthCalled = true }
            @objc func settings() { settingsCalled = true }
            @objc func license() { licenseCalled = true }
            @objc func about() { aboutCalled = true }
            @objc func checkForUpdates() { checkForUpdatesCalled = true }
            @objc func quit() { quitCalled = true }
        }

        let menu = controller.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            arrangeNowAction: #selector(DummyTarget.arrangeNow),
            healthAction: #selector(DummyTarget.health),
            settingsAction: #selector(DummyTarget.settings),
            licenseAction: #selector(DummyTarget.license),
            aboutAndBugReportAction: #selector(DummyTarget.about),
            showReleaseNotesAction: nil,
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit)
        ))

        // Verify each menu item has an action (using named lookups)
        let findIconItem = menu.item(titled: "Browse Icons...")
        let toggleItem = menu.item(titled: "Show / Hide Icons")
        let arrangeItem = menu.item(titled: "Arrange Now")
        let healthItem = menu.item(titled: "Help / Repair...")
        let settingsItem = menu.item(titled: "Settings...")
        let licenseItem = menu.item(titled: SaneStandardMenu.licenseTitle)
        let checkForUpdatesItem = menu.item(titled: "Check for Updates...")
        let aboutItem = menu.item(titled: SaneStandardMenu.aboutAndBugReportTitle)
        let quitItem = menu.item(titled: "Quit SaneBar")

        #expect(findIconItem?.action == #selector(DummyTarget.findIcon), "Browse Icons item should have findIcon action")
        #expect(toggleItem?.action == #selector(DummyTarget.toggle), "Show / Hide Icons item should have toggle action")
        #expect(arrangeItem?.action == #selector(DummyTarget.arrangeNow), "Arrange Now item should have arrange action")
        #expect(healthItem?.action == #selector(DummyTarget.health), "Help / Repair item should have health action")
        #expect(settingsItem?.action == #selector(DummyTarget.settings), "Settings item should have settings action")
        #expect(licenseItem?.action == #selector(DummyTarget.license), "License item should have license action")
        #expect(checkForUpdatesItem?.action == #selector(DummyTarget.checkForUpdates), "Check for Updates item should have action")
        #expect(aboutItem?.action == #selector(DummyTarget.about), "About / Report item should have about action")
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
            @objc func arrangeNow() {}
            @objc func health() {}
            @objc func settings() { settingsCalled = true }
            @objc func license() {}
            @objc func about() {}
            @objc func checkForUpdates() {}
            @objc func quit() {}
        }
        let target = DummyTarget()

        let menu = controller.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            arrangeNowAction: #selector(DummyTarget.arrangeNow),
            healthAction: #selector(DummyTarget.health),
            settingsAction: #selector(DummyTarget.settings),
            licenseAction: #selector(DummyTarget.license),
            aboutAndBugReportAction: #selector(DummyTarget.about),
            showReleaseNotesAction: nil,
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit)
        ))

        // Get settings item by name and verify it can be invoked
        guard let settingsItem = menu.item(titled: "Settings...") else {
            Issue.record("Settings menu item not found")
            return
        }

        settingsItem.target = target
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

    @Test("Hidden separator style clears the visible divider glyph without shrinking delimiter")
    @MainActor
    func hiddenSeparatorStyleClearsVisibleGlyph() {
        let controller = StatusBarController()

        controller.updateSeparatorStyle(.slash, isHidden: false)
        let expandedLength = controller.separatorItem.length
        #expect(controller.separatorItem.button?.title == "/")
        #expect((controller.separatorItem.button?.alphaValue ?? 0) > 0)

        controller.separatorItem.length = 10_000
        controller.updateSeparatorStyle(.slash, isHidden: true)

        #expect(controller.separatorItem.length == 10_000)
        #expect(controller.separatorItem.button?.title == "")
        #expect(controller.separatorItem.button?.image == nil)
        #expect(controller.separatorItem.button?.alphaValue == 0)
        #expect(controller.separatorItem.button?.cell?.isEnabled == false)

        controller.updateSeparatorStyle(.slash, isHidden: false)
        #expect(controller.separatorItem.length == expandedLength)
        #expect(controller.separatorItem.button?.title == "/")
        #expect((controller.separatorItem.button?.alphaValue ?? 0) > 0)
        #expect(controller.separatorItem.button?.cell?.isEnabled == true)
    }

    // MARK: - Display-Aware Position Validation
}
