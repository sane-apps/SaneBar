import AppKit
import SaneUI
@testable import SaneBar
import Testing

@Suite("StatusBarControllerStartupRecoveryTests", .serialized)
struct StatusBarControllerStartupRecoveryTests {
    @Test("Status item position validation fails when no window is attached")
    func statusItemWindowValidationRequiresWindow() {
        #expect(
            !StatusBarController.isStatusItemWindowFrameValid(
                windowFrame: nil,
                screenFrame: nil
            )
        )
        #expect(
            StatusBarController.isStatusItemWindowFrameValid(
                windowFrame: CGRect(x: 1200, y: 923, width: 30, height: 33),
                screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 956)
            )
        )
        #expect(
            !StatusBarController.isStatusItemWindowFrameValid(
                windowFrame: CGRect(x: -3780, y: 923, width: 30, height: 33),
                screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 956)
            )
        )
        #expect(
            StatusBarController.isStatusItemWindowFrameValid(
                windowFrame: CGRect(x: -3000, y: 923, width: 5001, height: 33),
                screenFrame: CGRect(x: 0, y: 0, width: 1512, height: 956)
            )
        )
    }

    @Test("Init restores matching display backup instead of resetting to ordinals")
    @MainActor
    func initRestoresMatchingDisplayBackup() {
        guard let currentWidth = NSScreen.main?.frame.width else {
            Issue.record("Expected a main screen for display backup test")
            return
        }

        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let screenWidthKey = "SaneBar_CalibratedScreenWidth"
        let migrationKey = "SaneBar_PositionRecovery_Migration_v1"
        let backupMainKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let keys = [mainKey, separatorKey, screenWidthKey, migrationKey, backupMainKey, backupSeparatorKey]
        let originalValues: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }

        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(true, forKey: migrationKey)
        defaults.set(currentWidth * 1.6, forKey: screenWidthKey)
        defaults.set(2200.0, forKey: mainKey)
        defaults.set(2100.0, forKey: separatorKey)
        defaults.set(180.0, forKey: backupMainKey)
        defaults.set(300.0, forKey: backupSeparatorKey)

        _ = StatusBarController()

        let restoredMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let restoredSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        let storedWidth = defaults.double(forKey: screenWidthKey)
        let expectedWidth = Double(currentWidth)
        let screenHasTopSafeAreaInset = StatusBarController.screenHasTopSafeAreaInset(NSScreen.main)
        let expectedMain = screenHasTopSafeAreaInset ? 180.0 : StatusBarController.launchSafePreferredMainPositionLimit(
            for: currentWidth,
            screenHasTopSafeAreaInset: false
        )
        let expectedSeparator = expectedMain + StatusBarController.launchSafePreferredSeparatorGap(for: currentWidth)

        #expect(restoredMain == expectedMain, "Matching display backup should restore or safely reanchor the main position")
        #expect(restoredSeparator == expectedSeparator, "Matching display backup should restore or safely reanchor the separator position")
        #expect(
            abs(storedWidth - expectedWidth) < 0.001,
            "Restoring a matching backup should stamp the current display width"
        )
    }

    @Test("Init widens launch-safe but narrow display backup")
    @MainActor
    func initWidensLaunchSafeNarrowDisplayBackup() {
        guard let currentWidth = NSScreen.main?.frame.width else {
            Issue.record("Expected a main screen for narrow display backup test")
            return
        }

        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let screenWidthKey = "SaneBar_CalibratedScreenWidth"
        let migrationKey = "SaneBar_PositionRecovery_Migration_v1"
        let backupMainKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let keys = [mainKey, separatorKey, screenWidthKey, migrationKey, backupMainKey, backupSeparatorKey]
        let originalValues: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }

        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        let screenHasTopSafeAreaInset = StatusBarController.screenHasTopSafeAreaInset(NSScreen.main)
        let safeMain = screenHasTopSafeAreaInset ? 180.0 : StatusBarController.launchSafePreferredMainPositionLimit(
            for: currentWidth,
            screenHasTopSafeAreaInset: false
        )
        let safeGap = StatusBarController.launchSafePreferredSeparatorGap(for: currentWidth)
        let narrowGap = max(24.0, safeGap - 9.0)

        defaults.set(true, forKey: migrationKey)
        defaults.set(currentWidth * 1.6, forKey: screenWidthKey)
        defaults.set(2200.0, forKey: mainKey)
        defaults.set(2100.0, forKey: separatorKey)
        defaults.set(safeMain, forKey: backupMainKey)
        defaults.set(safeMain + narrowGap, forKey: backupSeparatorKey)

        _ = StatusBarController()

        let restoredMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let restoredSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue

        #expect(restoredMain == safeMain)
        #expect(restoredSeparator == safeMain + safeGap)
    }

    @Test("Init uses launch-safe current-display recovery when width changed and no backup exists")
    @MainActor
    func initUsesLaunchSafeFallbackForDisplayResetWithoutBackup() {
        guard let currentWidth = NSScreen.main?.frame.width,
              let safeRecovery = launchSafeRecoveryPair()
        else {
            Issue.record("Expected a main screen for display reset fallback test")
            return
        }

        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let screenWidthKey = "SaneBar_CalibratedScreenWidth"
        let migrationKey = "SaneBar_PositionRecovery_Migration_v1"
        let backupMainKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let keys = [mainKey, separatorKey, screenWidthKey, migrationKey, backupMainKey, backupSeparatorKey]
        let originalValues: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }

        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(true, forKey: migrationKey)
        defaults.set(currentWidth * 1.6, forKey: screenWidthKey)
        defaults.set(2200.0, forKey: mainKey)
        defaults.set(2100.0, forKey: separatorKey)
        defaults.removeObject(forKey: backupMainKey)
        defaults.removeObject(forKey: backupSeparatorKey)

        _ = StatusBarController()

        let restoredMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let restoredSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        let storedWidth = defaults.double(forKey: screenWidthKey)

        #expect(restoredMain == safeRecovery.main, "Display-reset init should use a launch-safe main anchor before ordinals")
        #expect(restoredSeparator == safeRecovery.separator, "Display-reset init should use a launch-safe separator anchor before ordinals")
        #expect(abs(storedWidth - Double(currentWidth)) < 0.001, "Display-reset init should stamp the current screen width after applying the launch-safe anchor")
    }

    @Test("Init restores current-width backup when persisted positions are ordinal seeds")
    @MainActor
    func initRestoresCurrentWidthBackupOverOrdinalSeeds() {
        guard let currentWidth = NSScreen.main?.frame.width else {
            Issue.record("Expected a main screen for ordinal-seed backup test")
            return
        }

        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let screenWidthKey = "SaneBar_CalibratedScreenWidth"
        let migrationKey = "SaneBar_PositionRecovery_Migration_v1"
        let backupMainKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let keys = [mainKey, separatorKey, screenWidthKey, migrationKey, backupMainKey, backupSeparatorKey]
        let originalValues: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }

        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(true, forKey: migrationKey)
        defaults.set(currentWidth, forKey: screenWidthKey)
        defaults.set(0.0, forKey: mainKey)
        defaults.set(1.0, forKey: separatorKey)
        defaults.set(180.0, forKey: backupMainKey)
        defaults.set(300.0, forKey: backupSeparatorKey)

        _ = StatusBarController()

        let restoredMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let restoredSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        let screenHasTopSafeAreaInset = StatusBarController.screenHasTopSafeAreaInset(NSScreen.main)
        let expectedMain = screenHasTopSafeAreaInset ? 180.0 : StatusBarController.launchSafePreferredMainPositionLimit(
            for: currentWidth,
            screenHasTopSafeAreaInset: false
        )
        let expectedSeparator = expectedMain + StatusBarController.launchSafePreferredSeparatorGap(for: currentWidth)

        #expect(restoredMain == expectedMain, "Ordinal seed main position should be replaced with a safe current-width backup")
        #expect(restoredSeparator == expectedSeparator, "Ordinal seed separator position should be replaced with a safe current-width backup")
    }

    @Test("Init preserves same-display pixel positions instead of eager reanchoring before live validation")
    @MainActor
    func initPreservesSameDisplayPixelPositions() {
        guard let currentWidth = NSScreen.main?.frame.width else {
            Issue.record("Expected a main screen for same-display position preservation test")
            return
        }

        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let screenWidthKey = "SaneBar_CalibratedScreenWidth"
        let migrationKey = "SaneBar_PositionRecovery_Migration_v1"
        let backupMainKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let keys = [mainKey, separatorKey, screenWidthKey, migrationKey, backupMainKey, backupSeparatorKey]
        let originalValues: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }

        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(true, forKey: migrationKey)
        defaults.set(currentWidth, forKey: screenWidthKey)
        defaults.set(220.0, forKey: mainKey)
        defaults.set(340.0, forKey: separatorKey)
        defaults.removeObject(forKey: backupMainKey)
        defaults.removeObject(forKey: backupSeparatorKey)

        _ = StatusBarController()

        let restoredMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let restoredSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue

        #expect(restoredMain == 220.0, "Same-display pixel positions should survive launch preflight unchanged until live geometry says otherwise")
        #expect(restoredSeparator == 340.0, "Pre-launch display validation should not shrink the visible lane on a same-width launch")
    }

    @Test("Startup recovery restores current-width backup when available")
    @MainActor
    func startupRecoveryRestoresCurrentWidthBackup() {
        guard let currentWidth = NSScreen.main?.frame.width else {
            Issue.record("Expected a main screen for startup recovery backup test")
            return
        }

        let defaults = UserDefaults.standard
        let screenWidthKey = "SaneBar_CalibratedScreenWidth"
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let backupMainKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let keys = [screenWidthKey, mainKey, separatorKey, backupMainKey, backupSeparatorKey]
        let originalValues: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }

        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(currentWidth, forKey: screenWidthKey)
        defaults.set(0.0, forKey: mainKey)
        defaults.set(1.0, forKey: separatorKey)
        defaults.set(180.0, forKey: backupMainKey)
        defaults.set(300.0, forKey: backupSeparatorKey)

        StatusBarController.recoverStartupPositions(alwaysHiddenEnabled: false)

        let restoredMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let restoredSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        let screenHasTopSafeAreaInset = StatusBarController.screenHasTopSafeAreaInset(NSScreen.main)
        let expectedMain = screenHasTopSafeAreaInset ? 180.0 : StatusBarController.launchSafePreferredMainPositionLimit(
            for: currentWidth,
            screenHasTopSafeAreaInset: false
        )
        let expectedSeparator = expectedMain + StatusBarController.launchSafePreferredSeparatorGap(for: currentWidth)

        #expect(restoredMain == expectedMain, "Startup recovery should prefer a safe current-width backup over ordinal reseeds")
        #expect(restoredSeparator == expectedSeparator, "Startup recovery should restore or safely reanchor the separator from the current-width backup")
    }

    @Test("Startup recovery falls back to launch-safe current-display positions before ordinals")
    @MainActor
    func startupRecoveryUsesLaunchSafeFallbackWithoutBackup() {
        guard let currentWidth = NSScreen.main?.frame.width,
              let safeRecovery = launchSafeRecoveryPair()
        else {
            Issue.record("Expected a main screen for startup recovery fallback test")
            return
        }

        let defaults = UserDefaults.standard
        let screenWidthKey = "SaneBar_CalibratedScreenWidth"
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let backupMainKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let keys = [screenWidthKey, mainKey, separatorKey, backupMainKey, backupSeparatorKey]
        let originalValues: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }

        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(currentWidth, forKey: screenWidthKey)
        defaults.removeObject(forKey: backupMainKey)
        defaults.removeObject(forKey: backupSeparatorKey)
        defaults.removeObject(forKey: mainKey)
        defaults.removeObject(forKey: separatorKey)

        StatusBarController.recoverStartupPositions(alwaysHiddenEnabled: false)

        let restoredMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let restoredSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue

        #expect(restoredMain == safeRecovery.main, "Startup recovery should use a launch-safe main anchor before falling back to ordinals")
        #expect(restoredSeparator == safeRecovery.separator, "Startup recovery should use a launch-safe separator anchor before falling back to ordinals")
    }

    @Test("Autosave namespace recovery restores current-width backup into new version")
    @MainActor
    func recreateItemsWithBumpedVersionRestoresCurrentWidthBackup() {
        guard let currentWidth = NSScreen.main?.frame.width else {
            Issue.record("Expected a main screen for autosave recovery backup test")
            return
        }

        let defaults = UserDefaults.standard
        let versionKey = "SaneBar_AutosaveVersion"
        let originalVersion = defaults.object(forKey: versionKey)
        let backupMainKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let oldMainKey = "NSStatusItem Preferred Position SaneBar_Main_v10"
        let oldSeparatorKey = "NSStatusItem Preferred Position SaneBar_Separator_v10"
        let newMainKey = "NSStatusItem Preferred Position SaneBar_Main_v11"
        let newSeparatorKey = "NSStatusItem Preferred Position SaneBar_Separator_v11"
        let keys = [versionKey, backupMainKey, backupSeparatorKey, oldMainKey, oldSeparatorKey, newMainKey, newSeparatorKey]
        let originalValues: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }

        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            if let originalVersion {
                defaults.set(originalVersion, forKey: versionKey)
            } else {
                defaults.removeObject(forKey: versionKey)
            }
        }

        defaults.set(10, forKey: versionKey)
        defaults.set(0.0, forKey: oldMainKey)
        defaults.set(1.0, forKey: oldSeparatorKey)
        defaults.set(180.0, forKey: backupMainKey)
        defaults.set(300.0, forKey: backupSeparatorKey)

        let controller = StatusBarController()
        _ = controller.recreateItemsWithBumpedVersion()

        let restoredMain = (defaults.object(forKey: newMainKey) as? NSNumber)?.doubleValue
        let restoredSeparator = (defaults.object(forKey: newSeparatorKey) as? NSNumber)?.doubleValue
        let screenHasTopSafeAreaInset = StatusBarController.screenHasTopSafeAreaInset(NSScreen.main)
        let expectedMain = screenHasTopSafeAreaInset ? 180.0 : StatusBarController.launchSafePreferredMainPositionLimit(
            for: currentWidth,
            screenHasTopSafeAreaInset: false
        )
        let expectedSeparator = expectedMain + StatusBarController.launchSafePreferredSeparatorGap(for: currentWidth)

        #expect(defaults.integer(forKey: versionKey) == 11)
        #expect(restoredMain == expectedMain, "Autosave recovery should hydrate the new namespace from a safe current-width backup")
        #expect(restoredSeparator == expectedSeparator, "Autosave recovery should restore or safely reanchor separator ordering into the new namespace")
    }

    @Test("Launch-safe recovery preserves enough visible lane for leftmost shown items")
    func launchSafeRecoveryUsesWiderVisibleLane() {
        let miniExternalPair = StatusBarController.launchSafeCurrentDisplayRecoveryPair(
            screenWidth: 1920,
            screenHasTopSafeAreaInset: false
        )
        let externalDisplayPair = StatusBarController.launchSafeCurrentDisplayRecoveryPair(
            screenWidth: 2560,
            screenHasTopSafeAreaInset: false
        )
        let smallDisplayPair = StatusBarController.launchSafeCurrentDisplayRecoveryPair(
            screenWidth: 1512,
            screenHasTopSafeAreaInset: true
        )

        #expect(miniExternalPair?.main == 144)
        #expect((miniExternalPair?.separator ?? 0) - (miniExternalPair?.main ?? 0) >= 220)
        #expect(externalDisplayPair?.main == 160)
        #expect((externalDisplayPair?.separator ?? 0) - (externalDisplayPair?.main ?? 0) >= 220)
        #expect(smallDisplayPair?.main == 180)
        #expect((smallDisplayPair?.separator ?? 0) - (smallDisplayPair?.main ?? 0) >= 136)
    }

    @Test("App Shortcuts registration is skipped in test hosts")
    func appShortcutsRegistrationIsSkippedInTests() {
        #expect(!SaneBarAppDelegate.shouldUpdateAppShortcutParameters(
            environment: ["XCTestConfigurationFilePath": "/tmp/test.xctestconfiguration"],
            isRunningTests: false
        ))
        #expect(!SaneBarAppDelegate.shouldUpdateAppShortcutParameters(
            environment: [:],
            isRunningTests: true
        ))
        #expect(SaneBarAppDelegate.shouldUpdateAppShortcutParameters(
            environment: [:],
            isRunningTests: false
        ))
    }

    @Test("No-keychain automation skips duplicate self-termination guard")
    func noKeychainAutomationSkipsDuplicateSelfTerminationGuard() {
        #expect(SaneBarAppDelegate.shouldSkipDuplicateTerminationForAutomation(
            environment: ["SANEAPPS_DISABLE_KEYCHAIN": "1"],
            arguments: []
        ))
        #expect(SaneBarAppDelegate.shouldSkipDuplicateTerminationForAutomation(
            environment: [:],
            arguments: ["SaneBar", "--sane-no-keychain"]
        ))
        #expect(!SaneBarAppDelegate.shouldSkipDuplicateTerminationForAutomation(
            environment: [:],
            arguments: ["SaneBar"]
        ))
    }

    @Test("No-keychain automation cancels only unexpected termination")
    func noKeychainAutomationCancelsOnlyUnexpectedTermination() {
        #expect(SaneBarAppDelegate.shouldCancelUnexpectedTerminationForAutomation(
            explicitTerminationRequested: false,
            environment: ["SANEAPPS_DISABLE_KEYCHAIN": "1"],
            arguments: []
        ))
        #expect(!SaneBarAppDelegate.shouldCancelUnexpectedTerminationForAutomation(
            explicitTerminationRequested: false,
            environment: ["SANEAPPS_DISABLE_KEYCHAIN": "1"],
            arguments: [],
            automationExplicitTerminationRequested: true
        ))
        #expect(!SaneBarAppDelegate.shouldCancelUnexpectedTerminationForAutomation(
            explicitTerminationRequested: true,
            environment: ["SANEAPPS_DISABLE_KEYCHAIN": "1"],
            arguments: []
        ))
        #expect(!SaneBarAppDelegate.shouldCancelUnexpectedTerminationForAutomation(
            explicitTerminationRequested: false,
            environment: [:],
            arguments: ["SaneBar"]
        ))
    }

    @Test("No-keychain automation quit marker must match launch token")
    func noKeychainAutomationQuitMarkerMustMatchLaunchToken() {
        #expect(SaneBarAppDelegate.hasMatchingAutomationQuitMarker(
            environment: [SaneBarAppDelegate.automationQuitTokenEnvironmentKey: "fixture-token"],
            markerContents: "fixture-token\n"
        ))
        #expect(!SaneBarAppDelegate.hasMatchingAutomationQuitMarker(
            environment: [SaneBarAppDelegate.automationQuitTokenEnvironmentKey: "fixture-token"],
            markerContents: "other-token\n"
        ))
        #expect(!SaneBarAppDelegate.hasMatchingAutomationQuitMarker(
            environment: [:],
            markerContents: "fixture-token\n"
        ))
    }

}
