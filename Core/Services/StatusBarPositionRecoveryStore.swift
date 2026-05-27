import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "StatusBarPositionRecoveryStore")

enum StatusBarPositionRecoveryStore {
    // MARK: - Position Pre-Seeding

    /// Seed ordinal positions BEFORE creating status items.
    /// Only seed when positions are missing/invalid. Re-seeding on every launch
    /// destroys user-arranged visible/hidden layouts.
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
        StatusBarPositionDefaultsStore.setPreferredPosition(10000, forAutosaveName: StatusBarPositionStore.alwaysHiddenSeparatorAutosaveName)
    }

    /// Reset all status item positions to ordinal seeds. Call when positions are
    /// corrupted (e.g., display-specific pixel values from a different screen).
    static func resetPositionsToOrdinals() {
        StatusBarPositionDefaultsStore.removePreferredPosition(forAutosaveName: StatusBarPositionStore.mainAutosaveName)
        StatusBarPositionDefaultsStore.removePreferredPosition(forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
        StatusBarPositionDefaultsStore.removePreferredPosition(forAutosaveName: StatusBarPositionStore.alwaysHiddenSeparatorAutosaveName)
        logger.info("Reset all status item positions — will reseed on next creation")
    }

    /// Resets persisted status-item state to a clean, launch-safe baseline.
    /// Use this for explicit user recovery actions such as Reset to Defaults.
    static func resetPersistentStatusItemState(alwaysHiddenEnabled: Bool, referenceScreen: NSScreen? = nil) {
        resetPersistentStatusItemState(
            alwaysHiddenEnabled: alwaysHiddenEnabled,
            referenceScreen: referenceScreen,
            freshAutosaveNamespace: false
        )
    }

    /// Resets persisted status-item state to a clean, launch-safe baseline.
    /// When `freshAutosaveNamespace` is true, the reset also advances the
    /// autosave identity so recovery can escape a poisoned WindowServer cache.
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
            seedAlwaysHiddenSeparatorPositionIfNeeded()
        }

        if freshAutosaveNamespace {
            logger.info(
                "Reset persistent status item state to a startup-safe baseline with fresh autosave namespace v\(StatusBarPositionStore.autosaveVersion)"
            )
        } else {
            logger.info("Reset persistent status item state to a startup-safe baseline")
        }
    }

    /// Best-effort startup recovery used when runtime invariants detect a bad
    /// separator layout. This keeps the current session usable and seeds safe
    /// positions for the next status-item relayout/restart.
    static func recoverStartupPositions(alwaysHiddenEnabled: Bool, referenceScreen: NSScreen? = nil) {
        if StatusBarPositionStore.restoreCurrentDisplayPositionBackupIfAvailable(referenceScreen: referenceScreen) {
            if alwaysHiddenEnabled {
                seedAlwaysHiddenSeparatorPositionIfNeeded()
            }
            logger.info("Recovered startup positions from current-width display backup")
            return
        }
        if let currentWidth = StatusBarPositionStore.resolvedReferenceScreen(referenceScreen)?.frame.width,
           StatusBarPositionStore.reanchorCurrentDisplayPositionsIfNeeded(for: currentWidth, referenceScreen: referenceScreen) {
            if alwaysHiddenEnabled {
                seedAlwaysHiddenSeparatorPositionIfNeeded()
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
            seedAlwaysHiddenSeparatorPositionIfNeeded()
        }
    }
}
