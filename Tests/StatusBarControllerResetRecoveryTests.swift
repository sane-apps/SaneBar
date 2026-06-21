import AppKit
import SaneUI
@testable import SaneBar
import Testing

@Suite("StatusBarControllerResetRecoveryTests", .serialized)
struct StatusBarControllerResetRecoveryTests {
    @Test("Position seed runs when both app and ByHost values are missing")
    func shouldSeedWhenAllValuesMissing() {
        let shouldSeed = StatusBarPositionDefaultsStore.shouldSeedPreferredPosition(
            appValue: nil,
            byHostValue: nil
        )
        #expect(shouldSeed == true)
    }

    @Test("Position seed skips when app value already exists")
    func shouldNotSeedWhenAppValueExists() {
        let shouldSeed = StatusBarPositionDefaultsStore.shouldSeedPreferredPosition(
            appValue: 42,
            byHostValue: nil
        )
        #expect(shouldSeed == false)
    }

    @Test("Position seed skips when ByHost value already exists")
    func shouldNotSeedWhenByHostValueExists() {
        let shouldSeed = StatusBarPositionDefaultsStore.shouldSeedPreferredPosition(
            appValue: nil,
            byHostValue: NSNumber(value: 17)
        )
        #expect(shouldSeed == false)
    }

    @Test("Position seed skips when app value is numeric string")
    func shouldNotSeedWhenAppValueStringExists() {
        let shouldSeed = StatusBarPositionDefaultsStore.shouldSeedPreferredPosition(
            appValue: "42",
            byHostValue: nil
        )
        #expect(shouldSeed == false)
    }

    @Test("Position seed skips when ByHost value is numeric string")
    func shouldNotSeedWhenByHostValueStringExists() {
        let shouldSeed = StatusBarPositionDefaultsStore.shouldSeedPreferredPosition(
            appValue: nil,
            byHostValue: "17"
        )
        #expect(shouldSeed == false)
    }

    @Test("Position seed ignores invalid non-numeric values")
    func shouldSeedWhenValuesAreInvalid() {
        let shouldSeed = StatusBarPositionDefaultsStore.shouldSeedPreferredPosition(
            appValue: "bad",
            byHostValue: Date()
        )
        #expect(shouldSeed == true)
    }

    @Test("Ordinal-seed pair detection only flags tiny seed values")
    func ordinalSeedPairDetection() {
        #expect(StatusBarPositionStore.hasOrdinalSeedPair(mainPosition: 0, separatorPosition: 1))
        #expect(StatusBarPositionStore.hasOrdinalSeedPair(mainPosition: 2, separatorPosition: 3))
        #expect(!StatusBarPositionStore.hasOrdinalSeedPair(mainPosition: 233, separatorPosition: 314))
        #expect(!StatusBarPositionStore.hasOrdinalSeedPair(mainPosition: 0, separatorPosition: 314))
    }

