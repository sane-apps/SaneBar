import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "StatusBarPositionRecoveryStore")

enum StatusBarPositionRecoveryStore {
    // MARK: - Bumped-Namespace Recovery Positions (FM-2 #136/#168)

    /// Choose which persisted positions to re-seed into a freshly bumped autosave
    /// namespace during status-item recovery.
    ///
    /// `StatusBarController.recreateItemsWithBumpedVersion` advances the autosave
    /// identity to escape a poisoned WindowServer position cache and must re-seed the
    /// new namespace. On the steady-state wake / Space-change validation path the
    /// user's EXPLICIT persisted divider must survive the bump untouched
    /// (`reanchorUnsafePersistedPositions == false`): the original pair is replayed
    /// as-is. On genuine startup / display-topology recovery (`true`) an unsafe
    /// far-from-Control-Center pair is still clamped toward Control Center, since pixel
    /// positions from a different display are meaningless. Returns nil when there is
    /// nothing valid to replay, so the caller falls back to launch-safe / ordinal
    /// seeding.
    ///
    /// This is the THIRD FM-2 write path: before this gate the bump reanchored the
    /// explicit divider (e.g. main 900 -> 144, the launch-safe limit) on wake,
    /// laundering an explicit user value as if it were display drift (#136/#168).
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

    // MARK: - Explicit-Divider Launder Chokepoint (FM-2 #136/#168)

    /// Single chokepoint that undoes any recovery pass that laundered the user's
    /// EXPLICIT divider toward Control Center on the SAME display.
    ///
    /// Display sleep/wake fires `NSApplication.didChangeScreenParametersNotification`
    /// even when nothing about the display actually changed. That `.screenParametersChanged`
    /// validation is (correctly) treated as a display-topology context, so on a brief
    /// post-wake attachment glitch it forces a destructive reset / reanchor that clamps
    /// an explicit far divider (e.g. main 900 -> 144, the launch-safe limit). Per-path
    /// gating is whack-a-mole (reset, reanchor, namespace-bump, launch-safe all reach it),
    /// so this restores the captured explicit pair AFTER recovery rewrote the persisted
    /// positions — but ONLY when the display width is unchanged from calibration (a real
    /// topology change legitimately reanchors and is left alone) and the captured pair is
    /// an explicit far divider that still fits the current display.
    ///
    /// Callers capture (main, separator, calibratedWidth) BEFORE recovery and invoke this
    /// just before recreating the status items, so the items materialize at the restored
    /// explicit position (no live/persisted mismatch, no recovery loop).
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

        // Only protect a divider the reanchor would actually have clamped: one past the
        // launch-safe limit. A divider at/under the limit was never laundered.
        let safeLimit = StatusBarPositionStore.launchSafePreferredMainPositionLimit(
            for: currentWidth,
            screenHasTopSafeAreaInset: StatusBarPositionStore.screenHasTopSafeAreaInset(screen)
        )
        guard capturedMain > safeLimit else { return false }

        // A genuine display-topology change (width differs from where the divider was
        // calibrated) legitimately reanchors — do not fight it.
        if calibratedWidth > 0, abs(currentWidth - calibratedWidth) > calibratedWidth * 0.1 {
            return false
        }

        // Only act if recovery actually moved the persisted divider toward Control Center.
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

    static func seedAlwaysHiddenSeparatorPositionIfNeeded(referenceScreen: NSScreen? = nil) {
        // AH separator must be left of the regular Hidden separator, but on a
        // notched built-in display it still has to stay inside the usable
        // right-side status item region.
        // UserDefaults positions are pixel offsets from the right screen edge.
        // Plain external displays can use the far-left sentinel. Notched
        // displays need a bounded value so Always Hidden drag targets do not
        // land under the notch.
        let preferredPosition = StatusBarPositionStore.alwaysHiddenPreferredPosition(referenceScreen: referenceScreen)
        logger.info("Seeding AH separator position (\(preferredPosition, privacy: .public))")
        StatusBarPositionDefaultsStore.setPreferredPosition(preferredPosition, forAutosaveName: StatusBarPositionStore.alwaysHiddenSeparatorAutosaveName)
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

    /// Best-effort startup recovery used when runtime invariants detect a bad
    /// separator layout. This keeps the current session usable and seeds safe
    /// positions for the next status-item relayout/restart.
    ///
    /// `preserveExplicitPersistedPositions` is the FM-2 (#136/#168) guard: on the
    /// steady-state wake / Space-change validation path the user's EXPLICIT
    /// persisted divider must survive. Reanchoring toward Control Center there
    /// silently launders an explicit 900 -> 144 (the launch-safe limit), which is
    /// exactly the regression caught by the wake gate. The reanchor is only
    /// legitimate for genuine startup / display-topology recovery, where pixel
    /// positions from a different display are meaningless. When the flag is set we
    /// skip both the display-backup restore (which itself reanchors unsafe backups)
    /// and the explicit reanchor step, leaving the persisted user layout untouched
    /// for an as-is replay.
    static func recoverStartupPositions(
        alwaysHiddenEnabled: Bool,
        referenceScreen: NSScreen? = nil,
        preserveExplicitPersistedPositions: Bool = false
    ) {
        // FM2_TRACE — TEMPORARY DIAGNOSTIC (#136/#168). Remove before ship.
        // Records the preserve flag and the current persisted main value on entry
        // so the probe can see whether the ungated (preserve=false) branch — which
        // falls through to reanchorCurrentDisplayPositionsIfNeeded — was taken on
        // the wake path. A preserve=false entry here with an explicit main (e.g.
        // 900) is the smoking gun.
        os_log(
            "FM2_TRACE recoverStartupPositions preserveExplicit=%{public}@ persistedMainNow=%{public}@ frames=%{public}@",
            log: OSLog(subsystem: "com.sanebar.app", category: "FM2_TRACE"),
            // FM2_TRACE TEMPORARY (#136/#168): .default persists to the unified-log
            // store that `log show` reads; .info does not. Remove before ship.
            type: .default,
            preserveExplicitPersistedPositions ? "true" : "false",
            StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: StatusBarPositionStore.mainAutosaveName).map { String($0) } ?? "nil",
            Thread.callStackSymbols.dropFirst().prefix(6).joined(separator: " | ")
        )
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
