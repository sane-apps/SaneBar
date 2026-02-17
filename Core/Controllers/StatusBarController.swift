import AppKit
import KeyboardShortcuts
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
    var mainItem: NSStatusItem { get }
    var separatorItem: NSStatusItem { get }
    var alwaysHiddenSeparatorItem: NSStatusItem? { get }

    func iconName(for state: HidingState) -> String
    func createMenu(configuration: MenuConfiguration) -> NSMenu
}

// MARK: - StatusBarController

/// Controller responsible for status bar item configuration and appearance.
/// Seeds ordinal positions in UserDefaults before creating items with autosaveNames.
@MainActor
final class StatusBarController: StatusBarControllerProtocol {
    // MARK: - Status Items

    private(set) var mainItem: NSStatusItem
    private(set) var separatorItem: NSStatusItem
    private(set) var alwaysHiddenSeparatorItem: NSStatusItem?
    private var spacerItems: [NSStatusItem] = []

    // MARK: - Autosave Names

    nonisolated static let mainAutosaveName = "SaneBar_Main"
    nonisolated static let separatorAutosaveName = "SaneBar_Separator"
    nonisolated static let alwaysHiddenSeparatorAutosaveName = "SaneBar_AlwaysHiddenSeparator"

    // MARK: - Icon Names

    nonisolated static let iconExpanded = "line.3.horizontal.decrease"
    nonisolated static let iconHidden = "line.3.horizontal.decrease"
    nonisolated static let maxSpacerCount = 12

    // MARK: - Initialization

    init() {
        // Migrate: clear AH positions that are too small (< 200) — they place the
        // AH separator near the right edge, devouring all menu bar items.
        Self.migrateCorruptedPositionsIfNeeded()

        // Seed positions BEFORE creating items (position pre-seeding)
        // Position 0 = rightmost (main), Position 1 = second from right (separator)
        Self.seedPositionsIfNeeded()

        // Create main item (rightmost, near Control Center)
        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        mainItem.autosaveName = Self.mainAutosaveName

        // Create separator item (to the LEFT of main)
        separatorItem = NSStatusBar.system.statusItem(withLength: 20)
        separatorItem.autosaveName = Self.separatorAutosaveName

        // Configure buttons
        if let button = separatorItem.button {
            configureSeparatorButton(button)
        }

        if let button = mainItem.button {
            button.title = ""
            button.image = makeMainSymbolImage(name: Self.iconHidden)
        }

        logger.info("StatusBarController initialized")
    }

    // MARK: - Always-Hidden Separator (Experimental)

    func ensureAlwaysHiddenSeparator(enabled: Bool) {
        guard enabled else {
            if let item = alwaysHiddenSeparatorItem {
                NSStatusBar.system.removeStatusItem(item)
                alwaysHiddenSeparatorItem = nil
                // Clear the stale pixel position so it reseeds cleanly on re-enable.
                // macOS converts ordinals to pixels after creation — keeping the old
                // pixel value would skip re-seeding and reuse a stale position.
                let ahKey = "NSStatusItem Preferred Position \(Self.alwaysHiddenSeparatorAutosaveName)"
                UserDefaults.standard.removeObject(forKey: ahKey)
                logger.info("Always-hidden separator removed + position cleared")
            }
            return
        }
        guard alwaysHiddenSeparatorItem == nil else { return }

        Self.seedAlwaysHiddenSeparatorPositionIfNeeded()

        let item = NSStatusBar.system.statusItem(withLength: 14)
        item.autosaveName = Self.alwaysHiddenSeparatorAutosaveName

        if let button = item.button {
            configureAlwaysHiddenSeparatorButton(button)
        }

        alwaysHiddenSeparatorItem = item
        logger.info("Always-hidden separator created at ordinal 2")
    }

    // MARK: - Position Pre-Seeding

    /// Seed ordinal positions in UserDefaults BEFORE creating status items.
    /// macOS reads these at item creation time as ordering hints, then overwrites with pixels.
    /// Only seeds if no position exists yet - respects user's existing arrangement.
    private static func seedPositionsIfNeeded() {
        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(mainAutosaveName)"
        let sepKey = "NSStatusItem Preferred Position \(separatorAutosaveName)"

        if defaults.object(forKey: mainKey) == nil {
            logger.info("Seeding initial main icon position (ordinal 0)")
            defaults.set(0, forKey: mainKey)
        }
        if defaults.object(forKey: sepKey) == nil {
            logger.info("Seeding initial separator position (ordinal 1)")
            defaults.set(1, forKey: sepKey)
        }
    }

