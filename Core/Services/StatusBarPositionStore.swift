import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "StatusBarPositionStore")

enum StatusBarPositionStore {
    nonisolated static let autosaveVersionKey = "SaneBar_AutosaveVersion"
    nonisolated static let baseAutosaveVersion = 7
    nonisolated static let maxAutosaveVersion = 99
    nonisolated static func autosaveNamesForCleanup(version: Int) -> [String] {
        ["SaneBar_Main_v\(version)", "SaneBar_Separator_v\(version)", "SaneBar_AlwaysHiddenSeparator_v\(version)"]
    }
    nonisolated static var autosaveVersion: Int {
        let stored = UserDefaults.standard.integer(forKey: autosaveVersionKey)
        return stored > 0 ? stored : baseAutosaveVersion
    }
    nonisolated static var mainAutosaveName: String { "SaneBar_Main_v\(autosaveVersion)" }
    nonisolated static var separatorAutosaveName: String { "SaneBar_Separator_v\(autosaveVersion)" }
    nonisolated static var alwaysHiddenSeparatorAutosaveName: String { "SaneBar_AlwaysHiddenSeparator_v\(autosaveVersion)" }
    nonisolated static func spacerAutosaveName(index: Int) -> String { "SaneBar_spacer_\(index)" }

    nonisolated static let screenWidthKey = "SaneBar_CalibratedScreenWidth"
    nonisolated static let positionBackupKeyPrefix = "SaneBar_Position_Backup"
    static let stablePositionMigrationKey = "SaneBar_PositionRecovery_Migration_v1"
    static let legacyMigrationKeys = [
        "SaneBar_PositionMigration_v4",
        "SaneBar_PositionMigration_v5",
        "SaneBar_PositionMigration_v6",
        "SaneBar_PositionMigration_v7"
    ]
    static let minimumSafeAlwaysHiddenPosition = 200.0

    nonisolated static func resolvedReferenceScreen(_ referenceScreen: NSScreen? = nil) -> NSScreen? {
        if let referenceScreen {
            return referenceScreen
        }

        if let pointerScreen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) {
            return pointerScreen
        }

        return NSScreen.main ?? NSScreen.screens.first
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

    nonisolated static func displayPositionBackupKey(for widthBucket: Int, slot: String) -> String {
        "\(positionBackupKeyPrefix)_\(widthBucket)_\(slot)"
    }

    nonisolated static func displayPositionBackupKey(
        for widthBucket: Int,
        screenSignature: String?,
        slot: String
    ) -> String {
        guard let screenSignature,
              !screenSignature.isEmpty
        else {
            return displayPositionBackupKey(for: widthBucket, slot: slot)
        }
        return "\(positionBackupKeyPrefix)_\(widthBucket)_\(screenSignature)_\(slot)"
    }

    nonisolated static func shouldAllowLegacyDisplayBackupFallback(
        widthBucket: Int,
        activeWidthBuckets: [Int]
    ) -> Bool {
        activeWidthBuckets.filter { $0 == widthBucket }.count <= 1
    }

    nonisolated static func displayBackupScreenSignature(for screen: NSScreen?) -> String? {
        guard let screen else { return nil }
        let heightBucket = displayWidthBucket(screen.frame.height)
        let safeAreaToken = screenHasTopSafeAreaInset(screen) ? "safe-top" : "plain"
        if let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID {
            return "d\(displayID)-h\(heightBucket)-\(safeAreaToken)"
        }
        return "h\(heightBucket)-\(safeAreaToken)"
    }

    nonisolated static func displayPositionBackupKey(
        for width: Double,
        referenceScreen: NSScreen?,
        slot: String
    ) -> String {
        displayPositionBackupKey(
            for: displayWidthBucket(width),
            screenSignature: displayBackupScreenSignature(for: referenceScreen),
            slot: slot
        )
    }

