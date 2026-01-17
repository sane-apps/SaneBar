import AppKit
import Combine
import CoreGraphics
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
    // NOTE: Using property initializers like Hidden Bar does
    // Status items are created when StatusBarController is instantiated

    private(set) var mainItem: NSStatusItem
    private(set) var separatorItem: NSStatusItem
    private var spacerItems: [NSStatusItem] = []
    private var visibilityObservers: [NSKeyValueObservation] = []
    private var lastClickAction: Selector?
    private weak var lastClickTarget: AnyObject?

    // MARK: - Autosave Names
    // NOTE: Increment version to clear corrupted position cache without changing bundle ID

    nonisolated static let mainAutosaveName = "SaneBar_main_v6"
    nonisolated static let separatorAutosaveName = "SaneBar_separator_v6"

    // MARK: - Icon Names

    nonisolated static let iconExpanded = "line.3.horizontal.decrease"
    nonisolated static let iconHidden = "line.3.horizontal.decrease"
    nonisolated static let separatorIcon = "line.diagonal"
    nonisolated static let spacerIcon = "minus"
    nonisolated static let spacerDotIcon = "circle.fill"

    nonisolated static let maxSpacerCount = 12

    // MARK: - Position Keys
    // UserDefaults key format for status item positions (discovered via reverse engineering)
    // CORRECT: HIGH numbers = RIGHT side (near Control Center ~1200+), LOW numbers = LEFT side (~0-200)

    nonisolated private static let mainPositionKey = "NSStatusItem Preferred Position \(mainAutosaveName)"
    nonisolated private static let separatorPositionKey = "NSStatusItem Preferred Position \(separatorAutosaveName)"

    // MARK: - Initialization

    init() {
        // NOTE: Do NOT pre-set positions - let macOS position items naturally.
        // Previous code called ensureDefaultPositions() with x=100,120 thinking
        // low values = right side, but that's BACKWARDS. Low X = LEFT side.
        // macOS correctly positions new status items on the right by default.

        logger.info("Creating status items in init...")

        // CRITICAL: Create main FIRST, then separator SECOND.
        // macOS inserts newer status items to the LEFT of existing items.
        // Creating separator second places it LEFT of the main icon (lower x).
        self.mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.separatorItem = NSStatusBar.system.statusItem(withLength: 20)

        // Set autosaveName AFTER creation - this triggers position restoration from UserDefaults
        let env = ProcessInfo.processInfo.environment
        if env["SANEBAR_DISABLE_AUTOSAVE"] == "1" {
            separatorItem.autosaveName = nil
            mainItem.autosaveName = nil
            print("[StatusBarController] Autosave disabled via SANEBAR_DISABLE_AUTOSAVE=1")
        } else {
            separatorItem.autosaveName = StatusBarController.separatorAutosaveName
            mainItem.autosaveName = StatusBarController.mainAutosaveName
            seedDefaultPositionsIfNeeded()
        }

        if env["SANEBAR_CLEAR_STATUSITEM_PREFS"] == "1" {
            clearStatusItemPrefs()
        }

        if env["SANEBAR_DUMP_STATUSITEM_PREFS"] == "1" {
            dumpStatusItemPrefs()
        }

        // Configure separator with default style
        if let button = separatorItem.button {
            configureSeparatorButton(button)
            print("[StatusBarController] Separator button configured")
        } else {
            print("[StatusBarController] WARNING: Separator button is nil!")
        }

        // Also configure main button with a placeholder icon immediately
        if let button = mainItem.button {
            // Ensure title is cleared so image-only mode doesn't show stale text
            button.title = ""

            // Try SF Symbol first
            if let image = makeMainSymbolImage(name: Self.iconHidden) {
                button.image = image
                button.contentTintColor = NSColor.labelColor
                print("[StatusBarController] Main button image set to \(Self.iconHidden)")
            } else {
                // Fallback to text if SF Symbol fails
                button.title = "≡"
                print("[StatusBarController] WARNING: SF Symbol failed, using text fallback")
            }
        } else {
            print("[StatusBarController] WARNING: Main button is nil!")
        }

        if env["SANEBAR_FORCE_TEXT_ICON"] == "1" {
            separatorItem.button?.image = nil
            separatorItem.button?.title = "/"
            mainItem.button?.image = nil
            mainItem.button?.title = "SB"
            print("[StatusBarController] Forced text icons via SANEBAR_FORCE_TEXT_ICON=1")
        }

        logger.info("StatusBarController initialized with autosaveNames: \(String(describing: self.mainItem.autosaveName)), \(String(describing: self.separatorItem.autosaveName))")

        observeVisibilityChanges()

        if env["SANEBAR_FORCE_VISIBLE"] == "1" {
            mainItem.isVisible = true
            separatorItem.isVisible = true
            print("[StatusBarController] Forced isVisible=true via SANEBAR_FORCE_VISIBLE=1")
        }

        // Log initial positions
        logPositions(label: "init")
    }

    // MARK: - Recovery

    /// Recreate status items (used for recovery from offscreen/corrupted state).
    func resetStatusItems(autosaveEnabled: Bool, forceVisible: Bool) {
        NSStatusBar.system.removeStatusItem(mainItem)
        NSStatusBar.system.removeStatusItem(separatorItem)

        self.mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.separatorItem = NSStatusBar.system.statusItem(withLength: 20)

        if autosaveEnabled {
            separatorItem.autosaveName = StatusBarController.separatorAutosaveName
            mainItem.autosaveName = StatusBarController.mainAutosaveName
        } else {
            separatorItem.autosaveName = nil
            mainItem.autosaveName = nil
        }

        if let button = separatorItem.button {
            configureSeparatorButton(button)
        }

        if let button = mainItem.button {
            // Ensure title is cleared so image-only mode doesn't show stale text
            button.title = ""
            if let image = makeMainSymbolImage(name: Self.iconHidden) {
                button.image = image
                button.contentTintColor = NSColor.labelColor
            } else {
                button.title = "≡"
            }
        }

        if env["SANEBAR_FORCE_TEXT_ICON"] == "1" {
            separatorItem.button?.image = nil
            separatorItem.button?.title = "/"
            mainItem.button?.image = nil
            mainItem.button?.title = "SB"
        }

        observeVisibilityChanges()

        if forceVisible {
            mainItem.isVisible = true
            separatorItem.isVisible = true
        }

        logPositions(label: "reset")
    }

    /// Clear cached positions from GLOBAL UserDefaults domain
    /// This lets macOS position status items naturally on next launch (typically right side)
    /// Call this when positions become corrupted or user wants to reset
    /// CRITICAL: NSStatusItem positions are stored in the GLOBAL domain (kCFPreferencesAnyApplication),
    /// not in the app's domain. Using UserDefaults.standard reads/writes the wrong place!
    nonisolated static func clearPositionCache() {
        let mainKey = mainPositionKey as CFString
        let sepKey = separatorPositionKey as CFString

        // Delete positions from global domain (nil value = delete)
        CFPreferencesSetValue(mainKey, nil, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSetValue(sepKey, nil, kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)

        print("[StatusBarController] Cleared position cache - macOS will position items naturally on next launch")
    }

    /// Seed default positions near the right edge when no cached positions exist.
    /// This prevents first-run placement from defaulting to the far left of other icons.
    private func seedDefaultPositionsIfNeeded() {
        guard let screen = NSScreen.main else { return }

        let mainKey = StatusBarController.mainPositionKey as CFString
        let sepKey = StatusBarController.separatorPositionKey as CFString

        let mainValue = CFPreferencesCopyValue(
            mainKey,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        let sepValue = CFPreferencesCopyValue(
            sepKey,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )

        let needsMain = (mainValue == nil)
        let needsSep = (sepValue == nil)

        let mainNumber = mainValue as? NSNumber
        let sepNumber = sepValue as? NSNumber
        let mainTooLeft = (mainNumber?.doubleValue ?? 9999) < 200
        let sepTooLeft = (sepNumber?.doubleValue ?? 9999) < 200

        let defaults = UserDefaults.standard
        let hasSeeded = defaults.bool(forKey: "SaneBarDidSeedPositions")

        guard needsMain || needsSep || (!hasSeeded && (mainTooLeft || sepTooLeft)) else { return }

        let rightEdge = screen.frame.maxX
        let base = max(1200, rightEdge - 160)
        let mainPosition = NSNumber(value: Double(base))
        let separatorPosition = NSNumber(value: Double(base - 24))

        if needsMain || (!hasSeeded && mainTooLeft) {
            CFPreferencesSetValue(
                mainKey,
                mainPosition,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        }

        if needsSep || (!hasSeeded && sepTooLeft) {
            CFPreferencesSetValue(
                sepKey,
                separatorPosition,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        }

        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )

        defaults.set(true, forKey: "SaneBarDidSeedPositions")

        print("[StatusBarController] Seeded default positions: main=\(mainPosition), sep=\(separatorPosition)")
    }

    // MARK: - Status Item Configuration

    /// Configure the status items with click actions
    /// Called after init to set up button actions and targets
    func configureStatusItems(
        clickAction: Selector,
        target: AnyObject
    ) {
        logger.info("Configuring status items...")
        lastClickAction = clickAction
        lastClickTarget = target

        // Configure main button with click action
        if let button = mainItem.button {
            configureMainButton(button, action: clickAction, target: target)
            logger.info("Main button configured")
        }

        // Separator is visual-only; no click handling

        // Log positions after configuration
        logPositions(label: "configured")

        // Log positions after delays to verify they stabilize
        for delay in [0.5, 1.0, 2.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.logPositions(label: "\(delay)s")
            }
        }
    }

    /// Swap items if we detect separator is to the right of main.
    /// This normalizes item roles without relying on creation order.
    func swapItemsIfNeeded() {
        let env = ProcessInfo.processInfo.environment
        guard env["SANEBAR_ENABLE_ITEM_SWAP"] == "1" else { return }
        guard let mainWindow = mainItem.button?.window,
              let separatorWindow = separatorItem.button?.window else { return }

        let mainFrame = mainWindow.frame
        let separatorFrame = separatorWindow.frame

          // If frames are not ready or still offscreen, skip (startup transitions)
          guard mainFrame.width > 0, separatorFrame.width > 0 else { return }
          guard let screen = mainWindow.screen, screen == separatorWindow.screen else { return }

          let menuBarY = screen.frame.maxY - NSStatusBar.system.thickness
          let mainDeltaY = abs(mainFrame.origin.y - menuBarY)
          let sepDeltaY = abs(separatorFrame.origin.y - menuBarY)

          guard mainDeltaY <= NSStatusBar.system.thickness,
              sepDeltaY <= NSStatusBar.system.thickness else { return }

        let separatorLeftEdge = separatorFrame.origin.x
        let mainLeftEdge = mainFrame.origin.x

        guard separatorLeftEdge >= mainLeftEdge else { return }

        logger.warning("swapItemsIfNeeded: separator is right of main (sepLeft=\(separatorLeftEdge), mainLeft=\(mainLeftEdge)). Swapping items.")
        forceSwapItems()
    }

    /// Swap items immediately without additional position checks.
    func forceSwapItems() {
        let env = ProcessInfo.processInfo.environment
        guard env["SANEBAR_ENABLE_ITEM_SWAP"] == "1" else { return }
        let temp = mainItem
        mainItem = separatorItem
        separatorItem = temp

        mainItem.length = NSStatusItem.variableLength
        separatorItem.length = 20

        if let sepButton = separatorItem.button {
            configureSeparatorButton(sepButton)
        }

        if let action = lastClickAction, let target = lastClickTarget, let mainButton = mainItem.button {
            configureMainButton(mainButton, action: action, target: target)
        }

        // Separator is visual-only; no click handling

        if env["SANEBAR_FORCE_TEXT_ICON"] == "1" {
            separatorItem.button?.image = nil
            separatorItem.button?.title = "/"
            mainItem.button?.image = nil
            mainItem.button?.title = "SB"
            mainItem.length = 22
        }

        logPositions(label: "swap")
    }

    /// Log current window positions for debugging
    private func logPositions(label: String) {
        var logMsg = "[\(label)] "
        if let mainWin = mainItem.button?.window,
           let sepWin = separatorItem.button?.window {
            logMsg += "Main: x=\(mainWin.frame.origin.x) y=\(mainWin.frame.origin.y) | "
            logMsg += "Sep: x=\(sepWin.frame.origin.x) y=\(sepWin.frame.origin.y) | "
            logMsg += "MainVis=\(mainItem.isVisible) SepVis=\(separatorItem.isVisible)"
            let mainScreen = mainWin.screen.map { NSStringFromRect($0.frame) } ?? "nil"
            let sepScreen = sepWin.screen.map { NSStringFromRect($0.frame) } ?? "nil"
            logMsg += " | MainWinVisible=\(mainWin.isVisible) SepWinVisible=\(sepWin.isVisible)"
            logMsg += " | MainScreen=\(mainScreen) SepScreen=\(sepScreen)"
        } else {
            logMsg += "⚠️ Windows not yet available"
        }
        logMsg += " | MainAutosave=\(String(describing: mainItem.autosaveName)) SepAutosave=\(String(describing: separatorItem.autosaveName))"
        print(logMsg)
        logger.error("\(logMsg)")

        logWindowServerStatus(label: label)

        // Write to log file
        if let data = (logMsg + "\n").data(using: .utf8) {
            let logPath = "/tmp/sanebar_positions.log"
            if FileManager.default.fileExists(atPath: logPath) {
                if let handle = FileHandle(forWritingAtPath: logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: URL(fileURLWithPath: logPath))
            }
        }
    }

    private func observeVisibilityChanges() {
        visibilityObservers.removeAll()

        let mainObserver = self.mainItem.observe(\.isVisible, options: [.initial, .new, .old]) { _, change in
            print("[StatusBarController] mainItem.isVisible: \(String(describing: change.oldValue)) → \(String(describing: change.newValue))")
        }
        let separatorObserver = self.separatorItem.observe(\.isVisible, options: [.initial, .new, .old]) { _, change in
            print("[StatusBarController] separatorItem.isVisible: \(String(describing: change.oldValue)) → \(String(describing: change.newValue))")
        }

        visibilityObservers.append(mainObserver)
        visibilityObservers.append(separatorObserver)
    }

    private func logWindowServerStatus(label: String) {
        let pid = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? []
        let layer25 = windows.filter {
            ($0[kCGWindowOwnerPID as String] as? Int32) == pid &&
            ($0[kCGWindowLayer as String] as? Int) == 25
        }
        let logMsg = "[\(label)] WindowServer layer25 windows for pid \(pid): \(layer25.count)"
        print(logMsg)
    }

    private func dumpStatusItemPrefs() {
        guard let keys = CFPreferencesCopyKeyList(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? [String] else { return }

        let interesting = keys.filter { $0.localizedCaseInsensitiveContains("StatusItem") || $0.localizedCaseInsensitiveContains("SaneBar") }
        print("[StatusBarController] Global prefs keys containing StatusItem/SaneBar: \(interesting.count)")
        for key in interesting.sorted() {
            let value = CFPreferencesCopyValue(
                key as CFString,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
            print("[StatusBarController] PREF \(key) = \(String(describing: value))")
        }
    }

    private func clearStatusItemPrefs() {
        let autosaveNames = [StatusBarController.mainAutosaveName, StatusBarController.separatorAutosaveName]
        guard let keys = CFPreferencesCopyKeyList(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? [String] else { return }

        let toDelete = keys.filter { key in
            autosaveNames.contains(where: { key.contains($0) }) ||
                key.localizedCaseInsensitiveContains("StatusItem Visible")
        }

        for key in toDelete {
            CFPreferencesSetValue(
                key as CFString,
                nil,
                kCFPreferencesAnyApplication,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        }

        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )

        print("[StatusBarController] Cleared \(toDelete.count) global StatusItem prefs")
    }

    // MARK: - Button Configuration

    private func configureMainButton(_ button: NSStatusBarButton, action: Selector, target: AnyObject) {
        // Ensure image-only mode doesn't show stale text
        button.title = ""
        button.identifier = NSUserInterfaceItemIdentifier("SaneBar.main")
        button.image = makeMainSymbolImage(name: Self.iconHidden)
        button.contentTintColor = NSColor.labelColor
        configureActionButton(button, action: action, target: target)
    }

    private func configureActionButton(_ button: NSStatusBarButton, action: Selector, target: AnyObject) {
        button.action = action
        button.target = target
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    private func configureSeparatorButton(_ button: NSStatusBarButton) {
        button.identifier = NSUserInterfaceItemIdentifier("SaneBar.separator")
        // Default to slash style
        updateSeparatorStyle(.slash)
    }

    /// Update the separator style (icon/text and width)
    func updateSeparatorStyle(_ style: SaneBarSettings.DividerStyle) {
        guard let button = separatorItem.button else { return }

        // Reset state
        button.image = nil
        button.title = ""
        button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

        switch style {
        case .slash:
            button.title = "/"
            separatorItem.length = 14 // Reduced from 20 (User feedback #16)
        case .backslash:
            button.title = "\\"
            separatorItem.length = 14
        case .pipe:
            button.title = "|"
            separatorItem.length = 12
        case .pipeThin:
            button.title = "❘"
            button.font = NSFont.systemFont(ofSize: 13, weight: .light)
            separatorItem.length = 12
        case .dot:
            button.image = NSImage(
                systemSymbolName: "circle.fill",
                accessibilityDescription: "Separator"
            )
            // Scale down the dot
            button.image?.size = NSSize(width: 6, height: 6)
            separatorItem.length = 12
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
        guard let button = mainItem.button else { return }

        // Ensure image-only mode doesn't show stale text
        button.title = ""
        button.image = makeMainSymbolImage(name: iconName(for: state))
        button.contentTintColor = NSColor.labelColor
    }

    private func makeMainSymbolImage(name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
        return NSImage(systemSymbolName: name, accessibilityDescription: "SaneBar")?.withSymbolConfiguration(config)
    }

    // MARK: - Menu Creation

    /// Create the status menu with provided actions
    func createMenu(configuration: MenuConfiguration) -> NSMenu {
        let menu = NSMenu()

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
        if event.type == .rightMouseUp || event.type == .rightMouseDown || event.buttonNumber == 1 {
            return .rightClick
        } else if event.type == .leftMouseUp || event.type == .leftMouseDown {
            let optionPressed = event.modifierFlags.contains(.option)
            let controlPressed = event.modifierFlags.contains(.control)
            if controlPressed {
                return .rightClick
            }
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
