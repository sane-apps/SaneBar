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

    // Autosave namespace is versioned so we can hard-reset from historically
    // corrupted status item position keys without depending on manual cleanup.
    nonisolated static let mainAutosaveName = "SaneBar_Main_v7"
    nonisolated static let separatorAutosaveName = "SaneBar_Separator_v7"
    nonisolated static let alwaysHiddenSeparatorAutosaveName = "SaneBar_AlwaysHiddenSeparator_v7"

    // MARK: - Icon Names

    nonisolated static let iconExpanded = "line.3.horizontal.decrease"
    nonisolated static let iconHidden = "line.3.horizontal.decrease"
    nonisolated static let maxSpacerCount = 12
    private static let screenWidthKey = "SaneBar_CalibratedScreenWidth"
    private static let stablePositionMigrationKey = "SaneBar_PositionRecovery_Migration_v1"
    private static let legacyMigrationKeys = [
        "SaneBar_PositionMigration_v4",
        "SaneBar_PositionMigration_v5",
        "SaneBar_PositionMigration_v6",
        "SaneBar_PositionMigration_v7"
    ]
    private static let minimumSafeAlwaysHiddenPosition = 200.0

    // MARK: - Initialization

    init() {
        // Cmd-drag can persist NSStatusItem visibility overrides. Clear them on
        // every launch so a single drag-out cannot permanently hide SaneBar.
        Self.clearPersistedVisibilityOverrides()

        // One-time migration for known corrupted position state.
        // Healthy user layouts are preserved.
        Self.migrateCorruptedPositionsIfNeeded()

        // Display-aware validation: reset pixel positions from a different screen
        if Self.positionsNeedDisplayReset() {
            Self.resetPositionsToOrdinals()
            if let w = NSScreen.main?.frame.width {
                UserDefaults.standard.set(w, forKey: Self.screenWidthKey)
            }
        }

        // Seed positions BEFORE creating items (position pre-seeding)
        // Position 0 = rightmost (main), Position 1 = second from right (separator)
        Self.seedPositionsIfNeeded()

        // Create main item (rightmost, near Control Center)
        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        mainItem.autosaveName = Self.mainAutosaveName
        // Cmd-drag removal can persist hidden state per autosaveName.
        // Force visible on startup so users don't get "missing icon forever".
        mainItem.isVisible = true

        // Create separator item (to the LEFT of main)
        separatorItem = NSStatusBar.system.statusItem(withLength: 20)
        separatorItem.autosaveName = Self.separatorAutosaveName
        separatorItem.isVisible = true

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
        item.isVisible = true

        if let button = item.button {
            configureAlwaysHiddenSeparatorButton(button)
        }

        alwaysHiddenSeparatorItem = item
        logger.info("Always-hidden separator created at ordinal 2")
    }

    // MARK: - Position Pre-Seeding

    /// Seed ordinal positions BEFORE creating status items.
    /// Only seed when positions are missing/invalid. Re-seeding on every launch
    /// destroys user-arranged visible/hidden layouts.
    private static func seedPositionsIfNeeded() {
        let mainValues = preferredPositionValues(forAutosaveName: mainAutosaveName)
        let separatorValues = preferredPositionValues(forAutosaveName: separatorAutosaveName)

        let seedMain = shouldSeedPreferredPosition(appValue: mainValues.appValue, byHostValue: mainValues.byHostValue)
        let seedSeparator = shouldSeedPreferredPosition(appValue: separatorValues.appValue, byHostValue: separatorValues.byHostValue)

        if seedMain {
            logger.info("Seeding main position (main=0)")
            setPreferredPosition(0, forAutosaveName: mainAutosaveName)
        }
        if seedSeparator {
            logger.info("Seeding separator position (separator=1)")
            setPreferredPosition(1, forAutosaveName: separatorAutosaveName)
        }

        if !seedMain, !seedSeparator {
            logger.debug("Preserving existing main/separator positions")
        }
    }

    static func seedAlwaysHiddenSeparatorPositionIfNeeded() {
        // AH separator must be FAR to the left of all menu bar items.
        // UserDefaults positions are pixel offsets from the right screen edge.
        // Small values (0, 1, 50) all land near the right edge — useless for AH.
        //
        // 10000 is safe: macOS clamps it to the actual screen width and places
        // the item at the far left. Main/Separator use ordinals (0, 1) which
        // macOS handles independently — the large AH value doesn't affect them.
        logger.info("Seeding AH separator position (10000 = far left)")
        setPreferredPosition(10000, forAutosaveName: alwaysHiddenSeparatorAutosaveName)
    }

    /// Reset all status item positions to ordinal seeds. Call when positions are
    /// corrupted (e.g., display-specific pixel values from a different screen).
    static func resetPositionsToOrdinals() {
        removePreferredPosition(forAutosaveName: mainAutosaveName)
        removePreferredPosition(forAutosaveName: separatorAutosaveName)
        removePreferredPosition(forAutosaveName: alwaysHiddenSeparatorAutosaveName)
        logger.info("Reset all status item positions — will reseed on next creation")
    }

    /// Best-effort startup recovery used when runtime invariants detect a bad
    /// separator layout. This keeps the current session usable and seeds safe
    /// positions for the next status-item relayout/restart.
    static func recoverStartupPositions(alwaysHiddenEnabled: Bool) {
        resetPositionsToOrdinals()
        seedPositionsIfNeeded()
        if alwaysHiddenEnabled {
            seedAlwaysHiddenSeparatorPositionIfNeeded()
        }
        logger.info("Applied startup position recovery seeds")
    }

    // MARK: - Display-Aware Position Validation

    /// Returns true if a position value looks like a pixel offset rather than an ordinal seed.
    /// Ordinals are small integers (0, 1, 2). The AH sentinel is 10000.
    /// Pixel offsets from macOS fall in the range ~50–5000 for typical displays.
    nonisolated static func isPixelLikePosition(_ value: Double?) -> Bool {
        guard let v = value else { return false }
        return v > 10 && v < 9000
    }

    /// Returns true if the stored and current screen widths differ by more than 10%.
    nonisolated static func isSignificantWidthChange(stored: Double, current: Double) -> Bool {
        guard stored > 0 else { return false }
        let ratio = abs(current - stored) / stored
        return ratio > 0.10
    }

    /// Check if positions need a display reset due to a screen width change.
    /// - First launch after update (no stored width): stamps current width, returns false.
    /// - Same screen (width matches within 10%): returns false.
    /// - Different screen AND pixel-like positions: returns true (triggers reset).
    private static func positionsNeedDisplayReset() -> Bool {
        let defaults = UserDefaults.standard
        let storedWidth = defaults.double(forKey: screenWidthKey)

        guard let currentWidth = NSScreen.main?.frame.width else { return false }

        if storedWidth == 0 {
            // First launch after update — stamp current width, accept positions as-is
            defaults.set(currentWidth, forKey: screenWidthKey)
            logger.info("Display validation: first run, stamping screen width \(currentWidth)")
            return false
        }

        guard isSignificantWidthChange(stored: storedWidth, current: currentWidth) else {
            return false
        }

        // Screen changed significantly — check if positions are pixel values
        let mainKey = preferredPositionKey(for: mainAutosaveName)
        let sepKey = preferredPositionKey(for: separatorAutosaveName)
        let mainPos = defaults.object(forKey: mainKey) as? Double
        let sepPos = defaults.object(forKey: sepKey) as? Double

        let hasPixelPositions = isPixelLikePosition(mainPos) || isPixelLikePosition(sepPos)

        if hasPixelPositions {
            logger.info("Display validation: screen width changed (\(storedWidth) → \(currentWidth)) with pixel positions — resetting")
        }

        return hasPixelPositions
    }

    /// Clears persisted visibility overrides written by macOS after cmd-dragging
    /// a status item out of the menu bar.
    private static func clearPersistedVisibilityOverrides() {
        let defaults = UserDefaults.standard
        var clearedAny = false

        for name in [mainAutosaveName, separatorAutosaveName, alwaysHiddenSeparatorAutosaveName] {
            let appKey = "NSStatusItem Visible \(name)"
            if defaults.object(forKey: appKey) != nil {
                defaults.removeObject(forKey: appKey)
                clearedAny = true
            }

            if removeByHostVisibilityOverrides(forAutosaveName: name) {
                clearedAny = true
            }
        }

        if clearedAny {
            logger.info("Cleared persisted NSStatusItem visibility overrides")
        }
    }

    /// One-time recovery migration.
    /// Important: do not version-bump this key for routine patch releases.
    /// Position resets must be gated on explicit corruption checks.
    private static func migrateCorruptedPositionsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: stablePositionMigrationKey) else { return }

        if shouldResetPositionsForKnownCorruption() {
            logger.info("Applying status item position recovery for known corrupted state")
            resetPositionsToOrdinals()
        } else {
            logger.info("Skipping status item position reset (no known corruption)")
        }

        clearPersistedVisibilityOverrides()

        defaults.set(true, forKey: stablePositionMigrationKey)

        // Backfill legacy migration sentinels so downgrades/older builds don't
        // re-run broad reset paths on healthy layouts.
        for key in legacyMigrationKeys {
            defaults.set(true, forKey: key)
        }
    }

    private static func shouldResetPositionsForKnownCorruption() -> Bool {
        if hasInvalidPositionValue(forAutosaveName: mainAutosaveName) {
            return true
        }
        if hasInvalidPositionValue(forAutosaveName: separatorAutosaveName) {
            return true
        }
        if hasTooSmallAlwaysHiddenPosition(forAutosaveName: alwaysHiddenSeparatorAutosaveName) {
            return true
        }
        if hasTooSmallAlwaysHiddenPosition(forAutosaveName: "SaneBar_AlwaysHiddenSeparator") {
            return true
        }
        return false
    }

    private static func hasInvalidPositionValue(forAutosaveName autosaveName: String) -> Bool {
        let values = preferredPositionValues(forAutosaveName: autosaveName)
        return isInvalidPosition(values.appValue) || isInvalidPosition(values.byHostValue)
    }

    private static func hasTooSmallAlwaysHiddenPosition(forAutosaveName autosaveName: String) -> Bool {
        let values = preferredPositionValues(forAutosaveName: autosaveName)
        return isTooSmallAlwaysHiddenPosition(values.appValue) || isTooSmallAlwaysHiddenPosition(values.byHostValue)
    }

    private static func isInvalidPosition(_ value: Any?) -> Bool {
        guard let number = numericPositionValue(value) else { return false }
        return !number.isFinite || number < 0
    }

    private static func isTooSmallAlwaysHiddenPosition(_ value: Any?) -> Bool {
        guard let number = numericPositionValue(value), number.isFinite else { return false }
        return number > 0 && number < minimumSafeAlwaysHiddenPosition
    }

    // MARK: - Preferred Position Storage

    private static func preferredPositionKey(for autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    private static func byHostAutosaveName(for autosaveName: String) -> String {
        // macOS stores autosave keys in ByHost global prefs using a suffixed
        // v6 token (e.g. SaneBar_Main -> SaneBar_main_v6).
        guard let underscore = autosaveName.firstIndex(of: "_") else {
            return "\(autosaveName)_v6"
        }
        let prefix = autosaveName[..<underscore]
        var suffix = String(autosaveName[autosaveName.index(after: underscore)...])
        if let first = suffix.first {
            suffix.replaceSubrange(suffix.startIndex ... suffix.startIndex, with: String(first).lowercased())
        }
        return "\(prefix)_\(suffix)_v6"
    }

    /// Legacy variation observed in the field where the entire suffix is lowercased
    /// (e.g. SaneBar_AlwaysHiddenSeparator_v7 -> SaneBar_alwayshiddenseparator_v7_v6).
    private static func legacyLowercasedByHostAutosaveName(for autosaveName: String) -> String {
        guard let underscore = autosaveName.firstIndex(of: "_") else {
            return "\(autosaveName.lowercased())_v6"
        }
        let prefix = autosaveName[..<underscore]
        let suffix = String(autosaveName[autosaveName.index(after: underscore)...]).lowercased()
        return "\(prefix)_\(suffix)_v6"
    }

    private static func byHostPreferredPositionKey(for autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(byHostAutosaveName(for: autosaveName))"
    }

    private static func byHostVisibilityKey(for autosaveName: String) -> String {
        "NSStatusItem Visible \(byHostAutosaveName(for: autosaveName))"
    }

    private static func byHostVisibilityKeys(for autosaveName: String) -> [String] {
        let canonical = byHostVisibilityKey(for: autosaveName)
        let legacy = "NSStatusItem Visible \(legacyLowercasedByHostAutosaveName(for: autosaveName))"
        return canonical == legacy ? [canonical] : [canonical, legacy]
    }

    nonisolated static func shouldSeedPreferredPosition(appValue: Any?, byHostValue: Any?) -> Bool {
        if let appNumber = numericPositionValue(appValue), appNumber.isFinite {
            return false
        }
        if let byHostNumber = numericPositionValue(byHostValue), byHostNumber.isFinite {
            return false
        }
        return true
    }

    private nonisolated static func numericPositionValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let doubleValue = value as? Double {
            return doubleValue
        }
        if let intValue = value as? Int {
            return Double(intValue)
        }
        if let stringValue = value as? String {
            return Double(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    private static func preferredPositionValues(forAutosaveName autosaveName: String) -> (appValue: Any?, byHostValue: Any?) {
        let appKey = preferredPositionKey(for: autosaveName)
        let byHostKey = byHostPreferredPositionKey(for: autosaveName) as CFString
        let globalDomain = ".GlobalPreferences" as CFString
        let appValue = UserDefaults.standard.object(forKey: appKey)
        let byHostValue = CFPreferencesCopyValue(
            byHostKey,
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        return (appValue, byHostValue)
    }

    private static func setPreferredPosition(_ value: Double, forAutosaveName autosaveName: String) {
        let appKey = preferredPositionKey(for: autosaveName)
        UserDefaults.standard.set(value, forKey: appKey)
        setByHostPreferredPosition(value, forAutosaveName: autosaveName)
    }

    private static func removePreferredPosition(forAutosaveName autosaveName: String) {
        let appKey = preferredPositionKey(for: autosaveName)
        UserDefaults.standard.removeObject(forKey: appKey)
        removeByHostPreferredPosition(forAutosaveName: autosaveName)
    }

    private static func setByHostPreferredPosition(_ value: Double, forAutosaveName autosaveName: String) {
        let key = byHostPreferredPositionKey(for: autosaveName) as CFString
        let globalDomain = ".GlobalPreferences" as CFString
        CFPreferencesSetValue(
            key,
            value as NSNumber,
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSynchronize(
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    private static func removeByHostPreferredPosition(forAutosaveName autosaveName: String) {
        let key = byHostPreferredPositionKey(for: autosaveName) as CFString
        let globalDomain = ".GlobalPreferences" as CFString
        CFPreferencesSetValue(
            key,
            nil,
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSynchronize(
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    private static func removeByHostVisibilityOverrides(forAutosaveName autosaveName: String) -> Bool {
        let globalDomain = ".GlobalPreferences" as CFString
        var removedAny = false

        for keyString in byHostVisibilityKeys(for: autosaveName) {
            let key = keyString as CFString
            let existing = CFPreferencesCopyValue(
                key,
                globalDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
            guard existing != nil else { continue }

            CFPreferencesSetValue(
                key,
                nil,
                globalDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
            removedAny = true
        }

        if removedAny {
            CFPreferencesSynchronize(
                globalDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        }
        return removedAny
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
