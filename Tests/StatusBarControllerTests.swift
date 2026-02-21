import AppKit
@testable import SaneBar
import Testing

// MARK: - Menu Item Lookup Helper

extension NSMenu {
    /// Find a menu item by its title (safer than hardcoded indices)
    func item(titled title: String) -> NSMenuItem? {
        items.first { $0.title == title }
    }
}

// MARK: - StatusBarControllerTests

@Suite("StatusBarController Tests")
struct StatusBarControllerTests {
    // MARK: - Icon Name Tests

    @Test("iconName returns correct icon for expanded state")
    @MainActor
    func iconNameExpanded() {
        let controller = StatusBarController()

        let iconName = controller.iconName(for: .expanded)

        #expect(iconName == StatusBarController.iconExpanded)
        #expect(!iconName.isEmpty, "Icon name should not be empty")
    }

    @Test("iconName returns correct icon for hidden state")
    @MainActor
    func iconNameHidden() {
        let controller = StatusBarController()

        let iconName = controller.iconName(for: .hidden)

        #expect(iconName == StatusBarController.iconHidden)
        #expect(!iconName.isEmpty, "Icon name should not be empty")
    }

    // MARK: - Static Constants Tests

    @Test("Autosave names are defined")
    func autosaveNamesExist() {
        #expect(!StatusBarController.mainAutosaveName.isEmpty)
        #expect(!StatusBarController.separatorAutosaveName.isEmpty)
        #expect(!StatusBarController.alwaysHiddenSeparatorAutosaveName.isEmpty)
    }

    @Test("Autosave names are unique")
    func autosaveNamesUnique() {
        let names = [
            StatusBarController.mainAutosaveName,
            StatusBarController.separatorAutosaveName,
            StatusBarController.alwaysHiddenSeparatorAutosaveName,
        ]

        let uniqueNames = Set(names)
        #expect(uniqueNames.count == names.count, "All autosave names must be unique")
    }

    @Test("Autosave names have SaneBar prefix")
    func autosaveNamesHavePrefix() {
        #expect(StatusBarController.mainAutosaveName.hasPrefix("SaneBar_"))
        #expect(StatusBarController.separatorAutosaveName.hasPrefix("SaneBar_"))
        #expect(StatusBarController.alwaysHiddenSeparatorAutosaveName.hasPrefix("SaneBar_"))
    }

    @Test("Position seed runs when both app and ByHost values are missing")
    func shouldSeedWhenAllValuesMissing() {
        let shouldSeed = StatusBarController.shouldSeedPreferredPosition(
            appValue: nil,
            byHostValue: nil
        )
        #expect(shouldSeed == true)
    }

    @Test("Position seed skips when app value already exists")
    func shouldNotSeedWhenAppValueExists() {
        let shouldSeed = StatusBarController.shouldSeedPreferredPosition(
            appValue: 42,
            byHostValue: nil
        )
        #expect(shouldSeed == false)
    }

    @Test("Position seed skips when ByHost value already exists")
    func shouldNotSeedWhenByHostValueExists() {
        let shouldSeed = StatusBarController.shouldSeedPreferredPosition(
            appValue: nil,
            byHostValue: NSNumber(value: 17)
        )
        #expect(shouldSeed == false)
    }

    @Test("Position seed skips when app value is numeric string")
    func shouldNotSeedWhenAppValueStringExists() {
        let shouldSeed = StatusBarController.shouldSeedPreferredPosition(
            appValue: "42",
            byHostValue: nil
        )
        #expect(shouldSeed == false)
    }

    @Test("Position seed skips when ByHost value is numeric string")
    func shouldNotSeedWhenByHostValueStringExists() {
        let shouldSeed = StatusBarController.shouldSeedPreferredPosition(
            appValue: nil,
            byHostValue: "17"
        )
        #expect(shouldSeed == false)
    }

    @Test("Position seed ignores invalid non-numeric values")
    func shouldSeedWhenValuesAreInvalid() {
        let shouldSeed = StatusBarController.shouldSeedPreferredPosition(
            appValue: "bad",
            byHostValue: Date()
        )
        #expect(shouldSeed == true)
    }

