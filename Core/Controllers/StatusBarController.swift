import AppKit
import Combine
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "StatusBarController")

// MARK: - Menu Configuration

struct MenuConfiguration {
    let toggleAction: Selector
    let findIconAction: Selector
    let settingsAction: Selector
    let checkForUpdatesAction: Selector
    let quitAction: Selector
    let target: AnyObject
}

// MARK: - StatusBarControllerProtocol

/// @mockable
@MainActor
protocol StatusBarControllerProtocol {
    var mainItem: NSStatusItem? { get }
    var separatorItem: NSStatusItem? { get }

    func iconName(for state: HidingState) -> String
    func createMenu(configuration: MenuConfiguration) -> NSMenu
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

    nonisolated static let iconExpanded = "line.3.horizontal.decrease"
    nonisolated static let iconHidden = "line.3.horizontal.decrease"
    nonisolated static let separatorIcon = "line.diagonal"
    nonisolated static let spacerIcon = "minus"
    nonisolated static let spacerDotIcon = "circle.fill"

    nonisolated static let maxSpacerCount = 12

    // MARK: - Initialization

    init() {}

    // MARK: - Status Item Creation

    /// Check if WindowServer connection is likely ready
    /// Returns true if we can safely create status items
    private func isWindowServerReady() -> Bool {
        // Check if NSApp exists and has finished launching
        guard NSApp != nil else {
            logger.warning("NSApp is nil - WindowServer not ready")
            return false
        }

        // Check if we have a main screen (indicates display server is up)
        guard NSScreen.main != nil else {
            logger.warning("No main screen - WindowServer not ready")
            return false
        }

        // Check if system status bar exists
        let statusBar = NSStatusBar.system
        // If we can access the system status bar without crashing, we're likely good
        _ = statusBar.thickness
        return true
    }

    /// Create all status items in the correct order for menu bar positioning
    /// Order on screen: [separator] [main] [system icons]
    /// Includes retry logic for systems where WindowServer isn't immediately ready
    func createStatusItems(
        clickAction: Selector,
        target: AnyObject
    ) {
        createStatusItemsWithRetry(clickAction: clickAction, target: target, attempt: 1)
    }

    /// Internal retry implementation with exponential backoff
    private func createStatusItemsWithRetry(
        clickAction: Selector,
        target: AnyObject,
        attempt: Int
    ) {
        let maxAttempts = 5
        let baseDelay: Double = 0.2 // 200ms base delay

        // Check if WindowServer is ready
        guard isWindowServerReady() else {
            if attempt < maxAttempts {
                let delay = baseDelay * pow(2.0, Double(attempt - 1)) // Exponential backoff
                logger.info("WindowServer not ready, retry \(attempt)/\(maxAttempts) in \(delay)s")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.createStatusItemsWithRetry(
                        clickAction: clickAction,
                        target: target,
                        attempt: attempt + 1
                    )
                }
            } else {
                logger.error("Failed to create status items after \(maxAttempts) attempts - WindowServer unavailable")
            }
            return
        }