    nonisolated static func shouldAllowLegacyDisplayBackupFallback(
        for width: Double,
        referenceScreen: NSScreen?
    ) -> Bool {
        let widthBucket = displayWidthBucket(width)
        return shouldAllowLegacyDisplayBackupFallback(
            widthBucket: widthBucket,
            activeWidthBuckets: NSScreen.screens.map { displayWidthBucket($0.frame.width) }
        ) || displayBackupScreenSignature(for: referenceScreen) == nil
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

    nonisolated static func canSeedCurrentDisplayBackup(
        mainPosition: Double?,
        separatorPosition: Double?,
        screenWidth: Double,
        screenHasTopSafeAreaInset: Bool
    ) -> Bool {
        isLaunchSafeDisplayBackup(
            mainBackup: mainPosition,
            separatorBackup: separatorPosition,
            screenWidth: screenWidth,
            screenHasTopSafeAreaInset: screenHasTopSafeAreaInset
        ) || reanchoredPreferredPositionsTowardControlCenter(
            mainPosition: mainPosition,
            separatorPosition: separatorPosition,
            screenWidth: screenWidth,
            screenHasTopSafeAreaInset: screenHasTopSafeAreaInset
        ) != nil
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

    nonisolated static func launchSafePreferredSeparatorGap(for screenWidth: Double) -> Double {
        guard screenWidth > 0 else { return 120.0 }
        // Recovery is allowed to move SaneBar back beside Control Center, but it
        // must not collapse the user's visible lane so far that leftmost shown
        // items wake up hidden. Keep a moderate lane on external displays while
        // bounding it on smaller screens.
        return min(240.0, max(180.0, screenWidth * 0.09))
    }

    nonisolated static func migratedLegacyNarrowRecoveryPair(
        mainPosition: Double,
        separatorPosition: Double,
        screenWidth: Double,
        screenHasTopSafeAreaInset: Bool
    ) -> (main: Double, separator: Double)? {
        let safeMain = launchSafePreferredMainPositionLimit(
            for: screenWidth,
            screenHasTopSafeAreaInset: screenHasTopSafeAreaInset
        )
        let targetGap = launchSafePreferredSeparatorGap(for: screenWidth)
        guard targetGap > 0 else { return nil }
        guard abs(mainPosition - safeMain) < 0.5 else { return nil }
        let currentGap = separatorPosition - mainPosition
        guard currentGap < targetGap - 0.5 else { return nil }

        let widenedSeparator = min(screenWidth - 24.0, safeMain + targetGap)
        guard widenedSeparator > safeMain else { return nil }
        return (main: safeMain, separator: widenedSeparator)
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
        let safeSeparator = min(
            screenWidth - 24.0,
            safeMain + launchSafePreferredSeparatorGap(for: screenWidth)
        )
        guard safeSeparator > safeMain else { return nil }
        return (main: safeMain, separator: safeSeparator)
    }

    @discardableResult
    static func applyLaunchSafeRecoveryPositionsForCurrentDisplay(referenceScreen: NSScreen? = nil) -> Bool {
        guard let resolvedReferenceScreen = Self.resolvedReferenceScreen(referenceScreen),
              let currentWidth = Optional(resolvedReferenceScreen.frame.width),
              let recoveryPair = launchSafeCurrentDisplayRecoveryPair(
                  screenWidth: currentWidth,
                  screenHasTopSafeAreaInset: screenHasTopSafeAreaInset(resolvedReferenceScreen)
              )
        else { return false }

        StatusBarPositionDefaultsStore.setPreferredPosition(recoveryPair.main, forAutosaveName: mainAutosaveName)
        StatusBarPositionDefaultsStore.setPreferredPosition(recoveryPair.separator, forAutosaveName: separatorAutosaveName)
        saveDisplayPositionBackupIfNeeded(
            for: currentWidth,
            mainPosition: recoveryPair.main,
            separatorPosition: recoveryPair.separator,
            referenceScreen: resolvedReferenceScreen
        )
        UserDefaults.standard.set(currentWidth, forKey: screenWidthKey)
        logger.info(
            "Applied launch-safe recovery positions for width \(currentWidth, privacy: .public) (main=\(recoveryPair.main, privacy: .public), separator=\(recoveryPair.separator, privacy: .public))"
        )
        return true
    }

    static func saveDisplayPositionBackupIfNeeded(
        for width: Double,
        mainPosition: Double?,
        separatorPosition: Double?,
        referenceScreen: NSScreen? = nil
    ) {
        let currentScreenHasTopSafeAreaInset = screenHasTopSafeAreaInset(Self.resolvedReferenceScreen(referenceScreen))
        guard let mainPosition,
              let separatorPosition,
              isPixelLikePosition(mainPosition),
              isPixelLikePosition(separatorPosition)
        else {
            StatusBarPositionDefaultsStore.removeDisplayPositionBackup(for: width, referenceScreen: resolvedReferenceScreen(referenceScreen))
            return
        }

        guard isLaunchSafeDisplayBackup(
            mainBackup: mainPosition,
            separatorBackup: separatorPosition,
            screenWidth: width,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        ) else {
            StatusBarPositionDefaultsStore.removeDisplayPositionBackup(for: width, referenceScreen: resolvedReferenceScreen(referenceScreen))
            logger.warning(
                "Display validation: refusing to save unsafe current-width backup for width \(width, privacy: .public) (main=\(mainPosition, privacy: .public), separator=\(separatorPosition, privacy: .public))"
            )
            return
        }

        setDisplayPositionBackup(
            for: width,
            mainPosition: mainPosition,
            separatorPosition: separatorPosition,
            referenceScreen: resolvedReferenceScreen(referenceScreen)
        )
    }

    static func setDisplayPositionBackup(
        for width: Double,
        mainPosition: Double,
        separatorPosition: Double,
        referenceScreen: NSScreen? = nil
    ) {
        let defaults = UserDefaults.standard
        defaults.set(
            mainPosition,
            forKey: displayPositionBackupKey(for: width, referenceScreen: referenceScreen, slot: "main")
        )
        defaults.set(
            separatorPosition,
            forKey: displayPositionBackupKey(for: width, referenceScreen: referenceScreen, slot: "separator")
        )

        if shouldAllowLegacyDisplayBackupFallback(for: width, referenceScreen: referenceScreen) {
            defaults.set(mainPosition, forKey: displayPositionBackupKey(for: width, slot: "main"))
            defaults.set(separatorPosition, forKey: displayPositionBackupKey(for: width, slot: "separator"))
        } else {
            defaults.removeObject(forKey: displayPositionBackupKey(for: width, slot: "main"))
            defaults.removeObject(forKey: displayPositionBackupKey(for: width, slot: "separator"))
        }
    }

    nonisolated static func displayPositionBackupValue(
        for width: Double,
        referenceScreen: NSScreen?,
        slot: String
    ) -> Double? {
        let defaults = UserDefaults.standard
        let scopedKey = displayPositionBackupKey(for: width, referenceScreen: referenceScreen, slot: slot)
        let legacyKey = displayPositionBackupKey(for: width, slot: slot)

        if scopedKey != legacyKey,
           let scoped = StatusBarPositionDefaultsStore.numericPositionValue(defaults.object(forKey: scopedKey)) {
            return scoped
        }

        guard shouldAllowLegacyDisplayBackupFallback(for: width, referenceScreen: referenceScreen) else {
            return nil
        }
        return StatusBarPositionDefaultsStore.numericPositionValue(defaults.object(forKey: legacyKey))
    }

    static func restoreDisplayPositionBackupIfAvailable(for width: Double, referenceScreen: NSScreen? = nil) -> Bool {
        let resolvedReferenceScreen = Self.resolvedReferenceScreen(referenceScreen)
        let mainBackup = displayPositionBackupValue(for: width, referenceScreen: resolvedReferenceScreen, slot: "main")
        let separatorBackup = displayPositionBackupValue(for: width, referenceScreen: resolvedReferenceScreen, slot: "separator")
        let currentScreenHasTopSafeAreaInset = screenHasTopSafeAreaInset(resolvedReferenceScreen)

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
                let restoredPair = migratedLegacyNarrowRecoveryPair(
                    mainPosition: reanchored.main,
                    separatorPosition: reanchored.separator,
                    screenWidth: width,
                    screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
                ) ?? reanchored
                StatusBarPositionDefaultsStore.setPreferredPosition(restoredPair.main, forAutosaveName: mainAutosaveName)
                StatusBarPositionDefaultsStore.setPreferredPosition(restoredPair.separator, forAutosaveName: separatorAutosaveName)
                saveDisplayPositionBackupIfNeeded(
                    for: width,
                    mainPosition: restoredPair.main,
                    separatorPosition: restoredPair.separator,
                    referenceScreen: referenceScreen
                )
                logger.warning(
                    "Display validation: reanchored unsafe backup for width \(width, privacy: .public) (main=\(mainBackup, privacy: .public) -> \(restoredPair.main, privacy: .public), separator=\(separatorBackup, privacy: .public) -> \(restoredPair.separator, privacy: .public))"
                )
                return true
            }

            StatusBarPositionDefaultsStore.removeDisplayPositionBackup(for: width, referenceScreen: resolvedReferenceScreen)
            logger.warning(
                "Display validation: discarding unsafe backup for width \(width, privacy: .public) (main=\(mainBackup, privacy: .public), separator=\(separatorBackup, privacy: .public))"
            )
            return false
        }

        if let migrated = migratedLegacyNarrowRecoveryPair(
            mainPosition: mainBackup,
            separatorPosition: separatorBackup,
            screenWidth: width,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        ) {
            StatusBarPositionDefaultsStore.setPreferredPosition(migrated.main, forAutosaveName: mainAutosaveName)
            StatusBarPositionDefaultsStore.setPreferredPosition(migrated.separator, forAutosaveName: separatorAutosaveName)
            setDisplayPositionBackup(
                for: width,
                mainPosition: migrated.main,
                separatorPosition: migrated.separator,
                referenceScreen: resolvedReferenceScreen
            )
            logger.warning(
                "Display validation: widened legacy narrow recovery backup for width \(width, privacy: .public) (separator=\(separatorBackup, privacy: .public) -> \(migrated.separator, privacy: .public))"
            )
            return true
        }

        StatusBarPositionDefaultsStore.setPreferredPosition(mainBackup, forAutosaveName: mainAutosaveName)
        StatusBarPositionDefaultsStore.setPreferredPosition(separatorBackup, forAutosaveName: separatorAutosaveName)
        logger.info("Display validation: restored backup positions for width \(width)")
        return true
    }

