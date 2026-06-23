import AppKit
import os.log

private let backupCaptureLogger = Logger(
    subsystem: "com.sanebar.app",
    category: "StatusBarPositionBackupCaptureStore"
)

enum StatusBarPositionBackupCaptureStore {
    @discardableResult
    static func captureCurrentDisplayPositionBackupIfPossible(
        referenceScreen: NSScreen? = nil,
        mainPosition overrideMainPosition: Double? = nil,
        separatorPosition overrideSeparatorPosition: Double? = nil
    ) -> Bool {
        guard let resolvedReferenceScreen = StatusBarPositionStore.resolvedReferenceScreen(referenceScreen) else {
            return false
        }
        let currentWidth = resolvedReferenceScreen.frame.width
        let currentScreenHasTopSafeAreaInset = StatusBarPositionStore.screenHasTopSafeAreaInset(resolvedReferenceScreen)
        let mainValues = StatusBarPositionDefaultsStore.preferredPositionValues(
            forAutosaveName: StatusBarPositionStore.mainAutosaveName
        )
        let separatorValues = StatusBarPositionDefaultsStore.preferredPositionValues(
            forAutosaveName: StatusBarPositionStore.separatorAutosaveName
        )
        let appMainPosition = StatusBarPositionDefaultsStore.numericPositionValue(mainValues.appValue)
        let appSeparatorPosition = StatusBarPositionDefaultsStore.numericPositionValue(separatorValues.appValue)
        let byHostMainPosition = StatusBarPositionDefaultsStore.numericPositionValue(mainValues.byHostValue)
        let byHostSeparatorPosition = StatusBarPositionDefaultsStore.numericPositionValue(separatorValues.byHostValue)
        let hasAppOrdinalSeedPair = StatusBarPositionStore.hasOrdinalSeedPair(
            mainPosition: appMainPosition,
            separatorPosition: appSeparatorPosition
        )

        if hasAppOrdinalSeedPair,
           StatusBarPositionStore.restoreCurrentDisplayPositionBackupIfAvailable(
               referenceScreen: resolvedReferenceScreen
           ) {
            backupCaptureLogger.info(
                "Display validation: restored current-width backup over app-domain ordinal preferred positions"
            )
            return true
        }

        let appPairCanSeedBackup = StatusBarPositionStore.canSeedCurrentDisplayBackup(
            mainPosition: appMainPosition,
            separatorPosition: appSeparatorPosition,
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        )
        let byHostPairCanSeedBackup = StatusBarPositionStore.canSeedCurrentDisplayBackup(
            mainPosition: byHostMainPosition,
            separatorPosition: byHostSeparatorPosition,
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        )
        let shouldPromoteByHostPair = !appPairCanSeedBackup && byHostPairCanSeedBackup
        let persistedMainPosition = shouldPromoteByHostPair
            ? byHostMainPosition
            : (appMainPosition ?? byHostMainPosition)
        let persistedSeparatorPosition = shouldPromoteByHostPair
            ? byHostSeparatorPosition
            : (appSeparatorPosition ?? byHostSeparatorPosition)
        let hasExplicitOverride = overrideMainPosition != nil || overrideSeparatorPosition != nil
        let overridePairCanSeedBackup = StatusBarPositionStore.canSeedCurrentDisplayBackup(
            mainPosition: overrideMainPosition,
            separatorPosition: overrideSeparatorPosition,
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        )
        let persistedPairCanSeedBackup = shouldPromoteByHostPair || appPairCanSeedBackup
        let shouldIgnoreOverridePair = hasExplicitOverride &&
            !overridePairCanSeedBackup &&
            persistedPairCanSeedBackup
        let mainPosition = shouldIgnoreOverridePair
            ? persistedMainPosition
            : (overrideMainPosition ?? persistedMainPosition)
        let separatorPosition = shouldIgnoreOverridePair
            ? persistedSeparatorPosition
            : (overrideSeparatorPosition ?? persistedSeparatorPosition)

        if shouldIgnoreOverridePair {
            backupCaptureLogger.warning(
                "Display validation: ignoring invalid override positions during current-width backup capture (main=\(overrideMainPosition ?? -1, privacy: .public), separator=\(overrideSeparatorPosition ?? -1, privacy: .public))"
            )
        }

        if StatusBarPositionStore.isLaunchSafeDisplayBackup(
            mainBackup: mainPosition,
            separatorBackup: separatorPosition,
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        ) {
            if shouldPromoteByHostPair,
               let mainPosition,
               let separatorPosition {
                StatusBarPositionDefaultsStore.setPreferredPosition(
                    mainPosition,
                    forAutosaveName: StatusBarPositionStore.mainAutosaveName
                )
                StatusBarPositionDefaultsStore.setPreferredPosition(
                    separatorPosition,
                    forAutosaveName: StatusBarPositionStore.separatorAutosaveName
                )
                backupCaptureLogger.info(
                    "Display validation: promoted safe ByHost preferred positions into app defaults"
                )
            }
            StatusBarPositionStore.saveDisplayPositionBackupIfNeeded(
                for: currentWidth,
                mainPosition: mainPosition,
                separatorPosition: separatorPosition,
                referenceScreen: referenceScreen
            )
            return true
        }

        if hasAppOrdinalSeedPair,
           let recoveryPair = StatusBarPositionStore.launchSafeCurrentDisplayRecoveryPair(
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        ) {
            StatusBarPositionDefaultsStore.setPreferredPosition(
                recoveryPair.main,
                forAutosaveName: StatusBarPositionStore.mainAutosaveName
            )
            StatusBarPositionDefaultsStore.setPreferredPosition(
                recoveryPair.separator,
                forAutosaveName: StatusBarPositionStore.separatorAutosaveName
            )
            backupCaptureLogger.info(
                "Display validation: replaced app-domain ordinal preferred positions with launch-safe anchors"
            )
            StatusBarPositionStore.setDisplayPositionBackup(
                for: currentWidth,
                mainPosition: recoveryPair.main,
                separatorPosition: recoveryPair.separator,
                referenceScreen: resolvedReferenceScreen
            )
            backupCaptureLogger.info(
                "Display validation: captured launch-safe current-width backup from clean startup state (main=\(recoveryPair.main, privacy: .public), separator=\(recoveryPair.separator, privacy: .public), width=\(currentWidth, privacy: .public))"
            )
            return true
        }

        return StatusBarPositionStore.hasLaunchSafeCurrentDisplayBackupForCurrentDisplay(
            referenceScreen: referenceScreen
        )
    }
}