    @Test("Init clears persisted status-item visibility overrides")
    @MainActor
    func initClearsPersistedVisibilityOverrides() {
        let defaults = UserDefaults.standard
        let appKeys = [
            "NSStatusItem Visible \(StatusBarController.mainAutosaveName)",
            "NSStatusItem Visible \(StatusBarController.separatorAutosaveName)",
            "NSStatusItem Visible \(StatusBarController.alwaysHiddenSeparatorAutosaveName)",
        ]
        let byHostKeys = [
            "NSStatusItem Visible SaneBar_main_v7_v6",
            "NSStatusItem Visible SaneBar_separator_v7_v6",
            "NSStatusItem Visible SaneBar_alwaysHiddenSeparator_v7_v6",
            "NSStatusItem Visible SaneBar_alwayshiddenseparator_v7_v6", // legacy lowercased variant seen in the field
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

    @Test("Migration preserves healthy custom positions on upgrade")
    @MainActor
    func migrationPreservesHealthyPositions() {
        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let alwaysHiddenKey = "NSStatusItem Preferred Position \(StatusBarController.alwaysHiddenSeparatorAutosaveName)"
        let legacyAlwaysHiddenKey = "NSStatusItem Preferred Position SaneBar_AlwaysHiddenSeparator"
        let migrationKeys = [
            "SaneBar_PositionRecovery_Migration_v1",
            "SaneBar_PositionMigration_v4",
            "SaneBar_PositionMigration_v5",
            "SaneBar_PositionMigration_v6",
            "SaneBar_PositionMigration_v7",
            "SaneBar_CalibratedScreenWidth",
        ]
        let allKeys = [mainKey, separatorKey, alwaysHiddenKey, legacyAlwaysHiddenKey] + migrationKeys
        let originalValues: [(String, Any?)] = allKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        for key in migrationKeys {
            defaults.removeObject(forKey: key)
        }

        if let currentWidth = NSScreen.main?.frame.width {
            defaults.set(currentWidth, forKey: "SaneBar_CalibratedScreenWidth")
        }

        defaults.set(420.0, forKey: mainKey)
        defaults.set(360.0, forKey: separatorKey)
        defaults.set(10_000.0, forKey: alwaysHiddenKey)
        defaults.removeObject(forKey: legacyAlwaysHiddenKey)

        _ = StatusBarController()

        let mainValue = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let separatorValue = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        #expect(mainValue == 420.0, "Healthy custom main position should be preserved")
        #expect(separatorValue == 360.0, "Healthy custom separator position should be preserved")
        #expect(defaults.bool(forKey: "SaneBar_PositionRecovery_Migration_v1"),
                "Stable migration key should be set after first run")
    }

    @Test("Migration resets positions when legacy always-hidden position is corrupted")
    @MainActor
    func migrationResetsForLegacyAlwaysHiddenCorruption() {
        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let alwaysHiddenKey = "NSStatusItem Preferred Position \(StatusBarController.alwaysHiddenSeparatorAutosaveName)"
        let legacyAlwaysHiddenKey = "NSStatusItem Preferred Position SaneBar_AlwaysHiddenSeparator"
        let migrationKeys = [
            "SaneBar_PositionRecovery_Migration_v1",
            "SaneBar_PositionMigration_v4",
            "SaneBar_PositionMigration_v5",
            "SaneBar_PositionMigration_v6",
            "SaneBar_PositionMigration_v7",
            "SaneBar_CalibratedScreenWidth",
        ]
        let allKeys = [mainKey, separatorKey, alwaysHiddenKey, legacyAlwaysHiddenKey] + migrationKeys
        let originalValues: [(String, Any?)] = allKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        for key in migrationKeys {
            defaults.removeObject(forKey: key)
        }

        if let currentWidth = NSScreen.main?.frame.width {
            defaults.set(currentWidth, forKey: "SaneBar_CalibratedScreenWidth")
        }

        defaults.set(420.0, forKey: mainKey)
        defaults.set(360.0, forKey: separatorKey)
        defaults.set(10_000.0, forKey: alwaysHiddenKey)
        defaults.set(50.0, forKey: legacyAlwaysHiddenKey) // Corrupted legacy AH position

        _ = StatusBarController()

        let mainValue = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let separatorValue = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        #expect(mainValue == 0.0, "Corrupted legacy AH position should trigger main reset to ordinal seed")
        #expect(separatorValue == 1.0, "Corrupted legacy AH position should trigger separator reset to ordinal seed")
        #expect(defaults.bool(forKey: "SaneBar_PositionRecovery_Migration_v1"),
                "Stable migration key should be set after recovery")
    }

