import AppKit
import SaneUI
@testable import SaneBar
import Testing

@Suite("StatusBarControllerLifecycleTests", .serialized)
struct StatusBarControllerLifecycleTests {
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

    @Test("Autosave version defaults to base when key is unset")
    func autosaveVersionDefaultsToBase() {
        let defaults = UserDefaults.standard
        let key = "SaneBar_AutosaveVersion"
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.removeObject(forKey: key)
        #expect(StatusBarController.autosaveVersion == 7)
    }

    @Test("Autosave names use stored autosave version")
    func autosaveNamesUseStoredVersion() {
        let defaults = UserDefaults.standard
        let key = "SaneBar_AutosaveVersion"
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(14, forKey: key)
        #expect(StatusBarController.mainAutosaveName == "SaneBar_Main_v14")
        #expect(StatusBarController.separatorAutosaveName == "SaneBar_Separator_v14")
        #expect(StatusBarController.alwaysHiddenSeparatorAutosaveName == "SaneBar_AlwaysHiddenSeparator_v14")
    }

    @Test("Recreate with bumped version updates autosave namespace")
    @MainActor
    func recreateItemsBumpsAutosaveVersion() {
        let defaults = UserDefaults.standard
        let key = "SaneBar_AutosaveVersion"
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(10, forKey: key)
        let controller = StatusBarController()
        let oldMain = controller.mainItem

        let (newMain, _) = controller.recreateItemsWithBumpedVersion()

        #expect(defaults.integer(forKey: key) == 11)
        #expect(newMain !== oldMain)
        #expect(StatusBarController.mainAutosaveName == "SaneBar_Main_v11")
    }

    @Test("Recreate at autosave cap recycles the namespace instead of getting stuck")
    @MainActor
    func recreateItemsAtAutosaveCapRecyclesNamespace() {
        guard let currentWidth = NSScreen.main?.frame.width else {
            Issue.record("Expected a main screen for autosave cap recycle test")
            return
        }

        let defaults = UserDefaults.standard
        let versionKey = "SaneBar_AutosaveVersion"
        let originalVersion = defaults.object(forKey: versionKey)
        let cappedMainKey = "NSStatusItem Preferred Position SaneBar_Main_v99"
        let cappedSeparatorKey = "NSStatusItem Preferred Position SaneBar_Separator_v99"
        let recycledMainKey = "NSStatusItem Preferred Position SaneBar_Main_v7"
        let recycledSeparatorKey = "NSStatusItem Preferred Position SaneBar_Separator_v7"
        let backupMainKey = StatusBarPositionStore.displayPositionBackupKey(for: currentWidth, slot: "main")
        let backupSeparatorKey = StatusBarPositionStore.displayPositionBackupKey(for: currentWidth, slot: "separator")
        let keys = [versionKey, cappedMainKey, cappedSeparatorKey, recycledMainKey, recycledSeparatorKey, backupMainKey, backupSeparatorKey]
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

        defaults.set(99, forKey: versionKey)
        defaults.set(0.0, forKey: cappedMainKey)
        defaults.set(1.0, forKey: cappedSeparatorKey)
        defaults.set(180.0, forKey: backupMainKey)
        defaults.set(300.0, forKey: backupSeparatorKey)

        let controller = StatusBarController()
        let oldMain = controller.mainItem
        let (newMain, _) = controller.recreateItemsWithBumpedVersion()

        let recycledMain = (defaults.object(forKey: recycledMainKey) as? NSNumber)?.doubleValue
        let recycledSeparator = (defaults.object(forKey: recycledSeparatorKey) as? NSNumber)?.doubleValue

        #expect(defaults.integer(forKey: versionKey) == 7)
        #expect(newMain !== oldMain)
        #expect(recycledMain != nil)
        #expect(recycledSeparator != nil)
        #expect(defaults.object(forKey: cappedMainKey) == nil)
        #expect(defaults.object(forKey: cappedSeparatorKey) == nil)
    }