    static func restoreCurrentDisplayPositionBackupIfAvailable(referenceScreen: NSScreen? = nil) -> Bool {
        guard let resolvedReferenceScreen = Self.resolvedReferenceScreen(referenceScreen) else { return false }
        let currentWidth = resolvedReferenceScreen.frame.width
        guard restoreDisplayPositionBackupIfAvailable(for: currentWidth, referenceScreen: resolvedReferenceScreen) else { return false }
        UserDefaults.standard.set(currentWidth, forKey: screenWidthKey)
        return true
    }

    nonisolated static func hasLaunchSafeCurrentDisplayBackupForCurrentDisplay(referenceScreen: NSScreen? = nil) -> Bool {
        guard let resolvedReferenceScreen = Self.resolvedReferenceScreen(referenceScreen) else { return false }
        let currentWidth = resolvedReferenceScreen.frame.width
        let mainBackup = displayPositionBackupValue(for: currentWidth, referenceScreen: resolvedReferenceScreen, slot: "main")
        let separatorBackup = displayPositionBackupValue(for: currentWidth, referenceScreen: resolvedReferenceScreen, slot: "separator")
        return isLaunchSafeDisplayBackup(
            mainBackup: mainBackup,
            separatorBackup: separatorBackup,
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: screenHasTopSafeAreaInset(resolvedReferenceScreen)
        )
    }

