import AppKit
import SaneUI
@testable import SaneBar
import Testing

@Suite("StatusBarControllerBackupCaptureTests", .serialized)
struct StatusBarControllerBackupCaptureTests {
    @Test("Autosave namespace recovery falls back to launch-safe positions without backup")
    @MainActor
    func recreateItemsWithBumpedVersionUsesLaunchSafeFallback() {
        guard let currentWidth = NSScreen.main?.frame.width,
              let safeRecovery = launchSafeRecoveryPair()
        else {
            Issue.record("Expected a main screen for autosave recovery fallback test")
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
        defaults.removeObject(forKey: backupMainKey)
        defaults.removeObject(forKey: backupSeparatorKey)
        defaults.removeObject(forKey: oldMainKey)
        defaults.removeObject(forKey: oldSeparatorKey)

        let controller = StatusBarController()
        _ = controller.recreateItemsWithBumpedVersion()

        let restoredMain = (defaults.object(forKey: newMainKey) as? NSNumber)?.doubleValue
        let restoredSeparator = (defaults.object(forKey: newSeparatorKey) as? NSNumber)?.doubleValue

        #expect(restoredMain == safeRecovery.main, "Autosave recovery should fall back to a launch-safe main anchor before ordinals")
        #expect(restoredSeparator == safeRecovery.separator, "Autosave recovery should fall back to a launch-safe separator anchor before ordinals")
    }

    @Test("Escalated autosave recovery skips the current-width backup and uses launch-safe positions")
    @MainActor
    func recreateItemsWithBumpedVersionCanBypassCurrentWidthBackup() {
        guard let currentWidth = NSScreen.main?.frame.width,
              let safeRecovery = launchSafeRecoveryPair()
        else {
            Issue.record("Expected a main screen for escalated autosave recovery backup bypass test")
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
        _ = controller.recreateItemsWithBumpedVersion(allowCurrentDisplayBackup: false)

        let restoredMain = (defaults.object(forKey: newMainKey) as? NSNumber)?.doubleValue
        let restoredSeparator = (defaults.object(forKey: newSeparatorKey) as? NSNumber)?.doubleValue

        #expect(defaults.integer(forKey: versionKey) == 11)
        #expect(restoredMain == safeRecovery.main, "Escalated autosave recovery should stop replaying a potentially poisoned current-width backup")
        #expect(restoredSeparator == safeRecovery.separator, "Escalated autosave recovery should use the launch-safe separator anchor instead of the previous backup")
    }

    @Test("Init does not eager-reanchor far-left persisted positions on the current display")
    @MainActor
    func initDoesNotEagerlyReanchorFarLeftPersistedPositions() {
        guard let currentWidth = NSScreen.main?.frame.width else {
            Issue.record("Expected a main screen for current-display reanchor test")
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
        defaults.set(456.0, forKey: mainKey)
        defaults.set(574.0, forKey: separatorKey)
        defaults.set(456.0, forKey: backupMainKey)
        defaults.set(490.0, forKey: backupSeparatorKey)

        _ = StatusBarController()

        let restoredMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let restoredSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        let backupMain = (defaults.object(forKey: backupMainKey) as? NSNumber)?.doubleValue
        let backupSeparator = (defaults.object(forKey: backupSeparatorKey) as? NSNumber)?.doubleValue

        #expect(restoredMain == 456.0, "Same-display launch preflight should preserve persisted positions until live geometry proves they are bad")
        #expect(restoredSeparator == 574.0, "Launch preflight should not shrink the visible lane before status items exist")
        #expect(backupMain == nil, "Unsafe current-width backups should not be rewritten from prelaunch preferred-position heuristics")
        #expect(backupSeparator == nil, "Unsafe current-width backups should be cleared instead of replacing user layout early")
    }

    @Test("Stable live positions backfill the current-width display backup")
    @MainActor
    func captureCurrentDisplayPositionBackupFromStablePositions() {
        guard let currentWidth = NSScreen.main?.frame.width else {
            Issue.record("Expected a main screen for display backup capture test")
            return
        }

        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let backupMainKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let keys = [mainKey, separatorKey, backupMainKey, backupSeparatorKey]
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
        let safeMain = screenHasTopSafeAreaInset
            ? 180.0
            : StatusBarController.launchSafePreferredMainPositionLimit(
                for: currentWidth,
                screenHasTopSafeAreaInset: false
            )
        let safeSeparator = safeMain + StatusBarController.launchSafePreferredSeparatorGap(for: currentWidth)

        defaults.set(safeMain, forKey: mainKey)
        defaults.set(safeSeparator, forKey: separatorKey)
        defaults.removeObject(forKey: backupMainKey)
        defaults.removeObject(forKey: backupSeparatorKey)

        #expect(
            StatusBarController.captureCurrentDisplayPositionBackupIfPossible(),
            "Stable live positions should either create or confirm a safe current-width backup"
        )

        let storedBackupMain = (defaults.object(forKey: backupMainKey) as? NSNumber)?.doubleValue
        let storedBackupSeparator = (defaults.object(forKey: backupSeparatorKey) as? NSNumber)?.doubleValue

        #expect(storedBackupMain == safeMain, "Stable live positions should seed a current-width main backup for the next startup recovery")
        #expect(storedBackupSeparator == safeSeparator, "Stable live positions should seed a current-width separator backup for the next startup recovery")
    }

    @Test("Stable validation restores current-width backup over app-domain ordinal seeds")
    @MainActor
    func captureCurrentDisplayPositionBackupRepairsOrdinalAppDefaultsFromBackup() {
        guard let currentWidth = NSScreen.main?.frame.width,
              let safeRecovery = launchSafeRecoveryPair()
        else {
            Issue.record("Expected a main screen for ordinal backup repair test")
            return
        }

        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let backupMainKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let keys = [mainKey, separatorKey, backupMainKey, backupSeparatorKey]
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

        defaults.set(0.0, forKey: mainKey)
        defaults.set(1.0, forKey: separatorKey)
        defaults.set(safeRecovery.main, forKey: backupMainKey)
        defaults.set(safeRecovery.separator, forKey: backupSeparatorKey)

        #expect(
            StatusBarController.captureCurrentDisplayPositionBackupIfPossible(),
            "Stable validation should repair app-domain ordinal seeds from the current-width backup"
        )

        let restoredMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let restoredSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue

        #expect(restoredMain == safeRecovery.main)
        #expect(restoredSeparator == safeRecovery.separator)
    }

    @Test("Stable validation promotes safe ByHost preferred positions over app-domain ordinal seeds")
    @MainActor
    func captureCurrentDisplayPositionBackupPromotesSafeByHostOverOrdinalAppDefaults() {
        guard let currentWidth = NSScreen.main?.frame.width,
              let safeRecovery = launchSafeRecoveryPair()
        else {
            Issue.record("Expected a main screen for ByHost promotion test")
            return
        }

        let defaults = UserDefaults.standard
        let mainAutosaveName = StatusBarController.mainAutosaveName
        let separatorAutosaveName = StatusBarController.separatorAutosaveName
        let mainKey = "NSStatusItem Preferred Position \(mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(separatorAutosaveName)"
        let backupMainKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let scopedBackupMainKey = StatusBarPositionStore.displayPositionBackupKey(
            for: currentWidth,
            referenceScreen: NSScreen.main,
            slot: "main"
        )
        let scopedBackupSeparatorKey = StatusBarPositionStore.displayPositionBackupKey(
            for: currentWidth,
            referenceScreen: NSScreen.main,
            slot: "separator"
        )
        let byHostMainKey = StatusBarPositionDefaultsStore.byHostPreferredPositionKey(for: mainAutosaveName)
        let byHostSeparatorKey = StatusBarPositionDefaultsStore.byHostPreferredPositionKey(for: separatorAutosaveName)
        let globalDomain = ".GlobalPreferences" as CFString
        let keys = [mainKey, separatorKey, backupMainKey, backupSeparatorKey, scopedBackupMainKey, scopedBackupSeparatorKey]
        let originalValues: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }
        let originalByHostMain = CFPreferencesCopyValue(
            byHostMainKey as CFString,
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        let originalByHostSeparator = CFPreferencesCopyValue(
            byHostSeparatorKey as CFString,
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )

        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            CFPreferencesSetValue(
                byHostMainKey as CFString,
                originalByHostMain,
                globalDomain,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
            CFPreferencesSetValue(
                byHostSeparatorKey as CFString,
                originalByHostSeparator,
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

        defaults.set(0.0, forKey: mainKey)
        defaults.set(1.0, forKey: separatorKey)
        defaults.removeObject(forKey: backupMainKey)
        defaults.removeObject(forKey: backupSeparatorKey)
        defaults.removeObject(forKey: scopedBackupMainKey)
        defaults.removeObject(forKey: scopedBackupSeparatorKey)
        StatusBarPositionDefaultsStore.setByHostPreferredPosition(safeRecovery.main, forAutosaveName: mainAutosaveName)
        StatusBarPositionDefaultsStore.setByHostPreferredPosition(safeRecovery.separator, forAutosaveName: separatorAutosaveName)

        #expect(
            StatusBarController.captureCurrentDisplayPositionBackupIfPossible(),
            "Stable validation should promote a safe ByHost position pair when app-domain values are only ordinal seeds"
        )

        let restoredMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let restoredSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        let storedBackupMain = (defaults.object(forKey: backupMainKey) as? NSNumber)?.doubleValue
        let storedBackupSeparator = (defaults.object(forKey: backupSeparatorKey) as? NSNumber)?.doubleValue

        #expect(restoredMain == safeRecovery.main)
        #expect(restoredSeparator == safeRecovery.separator)
        #expect(storedBackupMain == safeRecovery.main)
        #expect(storedBackupSeparator == safeRecovery.separator)
    }

    @Test("Stable but startup-unsafe positions backfill a reanchored current-width backup")
    @MainActor
    func captureCurrentDisplayPositionBackupReanchorsUnsafePositions() {
        guard let currentWidth = NSScreen.main?.frame.width else {
            Issue.record("Expected a main screen for reanchored display backup capture test")
            return
        }

        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let backupMainKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let keys = [mainKey, separatorKey, backupMainKey, backupSeparatorKey]
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
        let safeMainLimit = StatusBarController.launchSafePreferredMainPositionLimit(
            for: currentWidth,
            screenHasTopSafeAreaInset: screenHasTopSafeAreaInset
        )
        let unsafeMain = safeMainLimit + 40.0
        let unsafeSeparator = unsafeMain + 34.0

        defaults.set(unsafeMain, forKey: mainKey)
        defaults.set(unsafeSeparator, forKey: separatorKey)
        defaults.removeObject(forKey: backupMainKey)
        defaults.removeObject(forKey: backupSeparatorKey)

        #expect(
            StatusBarController.captureCurrentDisplayPositionBackupIfPossible(),
            "Stable but startup-unsafe positions should still end with a safe current-width backup"
        )

        let storedBackupMain = (defaults.object(forKey: backupMainKey) as? NSNumber)?.doubleValue
        let storedBackupSeparator = (defaults.object(forKey: backupSeparatorKey) as? NSNumber)?.doubleValue

        #expect(abs((storedBackupMain ?? .nan) - safeMainLimit) < 0.0001, "Startup-unsafe live positions should still seed a launch-safe current-width main backup")
        #expect(abs((storedBackupSeparator ?? .nan) - (safeMainLimit + 34.0)) < 0.0001, "Reanchored separator backup should preserve the live gap while staying launch-safe")
    }

    @Test("Stable live positions can backfill the current-width backup when preferred positions are still missing")
    @MainActor
    func captureCurrentDisplayPositionBackupFromLiveFallbackPositions() {
        guard let currentWidth = NSScreen.main?.frame.width else {
            Issue.record("Expected a main screen for live fallback display backup capture test")
            return
        }

        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let backupMainKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let keys = [mainKey, separatorKey, backupMainKey, backupSeparatorKey]
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

        defaults.removeObject(forKey: mainKey)
        defaults.removeObject(forKey: separatorKey)
        defaults.removeObject(forKey: backupMainKey)
        defaults.removeObject(forKey: backupSeparatorKey)

        let screenHasTopSafeAreaInset = StatusBarController.screenHasTopSafeAreaInset(NSScreen.main)
        let liveMain = screenHasTopSafeAreaInset
            ? 180.0
            : StatusBarController.launchSafePreferredMainPositionLimit(
                for: currentWidth,
                screenHasTopSafeAreaInset: false
            )
        let liveSeparator = liveMain + StatusBarController.launchSafePreferredSeparatorGap(for: currentWidth)

        #expect(
            StatusBarController.captureCurrentDisplayPositionBackupIfPossible(
                mainPosition: liveMain,
                separatorPosition: liveSeparator
            ),
            "Healthy live positions should seed a current-width backup even before preferred-position keys exist"
        )

        let storedBackupMain = (defaults.object(forKey: backupMainKey) as? NSNumber)?.doubleValue
        let storedBackupSeparator = (defaults.object(forKey: backupSeparatorKey) as? NSNumber)?.doubleValue

        #expect(storedBackupMain == liveMain, "Live fallback main position should seed the current-width backup")
        #expect(storedBackupSeparator == liveSeparator, "Live fallback separator position should seed the current-width backup")
    }

