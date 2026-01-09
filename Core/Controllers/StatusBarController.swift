import AppKit
import Combine
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "StatusBarController")

// MARK: - StatusBarControllerProtocol

/// @mockable
@MainActor
protocol StatusBarControllerProtocol {
    var mainItem: NSStatusItem? { get }
    var separatorItem: NSStatusItem? { get }

    func iconName(for state: HidingState) -> String
    func createMenu(
        toggleAction: Selector,
        settingsAction: Selector,
        quitAction: Selector,
        target: AnyObject
    ) -> NSMenu
}

// MARK: - StatusBarController

/// Controller responsible for status bar item configuration and appearance.
///
/// Extracted from MenuBarManager to:
/// 1. Single responsibility for status bar UI
/// 2. Testable icon and menu logic
/// 3. Cleaner separation of concerns
///
/// Note: Status items are created here but actions are handled by MenuBarManager
/// because @objc selectors require an NSObject target.
@MainActor
final class StatusBarController: StatusBarControllerProtocol {

    // MARK: - Status Items

    private(set) var mainItem: NSStatusItem?
    private(set) var separatorItem: NSStatusItem?
    private var spacerItems: [NSStatusItem] = []

    // MARK: - Autosave Names

    nonisolated static let mainAutosaveName = "SaneBar_main"
    nonisolated static let separatorAutosaveName = "SaneBar_separator"

    // MARK: - Icon Names

    nonisolated static let iconExpanded = "line.3.horizontal.decrease.circle.fill"
    nonisolated static let iconHidden = "line.3.horizontal.decrease.circle"
    nonisolated static let separatorIcon = "line.diagonal"
    nonisolated static let spacerIcon = "minus"

    // MARK: - Initialization

    init() {}

    // MARK: - Status Item Creation

    /// Create all status items in the correct order for menu bar positioning
    /// Order on screen: [separator] [main] [system icons]
    func createStatusItems(
        clickAction: Selector,
        target: AnyObject
    ) {
        // 1. Create MAIN ICON first - appears to the RIGHT (stays visible)
        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        mainItem?.autosaveName = Self.mainAutosaveName

        if let button = mainItem?.button {
            configureMainButton(button, action: clickAction, target: target)
        }

        // 2. Create SEPARATOR second - appears to the LEFT of main icon
        separatorItem = NSStatusBar.system.statusItem(withLength: 20)
        separatorItem?.autosaveName = Self.separatorAutosaveName
        if let button = separatorItem?.button {
            configureSeparatorButton(button)
        }

        logger.info("Status items created")
    }

    // MARK: - Button Configuration

    private func configureMainButton(_ button: NSStatusBarButton, action: Selector, target: AnyObject) {
        button.image = NSImage(
            systemSymbolName: Self.iconHidden,
            accessibilityDescription: "SaneBar"
        )
        button.action = action
        button.target = target
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureSeparatorButton(_ button: NSStatusBarButton) {
        // Use a literal "/" marker so it stays legible at all sizes/themes.
        button.image = nil
        button.title = "/"
        button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        button.alphaValue = 0.7
    }

    // MARK: - Appearance

    /// Returns the appropriate icon name for a given hiding state
    func iconName(for state: HidingState) -> String {
        switch state {
        case .expanded:
            return Self.iconExpanded
        case .hidden:
            return Self.iconHidden
        }
    }

    /// Update the main button appearance based on hiding state
    func updateAppearance(for state: HidingState) {
        guard let button = mainItem?.button else { return }

        button.image = NSImage(
            systemSymbolName: iconName(for: state),
            accessibilityDescription: "SaneBar"
        )
    }

    // MARK: - Menu Creation

    /// Create the status menu with provided actions
    func createMenu(
        toggleAction: Selector,
        settingsAction: Selector,
        quitAction: Selector,
        target: AnyObject
    ) -> NSMenu {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Toggle Hidden Items",
            action: toggleAction,
            keyEquivalent: "\\"
        )
        toggleItem.target = target
        toggleItem.keyEquivalentModifierMask = [.command]
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: settingsAction,
            keyEquivalent: ","
        )
        settingsItem.target = target
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit SaneBar",
            action: quitAction,
            keyEquivalent: "q"
        )
        quitItem.target = target
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Spacer Management

    /// Update spacer items to match the desired count (0-3)
    func updateSpacers(count: Int) {
        let desiredCount = min(max(count, 0), 3)

        // Remove excess spacers
        while spacerItems.count > desiredCount {
            if let item = spacerItems.popLast() {
                NSStatusBar.system.removeStatusItem(item)
            }
        }

        // Add missing spacers
        while spacerItems.count < desiredCount {
            let spacer = NSStatusBar.system.statusItem(withLength: 12)
            spacer.autosaveName = "SaneBar_spacer_\(spacerItems.count)"
            if let button = spacer.button {
                button.image = NSImage(
                    systemSymbolName: Self.spacerIcon,
                    accessibilityDescription: "Spacer"
                )
                button.image?.isTemplate = true
            }
            spacerItems.append(spacer)
        }
    }

    // MARK: - Click Event Helpers

    /// Determine click type from an NSEvent
    static func clickType(from event: NSEvent) -> ClickType {
        if event.type == .rightMouseUp {
            return .rightClick
        } else if event.type == .leftMouseUp {
            let optionPressed = event.modifierFlags.contains(.option)
            return optionPressed ? .optionClick : .leftClick
        }
        return .leftClick
    }

    enum ClickType {
        case leftClick
        case rightClick
        case optionClick
    }
}
