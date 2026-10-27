import AppKit
import KeyboardShortcuts
import os.log
import SaneUI

private let logger = Logger(subsystem: "com.sanebar.app", category: "StatusBarController")


struct MenuConfiguration {
    let toggleAction: Selector
    let findIconAction: Selector
    let arrangeNowAction: Selector
    let healthAction: Selector
    let settingsAction: Selector
    let licenseAction: Selector
    let donateAction: Selector?
    let aboutAndBugReportAction: Selector
    let showReleaseNotesAction: Selector?
    let checkForUpdatesAction: Selector?
    let quitAction: Selector
}


@MainActor
protocol StatusBarControllerProtocol {
    var mainItem: NSStatusItem { get }
    var separatorItem: NSStatusItem { get }
    var alwaysHiddenSeparatorItem: NSStatusItem? { get }

    func iconName(for state: HidingState) -> String
    func createMenu(configuration: MenuConfiguration) -> NSMenu
}


@MainActor
final class StatusBarController: StatusBarControllerProtocol {

    private(set) var mainItem: NSStatusItem
    private(set) var separatorItem: NSStatusItem
    private(set) var alwaysHiddenSeparatorItem: NSStatusItem?
    private var spacerItems: [NSStatusItem] = []


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


    nonisolated static let iconExpanded = "line.3.horizontal.decrease"
    nonisolated static let iconHidden = "line.3.horizontal.decrease"
    nonisolated static let maxSpacerCount = 12
    private nonisolated static let interactiveRemovalBehaviors: NSStatusItem.Behavior = [
        .removalAllowed,
        .terminationOnRemoval,
    ]


    init() {
        StatusBarPositionStore.clearPersistedVisibilityOverrides()

        StatusBarPositionStore.migrateCorruptedPositionsIfNeeded()

        if StatusBarPositionStore.positionsNeedDisplayReset() {
            if !StatusBarPositionStore.applyLaunchSafeRecoveryPositionsForCurrentDisplay() {
                StatusBarPositionRecoveryStore.resetPositionsToOrdinals()
                if let w = StatusBarPositionStore.resolvedReferenceScreen()?.frame.width {
                    UserDefaults.standard.set(w, forKey: StatusBarPositionStore.screenWidthKey)
                }
            }
        }

        if StatusBarPositionRecoveryStore.shouldForceAnchorNearControlCenterOnLaunch() {
            StatusBarPositionRecoveryStore.forceMainAndSeparatorAnchorSeed()
        } else {
            StatusBarPositionRecoveryStore.seedPositionsIfNeeded()
        }

        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        Self.enforceNonRemovableBehavior(for: mainItem, role: "main")
        mainItem.autosaveName = Self.mainAutosaveName
        mainItem.isVisible = true

        separatorItem = NSStatusBar.system.statusItem(withLength: 20)
        Self.enforceNonRemovableBehavior(for: separatorItem, role: "separator")
        separatorItem.autosaveName = Self.separatorAutosaveName
        separatorItem.isVisible = true

        if let button = separatorItem.button {
            configureSeparatorButton(button)
        }

        if let button = mainItem.button {
            button.title = ""
            button.image = makeMainSymbolImage(name: Self.iconHidden)
        }

        logger.info("StatusBarController initialized")
    }


    var onItemsRecreated: ((_ main: NSStatusItem, _ separator: NSStatusItem) -> Void)?

    nonisolated static func isStatusItemWindowFrameValid(windowFrame: CGRect?, screenFrame: CGRect?) -> Bool {
        guard let windowFrame else { return false }
        return MenuBarMoveGeometryPolicy.statusItemFrameLooksLive(
            frame: windowFrame,
            screenFrame: screenFrame
        )
    }

    static func validateItemPosition(_ item: NSStatusItem) -> Bool {
        guard let windowFrame = item.button?.window?.frame else { return false }
        let attachedScreenFrame = item.button?.window?.screen?.frame
        let resolvedScreenFrame = MenuBarMoveGeometryPolicy.resolvedScreenFrameForStatusItemWindow(
            windowFrame: windowFrame,
            attachedScreenFrame: attachedScreenFrame,
            candidateScreenFrames: NSScreen.screens.map(\.frame)
        )
        return isStatusItemWindowFrameValid(windowFrame: windowFrame, screenFrame: resolvedScreenFrame)
    }

    static func validateStartupItems(main: NSStatusItem, separator: NSStatusItem) -> Bool {
        validateItemPosition(main) && validateItemPosition(separator)
    }