    @discardableResult
    static func captureCurrentDisplayPositionBackupIfPossible(
        referenceScreen: NSScreen? = nil,
        mainPosition overrideMainPosition: Double? = nil,
        separatorPosition overrideSeparatorPosition: Double? = nil
    ) -> Bool {
        guard let resolvedReferenceScreen = Self.resolvedReferenceScreen(referenceScreen) else { return false }
        let currentWidth = resolvedReferenceScreen.frame.width
        let currentScreenHasTopSafeAreaInset = screenHasTopSafeAreaInset(resolvedReferenceScreen)
        let persistedMainPosition = StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: mainAutosaveName)
        let persistedSeparatorPosition = StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: separatorAutosaveName)
        let hasExplicitOverride = overrideMainPosition != nil || overrideSeparatorPosition != nil
        let overridePairCanSeedBackup = canSeedCurrentDisplayBackup(
            mainPosition: overrideMainPosition,
            separatorPosition: overrideSeparatorPosition,
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        )
        let persistedPairCanSeedBackup = canSeedCurrentDisplayBackup(
            mainPosition: persistedMainPosition,
            separatorPosition: persistedSeparatorPosition,
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        )
        let shouldIgnoreOverridePair = hasExplicitOverride && !overridePairCanSeedBackup && persistedPairCanSeedBackup
        let mainPosition = shouldIgnoreOverridePair ? persistedMainPosition : (overrideMainPosition ?? persistedMainPosition)
        let separatorPosition = shouldIgnoreOverridePair ? persistedSeparatorPosition : (overrideSeparatorPosition ?? persistedSeparatorPosition)

        if shouldIgnoreOverridePair {
            logger.warning(
                "Display validation: ignoring invalid override positions during current-width backup capture (main=\(overrideMainPosition ?? -1, privacy: .public), separator=\(overrideSeparatorPosition ?? -1, privacy: .public))"
            )
        }

        if isLaunchSafeDisplayBackup(
            mainBackup: mainPosition,
            separatorBackup: separatorPosition,
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        ) {
            saveDisplayPositionBackupIfNeeded(
                for: currentWidth,
                mainPosition: mainPosition,
                separatorPosition: separatorPosition,
                referenceScreen: referenceScreen
            )
            return true
        }

        if let reanchored = reanchoredPreferredPositionsTowardControlCenter(
            mainPosition: mainPosition,
            separatorPosition: separatorPosition,
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        ) {
            setDisplayPositionBackup(
                for: currentWidth,
                mainPosition: reanchored.main,
                separatorPosition: reanchored.separator,
                referenceScreen: resolvedReferenceScreen
            )
            logger.info(
                "Display validation: captured reanchored current-width backup from stable live positions (main=\(reanchored.main, privacy: .public), separator=\(reanchored.separator, privacy: .public), width=\(currentWidth, privacy: .public))"
            )
            return true
        }

        if let recoveryPair = launchSafeCurrentDisplayRecoveryPair(
            screenWidth: currentWidth,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        ) {
            setDisplayPositionBackup(
                for: currentWidth,
                mainPosition: recoveryPair.main,
                separatorPosition: recoveryPair.separator,
                referenceScreen: resolvedReferenceScreen
            )
            logger.info(
                "Display validation: captured launch-safe current-width backup from clean startup state (main=\(recoveryPair.main, privacy: .public), separator=\(recoveryPair.separator, privacy: .public), width=\(currentWidth, privacy: .public))"
            )
            return true
        }

        return hasLaunchSafeCurrentDisplayBackupForCurrentDisplay(referenceScreen: referenceScreen)
    }

    static func reanchorCurrentDisplayPositionsIfNeeded(for width: Double, referenceScreen: NSScreen? = nil) -> Bool {
        let currentScreenHasTopSafeAreaInset = screenHasTopSafeAreaInset(Self.resolvedReferenceScreen(referenceScreen))
        guard let reanchored = reanchoredPreferredPositionsTowardControlCenter(
            mainPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: mainAutosaveName),
            separatorPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: separatorAutosaveName),
            screenWidth: width,
            screenHasTopSafeAreaInset: currentScreenHasTopSafeAreaInset
        ) else { return false }

        StatusBarPositionDefaultsStore.setPreferredPosition(reanchored.main, forAutosaveName: mainAutosaveName)
        StatusBarPositionDefaultsStore.setPreferredPosition(reanchored.separator, forAutosaveName: separatorAutosaveName)
        saveDisplayPositionBackupIfNeeded(
            for: width,
            mainPosition: reanchored.main,
            separatorPosition: reanchored.separator,
            referenceScreen: referenceScreen
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
    static func positionsNeedDisplayReset(referenceScreen: NSScreen? = nil) -> Bool {
        let defaults = UserDefaults.standard
        let storedWidth = defaults.double(forKey: screenWidthKey)

        guard let resolvedReferenceScreen = Self.resolvedReferenceScreen(referenceScreen) else { return false }
        let currentWidth = resolvedReferenceScreen.frame.width
        let screenCount = max(1, NSScreen.screens.count)

        let mainKey = StatusBarPositionDefaultsStore.preferredPositionKey(for: mainAutosaveName)
        let sepKey = StatusBarPositionDefaultsStore.preferredPositionKey(for: separatorAutosaveName)
        let mainPos = StatusBarPositionDefaultsStore.numericPositionValue(defaults.object(forKey: mainKey))
        let sepPos = StatusBarPositionDefaultsStore.numericPositionValue(defaults.object(forKey: sepKey))
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
                mainPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: mainAutosaveName),
                separatorPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: separatorAutosaveName),
                referenceScreen: resolvedReferenceScreen
            )
            logger.info("Display validation: first run, stamping screen width \(currentWidth)")
            return false
        }

        if hasOrdinalSeedPositions, restoreDisplayPositionBackupIfAvailable(for: currentWidth, referenceScreen: resolvedReferenceScreen) {
            defaults.set(currentWidth, forKey: screenWidthKey)
            logger.info("Display validation: restored current-width backup over ordinal startup seeds")
            return false
        }

        guard isSignificantWidthChange(stored: storedWidth, current: currentWidth) else {
            saveDisplayPositionBackupIfNeeded(
                for: currentWidth,
                mainPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: mainAutosaveName),
                separatorPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: separatorAutosaveName),
                referenceScreen: resolvedReferenceScreen
            )
            return false
        }

        // Preserve the last known-good layout for the previous display width
        // before we evaluate whether the current width should reset.
        saveDisplayPositionBackupIfNeeded(
            for: storedWidth,
            mainPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: mainAutosaveName),
            separatorPosition: StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: separatorAutosaveName)
        )

        // If we have a known-good layout for this display width, restore it and skip reset.
        if restoreDisplayPositionBackupIfAvailable(for: currentWidth, referenceScreen: resolvedReferenceScreen) {
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
    static func clearPersistedVisibilityOverrides() {
        var clearedAny = false

        // App-domain cleanup: all known SaneBar item namespaces, historical
        // versions, spacer items, and macOS 26 VisibleCC variants.
        if StatusBarPositionDefaultsStore.removeAllAppKeys(matchingPrefixes: [
            "NSStatusItem Visible SaneBar_",
            "NSStatusItem VisibleCC SaneBar_"
        ]) {
            clearedAny = true
        }

        // ByHost cleanup: wildcard enumeration catches ALL variants
        if StatusBarPositionDefaultsStore.removeAllByHostVisibilityOverrides() {
            clearedAny = true
        }

        if clearedAny {
            logger.info("Cleared persisted NSStatusItem visibility overrides")
        }
    }

    /// One-time recovery migration.
    /// Important: do not version-bump this key for routine patch releases.
    /// Position resets must be gated on explicit corruption checks.
    static func migrateCorruptedPositionsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: stablePositionMigrationKey) else { return }

        if shouldResetPositionsForKnownCorruption() {
            logger.info("Applying status item position recovery for known corrupted state")
            if !applyLaunchSafeRecoveryPositionsForCurrentDisplay() {
                StatusBarPositionRecoveryStore.resetPositionsToOrdinals()
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

    static func shouldResetPositionsForKnownCorruption() -> Bool {
        if StatusBarPositionDefaultsStore.hasInvalidPositionValue(forAutosaveName: mainAutosaveName) {
            return true
        }
        if StatusBarPositionDefaultsStore.hasInvalidPositionValue(forAutosaveName: separatorAutosaveName) {
            return true
        }
        if StatusBarPositionDefaultsStore.hasTooSmallAlwaysHiddenPosition(forAutosaveName: alwaysHiddenSeparatorAutosaveName) {
            return true
        }
        if StatusBarPositionDefaultsStore.hasTooSmallAlwaysHiddenPosition(forAutosaveName: "SaneBar_AlwaysHiddenSeparator") {
            return true
        }
        return false
    }

}