    @Test("Invalid override positions do not clobber a restorable current-width backup source")
    @MainActor
    func captureCurrentDisplayPositionBackupIgnoresInvalidOverridePositions() {
        guard let currentWidth = NSScreen.main?.frame.width else {
            Issue.record("Expected a main screen for invalid override display backup test")
            return
        }

        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let backupMainKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarController.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let keys = [mainKey, separatorKey, backupMainKey, backupSeparatorKey]
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
        let persistedMain = StatusBarController.launchSafePreferredMainPositionLimit(
            for: currentWidth,
            screenHasTopSafeAreaInset: screenHasTopSafeAreaInset
        )
        let persistedSeparator = persistedMain + 196.0
        defaults.set(persistedMain, forKey: mainKey)
        defaults.set(persistedSeparator, forKey: separatorKey)
        defaults.removeObject(forKey: backupMainKey)
        defaults.removeObject(forKey: backupSeparatorKey)

        #expect(
            StatusBarController.captureCurrentDisplayPositionBackupIfPossible(
                mainPosition: currentWidth - 222.0,
                separatorPosition: currentWidth - 359.0
            ),
            "Invalid override positions should fall back to the persisted preferred-position pair instead of shrinking the backup to a generic launch-safe anchor"
        )

        let storedBackupMain = (defaults.object(forKey: backupMainKey) as? NSNumber)?.doubleValue
        let storedBackupSeparator = (defaults.object(forKey: backupSeparatorKey) as? NSNumber)?.doubleValue

        #expect(storedBackupMain == persistedMain, "Invalid override positions should leave the current-width main backup anchored to the persisted preferred-position value")
        #expect(storedBackupSeparator == persistedSeparator, "Invalid override positions should leave the current-width separator backup anchored to the persisted preferred-position value")
    }
}