    func recreateItemsWithBumpedVersion(
        referenceScreen: NSScreen? = nil,
        allowCurrentDisplayBackup: Bool = true,
        reanchorUnsafePersistedPositions: Bool = true
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
        let currentScreenHasTopSafeAreaInset = StatusBarPositionStore.screenHasTopSafeAreaInset(resolvedReferenceScreen)
        let fm2BumpCalibratedWidth = UserDefaults.standard.double(forKey: StatusBarPositionStore.screenWidthKey)
        let originalPersistedMain = StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: Self.mainAutosaveName)
        let originalPersistedSeparator = StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: Self.separatorAutosaveName)
        let bumpedNamespacePositions = StatusBarPositionRecoveryStore.bumpedNamespaceRecoveryPositions(
            originalMain: originalPersistedMain,
            originalSeparator: originalPersistedSeparator,
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset,
            reanchorUnsafePersistedPositions: reanchorUnsafePersistedPositions
        )

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
        var shouldFlushCurrentDisplayBackupAfterRecreate = restoredCurrentDisplayBackup
        if !restoredCurrentDisplayBackup {
            if let bumpedNamespacePositions {
                StatusBarPositionDefaultsStore.setPreferredPosition(bumpedNamespacePositions.main, forAutosaveName: Self.mainAutosaveName)
                StatusBarPositionDefaultsStore.setPreferredPosition(bumpedNamespacePositions.separator, forAutosaveName: Self.separatorAutosaveName)
                if reanchorUnsafePersistedPositions {
                    if let currentWidth {
                        StatusBarPositionStore.saveDisplayPositionBackupIfNeeded(
                            for: currentWidth,
                            mainPosition: bumpedNamespacePositions.main,
                            separatorPosition: bumpedNamespacePositions.separator,
                            referenceScreen: resolvedReferenceScreen
                        )
                    }
                    shouldFlushCurrentDisplayBackupAfterRecreate = true
                    logger.info("Recreated status items with autosave version \(nextVersion) using reanchored persisted positions")
                } else {
                    logger.info("Recreated status items with autosave version \(nextVersion) preserving the explicit persisted divider (FM-2 wake/Space path)")
                }
            } else if reanchorUnsafePersistedPositions {
                if StatusBarPositionStore.applyLaunchSafeRecoveryPositionsForCurrentDisplay(referenceScreen: resolvedReferenceScreen) {
                    shouldFlushCurrentDisplayBackupAfterRecreate = true
                    logger.info("Recreated status items with autosave version \(nextVersion) using launch-safe recovery positions")
                } else {
                    StatusBarPositionRecoveryStore.seedPositionsIfNeeded()
                }
            } else {
                StatusBarPositionRecoveryStore.seedPositionsIfNeeded()
            }
        }
        if hadAlwaysHiddenSeparator {
            StatusBarPositionRecoveryStore.seedAlwaysHiddenSeparatorPositionIfNeeded(referenceScreen: resolvedReferenceScreen)
        }

        if !reanchorUnsafePersistedPositions {
            StatusBarPositionRecoveryStore.restoreExplicitDividerIfLaunderedOnSameDisplay(
                capturedMain: originalPersistedMain,
                capturedSeparator: originalPersistedSeparator,
                calibratedWidth: fm2BumpCalibratedWidth,
                referenceScreen: resolvedReferenceScreen
            )
        }

        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        Self.enforceNonRemovableBehavior(for: mainItem, role: "main(recreated)")
        mainItem.autosaveName = Self.mainAutosaveName
        mainItem.isVisible = true

        separatorItem = NSStatusBar.system.statusItem(withLength: 20)
        Self.enforceNonRemovableBehavior(for: separatorItem, role: "separator(recreated)")
        separatorItem.autosaveName = Self.separatorAutosaveName
        separatorItem.isVisible = true

        if shouldFlushCurrentDisplayBackupAfterRecreate {
            _ = StatusBarPositionStore.restoreCurrentDisplayPositionBackupIfAvailable(referenceScreen: resolvedReferenceScreen)
        }

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
        afterRemovingExistingItems: (() -> Void)? = nil,
        reanchorUnsafePersistedPositions: Bool = true
    ) -> (main: NSStatusItem, separator: NSStatusItem) {
        let fm2CapturedMain = StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: Self.mainAutosaveName)
        let fm2CapturedSeparator = StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: Self.separatorAutosaveName)
        let fm2CalibratedWidth = UserDefaults.standard.double(forKey: StatusBarPositionStore.screenWidthKey)
        NSStatusBar.system.removeStatusItem(mainItem)
        NSStatusBar.system.removeStatusItem(separatorItem)
        if let ah = alwaysHiddenSeparatorItem {
            NSStatusBar.system.removeStatusItem(ah)
            alwaysHiddenSeparatorItem = nil
        }
        removeSpacerItems()
        afterRemovingExistingItems?()

        let resolvedReferenceScreen = StatusBarPositionStore.resolvedReferenceScreen()
        if reanchorUnsafePersistedPositions,
           let screenWidth = resolvedReferenceScreen.map({ Double($0.frame.width) }),
           let reanchoredPair = StatusBarPositionStore.reanchoredPreferredPositionsTowardControlCenter(
               mainPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: Self.mainAutosaveName),
               separatorPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: Self.separatorAutosaveName),
               screenWidth: screenWidth,
               screenHasTopSafeAreaInset: StatusBarPositionStore.screenHasTopSafeAreaInset(resolvedReferenceScreen)
           )
        {
            StatusBarPositionDefaultsStore.setPreferredPosition(reanchoredPair.main, forAutosaveName: Self.mainAutosaveName)
            StatusBarPositionDefaultsStore.setPreferredPosition(reanchoredPair.separator, forAutosaveName: Self.separatorAutosaveName)
            logger.warning(
                "Reanchored unsafe persisted positions before replay (main=\(reanchoredPair.main, privacy: .public), separator=\(reanchoredPair.separator, privacy: .public))"
            )
        }

        if !reanchorUnsafePersistedPositions {
            StatusBarPositionRecoveryStore.restoreExplicitDividerIfLaunderedOnSameDisplay(
                capturedMain: fm2CapturedMain,
                capturedSeparator: fm2CapturedSeparator,
                calibratedWidth: fm2CalibratedWidth,
                referenceScreen: resolvedReferenceScreen
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


    func ensureAlwaysHiddenSeparator(enabled: Bool) {
        guard enabled else {
            if let item = alwaysHiddenSeparatorItem {
                NSStatusBar.system.removeStatusItem(item)
                alwaysHiddenSeparatorItem = nil
                let ahKey = "NSStatusItem Preferred Position \(Self.alwaysHiddenSeparatorAutosaveName)"
                UserDefaults.standard.removeObject(forKey: ahKey)
                logger.info("Always-hidden separator removed + position cleared")
            }
            return
        }
        guard alwaysHiddenSeparatorItem == nil else { return }

        StatusBarPositionRecoveryStore.seedAlwaysHiddenSeparatorPositionIfNeeded(referenceScreen: NSScreen.main ?? NSScreen.screens.first)

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


    private(set) var currentIconStyle: SaneBarSettings.MenuBarIconStyle = .filter

    private var customIconImage: NSImage?

    func iconName(for _: HidingState) -> String {
        currentIconStyle.sfSymbolName ?? "line.3.horizontal.decrease"
    }

    func updateAppearance(for _: HidingState) {
        guard let button = mainItem.button else { return }
        button.title = ""
        button.image = resolveIcon(for: currentIconStyle)
    }

    func updateIconStyle(_ style: SaneBarSettings.MenuBarIconStyle, customIcon: NSImage? = nil) {
        currentIconStyle = style
        if let customIcon {
            customIconImage = customIcon
        }
        guard let button = mainItem.button else { return }
        button.title = ""
        button.image = resolveIcon(for: style)
    }

    private func resolveIcon(for style: SaneBarSettings.MenuBarIconStyle) -> NSImage? {
        if style == .custom, let custom = customIconImage {
            return custom
        }
        guard let symbolName = style.sfSymbolName else {
            return Self.makeSymbolImage(name: "line.3.horizontal.decrease")
        }
        return Self.makeSymbolImage(name: symbolName)
    }

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


    func updateSeparatorStyle(_ style: SaneBarSettings.DividerStyle, isHidden: Bool = false) {
        guard let button = separatorItem.button else { return }

        button.image = nil
        button.title = ""
        button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        button.cell?.isEnabled = true

        if isHidden {
            button.alphaValue = 0
            button.cell?.isEnabled = false
            return
        }

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

        if !isHidden {
            separatorItem.length = styleLength
        }

        button.alphaValue = 0.7
    }


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
            extraUtilityItems: configuration.donateAction.map { action in
                [SaneStandardMenu.item(title: "Donate...", target: nil, action: action)]
            } ?? [],
            quitAction: configuration.quitAction,
            settingsKeyEquivalent: ","
        )

        return menu
    }


    func updateSpacers(count: Int, style: SaneBarSettings.SpacerStyle, width: SaneBarSettings.SpacerWidth) {
        let desiredCount = min(max(count, 0), Self.maxSpacerCount)

        let spacerLength: CGFloat = switch width {
        case .compact: 8
        case .normal: 12
        case .wide: 20
        }

        while spacerItems.count > desiredCount {
            if let item = spacerItems.popLast() {
                NSStatusBar.system.removeStatusItem(item)
            }
        }

        while spacerItems.count < desiredCount {
            let spacer = NSStatusBar.system.statusItem(withLength: spacerLength)
            Self.enforceNonRemovableBehavior(for: spacer, role: "spacer")
            spacer.autosaveName = Self.spacerAutosaveName(index: spacerItems.count)
            configureSpacer(spacer, style: style)
            spacerItems.append(spacer)
        }

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
