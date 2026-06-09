import AppKit
import KeyboardShortcuts
import os.log
import SaneUI

private let logger = Logger(subsystem: "com.sanebar.app", category: "StatusBarController")

// MARK: - Menu Configuration

struct MenuConfiguration {
    let toggleAction: Selector
    let findIconAction: Selector
    let arrangeNowAction: Selector
    let healthAction: Selector
    let settingsAction: Selector
    let licenseAction: Selector
    let aboutAndBugReportAction: Selector
    let showReleaseNotesAction: Selector?
    let checkForUpdatesAction: Selector
    let quitAction: Selector
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
    // Keep base at v7 to avoid resetting healthy existing user layouts.
    private nonisolated static let autosaveVersionKey = "SaneBar_AutosaveVersion"
    private nonisolated static let baseAutosaveVersion = 7
    private nonisolated static let maxAutosaveVersion = 99
    private nonisolated static func autosaveNamesForCleanup(version: Int) -> [String] {
        [
            "SaneBar_Main_v\(version)",
            "SaneBar_Separator_v\(version)",
            "SaneBar_AlwaysHiddenSeparator_v\(version)",
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
    private nonisolated static let interactiveRemovalBehaviors: NSStatusItem.Behavior = [
        .removalAllowed,
        .terminationOnRemoval,
    ]
nonisolated static func seedAlwaysHiddenSeparatorPositionIfNeeded() { StatusBarPositionRecoveryStore.seedAlwaysHiddenSeparatorPositionIfNeeded() }
nonisolated static func resetPositionsToOrdinals() { StatusBarPositionRecoveryStore.resetPositionsToOrdinals() }
nonisolated static func resetPersistentStatusItemState(alwaysHiddenEnabled: Bool, referenceScreen: NSScreen? = nil) {
    StatusBarPositionRecoveryStore.resetPersistentStatusItemState(alwaysHiddenEnabled: alwaysHiddenEnabled, referenceScreen: referenceScreen)
}
nonisolated static func resetPersistentStatusItemState(alwaysHiddenEnabled: Bool, referenceScreen: NSScreen? = nil, freshAutosaveNamespace: Bool) {
    StatusBarPositionRecoveryStore.resetPersistentStatusItemState(alwaysHiddenEnabled: alwaysHiddenEnabled, referenceScreen: referenceScreen, freshAutosaveNamespace: freshAutosaveNamespace)
}
nonisolated static func recoverStartupPositions(alwaysHiddenEnabled: Bool, referenceScreen: NSScreen? = nil) {
    StatusBarPositionRecoveryStore.recoverStartupPositions(alwaysHiddenEnabled: alwaysHiddenEnabled, referenceScreen: referenceScreen)
}
nonisolated static func isPixelLikePosition(_ value: Double?) -> Bool { StatusBarPositionStore.isPixelLikePosition(value) }
nonisolated static func isOrdinalSeedLikePosition(_ value: Double?) -> Bool { StatusBarPositionStore.isOrdinalSeedLikePosition(value) }
nonisolated static func hasOrdinalSeedPair(mainPosition: Double?, separatorPosition: Double?) -> Bool {
    StatusBarPositionStore.hasOrdinalSeedPair(mainPosition: mainPosition, separatorPosition: separatorPosition)
}
nonisolated static func isSignificantWidthChange(stored: Double, current: Double) -> Bool { StatusBarPositionStore.isSignificantWidthChange(stored: stored, current: current) }
nonisolated static func shouldResetForDisplayChange(storedWidth: Double, currentWidth: Double, hasPixelPositions: Bool, screenCount: Int) -> Bool {
    StatusBarPositionStore.shouldResetForDisplayChange(storedWidth: storedWidth, currentWidth: currentWidth, hasPixelPositions: hasPixelPositions, screenCount: screenCount)
}
nonisolated static func displayWidthBucket(_ width: Double) -> Int { StatusBarPositionStore.displayWidthBucket(width) }
nonisolated static func displayPositionBackupKey(for width: Double, slot: String) -> String { StatusBarPositionStore.displayPositionBackupKey(for: width, slot: slot) }
nonisolated static func displayPositionBackupKey(for widthBucket: Int, screenSignature: String?, slot: String) -> String {
    StatusBarPositionStore.displayPositionBackupKey(for: widthBucket, screenSignature: screenSignature, slot: slot)
}
nonisolated static func shouldAllowLegacyDisplayBackupFallback(widthBucket: Int, activeWidthBuckets: [Int]) -> Bool {
    StatusBarPositionStore.shouldAllowLegacyDisplayBackupFallback(widthBucket: widthBucket, activeWidthBuckets: activeWidthBuckets)
}
nonisolated static func hasRestorableDisplayBackup(mainBackup: Double?, separatorBackup: Double?) -> Bool {
    StatusBarPositionStore.hasRestorableDisplayBackup(mainBackup: mainBackup, separatorBackup: separatorBackup)
}
nonisolated static func fitsDisplayBackupWithinScreenWidth(mainBackup: Double, separatorBackup: Double, screenWidth: Double, trailingPadding: Double = 24) -> Bool {
    StatusBarPositionStore.fitsDisplayBackupWithinScreenWidth(mainBackup: mainBackup, separatorBackup: separatorBackup, screenWidth: screenWidth, trailingPadding: trailingPadding)
}
nonisolated static func screenHasTopSafeAreaInset(_ screen: NSScreen?) -> Bool { StatusBarPositionStore.screenHasTopSafeAreaInset(screen) }
nonisolated static func launchSafePreferredMainPositionLimit(for screenWidth: Double, screenHasTopSafeAreaInset: Bool) -> Double {
    StatusBarPositionStore.launchSafePreferredMainPositionLimit(for: screenWidth, screenHasTopSafeAreaInset: screenHasTopSafeAreaInset)
}
nonisolated static func isLaunchSafeDisplayBackup(mainBackup: Double?, separatorBackup: Double?, screenWidth: Double, screenHasTopSafeAreaInset: Bool) -> Bool {
    StatusBarPositionStore.isLaunchSafeDisplayBackup(mainBackup: mainBackup, separatorBackup: separatorBackup, screenWidth: screenWidth, screenHasTopSafeAreaInset: screenHasTopSafeAreaInset)
}
nonisolated static func reanchoredPreferredPositionsTowardControlCenter(mainPosition: Double?, separatorPosition: Double?, screenWidth: Double, screenHasTopSafeAreaInset: Bool) -> (main: Double, separator: Double)? {
    StatusBarPositionStore.reanchoredPreferredPositionsTowardControlCenter(mainPosition: mainPosition, separatorPosition: separatorPosition, screenWidth: screenWidth, screenHasTopSafeAreaInset: screenHasTopSafeAreaInset)
}
nonisolated static func launchSafePreferredSeparatorGap(for screenWidth: Double) -> Double { StatusBarPositionStore.launchSafePreferredSeparatorGap(for: screenWidth) }
nonisolated static func launchSafeCurrentDisplayRecoveryPair(screenWidth: Double, screenHasTopSafeAreaInset: Bool) -> (main: Double, separator: Double)? {
    StatusBarPositionStore.launchSafeCurrentDisplayRecoveryPair(screenWidth: screenWidth, screenHasTopSafeAreaInset: screenHasTopSafeAreaInset)
}
nonisolated static func hasLaunchSafeCurrentDisplayBackupForCurrentDisplay(referenceScreen: NSScreen? = nil) -> Bool {
    StatusBarPositionStore.hasLaunchSafeCurrentDisplayBackupForCurrentDisplay(referenceScreen: referenceScreen)
}
@discardableResult
nonisolated static func captureCurrentDisplayPositionBackupIfPossible(referenceScreen: NSScreen? = nil, mainPosition overrideMainPosition: Double? = nil, separatorPosition overrideSeparatorPosition: Double? = nil) -> Bool {
    StatusBarPositionStore.captureCurrentDisplayPositionBackupIfPossible(referenceScreen: referenceScreen, mainPosition: overrideMainPosition, separatorPosition: overrideSeparatorPosition)
}
nonisolated static func captureLayoutSnapshot() -> SaneBarLayoutSnapshot { StatusBarLayoutSnapshotStore.captureLayoutSnapshot() }
nonisolated static func applyLayoutSnapshot(_ snapshot: SaneBarLayoutSnapshot) { StatusBarLayoutSnapshotStore.applyLayoutSnapshot(snapshot) }
nonisolated static func shouldSeedPreferredPosition(appValue: Any?, byHostValue: Any?) -> Bool {
    StatusBarPositionDefaultsStore.shouldSeedPreferredPosition(appValue: appValue, byHostValue: byHostValue)
}

    // MARK: - Initialization

    init() {
        // Cmd-drag can persist NSStatusItem visibility overrides. Clear them on
        // every launch so a single drag-out cannot permanently hide SaneBar.
        StatusBarPositionStore.clearPersistedVisibilityOverrides()

        // One-time migration for known corrupted position state.
        // Healthy user layouts are preserved.
        StatusBarPositionStore.migrateCorruptedPositionsIfNeeded()

        // Display-aware validation: reset pixel positions from a different screen
        if StatusBarPositionStore.positionsNeedDisplayReset() {
            if !StatusBarPositionStore.applyLaunchSafeRecoveryPositionsForCurrentDisplay() {
                StatusBarPositionRecoveryStore.resetPositionsToOrdinals()
                if let w = StatusBarPositionStore.resolvedReferenceScreen()?.frame.width {
                    UserDefaults.standard.set(w, forKey: StatusBarPositionStore.screenWidthKey)
                }
            }
        }

        // First-run onboarding reliability: hard-anchor main/separator near
        // Control Center until onboarding is completed.
        // This prevents stale machine-specific placement state from shoving the
        // SaneBar icon to the far-left side on install/setup.
        if StatusBarPositionRecoveryStore.shouldForceAnchorNearControlCenterOnLaunch() {
            StatusBarPositionRecoveryStore.forceMainAndSeparatorAnchorSeed()
        } else {
            // Seed positions BEFORE creating items (position pre-seeding)
            // Position 0 = rightmost (main), Position 1 = second from right (separator)
            StatusBarPositionRecoveryStore.seedPositionsIfNeeded()
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
        let verticalTolerance: CGFloat = 50
        let horizontalTolerance: CGFloat = 8
        let verticalMatch = abs(screenFrame.maxY - windowFrame.maxY) <= verticalTolerance
        let horizontalOverlap = windowFrame.maxX >= (screenFrame.minX - horizontalTolerance) &&
            windowFrame.minX <= (screenFrame.maxX + horizontalTolerance)
        return verticalMatch && horizontalOverlap
    }

    /// Checks whether a status item window appears in the menu bar area.
    static func validateItemPosition(_ item: NSStatusItem) -> Bool {
        let window = item.button?.window
        let screenFrame = window?.screen?.frame ?? StatusBarPositionStore.resolvedReferenceScreen()?.frame
        return isStatusItemWindowFrameValid(windowFrame: window?.frame, screenFrame: screenFrame)
    }

    /// Startup is only healthy when both visible SaneBar status items are attached
    /// to real menu bar windows.
    static func validateStartupItems(main: NSStatusItem, separator: NSStatusItem) -> Bool {
        validateItemPosition(main) && validateItemPosition(separator)
    }

    /// Bumps autosave namespace and recreates status items to escape WindowServer
    /// position cache corruption keyed by autosaveName.
    /// When escalating after a failed recovery pass, callers can skip replaying the
    /// current-width backup so the new namespace falls back to stricter safe anchors.
    func recreateItemsWithBumpedVersion(
        referenceScreen: NSScreen? = nil,
        allowCurrentDisplayBackup: Bool = true
    ) -> (main: NSStatusItem, separator: NSStatusItem) {
        let oldVersion = Self.autosaveVersion
        let hadAlwaysHiddenSeparator = alwaysHiddenSeparatorItem != nil
        let nextVersion: Int
        let recycledNamespace: Bool

        if oldVersion < Self.maxAutosaveVersion {
            nextVersion = oldVersion + 1
            recycledNamespace = false
        } else {
            logger.error("Autosave version cap reached (\(Self.maxAutosaveVersion)) — recycling autosave namespace")
            StatusBarPositionDefaultsStore.clearHistoricalAutosaveNamespaces()
            nextVersion = Self.baseAutosaveVersion
            recycledNamespace = true
        }

        let resolvedReferenceScreen = referenceScreen ??
            mainItem.button?.window?.screen ??
            separatorItem.button?.window?.screen ??
            StatusBarPositionStore.resolvedReferenceScreen()
        let currentWidth = resolvedReferenceScreen.map { Double($0.frame.width) }
        let currentScreenHasTopSafeAreaInset = Self.screenHasTopSafeAreaInset(resolvedReferenceScreen)
        let reanchoredCurrentPair = currentWidth.flatMap { width in
            StatusBarPositionStore.reanchoredPreferredPositionsTowardControlCenter(
                mainPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: Self.mainAutosaveName),
                separatorPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: Self.separatorAutosaveName),
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
            StatusBarPositionDefaultsStore.removePreferredPosition(forAutosaveName: "SaneBar_Main_v\(oldVersion)")
            StatusBarPositionDefaultsStore.removePreferredPosition(forAutosaveName: "SaneBar_Separator_v\(oldVersion)")
            StatusBarPositionDefaultsStore.removePreferredPosition(forAutosaveName: "SaneBar_AlwaysHiddenSeparator_v\(oldVersion)")
        }

        let restoredCurrentDisplayBackup = allowCurrentDisplayBackup &&
            StatusBarPositionStore.restoreCurrentDisplayPositionBackupIfAvailable(referenceScreen: resolvedReferenceScreen)
        if !restoredCurrentDisplayBackup {
            if let reanchoredCurrentPair {
                StatusBarPositionDefaultsStore.setPreferredPosition(reanchoredCurrentPair.main, forAutosaveName: Self.mainAutosaveName)
                StatusBarPositionDefaultsStore.setPreferredPosition(reanchoredCurrentPair.separator, forAutosaveName: Self.separatorAutosaveName)
                if let currentWidth {
                    StatusBarPositionStore.saveDisplayPositionBackupIfNeeded(
                        for: currentWidth,
                        mainPosition: reanchoredCurrentPair.main,
                        separatorPosition: reanchoredCurrentPair.separator,
                        referenceScreen: resolvedReferenceScreen
                    )
                }
                logger.info("Recreated status items with autosave version \(nextVersion) using reanchored persisted positions")
            } else {
                if StatusBarPositionStore.applyLaunchSafeRecoveryPositionsForCurrentDisplay(referenceScreen: resolvedReferenceScreen) {
                    logger.info("Recreated status items with autosave version \(nextVersion) using launch-safe recovery positions")
                } else {
                    StatusBarPositionRecoveryStore.seedPositionsIfNeeded()
                }
            }
        }
        if hadAlwaysHiddenSeparator {
            StatusBarPositionRecoveryStore.seedAlwaysHiddenSeparatorPositionIfNeeded()
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

    func recreateItemsFromPersistedPositions(
        afterRemovingExistingItems: (() -> Void)? = nil
    ) -> (main: NSStatusItem, separator: NSStatusItem) {
        NSStatusBar.system.removeStatusItem(mainItem)
        NSStatusBar.system.removeStatusItem(separatorItem)
        if let ah = alwaysHiddenSeparatorItem {
            NSStatusBar.system.removeStatusItem(ah)
            alwaysHiddenSeparatorItem = nil
        }
        removeSpacerItems()
        afterRemovingExistingItems?()

        // Replaying stale persisted positions after wake/display changes can park
        // the toggle and separator far from Control Center (#136). Clamp unsafe
        // persisted positions toward the safe right zone before macOS replays them.
        let resolvedReferenceScreen = StatusBarPositionStore.resolvedReferenceScreen()
        if let screenWidth = resolvedReferenceScreen.map({ Double($0.frame.width) }),
           let reanchoredPair = StatusBarPositionStore.reanchoredPreferredPositionsTowardControlCenter(
               mainPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: Self.mainAutosaveName),
               separatorPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: Self.separatorAutosaveName),
               screenWidth: screenWidth,
               screenHasTopSafeAreaInset: Self.screenHasTopSafeAreaInset(resolvedReferenceScreen)
           ) {
            StatusBarPositionDefaultsStore.setPreferredPosition(reanchoredPair.main, forAutosaveName: Self.mainAutosaveName)
            StatusBarPositionDefaultsStore.setPreferredPosition(reanchoredPair.separator, forAutosaveName: Self.separatorAutosaveName)
            logger.warning(
                "Reanchored unsafe persisted positions before replay (main=\(reanchoredPair.main, privacy: .public), separator=\(reanchoredPair.separator, privacy: .public))"
            )
        }

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

        StatusBarPositionRecoveryStore.seedAlwaysHiddenSeparatorPositionIfNeeded()

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

    private func removeSpacerItems() {
        while let item = spacerItems.popLast() {
            NSStatusBar.system.removeStatusItem(item)
        }
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

        let toggleItem = NSMenuItem(title: "Show / Hide Icons", action: configuration.toggleAction, keyEquivalent: "")
        toggleItem.setShortcut(for: .toggleHiddenItems)
        menu.addItem(toggleItem)

        menu.addItem(NSMenuItem.separator())

        let arrangeItem = NSMenuItem(title: "Arrange Now", action: configuration.arrangeNowAction, keyEquivalent: "")
        menu.addItem(arrangeItem)

        let healthItem = NSMenuItem(title: "Help / Repair...", action: configuration.healthAction, keyEquivalent: "")
        menu.addItem(healthItem)

        menu.addItem(NSMenuItem.separator())

        SaneStandardMenu.addCoreUtilityItems(
            to: menu,
            appName: "SaneBar",
            target: nil,
            settingsAction: configuration.settingsAction,
            licenseAction: configuration.licenseAction,
            checkForUpdatesAction: configuration.checkForUpdatesAction,
            aboutAndBugReportAction: configuration.aboutAndBugReportAction,
            whatsNewAction: configuration.showReleaseNotesAction,
            quitAction: configuration.quitAction,
            settingsKeyEquivalent: ","
        )

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
