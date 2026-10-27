import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "StatusBarPositionRecoveryStore")

enum StatusBarPositionRecoveryStore {

    nonisolated static func bumpedNamespaceRecoveryPositions(
        originalMain: Double?,
        originalSeparator: Double?,
        screenWidth: Double?,
        screenHasTopSafeAreaInset: Bool,
        reanchorUnsafePersistedPositions: Bool
    ) -> (main: Double, separator: Double)? {
        if !reanchorUnsafePersistedPositions {
            guard let originalMain,
                  let originalSeparator,
                  originalMain.isFinite,
                  originalSeparator.isFinite,
                  originalSeparator > originalMain
            else { return nil }
            return (main: originalMain, separator: originalSeparator)
        }

        guard let screenWidth else { return nil }
        return StatusBarPositionStore.reanchoredPreferredPositionsTowardControlCenter(
            mainPosition: originalMain,
            separatorPosition: originalSeparator,
            screenWidth: screenWidth,
            screenHasTopSafeAreaInset: screenHasTopSafeAreaInset
        )
    }


    @discardableResult
    nonisolated static func restoreExplicitDividerIfLaunderedOnSameDisplay(
        capturedMain: Double?,
        capturedSeparator: Double?,
        calibratedWidth: Double,
        referenceScreen: NSScreen?
    ) -> Bool {
        guard let capturedMain,
              let capturedSeparator,
              capturedSeparator > capturedMain,
              StatusBarPositionStore.isPixelLikePosition(capturedMain),
              StatusBarPositionStore.isPixelLikePosition(capturedSeparator),
              let screen = StatusBarPositionStore.resolvedReferenceScreen(referenceScreen)
        else { return false }

        let currentWidth = Double(screen.frame.width)
        guard currentWidth > 0, capturedSeparator < currentWidth else { return false }

        let safeLimit = StatusBarPositionStore.launchSafePreferredMainPositionLimit(
            for: currentWidth,
            screenHasTopSafeAreaInset: StatusBarPositionStore.screenHasTopSafeAreaInset(screen)
        )
        guard capturedMain > safeLimit else { return false }

        if calibratedWidth > 0, abs(currentWidth - calibratedWidth) > calibratedWidth * 0.1 {
            return false
        }

        guard let currentMain = StatusBarPositionDefaultsStore.resolvedPreferredPosition(
            forAutosaveName: StatusBarPositionStore.mainAutosaveName
        ), currentMain < capturedMain - 8.0 else { return false }

        StatusBarPositionDefaultsStore.setPreferredPosition(capturedMain, forAutosaveName: StatusBarPositionStore.mainAutosaveName)
        StatusBarPositionDefaultsStore.setPreferredPosition(capturedSeparator, forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
        logger.info(
            "FM-2 chokepoint: restored explicit divider (main \(currentMain, privacy: .public) -> \(capturedMain, privacy: .public)) laundered during same-display recovery (width=\(currentWidth, privacy: .public))"
        )
        return true
    }


    static func seedPositionsIfNeeded() {
        let mainValues = StatusBarPositionDefaultsStore.preferredPositionValues(forAutosaveName: StatusBarPositionStore.mainAutosaveName)
        let separatorValues = StatusBarPositionDefaultsStore.preferredPositionValues(forAutosaveName: StatusBarPositionStore.separatorAutosaveName)

        let seedMain = StatusBarPositionDefaultsStore.shouldSeedPreferredPosition(appValue: mainValues.appValue, byHostValue: mainValues.byHostValue)
        let seedSeparator = StatusBarPositionDefaultsStore.shouldSeedPreferredPosition(appValue: separatorValues.appValue, byHostValue: separatorValues.byHostValue)

        if seedMain {
            logger.info("Seeding main position (main=0)")
            StatusBarPositionDefaultsStore.setPreferredPosition(0, forAutosaveName: StatusBarPositionStore.mainAutosaveName)
        }
        if seedSeparator {
            logger.info("Seeding separator position (separator=1)")
            StatusBarPositionDefaultsStore.setPreferredPosition(1, forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
        }

        if !seedMain, !seedSeparator {
            logger.debug("Preserving existing main/separator positions")
        }
    }

    static func forceMainAndSeparatorAnchorSeed() {
        logger.info("Onboarding startup: forcing main/separator anchor seeds near Control Center")
        StatusBarPositionDefaultsStore.setPreferredPosition(0, forAutosaveName: StatusBarPositionStore.mainAutosaveName)
        StatusBarPositionDefaultsStore.setPreferredPosition(1, forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
    }

    static func shouldForceAnchorNearControlCenterOnLaunch() -> Bool {
        if let forced = ProcessInfo.processInfo.environment["SANEBAR_FORCE_ANCHOR_ON_LAUNCH"] {
            return forced == "1"
        }

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
            return true
        }

        if json["hasCompletedOnboarding"] == nil {
            logger.info("Legacy settings detected (missing hasCompletedOnboarding) — skipping forced anchor seed")
            return false
        }

        let hasCompletedOnboarding = (json["hasCompletedOnboarding"] as? Bool) ?? false
        return !hasCompletedOnboarding
    }

    static func seedAlwaysHiddenSeparatorPositionIfNeeded(referenceScreen: NSScreen? = nil) {
        let preferredPosition = StatusBarPositionStore.alwaysHiddenPreferredPosition(referenceScreen: referenceScreen)
        logger.info("Seeding AH separator position (\(preferredPosition, privacy: .public))")
        StatusBarPositionDefaultsStore.setPreferredPosition(preferredPosition, forAutosaveName: StatusBarPositionStore.alwaysHiddenSeparatorAutosaveName)
    }

    static func resetPositionsToOrdinals() {
        StatusBarPositionDefaultsStore.removePreferredPosition(forAutosaveName: StatusBarPositionStore.mainAutosaveName)
        StatusBarPositionDefaultsStore.removePreferredPosition(forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
        StatusBarPositionDefaultsStore.removePreferredPosition(forAutosaveName: StatusBarPositionStore.alwaysHiddenSeparatorAutosaveName)
        logger.info("Reset all status item positions — will reseed on next creation")
    }

    static func resetPersistentStatusItemState(alwaysHiddenEnabled: Bool, referenceScreen: NSScreen? = nil) {
        resetPersistentStatusItemState(
            alwaysHiddenEnabled: alwaysHiddenEnabled,
            referenceScreen: referenceScreen,
            freshAutosaveNamespace: false
        )
    }

    static func resetPersistentStatusItemState(
        alwaysHiddenEnabled: Bool,
        referenceScreen: NSScreen? = nil,
        freshAutosaveNamespace: Bool
    ) {
        StatusBarPositionStore.clearPersistedVisibilityOverrides()
        StatusBarPositionDefaultsStore.clearHistoricalAutosaveNamespaces()
        StatusBarPositionDefaultsStore.clearDisplayPositionBackups()

        let defaults = UserDefaults.standard
        if freshAutosaveNamespace {
            defaults.set(StatusBarPositionDefaultsStore.nextFreshAutosaveVersion(after: StatusBarPositionStore.autosaveVersion), forKey: StatusBarPositionStore.autosaveVersionKey)
        } else {
            defaults.removeObject(forKey: StatusBarPositionStore.autosaveVersionKey)
        }
        defaults.removeObject(forKey: StatusBarPositionStore.screenWidthKey)

        if !StatusBarPositionStore.applyLaunchSafeRecoveryPositionsForCurrentDisplay(referenceScreen: referenceScreen) {
            seedPositionsIfNeeded()
        }

        if alwaysHiddenEnabled {
            seedAlwaysHiddenSeparatorPositionIfNeeded(referenceScreen: referenceScreen)
        }

        if freshAutosaveNamespace {
            logger.info(
                "Reset persistent status item state to a startup-safe baseline with fresh autosave namespace v\(StatusBarPositionStore.autosaveVersion)"
            )
        } else {
            logger.info("Reset persistent status item state to a startup-safe baseline")
        }
    }

    static func recoverStartupPositions(
        alwaysHiddenEnabled: Bool,
        referenceScreen: NSScreen? = nil,
        preserveExplicitPersistedPositions: Bool = false
    ) {
        if preserveExplicitPersistedPositions {
            logger.info("Wake/Space validation recovery: preserving explicit persisted positions (no reanchor toward Control Center)")
            if alwaysHiddenEnabled {
                seedAlwaysHiddenSeparatorPositionIfNeeded(referenceScreen: referenceScreen)
            }
            return
        }
        if StatusBarPositionStore.restoreCurrentDisplayPositionBackupIfAvailable(referenceScreen: referenceScreen) {
            if alwaysHiddenEnabled {
                seedAlwaysHiddenSeparatorPositionIfNeeded(referenceScreen: referenceScreen)
            }
            logger.info("Recovered startup positions from current-width display backup")
            return
        }
        if let currentWidth = StatusBarPositionStore.resolvedReferenceScreen(referenceScreen)?.frame.width,
           StatusBarPositionStore.reanchorCurrentDisplayPositionsIfNeeded(for: currentWidth, referenceScreen: referenceScreen) {
            if alwaysHiddenEnabled {
                seedAlwaysHiddenSeparatorPositionIfNeeded(referenceScreen: referenceScreen)
            }
            logger.info("Recovered startup positions by reanchoring persisted positions toward Control Center")
            return
        }
        if !StatusBarPositionStore.applyLaunchSafeRecoveryPositionsForCurrentDisplay(referenceScreen: referenceScreen) {
            resetPositionsToOrdinals()
            seedPositionsIfNeeded()
            logger.info("Applied startup position recovery ordinal seeds")
        } else {
            logger.info("Applied launch-safe startup recovery positions")
        }
        if alwaysHiddenEnabled {
            seedAlwaysHiddenSeparatorPositionIfNeeded(referenceScreen: referenceScreen)
        }
    }
}