        // Attempt to create status items
        do {
            try createStatusItemsUnsafe(clickAction: clickAction, target: target)
            logger.info("Status items created successfully on attempt \(attempt)")
        } catch {
            if attempt < maxAttempts {
                let delay = baseDelay * pow(2.0, Double(attempt - 1))
                logger.warning("Status item creation failed, retry \(attempt)/\(maxAttempts) in \(delay)s: \(error.localizedDescription)")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    self?.createStatusItemsWithRetry(
                        clickAction: clickAction,
                        target: target,
                        attempt: attempt + 1
                    )
                }
            } else {
                logger.error("Failed to create status items after \(maxAttempts) attempts: \(error.localizedDescription)")
            }
        }
    }

    /// Actually create the status items - may throw if WindowServer isn't ready
    private func createStatusItemsUnsafe(
        clickAction: Selector,
        target: AnyObject
    ) throws {
        // 1. Create MAIN ICON first - appears to the RIGHT (stays visible)
        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        guard mainItem != nil else {
            throw StatusBarError.creationFailed("Main status item creation returned nil")
        }

        mainItem?.autosaveName = Self.mainAutosaveName

        if let button = mainItem?.button {
            configureMainButton(button, action: clickAction, target: target)
        }

        // 2. Create SEPARATOR second - appears to the LEFT of main icon
        separatorItem = NSStatusBar.system.statusItem(withLength: 20)

        guard separatorItem != nil else {
            // Clean up main item if separator fails
            if let main = mainItem {
                NSStatusBar.system.removeStatusItem(main)
                mainItem = nil
            }
            throw StatusBarError.creationFailed("Separator status item creation returned nil")
        }

        separatorItem?.autosaveName = Self.separatorAutosaveName
        if let button = separatorItem?.button {
            configureSeparatorButton(button)
        }
    }

    /// Errors that can occur during status bar creation
    enum StatusBarError: LocalizedError {
        case creationFailed(String)

        var errorDescription: String? {
            switch self {
            case .creationFailed(let message):
                return "Status bar creation failed: \(message)"
            }
        }
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
        // Default to slash style
        updateSeparatorStyle(.slash)
    }

    /// Update the separator style (icon/text and width)
    func updateSeparatorStyle(_ style: SaneBarSettings.DividerStyle) {
        guard let separator = separatorItem, let button = separator.button else { return }

        // Reset state
        button.image = nil
        button.title = ""
        button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        switch style {
        case .slash:
            button.title = "/"
            separator.length = 14 // Reduced from 20 (User feedback #16)
        case .backslash:
            button.title = "\\"
            separator.length = 14
        case .pipe:
            button.title = "|"
            separator.length = 12
        case .pipeThin:
            button.title = "❘"
            button.font = NSFont.systemFont(ofSize: 13, weight: .light)
            separator.length = 12
        case .dot:
            button.image = NSImage(
                systemSymbolName: "circle.fill",
                accessibilityDescription: "Separator"
            )
            // Scale down the dot
            button.image?.size = NSSize(width: 6, height: 6)
            separator.length = 12
        }

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
    func createMenu(configuration: MenuConfiguration) -> NSMenu {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(
            title: "Toggle Hidden Items",
            action: configuration.toggleAction,
            keyEquivalent: "\\"
        )
        toggleItem.target = configuration.target
        toggleItem.keyEquivalentModifierMask = [.command]
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let findItem = NSMenuItem(
            title: "Find Icon...",
            action: configuration.findIconAction,
            keyEquivalent: " "
        )
        findItem.target = configuration.target
        findItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(findItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: configuration.settingsAction,
            keyEquivalent: ","
        )
        settingsItem.target = configuration.target
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(
            title: "Check for Updates...",
            action: configuration.checkForUpdatesAction,
            keyEquivalent: ""
        )
        updateItem.target = configuration.target
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(
            title: "Quit SaneBar",
            action: configuration.quitAction,
            keyEquivalent: "q"
        )
        quitItem.target = configuration.target
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Spacer Management

    /// Update spacer items to match the desired count (0-12)
    func updateSpacers(count: Int, style: SaneBarSettings.SpacerStyle, width: SaneBarSettings.SpacerWidth) {
        let desiredCount = min(max(count, 0), Self.maxSpacerCount)

        let spacerLength: CGFloat
        switch width {
        case .compact:
            spacerLength = 8
        case .normal:
            spacerLength = 12
        case .wide:
            spacerLength = 20
        }

        // Remove excess spacers
        while spacerItems.count > desiredCount {
            if let item = spacerItems.popLast() {
                NSStatusBar.system.removeStatusItem(item)
            }
        }

        // Add missing spacers
        while spacerItems.count < desiredCount {
            let spacer = NSStatusBar.system.statusItem(withLength: spacerLength)
            spacer.autosaveName = "SaneBar_spacer_\(spacerItems.count)"
            configureSpacer(spacer, style: style)
            spacerItems.append(spacer)
        }

        // Update existing spacer length/style
        for spacer in spacerItems {
            spacer.length = spacerLength
            configureSpacer(spacer, style: style)
        }
    }

    private func configureSpacer(_ spacer: NSStatusItem, style: SaneBarSettings.SpacerStyle) {
        guard let button = spacer.button else { return }

        button.image = nil
        button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        button.alphaValue = 0.7

        switch style {
        case .line:
            button.title = "│"
        case .dot:
            button.title = "•"
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
