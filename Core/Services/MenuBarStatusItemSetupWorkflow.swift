import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarStatusItemSetupWorkflow")

@MainActor
final class MenuBarStatusItemSetupWorkflow {
    private enum StatusItemVisibilityRole: String {
        case mainIcon = "main-icon"
        case separator
        case alwaysHiddenSeparator = "always-hidden-separator"
    }

    private unowned let manager: MenuBarManager
    private var mainStatusItemVisibilityObservation: NSKeyValueObservation?
    private var separatorItemVisibilityObservation: NSKeyValueObservation?
    private var alwaysHiddenSeparatorVisibilityObservation: NSKeyValueObservation?

    init(manager: MenuBarManager) {
        self.manager = manager
    }

    func setupStatusItem() {
        let statusBarController = manager.ensureStatusBarController()

        statusBarController.configureStatusItems(
            clickAction: #selector(MenuBarActionWorkflow.statusItemClicked(_:)),
            target: manager.actionWorkflow
        )

        manager.mainStatusItem = statusBarController.mainItem
        manager.separatorItem = statusBarController.separatorItem
        statusBarController.ensureAlwaysHiddenSeparator(enabled: manager.currentEffectiveAlwaysHiddenSectionEnabled())
        manager.alwaysHiddenSeparatorItem = statusBarController.alwaysHiddenSeparatorItem
        manager.markStatusItemsAwaitingAnchor(reason: "initial-setup")
        installStatusItemVisibilityObservers()

        manager.statusMenu = statusBarController.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(MenuBarActionWorkflow.menuToggleHiddenItems(_:)),
            findIconAction: #selector(MenuBarActionWorkflow.openFindIcon(_:)),
            arrangeNowAction: #selector(MenuBarActionWorkflow.menuArrangeNow(_:)),
            healthAction: #selector(MenuBarActionWorkflow.openHealth(_:)),
            settingsAction: #selector(MenuBarActionWorkflow.openSettings(_:)),
            licenseAction: #selector(MenuBarActionWorkflow.openLicense(_:)),
            aboutAndBugReportAction: #selector(MenuBarActionWorkflow.openAbout(_:)),
            showReleaseNotesAction: LicenseService.shared.usesSetappDistribution
                ? #selector(MenuBarActionWorkflow.showReleaseNotes(_:))
                : nil,
            checkForUpdatesAction: LicenseService.shared.distributionChannel.supportsInAppUpdates
                ? #selector(MenuBarActionWorkflow.userDidClickCheckForUpdates(_:))
                : nil,
            quitAction: #selector(MenuBarActionWorkflow.quitApp(_:))
        ))
        wireStatusMenuTargets()
        manager.actionWorkflow.updateUpdateMenuAvailability()
        manager.statusMenu?.delegate = manager.actionWorkflow
        manager.clearStatusItemMenus()

        if let separator = manager.separatorItem {
            manager.hidingService.configure(delimiterItem: separator)
        }
        manager.hidingService.configureAlwaysHiddenDelimiter(manager.alwaysHiddenSeparatorItem)
        manager.hidingService.shouldRehide = { [weak manager] in
            guard let manager else { return true }
            return manager.visibilityWorkflow.canAutoRehideAtFireTime()
        }

        statusBarController.onItemsRecreated = { [weak self] main, separator in
            self?.rewireRecreatedStatusItems(main: main, separator: separator)
        }

        manager.updateMainIconVisibility()
        manager.updateDividerStyle()
        manager.updateIconStyle()
        scheduleStartupHideEvaluation()
    }

    func installStatusItemVisibilityObservers() {
        mainStatusItemVisibilityObservation = makeVisibilityObservation(
            for: manager.mainStatusItem,
            role: .mainIcon
        )
        separatorItemVisibilityObservation = makeVisibilityObservation(
            for: manager.separatorItem,
            role: .separator
        )
        alwaysHiddenSeparatorVisibilityObservation = makeVisibilityObservation(
            for: manager.alwaysHiddenSeparatorItem,
            role: .alwaysHiddenSeparator
        )
    }

    func updateMainIconVisibility() {
        guard let mainItem = manager.mainStatusItem,
              let separator = manager.separatorItem else { return }

        if manager.settings.hideMainIcon {
            manager.settings.hideMainIcon = false
            manager.settingsController.settings.hideMainIcon = false
            manager.settingsController.saveQuietly()
            logger.info("hideMainIcon is deprecated - forcing visible main icon")
        }

        mainItem.isVisible = true
        separator.isVisible = true
        manager.alwaysHiddenSeparatorItem?.isVisible = true
        mainItem.menu = nil
        mainItem.button?.menu = nil

        if let button = mainItem.button {
            button.action = #selector(MenuBarActionWorkflow.statusItemClicked(_:))
            button.target = manager.actionWorkflow
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            installMainStatusItemHoverTrackingArea(on: button)
        }

        if let button = separator.button {
            button.action = nil
            button.target = nil
            button.sendAction(on: [])
        }

        separator.menu = nil
        separator.button?.menu = nil

        manager.clearStatusItemMenus()

        logger.info("Main icon visible - separator menu-only mode")
    }

    func installMainStatusItemHoverTrackingArea(on button: NSStatusBarButton) {
        if let trackingArea = manager.mainStatusItemHoverTrackingArea {
            button.removeTrackingArea(trackingArea)
            manager.mainStatusItemHoverTrackingArea = nil
        }

        let area = NSTrackingArea(
            rect: button.bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: manager,
            userInfo: ["role": "mainStatusItem"]
        )
        button.addTrackingArea(area)
        manager.mainStatusItemHoverTrackingArea = area
    }

    private func wireStatusMenuTargets() {
        for item in manager.statusMenu?.items ?? [] where item.action != nil {
            item.target = manager.actionWorkflow
        }
    }

    private func rewireRecreatedStatusItems(main: NSStatusItem, separator: NSStatusItem) {
        manager.mainStatusItem = main
        manager.separatorItem = separator
        manager.alwaysHiddenSeparatorItem = manager.statusBarController.alwaysHiddenSeparatorItem
        manager.markStatusItemsAwaitingAnchor(reason: "status-item-recreate")
        installStatusItemVisibilityObservers()
        let shouldRestoreHidden = manager.pendingRecoveryHideRestore
        let preservedHidingState: HidingState = shouldRestoreHidden ? .hidden : manager.hidingService.state
        manager.pendingRecoveryHideRestore = false

        if let button = main.button {
            manager.statusBarController.configureStatusItems(
                clickAction: #selector(MenuBarActionWorkflow.statusItemClicked(_:)),
                target: manager.actionWorkflow
            )
            manager.installMainStatusItemHoverTrackingArea(on: button)
        }

        manager.hidingService.reconfigure(
            delimiterItem: separator,
            preserving: preservedHidingState,
            deferApplyingState: shouldRestoreHidden
        )
        manager.hidingService.configureAlwaysHiddenDelimiter(manager.alwaysHiddenSeparatorItem)
        manager.clearStatusItemMenus()
        manager.updateMainIconVisibility()
        manager.updateDividerStyle()
        manager.updateIconStyle()
        manager.updateAlwaysHiddenSeparator()
        manager.updateSpacers()
        manager.schedulePostRecoveryGeometryWarmup(restoreHiddenStateAfterWarmup: shouldRestoreHidden)
        manager.schedulePostRecoveryVisibilityIntentReplay(reason: "status-item-recreate")

        if shouldRestoreHidden {
            logger.info("Preserved hidden state during status item recovery")
        }

        logger.info("Re-wired status items after autosave recovery")
    }

    private func scheduleStartupHideEvaluation() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.evaluateStartupHide()
            }
        }
    }

    private func evaluateStartupHide() async {
        await manager.geometryResolver.warmSeparatorPositionCache()

        if let width = manager.currentRecoveryReferenceScreen()?.frame.width {
            UserDefaults.standard.set(width, forKey: "SaneBar_CalibratedScreenWidth")
        }

        let startupSnapshot = manager.currentStatusItemRecoverySnapshot()
        let hasConnectedExternalMonitorWithAlwaysShow = manager.settings.disableOnExternalMonitor &&
            NSScreen.screens.contains(where: { screen in
                guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                    return false
                }
                return CGDisplayIsBuiltin(displayID) == 0
            })
        let startupAction = MenuBarOperationCoordinator.statusItemRecoveryAction(
            snapshot: startupSnapshot,
            context: .startupInitial(.init(
                hasCompletedOnboarding: manager.settings.hasCompletedOnboarding,
                autoRehideEnabled: manager.settings.autoRehide,
                shouldSkipHideForExternalMonitor: manager.shouldSkipHideForExternalMonitor,
                hasConnectedExternalMonitorWithAlwaysShow: hasConnectedExternalMonitorWithAlwaysShow
            )),
            recoveryCount: 0,
            maxRecoveryCount: MenuBarManager.maxStatusItemRecoveryCount
        )

        switch startupAction {
        case .waitForLiveAnchor:
            logger.warning("Startup separator anchor is still estimated - skipping initial hide and relying on position validation")
            manager.scheduleInitialPositionValidationAfterStartup()
            return

        case let .repairPersistedLayoutAndRecreate(reason):
            manager.logStatusItemRecoveryReason(
                reason,
                snapshot: startupSnapshot,
                prefix: "Startup recovery"
            )
            manager.executeStatusItemRecoveryAction(
                startupAction,
                trigger: "startup-\(reason?.rawValue ?? "recovery")",
                validationContext: nil,
                recoveryCount: 0
            )
            await manager.hidingService.show()
            manager.scheduleInitialPositionValidationAfterStartup()
            return

        case .keepExpanded(.waitingForLiveCoordinates):
            logger.warning("Startup coordinates were still missing after initial settle - skipping initial hide and relying on position validation")
            manager.scheduleInitialPositionValidationAfterStartup()
            return

        case let .keepExpanded(reason):
            manager.alwaysHiddenPinWorkflow.repairSeparatorPositionIfNeeded(reason: "startup")
            switch reason {
            case .autoRehideDisabled:
                logger.info("Skipping initial hide: auto-rehide disabled")
            case .externalMonitorPolicy:
                logger.info("Skipping initial hide: user is on external monitor")
            case .externalMonitorConnectedAlwaysShow:
                logger.info("Skipping initial hide: external monitor connected with always-show enabled")
            case .waitingForLiveCoordinates:
                break
            }
            manager.scheduleInitialPositionValidationAfterStartup()
            return

        case .performInitialHide:
            manager.alwaysHiddenPinWorkflow.repairSeparatorPositionIfNeeded(reason: "startup")

        case .captureCurrentDisplayBackup, .recreateFromPersistedLayout, .bumpAutosaveVersion, .stop:
            logger.error("Unexpected startup recovery action \(String(describing: startupAction), privacy: .public) - continuing with initial hide path")
        }

        let hasAccessibilityPermission = AccessibilityService.shared.isGranted
        if !hasAccessibilityPermission {
            logger.warning(
                "Accessibility permission not granted at startup - continuing initial hide; launch-time pin automation is deferred"
            )
        } else if !manager.settings.alwaysHiddenPinnedItemIds.isEmpty {
            logger.info("Skipping launch-time always-hidden pin automation to keep startup hide deterministic")
        }

        await manager.hidingService.hide()
        logger.info("Initial hide complete")
        manager.scheduleInitialPositionValidationAfterStartup()
    }

    private func makeVisibilityObservation(
        for item: NSStatusItem?,
        role: StatusItemVisibilityRole
    ) -> NSKeyValueObservation? {
        guard let item else { return nil }

        return item.observe(\.isVisible, options: [.new]) { [weak self] _, change in
            guard let self,
                  let isVisible = change.newValue
            else { return }

            Task { @MainActor in
                self.handleUnexpectedStatusItemVisibilityChange(
                    role: role,
                    isVisible: isVisible
                )
            }
        }
    }

    private func handleUnexpectedStatusItemVisibilityChange(
        role: StatusItemVisibilityRole,
        isVisible: Bool
    ) {
        guard role != .alwaysHiddenSeparator || manager.currentEffectiveAlwaysHiddenSectionEnabled() else { return }

        let now = Date()
        guard MenuBarManager.shouldRecoverUnexpectedVisibilityLoss(
            isVisible: isVisible,
            isExecutingRecovery: manager.isExecutingStatusItemRecovery,
            lastRecoveryAt: manager.lastUnexpectedVisibilityRecoveryAt,
            now: now,
            minimumInterval: MenuBarManager.unexpectedVisibilityRecoveryDebounceSeconds
        ) else {
            return
        }

        manager.lastUnexpectedVisibilityRecoveryAt = now
        logger.error(
            "Observed unexpected invisible status item for \(role.rawValue, privacy: .public) - triggering structural recovery"
        )
        manager.executeStatusItemRecoveryAction(
            .repairPersistedLayoutAndRecreate(.invalidStatusItems),
            trigger: "unexpected-visibility-loss-\(role.rawValue)",
            validationContext: .manualLayoutRestore,
            recoveryCount: 0
        )
    }
}