    @Test("Main and separator disable interactive removal behaviors on init")
    @MainActor
    func initDisablesInteractiveRemoval() {
        let controller = StatusBarController()

        #expect(!controller.mainItem.behavior.contains(.removalAllowed))
        #expect(!controller.mainItem.behavior.contains(.terminationOnRemoval))
        #expect(!controller.separatorItem.behavior.contains(.removalAllowed))
        #expect(!controller.separatorItem.behavior.contains(.terminationOnRemoval))
    }

    @Test("Recreated items keep interactive removal disabled")
    @MainActor
    func recreateKeepsInteractiveRemovalDisabled() {
        let controller = StatusBarController()

        let (newMain, newSeparator) = controller.recreateItemsWithBumpedVersion()

        #expect(!newMain.behavior.contains(.removalAllowed))
        #expect(!newMain.behavior.contains(.terminationOnRemoval))
        #expect(!newSeparator.behavior.contains(.removalAllowed))
        #expect(!newSeparator.behavior.contains(.terminationOnRemoval))
    }

    @Test("Recreate from persisted positions can reseed after removing old items")
    @MainActor
    func recreatePersistedPositionsRunsResetBeforeNewAutosaveNames() {
        let defaults = UserDefaults.standard
        let key = "SaneBar_AutosaveVersion"
        let original = defaults.object(forKey: key)
        defer {
            if let original {
                defaults.set(original, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }

        defaults.set(30, forKey: key)
        let controller = StatusBarController()
        let (newMain, newSeparator) = controller.recreateItemsFromPersistedPositions {
            defaults.set(31, forKey: key)
        }

        #expect(newMain.autosaveName == "SaneBar_Main_v31")
        #expect(newSeparator.autosaveName == "SaneBar_Separator_v31")
    }

    @Test("Diagnostics detect visible status items suppressed by missing or detached menu bar window")
    func likelySystemSuppressedStatusItemRequiresVisibleFlagAndInvalidWindow() {
        let screen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let validWindow = CGRect(x: 1600, y: 1084, width: 30, height: 33)
        let invalidWindow = CGRect(x: 1600, y: 200, width: 30, height: 33)
        let parkedWithoutScreen = CGRect(x: 0, y: -22, width: 19, height: 22)
        let delimiterParkedWithoutScreen = CGRect(x: 0, y: -22, width: 5003, height: 22)
        let transientDetachedAwayFromOrigin = CGRect(x: 1600, y: -22, width: 19, height: 22)
        let leftDisplayDetached = CGRect(x: -1100, y: -22, width: 19, height: 22)
        let nonParkedWithoutScreen = CGRect(x: 0, y: 0, width: 19, height: 22)

        #expect(!StatusBarDiagnostics.likelySystemSuppressedStatusItem(
            isVisibleFlag: true,
            windowFrame: validWindow,
            screenFrame: screen
        ))
        #expect(StatusBarDiagnostics.likelySystemSuppressedStatusItem(
            isVisibleFlag: true,
            windowFrame: invalidWindow,
            screenFrame: screen
        ))
        #expect(!StatusBarDiagnostics.likelySystemSuppressedStatusItem(
            isVisibleFlag: false,
            windowFrame: invalidWindow,
            screenFrame: screen
        ))
        #expect(StatusBarDiagnostics.likelySystemSuppressedStatusItem(
            isVisibleFlag: true,
            windowFrame: parkedWithoutScreen,
            screenFrame: nil
        ))
        #expect(StatusBarDiagnostics.likelySystemSuppressedStatusItem(
            isVisibleFlag: true,
            windowFrame: delimiterParkedWithoutScreen,
            screenFrame: nil
        ))
        #expect(!StatusBarDiagnostics.likelySystemSuppressedStatusItem(
            isVisibleFlag: false,
            windowFrame: parkedWithoutScreen,
            screenFrame: nil
        ))
        #expect(!StatusBarDiagnostics.likelySystemSuppressedStatusItem(
            isVisibleFlag: true,
            windowFrame: transientDetachedAwayFromOrigin,
            screenFrame: nil
        ))
        #expect(!StatusBarDiagnostics.likelySystemSuppressedStatusItem(
            isVisibleFlag: true,
            windowFrame: leftDisplayDetached,
            screenFrame: nil
        ))
        #expect(!StatusBarDiagnostics.likelySystemSuppressedStatusItem(
            isVisibleFlag: true,
            windowFrame: nonParkedWithoutScreen,
            screenFrame: nil
        ))
        #expect(!StatusBarDiagnostics.likelySystemSuppressedStatusItem(
            isVisibleFlag: true,
            windowFrame: nil,
            screenFrame: screen
        ))
    }

    @Test("Diagnostics wire parked nil-screen status items into the recovery suppression flag")
    func likelySystemSuppressedStatusItemsRequiresInvalidStartupAndParkedVisibleItem() {
        let parkedWithoutScreen = CGRect(x: 0, y: -22, width: 19, height: 22)
        let liveScreen = CGRect(x: 0, y: 0, width: 1728, height: 1117)
        let liveWindow = CGRect(x: 1600, y: 1093, width: 30, height: 24)

        let parkedMain = StatusItemSuppressionInput(
            isVisibleFlag: true,
            windowFrame: parkedWithoutScreen,
            screenFrame: nil
        )
        let healthySeparator = StatusItemSuppressionInput(
            isVisibleFlag: true,
            windowFrame: liveWindow,
            screenFrame: liveScreen
        )

        #expect(StatusBarDiagnostics.likelySystemSuppressedStatusItems(
            startupItemsValid: false,
            main: parkedMain,
            separator: healthySeparator
        ))
        #expect(!StatusBarDiagnostics.likelySystemSuppressedStatusItems(
            startupItemsValid: true,
            main: parkedMain,
            separator: healthySeparator
        ))
    }

    @Test("Diagnostics collect SaneBar VisibleCC override keys")
    func visibilityOverrideKeyFilteringIncludesTahoeVisibleCC() {
        let keys = StatusBarDiagnostics.visibilityOverrideKeys(from: [
            "NSStatusItem Visible SaneBar_Main_v7",
            "NSStatusItem VisibleCC SaneBar_Main_v7",
            "NSStatusItem Visible OtherApp",
            "NSStatusItem Preferred Position SaneBar_Main_v7",
        ])

        #expect(keys == [
            "NSStatusItem Visible SaneBar_Main_v7",
            "NSStatusItem VisibleCC SaneBar_Main_v7",
        ])
    }

    @Test("Mission Control spaces summary keeps raw spans-displays polarity visible")
    func missionControlSpacesSummaryShowsRawPolarity() {
        #expect(StatusBarDiagnostics.missionControlSpacesSummary(spansDisplays: nil) == "unknown")
        #expect(StatusBarDiagnostics.missionControlSpacesSummary(spansDisplays: true).contains("spans-displays=true"))
        #expect(StatusBarDiagnostics.missionControlSpacesSummary(spansDisplays: false).contains("spans-displays=false"))
    }

    @Test("Always-hidden separator disables interactive removal behaviors")
    @MainActor
    func alwaysHiddenSeparatorDisablesInteractiveRemoval() {
        let controller = StatusBarController()

        controller.ensureAlwaysHiddenSeparator(enabled: true)
        let alwaysHiddenItem = controller.alwaysHiddenSeparatorItem

        #expect(alwaysHiddenItem != nil)
        #expect(!(alwaysHiddenItem?.behavior.contains(.removalAllowed) ?? true))
        #expect(!(alwaysHiddenItem?.behavior.contains(.terminationOnRemoval) ?? true))
    }

}
