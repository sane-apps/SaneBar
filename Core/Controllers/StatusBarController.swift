import AppKit
import KeyboardShortcuts
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "StatusBarController")

// MARK: - Menu Configuration

struct MenuConfiguration {
    let findIconAction: Selector
    let settingsAction: Selector
    let showReleaseNotesAction: Selector?
    let checkForUpdatesAction: Selector
    let quitAction: Selector
}
// swiftlint:enable file_length

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
    // Keep base at v7 to avoid resetting healthy existing user layouts.
    nonisolated private static let autosaveVersionKey = "SaneBar_AutosaveVersion"
    nonisolated private static let baseAutosaveVersion = 7
    nonisolated private static let maxAutosaveVersion = 99
    nonisolated private static func autosaveNamesForCleanup(version: Int) -> [String] {
        [
            "SaneBar_Main_v\(version)",
            "SaneBar_Separator_v\(version)",
            "SaneBar_AlwaysHiddenSeparator_v\(version)"
        ]
    }

    nonisolated static var autosaveVersion: Int {
        let stored = UserDefaults.standard.integer(forKey: autosaveVersionKey)
        return stored > 0 ? stored : baseAutosaveVersion
    }

    nonisolated static var mainAutosaveName: String {
        "SaneBar_Main_v\(autosaveVersion)"
    }

    nonisolated static var separatorAutosaveName: String {
        "SaneBar_Separator_v\(autosaveVersion)"
    }

    nonisolated static var alwaysHiddenSeparatorAutosaveName: String {
        "SaneBar_AlwaysHiddenSeparator_v\(autosaveVersion)"
    }

    nonisolated static func spacerAutosaveName(index: Int) -> String {
        "SaneBar_spacer_\(index)"
    }

    // MARK: - Icon Names

    nonisolated static let iconExpanded = "line.3.horizontal.decrease"
    nonisolated static let iconHidden = "line.3.horizontal.decrease"
    nonisolated static let maxSpacerCount = 12
    nonisolated private static let interactiveRemovalBehaviors: NSStatusItem.Behavior = [
        .removalAllowed,
        .terminationOnRemoval
    ]
    nonisolated private static let screenWidthKey = "SaneBar_CalibratedScreenWidth"
    nonisolated private static let positionBackupKeyPrefix = "SaneBar_Position_Backup"
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
            if !Self.applyLaunchSafeRecoveryPositionsForCurrentDisplay() {
                Self.resetPositionsToOrdinals()
                if let w = NSScreen.main?.frame.width {
                    UserDefaults.standard.set(w, forKey: Self.screenWidthKey)
                }
            }
        }

        // First-run onboarding reliability: hard-anchor main/separator near
        // Control Center until onboarding is completed.
        // This prevents stale machine-specific placement state from shoving the
        // SaneBar icon to the far-left side on install/setup.
        if Self.shouldForceAnchorNearControlCenterOnLaunch() {
            Self.forceMainAndSeparatorAnchorSeed()
        } else {
            // Seed positions BEFORE creating items (position pre-seeding)
            // Position 0 = rightmost (main), Position 1 = second from right (separator)
            Self.seedPositionsIfNeeded()
        }

        // Create main item (rightmost, near Control Center)
        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        Self.enforceNonRemovableBehavior(for: mainItem, role: "main")
        mainItem.autosaveName = Self.mainAutosaveName
        // Cmd-drag removal can persist hidden state per autosaveName.
        // Force visible on startup so users don't get "missing icon forever".
        mainItem.isVisible = true

        // Create separator item (to the LEFT of main)
        separatorItem = NSStatusBar.system.statusItem(withLength: 20)
        Self.enforceNonRemovableBehavior(for: separatorItem, role: "separator")
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

    // MARK: - Position Validation & Self-Healing

    /// Callback invoked after status items are recreated due to corruption recovery.
    var onItemsRecreated: ((_ main: NSStatusItem, _ separator: NSStatusItem) -> Void)?

    /// Checks whether a status item window appears in the menu bar area.
    /// A missing window is treated as invalid so startup recovery can catch
    /// disconnected status-bar scenes where the item never renders at all.
    nonisolated static func isStatusItemWindowFrameValid(windowFrame: CGRect?, screenFrame: CGRect?) -> Bool {
        guard let windowFrame, let screenFrame else {
            return false
        }
        let tolerance: CGFloat = 50
        return abs(screenFrame.maxY - windowFrame.maxY) <= tolerance
    }

    /// Checks whether a status item window appears in the menu bar area.
    static func validateItemPosition(_ item: NSStatusItem) -> Bool {
        let window = item.button?.window
        let screenFrame = window?.screen?.frame ?? NSScreen.main?.frame
        return isStatusItemWindowFrameValid(windowFrame: window?.frame, screenFrame: screenFrame)
    }

    /// Startup is only healthy when both visible SaneBar status items are attached
    /// to real menu bar windows.
    static func validateStartupItems(main: NSStatusItem, separator: NSStatusItem) -> Bool {
        validateItemPosition(main) && validateItemPosition(separator)
    }

    /// Bumps autosave namespace and recreates status items to escape WindowServer
    /// position cache corruption keyed by autosaveName.
    func recreateItemsWithBumpedVersion() -> (main: NSStatusItem, separator: NSStatusItem) {
        let oldVersion = Self.autosaveVersion
        let hadAlwaysHiddenSeparator = alwaysHiddenSeparatorItem != nil
        let nextVersion: Int
        let recycledNamespace: Bool

        if oldVersion < Self.maxAutosaveVersion {
            nextVersion = oldVersion + 1
            recycledNamespace = false
        } else {
            logger.error("Autosave version cap reached (\(Self.maxAutosaveVersion)) — recycling autosave namespace")
            Self.clearHistoricalAutosaveNamespaces()
            nextVersion = Self.baseAutosaveVersion
            recycledNamespace = true
        }

        let currentWidth = NSScreen.main.map { Double($0.frame.width) }
        let currentScreenHasTopSafeAreaInset = Self.screenHasTopSafeAreaInset(NSScreen.main)
        let reanchoredCurrentPair = currentWidth.flatMap { width in
            Self.reanchoredPreferredPositionsTowardControlCenter(
                mainPosition: Self.resolvedPreferredPosition(forAutosaveName: Self.mainAutosaveName),
                separatorPosition: Self.resolvedPreferredPosition(forAutosaveName: Self.separatorAutosaveName),
                screenWidth: width,
                screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
            )
        }

        UserDefaults.standard.set(nextVersion, forKey: Self.autosaveVersionKey)
        if recycledNamespace {
            logger.warning("Recycled autosave namespace \(oldVersion) → \(nextVersion) for status item recovery")
        } else {
            logger.warning("Bumping autosave version \(oldVersion) → \(nextVersion) for status item recovery")
        }

        NSStatusBar.system.removeStatusItem(mainItem)
        NSStatusBar.system.removeStatusItem(separatorItem)
        if let ah = alwaysHiddenSeparatorItem {
            NSStatusBar.system.removeStatusItem(ah)
            alwaysHiddenSeparatorItem = nil
        }
        removeSpacerItems()

        if !recycledNamespace {
            Self.removePreferredPosition(forAutosaveName: "SaneBar_Main_v\(oldVersion)")
            Self.removePreferredPosition(forAutosaveName: "SaneBar_Separator_v\(oldVersion)")
            Self.removePreferredPosition(forAutosaveName: "SaneBar_AlwaysHiddenSeparator_v\(oldVersion)")
        }

        let restoredCurrentDisplayBackup = Self.restoreCurrentDisplayPositionBackupIfAvailable()
        if !restoredCurrentDisplayBackup {
            if let reanchoredCurrentPair {
                Self.setPreferredPosition(reanchoredCurrentPair.main, forAutosaveName: Self.mainAutosaveName)
                Self.setPreferredPosition(reanchoredCurrentPair.separator, forAutosaveName: Self.separatorAutosaveName)
                if let currentWidth {
                    Self.saveDisplayPositionBackupIfNeeded(
                        for: currentWidth,
                        mainPosition: reanchoredCurrentPair.main,
                        separatorPosition: reanchoredCurrentPair.separator
                    )
                }
                logger.info("Recreated status items with autosave version \(nextVersion) using reanchored persisted positions")
            } else {
                if Self.applyLaunchSafeRecoveryPositionsForCurrentDisplay() {
                    logger.info("Recreated status items with autosave version \(nextVersion) using launch-safe recovery positions")
                } else {
                    Self.seedPositionsIfNeeded()
                }
            }
        }
        if hadAlwaysHiddenSeparator {
            Self.seedAlwaysHiddenSeparatorPositionIfNeeded()
        }

        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        Self.enforceNonRemovableBehavior(for: mainItem, role: "main(recreated)")
        mainItem.autosaveName = Self.mainAutosaveName
        mainItem.isVisible = true

        separatorItem = NSStatusBar.system.statusItem(withLength: 20)
        Self.enforceNonRemovableBehavior(for: separatorItem, role: "separator(recreated)")
        separatorItem.autosaveName = Self.separatorAutosaveName
        separatorItem.isVisible = true

        if let button = separatorItem.button {
            configureSeparatorButton(button)
        }
        if let button = mainItem.button {
            button.title = ""
            button.image = makeMainSymbolImage(name: Self.iconHidden)
        }

        if hadAlwaysHiddenSeparator {
            ensureAlwaysHiddenSeparator(enabled: true)
        }

        if restoredCurrentDisplayBackup {
            logger.info("Recreated status items with autosave version \(nextVersion) using current-width display backup")
        } else {
            logger.info("Recreated status items with autosave version \(nextVersion)")
        }
        return (mainItem, separatorItem)
    }

    func recreateItemsFromPersistedPositions() -> (main: NSStatusItem, separator: NSStatusItem) {
        NSStatusBar.system.removeStatusItem(mainItem)
        NSStatusBar.system.removeStatusItem(separatorItem)
        if let ah = alwaysHiddenSeparatorItem {
            NSStatusBar.system.removeStatusItem(ah)
            alwaysHiddenSeparatorItem = nil
        }
        removeSpacerItems()

        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        Self.enforceNonRemovableBehavior(for: mainItem, role: "main(recreated-layout)")
        mainItem.autosaveName = Self.mainAutosaveName
        mainItem.isVisible = true

        separatorItem = NSStatusBar.system.statusItem(withLength: 20)
        Self.enforceNonRemovableBehavior(for: separatorItem, role: "separator(recreated-layout)")
        separatorItem.autosaveName = Self.separatorAutosaveName
        separatorItem.isVisible = true

        if let button = separatorItem.button {
            configureSeparatorButton(button)
        }
        if let button = mainItem.button {
            button.title = ""
            button.image = makeMainSymbolImage(name: Self.iconHidden)
        }

        logger.info("Recreated status items from persisted layout snapshot")
        return (mainItem, separatorItem)
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
        Self.enforceNonRemovableBehavior(for: item, role: "always-hidden-separator")
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

    private static func forceMainAndSeparatorAnchorSeed() {
        logger.info("Onboarding startup: forcing main/separator anchor seeds near Control Center")
        setPreferredPosition(0, forAutosaveName: mainAutosaveName)
        setPreferredPosition(1, forAutosaveName: separatorAutosaveName)
    }

    private static func shouldForceAnchorNearControlCenterOnLaunch() -> Bool {
        if let forced = ProcessInfo.processInfo.environment["SANEBAR_FORCE_ANCHOR_ON_LAUNCH"] {
            return forced == "1"
        }

        // Unit tests intentionally exercise migration/seed behavior with crafted
        // defaults and should not be affected by onboarding-first-run policy.
        if NSClassFromString("XCTestCase") != nil ||
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return false
        }

        guard let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return true
        }
        let settingsURL = base.appendingPathComponent("SaneBar", isDirectory: true)
            .appendingPathComponent("settings.json")

        guard let data = try? Data(contentsOf: settingsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            // No settings file yet => true first launch.
            return true
        }

        // Legacy upgrade path:
        // Older installs may have a settings file without onboarding keys.
        // Treat those users as completed so we do NOT re-force anchor seeds.
        if json["hasCompletedOnboarding"] == nil {
            logger.info("Legacy settings detected (missing hasCompletedOnboarding) — skipping forced anchor seed")
            return false
        }

        // Keep forcing anchor until onboarding is fully complete.
        let hasCompletedOnboarding = (json["hasCompletedOnboarding"] as? Bool) ?? false
        return !hasCompletedOnboarding
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

    /// Resets persisted status-item state to a clean, launch-safe baseline.
    /// Use this for explicit user recovery actions such as Reset to Defaults.
    static func resetPersistentStatusItemState(alwaysHiddenEnabled: Bool) {
        clearPersistedVisibilityOverrides()
        clearHistoricalAutosaveNamespaces()
        clearDisplayPositionBackups()

        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: autosaveVersionKey)
        defaults.removeObject(forKey: screenWidthKey)

        if !applyLaunchSafeRecoveryPositionsForCurrentDisplay() {
            seedPositionsIfNeeded()
        }

        if alwaysHiddenEnabled {
            seedAlwaysHiddenSeparatorPositionIfNeeded()
        }

        logger.info("Reset persistent status item state to a startup-safe baseline")
    }

    /// Best-effort startup recovery used when runtime invariants detect a bad
    /// separator layout. This keeps the current session usable and seeds safe
    /// positions for the next status-item relayout/restart.
    static func recoverStartupPositions(alwaysHiddenEnabled: Bool) {
        if restoreCurrentDisplayPositionBackupIfAvailable() {
            if alwaysHiddenEnabled {
                seedAlwaysHiddenSeparatorPositionIfNeeded()
            }
            logger.info("Recovered startup positions from current-width display backup")
            return
        }
        if let currentWidth = NSScreen.main?.frame.width,
           reanchorCurrentDisplayPositionsIfNeeded(for: currentWidth) {
            if alwaysHiddenEnabled {
                seedAlwaysHiddenSeparatorPositionIfNeeded()
            }
            logger.info("Recovered startup positions by reanchoring persisted positions toward Control Center")
            return
        }
        if !applyLaunchSafeRecoveryPositionsForCurrentDisplay() {
            resetPositionsToOrdinals()
            seedPositionsIfNeeded()
            logger.info("Applied startup position recovery ordinal seeds")
        } else {
            logger.info("Applied launch-safe startup recovery positions")
        }
        if alwaysHiddenEnabled {
            seedAlwaysHiddenSeparatorPositionIfNeeded()
        }
    }

    // MARK: - Display-Aware Position Validation

    /// Returns true if a position value looks like a pixel offset rather than an ordinal seed.
    /// Ordinals are small integers (0, 1, 2). The AH sentinel is 10000.
    /// Pixel offsets from macOS fall in the range ~50–5000 for typical displays.
    nonisolated static func isPixelLikePosition(_ value: Double?) -> Bool {
        guard let v = value else { return false }
        return v > 10 && v < 9000
    }

    nonisolated static func isOrdinalSeedLikePosition(_ value: Double?) -> Bool {
        guard let v = value else { return false }
        return v >= 0 && v <= 10
    }

    nonisolated static func hasOrdinalSeedPair(mainPosition: Double?, separatorPosition: Double?) -> Bool {
        isOrdinalSeedLikePosition(mainPosition) && isOrdinalSeedLikePosition(separatorPosition)
    }

    /// Returns true if the stored and current screen widths differ by more than 10%.
    nonisolated static func isSignificantWidthChange(stored: Double, current: Double) -> Bool {
        guard stored > 0 else { return false }
        let ratio = abs(current - stored) / stored
        return ratio > 0.10
    }

    /// Decide whether a display-change-based position reset is safe to apply.
    /// We only auto-reset when all of the following are true:
    /// - width change is significant
    /// - stored values look pixel-based (not ordinal seeds)
    /// - user is on a single-display setup
    ///
    /// Multi-display setups frequently report different "main" widths across restarts
    /// even when layout is healthy. Resetting there causes avoidable layout regressions.
    nonisolated static func shouldResetForDisplayChange(
        storedWidth: Double,
        currentWidth: Double,
        hasPixelPositions: Bool,
        screenCount: Int
    ) -> Bool {
        guard hasPixelPositions else { return false }
        guard isSignificantWidthChange(stored: storedWidth, current: currentWidth) else { return false }
        guard screenCount <= 1 else { return false }
        return true
    }

    nonisolated static func displayWidthBucket(_ width: Double) -> Int {
        Int(width.rounded())
    }

    nonisolated static func displayPositionBackupKey(for width: Double, slot: String) -> String {
        "\(positionBackupKeyPrefix)_\(displayWidthBucket(width))_\(slot)"
    }

    private nonisolated static func displayPositionBackupKey(for widthBucket: Int, slot: String) -> String {
        "\(positionBackupKeyPrefix)_\(widthBucket)_\(slot)"
    }

    nonisolated static func hasRestorableDisplayBackup(mainBackup: Double?, separatorBackup: Double?) -> Bool {
        isPixelLikePosition(mainBackup) && isPixelLikePosition(separatorBackup)
    }

    nonisolated static func fitsDisplayBackupWithinScreenWidth(
        mainBackup: Double,
        separatorBackup: Double,
        screenWidth: Double,
        trailingPadding: Double = 24
    ) -> Bool {
        guard screenWidth > 0 else { return false }
        let maxPosition = max(10.0, screenWidth - trailingPadding)
        return mainBackup <= maxPosition && separatorBackup <= maxPosition
    }

    nonisolated static func screenHasTopSafeAreaInset(_ screen: NSScreen?) -> Bool {
        guard let screen else { return false }
        return screen.safeAreaInsets.top > 0
    }

    nonisolated static func launchSafePreferredMainPositionLimit(
        for screenWidth: Double,
        screenHasTopSafeAreaInset: Bool
    ) -> Double {
        guard screenWidth > 0 else { return 0 }
        if !screenHasTopSafeAreaInset {
            // Plain external displays need a much tighter recovery anchor than
            // notched displays. On the mini's 1920-wide external panel, values
            // around 140–144 stay pinned beside Control Center while 200 drifts
            // left into the bad startup lane again.
            return min(160, max(60, screenWidth * 0.075))
        }

        // On notched 14/16" MacBook displays, wider preferred-position values
        // like 216 on a 1512-wide screen can still relaunch noticeably left of
        // Control Center. Keep the startup recovery anchor tighter here.
        return 180
    }

    nonisolated static func isLaunchSafeDisplayBackup(
        mainBackup: Double?,
        separatorBackup: Double?,
        screenWidth: Double,
        screenHasTopSafeAreaInset: Bool
    ) -> Bool {
        guard screenWidth > 0,
              hasRestorableDisplayBackup(mainBackup: mainBackup, separatorBackup: separatorBackup),
              let mainBackup,
              let separatorBackup
        else { return false }

        guard separatorBackup > mainBackup else { return false }
        guard fitsDisplayBackupWithinScreenWidth(
            mainBackup: mainBackup,
            separatorBackup: separatorBackup,
            screenWidth: screenWidth
        ) else { return false }
        return mainBackup <= launchSafePreferredMainPositionLimit(
            for: screenWidth,
            screenHasTopSafeAreaInset: screenHasTopSafeAreaInset
        )
    }

    nonisolated static func reanchoredPreferredPositionsTowardControlCenter(
        mainPosition: Double?,
        separatorPosition: Double?,
        screenWidth: Double,
        screenHasTopSafeAreaInset: Bool
    ) -> (main: Double, separator: Double)? {
        guard screenWidth > 0,
              let mainPosition,
              let separatorPosition,
              isPixelLikePosition(mainPosition),
              isPixelLikePosition(separatorPosition),
              separatorPosition > mainPosition
        else { return nil }

        let safeMainLimit = launchSafePreferredMainPositionLimit(
            for: screenWidth,
            screenHasTopSafeAreaInset: screenHasTopSafeAreaInset
        )
        guard mainPosition > safeMainLimit else { return nil }

        let maxSeparator = max(safeMainLimit + 24.0, screenWidth - 24.0)
        let maxGap = max(24.0, maxSeparator - safeMainLimit)
        let preservedGap = min(max(24.0, separatorPosition - mainPosition), maxGap)
        return (main: safeMainLimit, separator: safeMainLimit + preservedGap)
    }

    nonisolated static func launchSafeCurrentDisplayRecoveryPair(
        screenWidth: Double,
        screenHasTopSafeAreaInset: Bool
    ) -> (main: Double, separator: Double)? {
        guard screenWidth > 0 else { return nil }

        let safeMain = launchSafePreferredMainPositionLimit(
            for: screenWidth,
            screenHasTopSafeAreaInset: screenHasTopSafeAreaInset
        )
        let safeSeparator = min(screenWidth - 24.0, safeMain + 120.0)
        guard safeSeparator > safeMain else { return nil }
        return (main: safeMain, separator: safeSeparator)
    }

    @discardableResult
    private static func applyLaunchSafeRecoveryPositionsForCurrentDisplay() -> Bool {
        guard let currentWidth = NSScreen.main?.frame.width,
              let recoveryPair = launchSafeCurrentDisplayRecoveryPair(
                  screenWidth: currentWidth,
                  screenHasTopSafeAreaInset: screenHasTopSafeAreaInset(NSScreen.main)
              )
        else { return false }

        setPreferredPosition(recoveryPair.main, forAutosaveName: mainAutosaveName)
        setPreferredPosition(recoveryPair.separator, forAutosaveName: separatorAutosaveName)
        saveDisplayPositionBackupIfNeeded(
            for: currentWidth,
            mainPosition: recoveryPair.main,
            separatorPosition: recoveryPair.separator
        )
        UserDefaults.standard.set(currentWidth, forKey: screenWidthKey)
        logger.info(
            "Applied launch-safe recovery positions for width \(currentWidth, privacy: .public) (main=\(recoveryPair.main, privacy: .public), separator=\(recoveryPair.separator, privacy: .public))"
        )
        return true
    }

    private static func saveDisplayPositionBackupIfNeeded(
        for width: Double,
        mainPosition: Double?,
        separatorPosition: Double?
    ) {
        let currentScreenHasTopSafeAreaInset = screenHasTopSafeAreaInset(NSScreen.main)
        guard let mainPosition,
              let separatorPosition,
              isPixelLikePosition(mainPosition),
              isPixelLikePosition(separatorPosition)
        else {
            removeDisplayPositionBackup(for: width)
            return
        }

        guard isLaunchSafeDisplayBackup(
            mainBackup: mainPosition,
            separatorBackup: separatorPosition,
            screenWidth: width,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        ) else {
            removeDisplayPositionBackup(for: width)
            logger.warning(
                "Display validation: refusing to save unsafe current-width backup for width \(width, privacy: .public) (main=\(mainPosition, privacy: .public), separator=\(separatorPosition, privacy: .public))"
            )
            return
        }

        let defaults = UserDefaults.standard
        defaults.set(mainPosition, forKey: displayPositionBackupKey(for: width, slot: "main"))
        defaults.set(separatorPosition, forKey: displayPositionBackupKey(for: width, slot: "separator"))
    }

    private static func restoreDisplayPositionBackupIfAvailable(for width: Double) -> Bool {
        let defaults = UserDefaults.standard
        let mainBackup = numericPositionValue(defaults.object(forKey: displayPositionBackupKey(for: width, slot: "main")))
        let separatorBackup = numericPositionValue(defaults.object(forKey: displayPositionBackupKey(for: width, slot: "separator")))
        let currentScreenHasTopSafeAreaInset = screenHasTopSafeAreaInset(NSScreen.main)

        guard hasRestorableDisplayBackup(mainBackup: mainBackup, separatorBackup: separatorBackup),
              let mainBackup,
              let separatorBackup
        else { return false }

        if !isLaunchSafeDisplayBackup(
            mainBackup: mainBackup,
            separatorBackup: separatorBackup,
            screenWidth: width,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        ) {
            if let reanchored = reanchoredPreferredPositionsTowardControlCenter(
                mainPosition: mainBackup,
                separatorPosition: separatorBackup,
                screenWidth: width,
                screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
            ) {
                setPreferredPosition(reanchored.main, forAutosaveName: mainAutosaveName)
                setPreferredPosition(reanchored.separator, forAutosaveName: separatorAutosaveName)
                saveDisplayPositionBackupIfNeeded(
                    for: width,
                    mainPosition: reanchored.main,
                    separatorPosition: reanchored.separator
                )
                logger.warning(
                    "Display validation: reanchored unsafe backup for width \(width, privacy: .public) (main=\(mainBackup, privacy: .public) -> \(reanchored.main, privacy: .public), separator=\(separatorBackup, privacy: .public) -> \(reanchored.separator, privacy: .public))"
                )
                return true
            }

            removeDisplayPositionBackup(for: width)
            logger.warning(
                "Display validation: discarding unsafe backup for width \(width, privacy: .public) (main=\(mainBackup, privacy: .public), separator=\(separatorBackup, privacy: .public))"
            )
            return false
        }

        setPreferredPosition(mainBackup, forAutosaveName: mainAutosaveName)
        setPreferredPosition(separatorBackup, forAutosaveName: separatorAutosaveName)
        logger.info("Display validation: restored backup positions for width \(width)")
        return true
    }

    private static func restoreCurrentDisplayPositionBackupIfAvailable() -> Bool {
        guard let currentWidth = NSScreen.main?.frame.width else { return false }
        guard restoreDisplayPositionBackupIfAvailable(for: currentWidth) else { return false }
        UserDefaults.standard.set(currentWidth, forKey: screenWidthKey)
        return true
    }

    nonisolated static func hasLaunchSafeCurrentDisplayBackupForCurrentDisplay() -> Bool {
        guard let currentWidth = NSScreen.main?.frame.width else { return false }
        let defaults = UserDefaults.standard
        let mainBackup = numericPositionValue(defaults.object(forKey: displayPositionBackupKey(for: currentWidth, slot: "main")))
        let separatorBackup = numericPositionValue(defaults.object(forKey: displayPositionBackupKey(for: currentWidth, slot: "separator")))
        return isLaunchSafeDisplayBackup(
            mainBackup: mainBackup,
            separatorBackup: separatorBackup,
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: screenHasTopSafeAreaInset(NSScreen.main)
        )
    }

    @discardableResult
    static func captureCurrentDisplayPositionBackupIfPossible() -> Bool {
        guard let currentWidth = NSScreen.main?.frame.width else { return false }
        let currentScreenHasTopSafeAreaInset = screenHasTopSafeAreaInset(NSScreen.main)
        let mainPosition = resolvedPreferredPosition(forAutosaveName: mainAutosaveName)
        let separatorPosition = resolvedPreferredPosition(forAutosaveName: separatorAutosaveName)

        if isLaunchSafeDisplayBackup(
            mainBackup: mainPosition,
            separatorBackup: separatorPosition,
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        ) {
            saveDisplayPositionBackupIfNeeded(
                for: currentWidth,
                mainPosition: mainPosition,
                separatorPosition: separatorPosition
            )
            return true
        }

        guard let reanchored = reanchoredPreferredPositionsTowardControlCenter(
            mainPosition: mainPosition,
            separatorPosition: separatorPosition,
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        ) else { return hasLaunchSafeCurrentDisplayBackupForCurrentDisplay() }

        let defaults = UserDefaults.standard
        defaults.set(reanchored.main, forKey: displayPositionBackupKey(for: currentWidth, slot: "main"))
        defaults.set(reanchored.separator, forKey: displayPositionBackupKey(for: currentWidth, slot: "separator"))
        logger.info(
            "Display validation: captured reanchored current-width backup from stable live positions (main=\(reanchored.main, privacy: .public), separator=\(reanchored.separator, privacy: .public), width=\(currentWidth, privacy: .public))"
        )
        return true
    }

    private static func reanchorCurrentDisplayPositionsIfNeeded(for width: Double) -> Bool {
        let currentScreenHasTopSafeAreaInset = screenHasTopSafeAreaInset(NSScreen.main)
        guard let reanchored = reanchoredPreferredPositionsTowardControlCenter(
            mainPosition: resolvedPreferredPosition(forAutosaveName: mainAutosaveName),
            separatorPosition: resolvedPreferredPosition(forAutosaveName: separatorAutosaveName),
            screenWidth: width,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        ) else { return false }

        setPreferredPosition(reanchored.main, forAutosaveName: mainAutosaveName)
        setPreferredPosition(reanchored.separator, forAutosaveName: separatorAutosaveName)
        saveDisplayPositionBackupIfNeeded(
            for: width,
            mainPosition: reanchored.main,
            separatorPosition: reanchored.separator
        )
        logger.warning(
            "Display validation: reanchored current persisted positions toward Control Center (main=\(reanchored.main, privacy: .public), separator=\(reanchored.separator, privacy: .public), width=\(width, privacy: .public))"
        )
        return true
    }

    /// Check if positions need a display reset due to a screen width change.
    /// - First launch after update (no stored width): stamps current width, returns false.
    /// - Same screen (width matches within 10%): returns false.
    /// - Different screen AND pixel-like positions: returns true (triggers reset).
    private static func positionsNeedDisplayReset() -> Bool {
        let defaults = UserDefaults.standard
        let storedWidth = defaults.double(forKey: screenWidthKey)

        guard let currentWidth = NSScreen.main?.frame.width else { return false }
        let screenCount = max(1, NSScreen.screens.count)

        let mainKey = preferredPositionKey(for: mainAutosaveName)
        let sepKey = preferredPositionKey(for: separatorAutosaveName)
        let mainPos = numericPositionValue(defaults.object(forKey: mainKey))
        let sepPos = numericPositionValue(defaults.object(forKey: sepKey))
        let hasPixelPositions = isPixelLikePosition(mainPos) || isPixelLikePosition(sepPos)
        let hasOrdinalSeedPositions = hasOrdinalSeedPair(mainPosition: mainPos, separatorPosition: sepPos)

        if storedWidth == 0 {
            // First launch after update — stamp current width, accept positions as-is
            // Do not eager-reanchor here: the persisted preferred-position values are
            // not a trustworthy proxy for bad live launch geometry, and mutating them
            // before status items exist can collapse the user's visible lane.
            defaults.set(currentWidth, forKey: screenWidthKey)
            saveDisplayPositionBackupIfNeeded(
                for: currentWidth,
                mainPosition: resolvedPreferredPosition(forAutosaveName: mainAutosaveName),
                separatorPosition: resolvedPreferredPosition(forAutosaveName: separatorAutosaveName)
            )
            logger.info("Display validation: first run, stamping screen width \(currentWidth)")
            return false
        }

        if hasOrdinalSeedPositions, restoreDisplayPositionBackupIfAvailable(for: currentWidth) {
            defaults.set(currentWidth, forKey: screenWidthKey)
            logger.info("Display validation: restored current-width backup over ordinal startup seeds")
            return false
        }

        guard isSignificantWidthChange(stored: storedWidth, current: currentWidth) else {
            saveDisplayPositionBackupIfNeeded(
                for: currentWidth,
                mainPosition: resolvedPreferredPosition(forAutosaveName: mainAutosaveName),
                separatorPosition: resolvedPreferredPosition(forAutosaveName: separatorAutosaveName)
            )
            return false
        }

        // Preserve the last known-good layout for the previous display width
        // before we evaluate whether the current width should reset.
        saveDisplayPositionBackupIfNeeded(
            for: storedWidth,
            mainPosition: resolvedPreferredPosition(forAutosaveName: mainAutosaveName),
            separatorPosition: resolvedPreferredPosition(forAutosaveName: separatorAutosaveName)
        )

        // If we have a known-good layout for this display width, restore it and skip reset.
        if restoreDisplayPositionBackupIfAvailable(for: currentWidth) {
            defaults.set(currentWidth, forKey: screenWidthKey)
            return false
        }

        let shouldReset = shouldResetForDisplayChange(
            storedWidth: storedWidth,
            currentWidth: currentWidth,
            hasPixelPositions: hasPixelPositions,
            screenCount: screenCount
        )

        if shouldReset {
            logger.info(
                "Display validation: screen width changed (\(storedWidth) → \(currentWidth)) with pixel positions on single display — resetting"
            )
            return true
        }

        // Preserve healthy layouts on multi-display setups where "main" width
        // can legitimately vary between launches. Re-stamp width to avoid
        // repeatedly re-evaluating the same benign drift.
        if hasPixelPositions, screenCount > 1 {
            logger.info(
                "Display validation: width changed (\(storedWidth) → \(currentWidth)) on multi-display setup (\(screenCount) screens) — preserving layout"
            )
            defaults.set(currentWidth, forKey: screenWidthKey)
        }

        if !hasPixelPositions {
            logger.info(
                "Display validation: width changed (\(storedWidth) → \(currentWidth)) with ordinal positions — preserving layout"
            )
            defaults.set(currentWidth, forKey: screenWidthKey)
        }

        return false
    }

    /// Clears persisted visibility overrides written by macOS after cmd-dragging
    /// a status item out of the menu bar.
    private static func clearPersistedVisibilityOverrides() {
        let defaults = UserDefaults.standard
        var clearedAny = false
        let currentAutosaveNames = [mainAutosaveName, separatorAutosaveName, alwaysHiddenSeparatorAutosaveName]

        // App-domain cleanup: named items + spacer prefix sweep
        for name in currentAutosaveNames {
            let appKey = "NSStatusItem Visible \(name)"
            if defaults.object(forKey: appKey) != nil {
                defaults.removeObject(forKey: appKey)
                clearedAny = true
            }
        }

        // Spacer app-domain keys (SaneBar_spacer_0 through SaneBar_spacer_11)
        let spacerPrefix = "NSStatusItem Visible SaneBar_spacer_"
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(spacerPrefix) {
            defaults.removeObject(forKey: key)
            clearedAny = true
        }

        // ByHost cleanup: wildcard enumeration catches ALL variants
        if removeAllByHostVisibilityOverrides() {
            clearedAny = true
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
            if !applyLaunchSafeRecoveryPositionsForCurrentDisplay() {
                resetPositionsToOrdinals()
            }
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

    nonisolated static func captureLayoutSnapshot() -> SaneBarLayoutSnapshot {
        let defaults = UserDefaults.standard
        var spacerPositions: [Int: Double] = [:]
        for index in 0 ..< maxSpacerCount {
            if let position = resolvedPreferredPosition(forAutosaveName: spacerAutosaveName(index: index)) {
                spacerPositions[index] = position
            }
        }

        return SaneBarLayoutSnapshot(
            mainPosition: resolvedPreferredPosition(forAutosaveName: mainAutosaveName),
            separatorPosition: resolvedPreferredPosition(forAutosaveName: separatorAutosaveName),
            alwaysHiddenSeparatorPosition: resolvedPreferredPosition(forAutosaveName: alwaysHiddenSeparatorAutosaveName),
            spacerPositions: spacerPositions,
            calibratedScreenWidth: numericPositionValue(defaults.object(forKey: screenWidthKey)),
            displayBackups: displayBackupSnapshots()
        )
    }

    nonisolated static func applyLayoutSnapshot(_ snapshot: SaneBarLayoutSnapshot) {
        applyPreferredPosition(snapshot.mainPosition, forAutosaveName: mainAutosaveName)
        applyPreferredPosition(snapshot.separatorPosition, forAutosaveName: separatorAutosaveName)
        applyPreferredPosition(snapshot.alwaysHiddenSeparatorPosition, forAutosaveName: alwaysHiddenSeparatorAutosaveName)

        for index in 0 ..< maxSpacerCount {
            applyPreferredPosition(snapshot.spacerPositions[index], forAutosaveName: spacerAutosaveName(index: index))
        }

        let defaults = UserDefaults.standard
        if let calibratedScreenWidth = snapshot.calibratedScreenWidth {
            defaults.set(calibratedScreenWidth, forKey: screenWidthKey)
        } else {
            defaults.removeObject(forKey: screenWidthKey)
        }

        clearDisplayPositionBackups()
        for backup in snapshot.displayBackups {
            guard let mainPosition = backup.mainPosition,
                  let separatorPosition = backup.separatorPosition,
                  hasRestorableDisplayBackup(mainBackup: mainPosition, separatorBackup: separatorPosition),
                  separatorPosition > mainPosition,
                  fitsDisplayBackupWithinScreenWidth(
                      mainBackup: mainPosition,
                      separatorBackup: separatorPosition,
                      screenWidth: Double(backup.widthBucket)
                  )
            else { continue }

            defaults.set(mainPosition, forKey: displayPositionBackupKey(for: backup.widthBucket, slot: "main"))
            defaults.set(separatorPosition, forKey: displayPositionBackupKey(for: backup.widthBucket, slot: "separator"))
        }
    }

    private static func hasInvalidPositionValue(forAutosaveName autosaveName: String) -> Bool {
        let values = preferredPositionValues(forAutosaveName: autosaveName)
        return isInvalidPosition(values.appValue) || isInvalidPosition(values.byHostValue)
    }

    private static func hasTooSmallAlwaysHiddenPosition(forAutosaveName autosaveName: String) -> Bool {
        let values = preferredPositionValues(forAutosaveName: autosaveName)
        return isTooSmallAlwaysHiddenPosition(values.appValue) || isTooSmallAlwaysHiddenPosition(values.byHostValue)
    }

    private func removeSpacerItems() {
        while let item = spacerItems.popLast() {
            NSStatusBar.system.removeStatusItem(item)
        }
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

    private nonisolated static func preferredPositionKey(for autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(autosaveName)"
    }

    private nonisolated static func byHostAutosaveName(for autosaveName: String) -> String {
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

    private nonisolated static func byHostPreferredPositionKey(for autosaveName: String) -> String {
        "NSStatusItem Preferred Position \(byHostAutosaveName(for: autosaveName))"
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

    private nonisolated static func preferredPositionValues(forAutosaveName autosaveName: String) -> (appValue: Any?, byHostValue: Any?) {
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

    private nonisolated static func resolvedPreferredPosition(forAutosaveName autosaveName: String) -> Double? {
        let values = preferredPositionValues(forAutosaveName: autosaveName)
        return numericPositionValue(values.appValue) ?? numericPositionValue(values.byHostValue)
    }

    private nonisolated static func applyPreferredPosition(_ value: Double?, forAutosaveName autosaveName: String) {
        if let value {
            setPreferredPosition(value, forAutosaveName: autosaveName)
        } else {
            removePreferredPosition(forAutosaveName: autosaveName)
        }
    }

    private nonisolated static func displayBackupSnapshots() -> [SaneBarLayoutSnapshot.DisplayBackup] {
        let defaults = UserDefaults.standard
        let prefix = "\(positionBackupKeyPrefix)_"
        let backupKeys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix(prefix) }

        let bucketPattern = /SaneBar_Position_Backup_(\d+)_(main|separator)/
        var backups: [Int: SaneBarLayoutSnapshot.DisplayBackup] = [:]

        for key in backupKeys {
            guard let match = key.wholeMatch(of: bucketPattern),
                  let widthBucket = Int(match.1)
            else { continue }

            var backup = backups[widthBucket] ?? SaneBarLayoutSnapshot.DisplayBackup(
                widthBucket: widthBucket,
                mainPosition: nil,
                separatorPosition: nil
            )
            let position = numericPositionValue(defaults.object(forKey: key))
            if match.2 == "main" {
                backup.mainPosition = position
            } else {
                backup.separatorPosition = position
            }
            backups[widthBucket] = backup
        }

        return backups.values
            .filter { backup in
                guard let mainPosition = backup.mainPosition,
                      let separatorPosition = backup.separatorPosition,
                      hasRestorableDisplayBackup(mainBackup: mainPosition, separatorBackup: separatorPosition),
                      separatorPosition > mainPosition
                else { return false }

                return fitsDisplayBackupWithinScreenWidth(
                    mainBackup: mainPosition,
                    separatorBackup: separatorPosition,
                    screenWidth: Double(backup.widthBucket)
                )
            }
            .sorted { $0.widthBucket < $1.widthBucket }
    }

    private nonisolated static func clearDisplayPositionBackups() {
        let defaults = UserDefaults.standard
        let prefix = "\(positionBackupKeyPrefix)_"
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }

    private nonisolated static func clearHistoricalAutosaveNamespaces() {
        for version in baseAutosaveVersion ... maxAutosaveVersion {
            for autosaveName in autosaveNamesForCleanup(version: version) {
                removePreferredPosition(forAutosaveName: autosaveName)
                let appVisibilityKey = "NSStatusItem Visible \(autosaveName)"
                UserDefaults.standard.removeObject(forKey: appVisibilityKey)
            }
        }
        _ = removeAllByHostVisibilityOverrides()
    }

    private nonisolated static func removeDisplayPositionBackup(for width: Double) {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: displayPositionBackupKey(for: width, slot: "main"))
        defaults.removeObject(forKey: displayPositionBackupKey(for: width, slot: "separator"))
    }

    private nonisolated static func setPreferredPosition(_ value: Double, forAutosaveName autosaveName: String) {
        let appKey = preferredPositionKey(for: autosaveName)
        UserDefaults.standard.set(value, forKey: appKey)
        setByHostPreferredPosition(value, forAutosaveName: autosaveName)
    }

    private nonisolated static func removePreferredPosition(forAutosaveName autosaveName: String) {
        let appKey = preferredPositionKey(for: autosaveName)
        UserDefaults.standard.removeObject(forKey: appKey)
        removeByHostPreferredPosition(forAutosaveName: autosaveName)
    }

    private nonisolated static func setByHostPreferredPosition(_ value: Double, forAutosaveName autosaveName: String) {
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

    private nonisolated static func removeByHostPreferredPosition(forAutosaveName autosaveName: String) {
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

    /// Enumerate ALL ByHost keys matching SaneBar visibility prefixes and remove them.
    /// This catches every variant macOS may write — known casing, legacy lowercased,
    /// future `_vN` suffixes, spacer items, and macOS 26's `VisibleCC` keys.
    private nonisolated static func removeAllByHostVisibilityOverrides() -> Bool {
        let globalDomain = ".GlobalPreferences" as CFString
        guard let allKeys = CFPreferencesCopyKeyList(
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? [String] else { return false }

        let prefixes = [
            "NSStatusItem Visible SaneBar_",
            "NSStatusItem VisibleCC SaneBar_"
        ]
        let keysToRemove = allKeys.filter { key in
            prefixes.contains(where: { key.hasPrefix($0) })
        }
        guard !keysToRemove.isEmpty else { return false }

        for key in keysToRemove {
            CFPreferencesSetValue(
                key as CFString,
                nil,
                globalDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        }
        CFPreferencesSynchronize(
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        return true
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
        findItem.setShortcut(for: .searchMenuBar)
        menu.addItem(findItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: configuration.settingsAction, keyEquivalent: ",")
        menu.addItem(settingsItem)

        if let showReleaseNotesAction = configuration.showReleaseNotesAction {
            let whatsNewItem = NSMenuItem(title: "What's New...", action: showReleaseNotesAction, keyEquivalent: "")
            menu.addItem(whatsNewItem)
        }

        let updateItem = NSMenuItem(title: "Check for Updates...", action: configuration.checkForUpdatesAction, keyEquivalent: "")
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit SaneBar", action: configuration.quitAction, keyEquivalent: "q")
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
            Self.enforceNonRemovableBehavior(for: spacer, role: "spacer")
            spacer.autosaveName = Self.spacerAutosaveName(index: spacerItems.count)
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
        Self.enforceNonRemovableBehavior(for: spacer, role: "spacer")
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

    private static func enforceNonRemovableBehavior(for item: NSStatusItem, role: String) {
        let original = item.behavior
        let sanitized = original.subtracting(Self.interactiveRemovalBehaviors)
        item.behavior = sanitized
        if sanitized != original {
            logger.info("Removed interactive removal behavior for \(role, privacy: .public)")
        } else {
            logger.debug("Interactive removal disabled for \(role, privacy: .public)")
        }
    }
}