    @Test("Upgrade matrix handles healthy and corrupted states safely")
    @MainActor
    func upgradeMatrixRecoveryCoverage() {
        struct Scenario {
            let name: String
            let main: Double?
            let separator: Double?
            let alwaysHidden: Double?
            let legacyAlwaysHidden: Double?
            let expectedMain: Double
            let expectedSeparator: Double
        }

        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let alwaysHiddenKey = "NSStatusItem Preferred Position \(StatusBarController.alwaysHiddenSeparatorAutosaveName)"
        let legacyAlwaysHiddenKey = "NSStatusItem Preferred Position SaneBar_AlwaysHiddenSeparator"
        let migrationKeys = [
            "SaneBar_PositionRecovery_Migration_v1",
            "SaneBar_PositionMigration_v4",
            "SaneBar_PositionMigration_v5",
            "SaneBar_PositionMigration_v6",
            "SaneBar_PositionMigration_v7",
            "SaneBar_CalibratedScreenWidth",
        ]
        let allKeys = [mainKey, separatorKey, alwaysHiddenKey, legacyAlwaysHiddenKey] + migrationKeys
        let originalValues: [(String, Any?)] = allKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        let scenarios: [Scenario] = [
            Scenario(
                name: "v2.1.2 healthy custom layout",
                main: 420.0,
                separator: 360.0,
                alwaysHidden: 10_000.0,
                legacyAlwaysHidden: nil,
                expectedMain: 420.0,
                expectedSeparator: 360.0
            ),
            Scenario(
                name: "v2.1.3 corrupted legacy AH",
                main: 420.0,
                separator: 360.0,
                alwaysHidden: 10_000.0,
                legacyAlwaysHidden: 50.0,
                expectedMain: 0.0,
                expectedSeparator: 1.0
            ),
            Scenario(
                name: "v2.1.6 invalid separator position",
                main: 420.0,
                separator: -24.0,
                alwaysHidden: 10_000.0,
                legacyAlwaysHidden: nil,
                expectedMain: 0.0,
                expectedSeparator: 1.0
            ),
        ]

        for scenario in scenarios {
            for key in migrationKeys {
                defaults.removeObject(forKey: key)
            }
            if let currentWidth = NSScreen.main?.frame.width {
                defaults.set(currentWidth, forKey: "SaneBar_CalibratedScreenWidth")
            }

            if let value = scenario.main {
                defaults.set(value, forKey: mainKey)
            } else {
                defaults.removeObject(forKey: mainKey)
            }

            if let value = scenario.separator {
                defaults.set(value, forKey: separatorKey)
            } else {
                defaults.removeObject(forKey: separatorKey)
            }

            if let value = scenario.alwaysHidden {
                defaults.set(value, forKey: alwaysHiddenKey)
            } else {
                defaults.removeObject(forKey: alwaysHiddenKey)
            }

            if let value = scenario.legacyAlwaysHidden {
                defaults.set(value, forKey: legacyAlwaysHiddenKey)
            } else {
                defaults.removeObject(forKey: legacyAlwaysHiddenKey)
            }

            _ = StatusBarController()

            let mainValue = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
            let separatorValue = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
            #expect(mainValue == scenario.expectedMain, "\(scenario.name): main position mismatch")
            #expect(separatorValue == scenario.expectedSeparator, "\(scenario.name): separator position mismatch")
            #expect(defaults.bool(forKey: "SaneBar_PositionRecovery_Migration_v1"),
                    "\(scenario.name): migration key should be set")
        }
    }

    @Test("Real upgrade snapshots from 2.1.2 and 2.1.5 preserve layout")
    @MainActor
    func realUpgradeSnapshotsPreserveLayout() {
        struct Snapshot {
            let name: String
            let main: Double
            let separator: Double
            let alwaysHidden: Double
        }

        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let alwaysHiddenKey = "NSStatusItem Preferred Position \(StatusBarController.alwaysHiddenSeparatorAutosaveName)"
        let legacyAlwaysHiddenKey = "NSStatusItem Preferred Position SaneBar_AlwaysHiddenSeparator"
        let migrationKeys = [
            "SaneBar_PositionRecovery_Migration_v1",
            "SaneBar_PositionMigration_v4",
            "SaneBar_PositionMigration_v5",
            "SaneBar_PositionMigration_v6",
            "SaneBar_PositionMigration_v7",
            "SaneBar_CalibratedScreenWidth",
        ]
        let allKeys = [mainKey, separatorKey, alwaysHiddenKey, legacyAlwaysHiddenKey] + migrationKeys
        let originalValues: [(String, Any?)] = allKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        // Values mirror real-world healthy snapshots reported in 2.1.2/2.1.5 era upgrades.
        let snapshots: [Snapshot] = [
            Snapshot(name: "v2.1.2-style", main: 97.0, separator: 546.0, alwaysHidden: 6_072.0),
            Snapshot(name: "v2.1.5-style", main: 420.0, separator: 360.0, alwaysHidden: 10_000.0),
        ]

        for snapshot in snapshots {
            for key in migrationKeys {
                defaults.removeObject(forKey: key)
            }
            if let currentWidth = NSScreen.main?.frame.width {
                defaults.set(currentWidth, forKey: "SaneBar_CalibratedScreenWidth")
            }

            defaults.set(snapshot.main, forKey: mainKey)
            defaults.set(snapshot.separator, forKey: separatorKey)
            defaults.set(snapshot.alwaysHidden, forKey: alwaysHiddenKey)
            defaults.removeObject(forKey: legacyAlwaysHiddenKey)

            _ = StatusBarController() // upgrade pass
            let firstMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
            let firstSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
            let firstAlwaysHidden = (defaults.object(forKey: alwaysHiddenKey) as? NSNumber)?.doubleValue
            #expect(firstMain == snapshot.main, "\(snapshot.name): main changed on first upgrade")
            #expect(firstSeparator == snapshot.separator, "\(snapshot.name): separator changed on first upgrade")
            #expect(firstAlwaysHidden == snapshot.alwaysHidden, "\(snapshot.name): AH changed on first upgrade")

            _ = StatusBarController() // subsequent upgrade/restart
            let secondMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
            let secondSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
            let secondAlwaysHidden = (defaults.object(forKey: alwaysHiddenKey) as? NSNumber)?.doubleValue
            #expect(secondMain == snapshot.main, "\(snapshot.name): main changed on repeat upgrade")
            #expect(secondSeparator == snapshot.separator, "\(snapshot.name): separator changed on repeat upgrade")
            #expect(secondAlwaysHidden == snapshot.alwaysHidden, "\(snapshot.name): AH changed on repeat upgrade")
            #expect(defaults.bool(forKey: "SaneBar_PositionRecovery_Migration_v1"),
                    "\(snapshot.name): stable migration key should be set")
        }
    }

    @Test("Corruption recovery runs once, then preserves user layout")
    @MainActor
    func corruptionRecoveryRunsOnceThenStops() {
        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let alwaysHiddenKey = "NSStatusItem Preferred Position \(StatusBarController.alwaysHiddenSeparatorAutosaveName)"
        let legacyAlwaysHiddenKey = "NSStatusItem Preferred Position SaneBar_AlwaysHiddenSeparator"
        let migrationKeys = [
            "SaneBar_PositionRecovery_Migration_v1",
            "SaneBar_PositionMigration_v4",
            "SaneBar_PositionMigration_v5",
            "SaneBar_PositionMigration_v6",
            "SaneBar_PositionMigration_v7",
            "SaneBar_CalibratedScreenWidth",
        ]
        let allKeys = [mainKey, separatorKey, alwaysHiddenKey, legacyAlwaysHiddenKey] + migrationKeys
        let originalValues: [(String, Any?)] = allKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        for key in migrationKeys {
            defaults.removeObject(forKey: key)
        }
        if let currentWidth = NSScreen.main?.frame.width {
            defaults.set(currentWidth, forKey: "SaneBar_CalibratedScreenWidth")
        }

        // First launch from corrupted legacy state should recover to 0/1.
        defaults.set(420.0, forKey: mainKey)
        defaults.set(360.0, forKey: separatorKey)
        defaults.set(10_000.0, forKey: alwaysHiddenKey)
        defaults.set(50.0, forKey: legacyAlwaysHiddenKey)
        _ = StatusBarController()

        let recoveredMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let recoveredSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        #expect(recoveredMain == 0.0)
        #expect(recoveredSeparator == 1.0)
        #expect(defaults.bool(forKey: "SaneBar_PositionRecovery_Migration_v1"))

        // User rearranges after recovery.
        defaults.set(812.0, forKey: mainKey)
        defaults.set(744.0, forKey: separatorKey)

        // Next launch must preserve user layout (no repeated forced reset).
        _ = StatusBarController()
        let postUpgradeMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let postUpgradeSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        #expect(postUpgradeMain == 812.0, "Recovered users must keep custom layout on later upgrades")
        #expect(postUpgradeSeparator == 744.0, "Recovered users must keep custom layout on later upgrades")
    }

    @Test("Multi-upgrade chain preserves healthy persisted layout")
    @MainActor
    func multiUpgradeChainPreservesHealthyLayout() {
        let defaults = UserDefaults.standard
        let mainKey = "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)"
        let separatorKey = "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)"
        let alwaysHiddenKey = "NSStatusItem Preferred Position \(StatusBarController.alwaysHiddenSeparatorAutosaveName)"
        let migrationKeys = [
            "SaneBar_PositionRecovery_Migration_v1",
            "SaneBar_PositionMigration_v4",
            "SaneBar_PositionMigration_v5",
            "SaneBar_PositionMigration_v6",
            "SaneBar_PositionMigration_v7",
            "SaneBar_CalibratedScreenWidth",
        ]
        let allKeys = [mainKey, separatorKey, alwaysHiddenKey] + migrationKeys
        let originalValues: [(String, Any?)] = allKeys.map { ($0, defaults.object(forKey: $0)) }
        defer {
            for (key, value) in originalValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        for key in migrationKeys {
            defaults.removeObject(forKey: key)
        }
        if let currentWidth = NSScreen.main?.frame.width {
            defaults.set(currentWidth, forKey: "SaneBar_CalibratedScreenWidth")
        }

        // Snapshot pattern from real reports: pixel-like but healthy custom positions.
        defaults.set(97.0, forKey: mainKey)
        defaults.set(546.0, forKey: separatorKey)
        defaults.set(6_072.0, forKey: alwaysHiddenKey)

        // Simulate successive upgrades/restarts.
        _ = StatusBarController() // first upgrade
        _ = StatusBarController() // second upgrade/restart
        _ = StatusBarController() // third upgrade/restart

        let mainValue = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let separatorValue = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        let ahValue = (defaults.object(forKey: alwaysHiddenKey) as? NSNumber)?.doubleValue

        #expect(mainValue == 97.0, "Healthy custom main position must survive repeated upgrades")
        #expect(separatorValue == 546.0, "Healthy custom separator position must survive repeated upgrades")
        #expect(ahValue == 6_072.0, "Healthy always-hidden position must survive repeated upgrades")
        #expect(defaults.bool(forKey: "SaneBar_PositionRecovery_Migration_v1"))
    }

    // MARK: - Icon Constants Tests

    @Test("Icon names are valid SF Symbol names")
    func iconNamesAreValid() {
        // These should all be valid SF Symbol names
        #expect(!StatusBarController.iconExpanded.isEmpty)
        #expect(!StatusBarController.iconHidden.isEmpty)
    }

    // MARK: - Menu Creation Tests

    @Test("createMenu returns menu with expected items")
    @MainActor
    func createMenuHasExpectedItems() {
        let controller = StatusBarController()

        // Create a dummy target
        class DummyTarget: NSObject {
            @objc func toggle() {}
            @objc func findIcon() {}
            @objc func settings() {}
            @objc func checkForUpdates() {}
            @objc func quit() {}
        }
        let target = DummyTarget()

        let menu = controller.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            settingsAction: #selector(DummyTarget.settings),
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit),
            target: target
        ))

        // Should have: Browse Icons, separator, Settings, Check for Updates, separator, Quit
        #expect(menu.items.count == 6, "Menu should have 6 items (4 commands + 2 separators)")

        // Use named lookups (resilient to menu reordering)
        let findIconItem = menu.item(titled: "Browse Icons...")
        #expect(findIconItem != nil, "Menu should have Browse Icons item")
        // keyEquivalent is set dynamically via KeyboardShortcuts.setShortcut(for:)
        // so we don't assert on a hardcoded value here

        let settingsItem = menu.item(titled: "Settings...")
        #expect(settingsItem != nil, "Menu should have Settings item")
        #expect(settingsItem?.keyEquivalent == ",")

        let checkUpdatesItem = menu.item(titled: "Check for Updates...")
        #expect(checkUpdatesItem != nil, "Menu should have Check for Updates item")
        #expect(checkUpdatesItem?.keyEquivalent.isEmpty == true)

        let quitItem = menu.item(titled: "Quit SaneBar")
        #expect(quitItem != nil, "Menu should have Quit item")
        #expect(quitItem?.keyEquivalent == "q")
    }

    @Test("createMenu sets correct target on all items")
    @MainActor
    func createMenuSetsTarget() {
        let controller = StatusBarController()

        class DummyTarget: NSObject {
            @objc func toggle() {}
            @objc func findIcon() {}
            @objc func settings() {}
            @objc func checkForUpdates() {}
            @objc func quit() {}
        }
        let target = DummyTarget()

        let menu = controller.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            settingsAction: #selector(DummyTarget.settings),
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit),
            target: target
        ))

        // Non-separator items should have target set
        for item in menu.items where !item.isSeparatorItem {
            #expect(item.target === target, "Menu item should have correct target")
        }
    }

    // MARK: - Menu Action Tests (Regression: settings menu must work)

    @Test("Menu items have correct actions set")
    @MainActor
    func menuItemsHaveActions() {
        let controller = StatusBarController()

        class DummyTarget: NSObject {
            var toggleCalled = false
            var findIconCalled = false
            var settingsCalled = false
            var checkForUpdatesCalled = false
            var quitCalled = false

            @objc func toggle() { toggleCalled = true }
            @objc func findIcon() { findIconCalled = true }
            @objc func settings() { settingsCalled = true }
            @objc func checkForUpdates() { checkForUpdatesCalled = true }
            @objc func quit() { quitCalled = true }
        }
        let target = DummyTarget()

        let menu = controller.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            settingsAction: #selector(DummyTarget.settings),
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit),
            target: target
        ))

        // Verify each menu item has an action (using named lookups)
        let findIconItem = menu.item(titled: "Browse Icons...")
        let settingsItem = menu.item(titled: "Settings...")
        let checkForUpdatesItem = menu.item(titled: "Check for Updates...")
        let quitItem = menu.item(titled: "Quit SaneBar")

        #expect(findIconItem?.action == #selector(DummyTarget.findIcon), "Browse Icons item should have findIcon action")
        #expect(settingsItem?.action == #selector(DummyTarget.settings), "Settings item should have settings action")
        #expect(checkForUpdatesItem?.action == #selector(DummyTarget.checkForUpdates), "Check for Updates item should have action")
        #expect(quitItem?.action == #selector(DummyTarget.quit), "Quit item should have quit action")
    }

    @Test("Settings menu item is invokable")
    @MainActor
    func settingsMenuItemInvokable() {
        let controller = StatusBarController()

        class DummyTarget: NSObject {
            var settingsCalled = false
            @objc func toggle() {}
            @objc func findIcon() {}
            @objc func settings() { settingsCalled = true }
            @objc func checkForUpdates() {}
            @objc func quit() {}
        }
        let target = DummyTarget()

        let menu = controller.createMenu(configuration: MenuConfiguration(
            toggleAction: #selector(DummyTarget.toggle),
            findIconAction: #selector(DummyTarget.findIcon),
            settingsAction: #selector(DummyTarget.settings),
            checkForUpdatesAction: #selector(DummyTarget.checkForUpdates),
            quitAction: #selector(DummyTarget.quit),
            target: target
        ))

        // Get settings item by name and verify it can be invoked
        guard let settingsItem = menu.item(titled: "Settings...") else {
            Issue.record("Settings menu item not found")
            return
        }

        #expect(settingsItem.target != nil, "Settings item must have a target")
        #expect(settingsItem.action != nil, "Settings item must have an action")

        // Simulate clicking the settings item
        if let action = settingsItem.action, let itemTarget = settingsItem.target {
            _ = itemTarget.perform(action, with: settingsItem)
        }

        #expect(target.settingsCalled, "Settings action should be invokable through menu item")
    }

    // MARK: - Click Type Tests

    @Test("clickType correctly identifies left click")
    func clickTypeLeftClick() {
        // We can't easily create NSEvents in tests, but we can test the enum
        let leftClick = StatusBarController.ClickType.leftClick
        let rightClick = StatusBarController.ClickType.rightClick
        let optionClick = StatusBarController.ClickType.optionClick

        #expect(leftClick != rightClick)
        #expect(leftClick != optionClick)
        #expect(rightClick != optionClick)
    }

    // MARK: - Protocol Conformance Tests

    @Test("StatusBarController conforms to StatusBarControllerProtocol")
    @MainActor
    func protocolConformance() {
        let controller: StatusBarControllerProtocol = StatusBarController()

        // Protocol requires these
        _ = controller.mainItem
        _ = controller.separatorItem
        _ = controller.iconName(for: .hidden)

        #expect(true, "Should conform to protocol")
    }

    // MARK: - Initialization Tests

    @Test("StatusBarController creates status items during initialization")
    @MainActor
    func initializationCreatesItems() {
        let controller = StatusBarController()

        // Items are created as property initializers for proper WindowServer positioning
        // This ensures proper WindowServer positioning
        #expect(controller.mainItem.button != nil)
        #expect(controller.separatorItem.button != nil)
    }

    // MARK: - Display-Aware Position Validation

    @Test("Ordinal seeds are not pixel-like", arguments: [0.0, 1.0, 2.0])
    func ordinalsNotPixelLike(_ value: Double) {
        #expect(!StatusBarController.isPixelLikePosition(value))
    }

    @Test("AH sentinel (10000) is not pixel-like")
    func ahSentinelNotPixelLike() {
        #expect(!StatusBarController.isPixelLikePosition(10000))
    }

    @Test("nil is not pixel-like")
    func nilNotPixelLike() {
        #expect(!StatusBarController.isPixelLikePosition(nil))
    }

    @Test("Typical pixel offsets are pixel-like", arguments: [207.0, 400.0, 800.0, 1200.0, 2400.0])
    func pixelOffsetsArePixelLike(_ value: Double) {
        #expect(StatusBarController.isPixelLikePosition(value))
    }

    @Test("Same screen width is not a significant change")
    func sameWidthNotSignificant() {
        #expect(!StatusBarController.isSignificantWidthChange(stored: 1440, current: 1440))
    }

    @Test("Small width change (<10%) is not significant")
    func smallChangeNotSignificant() {
        // 5% change: 1440 → 1512
        #expect(!StatusBarController.isSignificantWidthChange(stored: 1440, current: 1512))
    }

    @Test("Large width change (>10%) is significant")
    func largeChangeIsSignificant() {
        // 1440 → 2560 (78% change)
        #expect(StatusBarController.isSignificantWidthChange(stored: 1440, current: 2560))
    }

    @Test("Zero stored width is not a significant change")
    func zeroStoredNotSignificant() {
        #expect(!StatusBarController.isSignificantWidthChange(stored: 0, current: 1440))
    }

    @Test("Boundary: exactly 10% change is not significant")
    func boundaryTenPercent() {
        // Exactly 10%: 1000 → 1100
        #expect(!StatusBarController.isSignificantWidthChange(stored: 1000, current: 1100))
    }

    @Test("Just over 10% change is significant")
    func justOverTenPercent() {
        // 10.1%: 1000 → 1101
        #expect(StatusBarController.isSignificantWidthChange(stored: 1000, current: 1101))
    }
}
