import AppKit
import SaneUI
@testable import SaneBar
import Testing

@Suite("StatusBarControllerMigrationTests", .serialized)
struct StatusBarControllerMigrationTests {
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
        defaults.set(10000.0, forKey: alwaysHiddenKey)
        defaults.removeObject(forKey: legacyAlwaysHiddenKey)

        _ = StatusBarController()

        let mainValue = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let separatorValue = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        #expect(mainValue == 420.0, "Healthy custom main position should be preserved")
        #expect(separatorValue == 360.0, "Healthy custom separator position should be preserved")
        #expect(defaults.bool(forKey: "SaneBar_PositionRecovery_Migration_v1"),
                "Stable migration key should be set after first run")
    }

    @Test("Migration reanchors positions when legacy always-hidden position is corrupted")
    @MainActor
    func migrationResetsForLegacyAlwaysHiddenCorruption() {
        guard let safeRecovery = launchSafeRecoveryPair() else {
            Issue.record("Expected a main screen for migration recovery test")
            return
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

        for key in migrationKeys {
            defaults.removeObject(forKey: key)
        }

        if let currentWidth = NSScreen.main?.frame.width {
            defaults.set(currentWidth, forKey: "SaneBar_CalibratedScreenWidth")
        }

        defaults.set(420.0, forKey: mainKey)
        defaults.set(360.0, forKey: separatorKey)
        defaults.set(10000.0, forKey: alwaysHiddenKey)
        defaults.set(50.0, forKey: legacyAlwaysHiddenKey) // Corrupted legacy AH position

        _ = StatusBarController()

        let mainValue = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let separatorValue = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        #expect(mainValue == safeRecovery.main, "Corrupted legacy AH position should trigger a launch-safe main recovery anchor")
        #expect(separatorValue == safeRecovery.separator, "Corrupted legacy AH position should trigger a launch-safe separator recovery anchor")
        #expect(defaults.bool(forKey: "SaneBar_PositionRecovery_Migration_v1"),
                "Stable migration key should be set after recovery")
    }

    @Test("Upgrade matrix handles healthy and corrupted states safely")
    @MainActor
    func upgradeMatrixRecoveryCoverage() {
        guard let safeRecovery = launchSafeRecoveryPair() else {
            Issue.record("Expected a main screen for upgrade matrix recovery test")
            return
        }

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
                alwaysHidden: 10000.0,
                legacyAlwaysHidden: nil,
                expectedMain: 420.0,
                expectedSeparator: 360.0
            ),
            Scenario(
                name: "v2.1.3 corrupted legacy AH",
                main: 420.0,
                separator: 360.0,
                alwaysHidden: 10000.0,
                legacyAlwaysHidden: 50.0,
                expectedMain: safeRecovery.main,
                expectedSeparator: safeRecovery.separator
            ),
            Scenario(
                name: "v2.1.6 invalid separator position",
                main: 420.0,
                separator: -24.0,
                alwaysHidden: 10000.0,
                legacyAlwaysHidden: nil,
                expectedMain: safeRecovery.main,
                expectedSeparator: safeRecovery.separator
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
            Snapshot(name: "v2.1.2-style", main: 97.0, separator: 546.0, alwaysHidden: 6072.0),
            Snapshot(name: "v2.1.5-style", main: 420.0, separator: 360.0, alwaysHidden: 10000.0),
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
        guard let safeRecovery = launchSafeRecoveryPair() else {
            Issue.record("Expected a main screen for corruption recovery test")
            return
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

        for key in migrationKeys {
            defaults.removeObject(forKey: key)
        }
        if let currentWidth = NSScreen.main?.frame.width {
            defaults.set(currentWidth, forKey: "SaneBar_CalibratedScreenWidth")
        }

        // First launch from corrupted legacy state should recover to a launch-safe anchor.
        defaults.set(420.0, forKey: mainKey)
        defaults.set(360.0, forKey: separatorKey)
        defaults.set(10000.0, forKey: alwaysHiddenKey)
        defaults.set(50.0, forKey: legacyAlwaysHiddenKey)
        _ = StatusBarController()

        let recoveredMain = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let recoveredSeparator = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        #expect(recoveredMain == safeRecovery.main)
        #expect(recoveredSeparator == safeRecovery.separator)
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
        defaults.removeObject(forKey: legacyAlwaysHiddenKey)
        if let currentWidth = NSScreen.main?.frame.width {
            defaults.set(currentWidth, forKey: "SaneBar_CalibratedScreenWidth")
        }

        // Snapshot pattern from real reports: pixel-like but healthy custom positions.
        defaults.set(97.0, forKey: mainKey)
        defaults.set(546.0, forKey: separatorKey)
        defaults.set(6072.0, forKey: alwaysHiddenKey)

        // Simulate successive upgrades/restarts.
        _ = StatusBarController() // first upgrade
        _ = StatusBarController() // second upgrade/restart
        _ = StatusBarController() // third upgrade/restart

        let mainValue = (defaults.object(forKey: mainKey) as? NSNumber)?.doubleValue
        let separatorValue = (defaults.object(forKey: separatorKey) as? NSNumber)?.doubleValue
        let ahValue = (defaults.object(forKey: alwaysHiddenKey) as? NSNumber)?.doubleValue

        #expect(mainValue == 97.0, "Healthy custom main position must survive repeated upgrades")
        #expect(separatorValue == 546.0, "Healthy custom separator position must survive repeated upgrades")
        #expect(ahValue == 6072.0, "Healthy always-hidden position must survive repeated upgrades")
        #expect(defaults.bool(forKey: "SaneBar_PositionRecovery_Migration_v1"))
    }

    // MARK: - Icon Constants Tests

}