    static func seedAlwaysHiddenSeparatorPositionIfNeeded() {
        let defaults = UserDefaults.standard
        let key = "NSStatusItem Preferred Position \(alwaysHiddenSeparatorAutosaveName)"

        // AH separator must be FAR to the left of all menu bar items.
        // UserDefaults positions are pixel offsets from the right screen edge.
        // Small values (0, 1, 50) all land near the right edge — useless for AH.
        //
        // 10000 is safe: macOS clamps it to the actual screen width and places
        // the item at the far left. Main/Separator use ordinals (0, 1) which
        // macOS handles independently — the large AH value doesn't affect them.
        if defaults.object(forKey: key) == nil {
            logger.info("Seeding initial AH separator position (10000 = far left)")
            defaults.set(10000, forKey: key)
        }
    }

    /// Reset all status item positions to ordinal seeds. Call when positions are
    /// corrupted (e.g., display-specific pixel values from a different screen).
    static func resetPositionsToOrdinals() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "NSStatusItem Preferred Position \(mainAutosaveName)")
        defaults.removeObject(forKey: "NSStatusItem Preferred Position \(separatorAutosaveName)")
        defaults.removeObject(forKey: "NSStatusItem Preferred Position \(alwaysHiddenSeparatorAutosaveName)")
        logger.info("Reset all status item positions — will reseed on next creation")
    }

    /// One-time migration: clear AH positions that are too small.
    /// Values < 200 land near the right edge of the screen, causing the AH
    /// separator to "devour" all items. Clearing lets seedAlwaysHiddenSeparator
    /// write 10000 (far left) on next enable.
    private static func migrateCorruptedPositionsIfNeeded() {
        let defaults = UserDefaults.standard
        let migrationKey = "SaneBar_PositionMigration_v4"
        guard !defaults.bool(forKey: migrationKey) else { return }

        let ahKey = "NSStatusItem Preferred Position \(alwaysHiddenSeparatorAutosaveName)"

        if let ahPos = defaults.object(forKey: ahKey) as? Double, ahPos < 200 {
            // Values like 2 or 50 place AH right next to main/separator.
            // Clear so it reseeds as 10000 (far left).
            logger.info("Migrating too-small AH position (was \(ahPos), clearing for reseed)")
            defaults.removeObject(forKey: ahKey)
        }

        defaults.set(true, forKey: migrationKey)
    }

    // MARK: - Configuration

    /// Configure click actions for the main status item
    func configureStatusItems(clickAction: Selector, target: AnyObject) {
        if let button = mainItem.button {
            configureMainButton(button, action: clickAction, target: target)
        }
    }

    private func configureMainButton(_ button: NSStatusBarButton, action: Selector, target: AnyObject) {
        button.title = ""
        button.identifier = NSUserInterfaceItemIdentifier("SaneBar.main")
        button.image = makeMainSymbolImage(name: Self.iconHidden)
        button.action = action
        button.target = target
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureSeparatorButton(_ button: NSStatusBarButton) {
        button.identifier = NSUserInterfaceItemIdentifier("SaneBar.separator")
        updateSeparatorStyle(.slash)
    }

    private func configureAlwaysHiddenSeparatorButton(_ button: NSStatusBarButton) {
        button.identifier = NSUserInterfaceItemIdentifier("SaneBar.alwaysHiddenSeparator")
        button.image = nil
        button.title = "┊"
        button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .light)
        button.alphaValue = 0.5
    }

    // MARK: - Appearance

    /// Current icon style (updated via updateIconStyle)
    private(set) var currentIconStyle: SaneBarSettings.MenuBarIconStyle = .filter

    /// Cached custom icon image (loaded from disk)
    private var customIconImage: NSImage?

    func iconName(for _: HidingState) -> String {
        currentIconStyle.sfSymbolName ?? "line.3.horizontal.decrease"
    }

    func updateAppearance(for _: HidingState) {
        guard let button = mainItem.button else { return }
        button.title = ""
        button.image = resolveIcon(for: currentIconStyle)
    }

    /// Update the menu bar icon to match the selected style
    func updateIconStyle(_ style: SaneBarSettings.MenuBarIconStyle, customIcon: NSImage? = nil) {
        currentIconStyle = style
        if let customIcon {
            customIconImage = customIcon
        }
        guard let button = mainItem.button else { return }
        button.title = ""
        button.image = resolveIcon(for: style)
    }

    /// Resolve the icon image for a given style
    private func resolveIcon(for style: SaneBarSettings.MenuBarIconStyle) -> NSImage? {
        if style == .custom, let custom = customIconImage {
            return custom
        }
        guard let symbolName = style.sfSymbolName else {
            // Fallback to default if custom icon not loaded
            return Self.makeSymbolImage(name: "line.3.horizontal.decrease")
        }
        return Self.makeSymbolImage(name: symbolName)
    }

    /// Create an SF Symbol image suitable for the menu bar
    static func makeSymbolImage(name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        guard let image = NSImage(systemSymbolName: name, accessibilityDescription: "SaneBar")?.withSymbolConfiguration(config) else {
            return nil
        }
        image.isTemplate = true
        return image
    }

    private func makeMainSymbolImage(name: String) -> NSImage? {
        Self.makeSymbolImage(name: name)
    }

    // MARK: - Separator Style (Settings Feature)

    /// Update separator visual style. Only sets length if not hidden (to avoid overriding HidingService's collapsed length)
    func updateSeparatorStyle(_ style: SaneBarSettings.DividerStyle, isHidden: Bool = false) {
        guard let button = separatorItem.button else { return }

        button.image = nil
        button.title = ""
        button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        // Determine the visual length for this style (only applies when expanded)
        let styleLength: CGFloat
        switch style {
        case .slash:
            button.title = "/"
            styleLength = 14
        case .backslash:
            button.title = "\\"
            styleLength = 14
        case .pipe:
            button.title = "|"
            styleLength = 12
        case .pipeThin:
            button.title = "❘"
            button.font = NSFont.systemFont(ofSize: 13, weight: .light)
            styleLength = 12
        case .dot:
            button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "Separator")
            button.image?.size = NSSize(width: 6, height: 6)
            styleLength = 12
        }

        // IMPORTANT: Only set length if NOT hidden!
        // When hidden, HidingService sets length to 10000 to push items off screen.
        // Setting length here would override that and cause state/visual mismatch.
        if !isHidden {
            separatorItem.length = styleLength
        }

        button.alphaValue = 0.7
    }

    // MARK: - Menu Creation

    func createMenu(configuration: MenuConfiguration) -> NSMenu {
        let menu = NSMenu()

        let findItem = NSMenuItem(title: "Browse Icons...", action: configuration.findIconAction, keyEquivalent: "")
        findItem.target = configuration.target
        findItem.setShortcut(for: .searchMenuBar)
        menu.addItem(findItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: configuration.settingsAction, keyEquivalent: ",")
        settingsItem.target = configuration.target
        menu.addItem(settingsItem)

        let updateItem = NSMenuItem(title: "Check for Updates...", action: configuration.checkForUpdatesAction, keyEquivalent: "")
        updateItem.target = configuration.target
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit SaneBar", action: configuration.quitAction, keyEquivalent: "q")
        quitItem.target = configuration.target
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Spacer Management (Settings Feature)

    func updateSpacers(count: Int, style: SaneBarSettings.SpacerStyle, width: SaneBarSettings.SpacerWidth) {
        let desiredCount = min(max(count, 0), Self.maxSpacerCount)

        let spacerLength: CGFloat = switch width {
        case .compact: 8
        case .normal: 12
        case .wide: 20
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
        case .line: button.title = "│"
        case .dot: button.title = "•"
        }
    }

    // MARK: - Click Event Helpers

    static func clickType(from event: NSEvent) -> ClickType {
        if event.type == .rightMouseUp || event.type == .rightMouseDown || event.buttonNumber == 1 {
            return .rightClick
        } else if event.type == .leftMouseUp || event.type == .leftMouseDown {
            if event.modifierFlags.contains(.control) {
                return .rightClick
            }
            return event.modifierFlags.contains(.option) ? .optionClick : .leftClick
        }
        return .leftClick
    }

    enum ClickType {
        case leftClick
        case rightClick
        case optionClick
    }
}