    @Test("Init forces anchor seeding when launch override is enabled")
    @MainActor
    func initForcesAnchorWhenOverrideEnabled() {
        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let screenWidthKey = "SaneBar_CalibratedScreenWidth"
        let migrationKey = "SaneBar_PositionRecovery_Migration_v1"
        let keys = [mainKey, separatorKey, screenWidthKey, migrationKey]
        let originalValues: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }
        let variable = "SANEBAR_FORCE_ANCHOR_ON_LAUNCH"
        let originalEnv = getenv(variable).map { String(cString: $0) }
        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            if let originalEnv {
                setenv(variable, originalEnv, 1)
            } else {
                unsetenv(variable)
            }
        }

        defaults.set(true, forKey: migrationKey)
        if let width = NSScreen.main?.frame.width {
            defaults.set(width, forKey: screenWidthKey)
        }
        defaults.set(420.0, forKey: mainKey)
        defaults.set(360.0, forKey: separatorKey)

        setenv(variable, "1", 1)
        _ = StatusBarController()

        let mainValue = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let separatorValue = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        #expect(mainValue == 0.0, "Override should force main anchor seed")
        #expect(separatorValue == 1.0, "Override should force separator anchor seed")
    }

    @Test("Init preserves existing positions when launch override is disabled")
    @MainActor
    func initPreservesPositionsWhenOverrideDisabled() {
        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let screenWidthKey = "SaneBar_CalibratedScreenWidth"
        let migrationKey = "SaneBar_PositionRecovery_Migration_v1"
        let keys = [mainKey, separatorKey, screenWidthKey, migrationKey]
        let originalValues: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }
        let variable = "SANEBAR_FORCE_ANCHOR_ON_LAUNCH"
        let originalEnv = getenv(variable).map { String(cString: $0) }
        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            if let originalEnv {
                setenv(variable, originalEnv, 1)
            } else {
                unsetenv(variable)
            }
        }

        defaults.set(true, forKey: migrationKey)
        if let width = NSScreen.main?.frame.width {
            defaults.set(width, forKey: screenWidthKey)
        }
        defaults.set(420.0, forKey: mainKey)
        defaults.set(360.0, forKey: separatorKey)

        setenv(variable, "0", 1)
        _ = StatusBarController()

        let mainValue = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let separatorValue = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        #expect(mainValue == 420.0, "Disabled override should preserve existing main position")
        #expect(separatorValue == 360.0, "Disabled override should preserve existing separator position")
    }

    @Test("Init clears persisted status-item visibility overrides")
    @MainActor
    func initClearsPersistedVisibilityOverrides() {
        let defaults = UserDefaults.standard
        let appKeys = [
            "NSStatusItem Visible \(StatusBarController.mainAutosaveName)",
            "NSStatusItem Visible \(StatusBarController.separatorAutosaveName)",
            "NSStatusItem Visible \(StatusBarController.alwaysHiddenSeparatorAutosaveName)",
            "NSStatusItem VisibleCC SaneBar_Main_v7",
            "NSStatusItem Visible SaneBar_spacer_0", // spacer app-domain
        ]
        let byHostKeys = [
            "NSStatusItem Visible SaneBar_main_v7_v6",
            "NSStatusItem Visible SaneBar_separator_v7_v6",
            "NSStatusItem Visible SaneBar_alwaysHiddenSeparator_v7_v6",
            "NSStatusItem Visible SaneBar_alwayshiddenseparator_v7_v6", // legacy lowercased variant
            "NSStatusItem Visible SaneBar_Main_v7_v6", // unknown variant: no lowercasing (#86)
            "NSStatusItem VisibleCC SaneBar_main_v7_v6", // macOS 26 VisibleCC key
            "NSStatusItem Visible SaneBar_spacer_0_v6", // spacer ByHost key
        ]
        let originalAppValues: [(String, Any?)] = appKeys.map { ($0, defaults.object(forKey: $0)) }
        let originalByHostValues: [(String, CFPropertyList?)] = byHostKeys.map { key in
            let value = CFPreferencesCopyValue(
                key as CFString,
                ".GlobalPreferences" as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
            return (key, value as CFPropertyList?)
        }
        defer {
            for (key, value) in originalAppValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
            for (key, value) in originalByHostValues {
                if let value {
                    CFPreferencesSetValue(
                        key as CFString,
                        value,
                        ".GlobalPreferences" as CFString,
                        kCFPreferencesCurrentUser,
                        kCFPreferencesCurrentHost
                    )
                } else {
                    CFPreferencesSetValue(
                        key as CFString,
                        nil,
                        ".GlobalPreferences" as CFString,
                        kCFPreferencesCurrentUser,
                        kCFPreferencesCurrentHost
                    )
                }
            }
            CFPreferencesSynchronize(
                ".GlobalPreferences" as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        }

        for key in appKeys {
            defaults.set(false, forKey: key)
        }
        for key in byHostKeys {
            CFPreferencesSetValue(
                key as CFString,
                kCFBooleanFalse,
                ".GlobalPreferences" as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        }
        CFPreferencesSynchronize(
            ".GlobalPreferences" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )

        _ = StatusBarController()

        for key in appKeys {
            #expect(defaults.object(forKey: key) == nil, "Visibility override should be cleared for \(key)")
        }
        for key in byHostKeys {
            let value = CFPreferencesCopyValue(
                key as CFString,
                ".GlobalPreferences" as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
            #expect(value == nil, "ByHost visibility override should be cleared for \(key)")
        }
    }

    @Test("Explicit reset clears persistent status-item state and reseeds startup-safe positions")
    @MainActor
    func resetPersistentStatusItemStateClearsCorruptState() {
        guard let currentWidth = NSScreen.main?.frame.width,
              let safeRecovery = launchSafeRecoveryPair()
        else {
            Issue.record("Expected a main screen for persistent state reset test")
            return
        }

        let defaults = UserDefaults.standard
        let versionKey = "SaneBar_AutosaveVersion"
        let screenWidthKey = "SaneBar_CalibratedScreenWidth"
        let mainKey = "NSStatusItem Preferred Position SaneBar_Main_v10"
        let separatorKey = "NSStatusItem Preferred Position SaneBar_Separator_v10"
        let alwaysHiddenKey = "NSStatusItem Preferred Position SaneBar_AlwaysHiddenSeparator_v10"
        let spacerKey = "NSStatusItem Preferred Position SaneBar_spacer_0"
        let backupMainKey = StatusBarPositionStore.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarPositionStore.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let appVisibilityKey = "NSStatusItem Visible SaneBar_Main_v10"
        let byHostVisibilityKey = "NSStatusItem Visible SaneBar_Main_v10_v6"
        let byHostPreferredKey = "NSStatusItem Preferred Position SaneBar_Main_v10_v6"
        let keys = [
            versionKey, screenWidthKey, mainKey, separatorKey, alwaysHiddenKey, spacerKey,
            backupMainKey, backupSeparatorKey, appVisibilityKey,
        ]
        let originalValues: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }
        let originalByHostVisibility = CFPreferencesCopyValue(
            byHostVisibilityKey as CFString,
            ".GlobalPreferences" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        let originalByHostPreferred = CFPreferencesCopyValue(
            byHostPreferredKey as CFString,
            ".GlobalPreferences" as CFString,
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
                byHostVisibilityKey as CFString,
                originalByHostVisibility,
                ".GlobalPreferences" as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
            CFPreferencesSetValue(
                byHostPreferredKey as CFString,
                originalByHostPreferred,
                ".GlobalPreferences" as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
            CFPreferencesSynchronize(
                ".GlobalPreferences" as CFString,
                kCFPreferencesCurrentUser,
                kCFPreferencesCurrentHost
            )
        }

        defaults.set(10, forKey: versionKey)
        defaults.set(currentWidth, forKey: screenWidthKey)
        defaults.set(420.0, forKey: mainKey)
        defaults.set(360.0, forKey: separatorKey)
        defaults.set(10000.0, forKey: alwaysHiddenKey)
        defaults.set(255.0, forKey: spacerKey)
        defaults.set(180.0, forKey: backupMainKey)
        defaults.set(300.0, forKey: backupSeparatorKey)
        defaults.set(false, forKey: appVisibilityKey)
        CFPreferencesSetValue(
            byHostVisibilityKey as CFString,
            kCFBooleanFalse,
            ".GlobalPreferences" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSetValue(
            byHostPreferredKey as CFString,
            999.0 as NSNumber,
            ".GlobalPreferences" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSynchronize(
            ".GlobalPreferences" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )

        StatusBarPositionRecoveryStore.resetPersistentStatusItemState(alwaysHiddenEnabled: true)

        #expect(defaults.object(forKey: versionKey) == nil)
        #expect(defaults.object(forKey: appVisibilityKey) == nil)
        #expect((defaults.object(forKey: screenWidthKey) as? NSNumber)?.doubleValue == Double(currentWidth))
        #expect((defaults.object(forKey: backupMainKey) as? NSNumber)?.doubleValue == safeRecovery.main)
        #expect((defaults.object(forKey: backupSeparatorKey) as? NSNumber)?.doubleValue == safeRecovery.separator)

        let byHostVisibility = CFPreferencesCopyValue(
            byHostVisibilityKey as CFString,
            ".GlobalPreferences" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        let byHostPreferred = CFPreferencesCopyValue(
            byHostPreferredKey as CFString,
            ".GlobalPreferences" as CFString,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        #expect(byHostVisibility == nil)
        #expect(byHostPreferred == nil)
        #expect(defaults.object(forKey: spacerKey) == nil)

        let reseededMain = UserDefaults.standard.object(
            forKey: "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        )
        let reseededSeparator = UserDefaults.standard.object(
            forKey: "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        )
        let reseededAlwaysHidden = UserDefaults.standard.object(
            forKey: "NSStatusItem Preferred Position \(StatusBarController.alwaysHiddenSeparatorAutosaveName)"
        ) as? NSNumber
        #expect(reseededMain != nil)
        #expect(reseededSeparator != nil)
        #expect(
            reseededAlwaysHidden?.doubleValue == StatusBarPositionStore.alwaysHiddenPreferredPosition(referenceScreen: NSScreen.main ?? NSScreen.screens.first)
        )
    }

    @Test("Reset persistent state can advance to a fresh autosave namespace")
    @MainActor
    func resetPersistentStatusItemStateUsesFreshNamespaceWhenRequested() {
        guard let currentWidth = NSScreen.main?.frame.width,
              let safeRecovery = launchSafeRecoveryPair()
        else {
            Issue.record("Expected a main screen for fresh autosave reset test")
            return
        }

        let defaults = UserDefaults.standard
        let versionKey = "SaneBar_AutosaveVersion"
        let screenWidthKey = "SaneBar_CalibratedScreenWidth"
        let oldMainKey = "NSStatusItem Preferred Position SaneBar_Main_v10"
        let oldSeparatorKey = "NSStatusItem Preferred Position SaneBar_Separator_v10"
        let freshMainKey = "NSStatusItem Preferred Position SaneBar_Main_v11"
        let freshSeparatorKey = "NSStatusItem Preferred Position SaneBar_Separator_v11"
        let backupMainKey = StatusBarPositionStore.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarPositionStore.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let keys = [
            versionKey,
            screenWidthKey,
            oldMainKey,
            oldSeparatorKey,
            freshMainKey,
            freshSeparatorKey,
            backupMainKey,
            backupSeparatorKey,
        ]
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

        defaults.set(10, forKey: versionKey)
        defaults.set(currentWidth, forKey: screenWidthKey)
        defaults.set(420.0, forKey: oldMainKey)
        defaults.set(360.0, forKey: oldSeparatorKey)

        StatusBarPositionRecoveryStore.resetPersistentStatusItemState(
            alwaysHiddenEnabled: false,
            freshAutosaveNamespace: true
        )

        #expect(defaults.integer(forKey: versionKey) == 11)
        #expect((defaults.object(forKey: backupMainKey) as? NSNumber)?.doubleValue == safeRecovery.main)
        #expect((defaults.object(forKey: backupSeparatorKey) as? NSNumber)?.doubleValue == safeRecovery.separator)
        #expect((defaults.object(forKey: freshMainKey) as? NSNumber)?.doubleValue == safeRecovery.main)
        #expect((defaults.object(forKey: freshSeparatorKey) as? NSNumber)?.doubleValue == safeRecovery.separator)
        #expect(defaults.object(forKey: oldMainKey) == nil)
        #expect(defaults.object(forKey: oldSeparatorKey) == nil)
    }

}
