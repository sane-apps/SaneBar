@testable import SaneBar
import XCTest

@MainActor
final class RuntimeGuardAppleScriptActivationXCTests: RuntimeGuardTestCase {
    func testAppleScriptActivationCommandsUseRunLoopWaitInsteadOfSemaphore() throws {
        let fileURL = projectRootURL().appendingPathComponent("Core/Services/AppleScriptActivationCommands.swift")
        let source = try String(contentsOf: fileURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("private func runScriptActivation("),
            "AppleScript activation commands should centralize async wait behavior in a run-loop helper"
        )
        XCTAssertTrue(
            source.contains("RunLoop.current.run(mode: .default"),
            "AppleScript activation commands should pump the run loop while main-actor work completes"
        )
        XCTAssertFalse(
            source.contains("DispatchSemaphore"),
            "AppleScript activation commands must not block the main thread with a semaphore"
        )
    }

    func testListIconsAppleScriptCommandDoesNotDeadlockMainThread() throws {
        let source = try appleScriptCommandSource()

        XCTAssertTrue(
            source.contains("@objc(ListIconsCommand)"),
            "ListIconsCommand should exist as a scriptable command"
        )
        XCTAssertTrue(
            source.contains("if Thread.isMainThread"),
            "ListIconsCommand should detect the main-thread scripting path"
        )
        XCTAssertTrue(
            source.contains("RunLoop.current.run(mode: .default"),
            "ListIconsCommand should pump the run loop while waiting for async refresh on the main thread"
        )
        XCTAssertTrue(
            source.contains("runScriptRead(timeoutSeconds: 15.0)"),
            "ListIconsCommand should use the shared read helper with a longer timeout for slower owner scans"
        )
        XCTAssertTrue(
            source.contains("scriptErrorOperationTimedOut(self)"),
            "ListIconsCommand should report a real timeout instead of silently returning an empty result"
        )
    }

    func testAppleScriptMoveCommandsRequireProBeforeRunning() throws {
        let source = try appleScriptCommandSource()

        XCTAssertTrue(
            source.contains("func setProRequiredError()"),
            "AppleScript commands should expose a shared Pro-required scripting error"
        )
        XCTAssertTrue(
            source.contains("guard checkIsProUnlocked() else {") &&
                source.contains("func checkIsProUnlocked() -> Bool"),
            "MoveIconScriptCommand should block Basic mode before attempting any icon move through the shared Pro-check helper"
        )
        XCTAssertTrue(
            source.contains("Hide, show, and move icon commands require SaneBar Pro. Basic can browse, click, and list icons. Open SaneBar's License window to unlock these commands."),
            "The AppleScript move gate should explain the exact Basic vs Pro boundary"
        )
    }

    func testLayoutRescueAndHealthWizardAreFirstClassHealthFlows() throws {
        let healthURL = projectRootURL().appendingPathComponent("UI/Settings/HealthSettingsView.swift")
        let healthSource = try String(contentsOf: healthURL, encoding: .utf8)
        let wizardURL = projectRootURL().appendingPathComponent("UI/Settings/HealthWizardView.swift")
        let wizardSource = try String(contentsOf: wizardURL, encoding: .utf8)
        let profileURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarProfileWorkflow.swift")
        let profileSource = try String(contentsOf: profileURL, encoding: .utf8)
        let startupURL = projectRootURL().appendingPathComponent("Core/Services/MenuBarLifecycleWorkflow.swift")
        let startupSource = try String(contentsOf: startupURL, encoding: .utf8)
        let onboardingURL = projectRootURL().appendingPathComponent("UI/Onboarding/OnboardingController.swift")
        let onboardingSource = try String(contentsOf: onboardingURL, encoding: .utf8)

        XCTAssertTrue(
            healthSource.contains("CompactSection(\"Layout Rescue\"") &&
                healthSource.contains("Save Current Layout") &&
                healthSource.contains("Restore Last Good Layout"),
            "Health should expose Layout Rescue as a first-class restore-point workflow, not only Arrange Now"
        )
        XCTAssertTrue(
            profileSource.contains("func createLayoutRescueRestorePoint") &&
                profileSource.contains("StatusBarController.captureLayoutSnapshot()") &&
                profileSource.contains("func restoreLayoutRescueRestorePoint") &&
                profileSource.contains("StatusBarController.applyLayoutSnapshot(snapshot)") &&
                profileSource.contains("manager.restoreStatusItemLayoutIfNeeded()") &&
                profileSource.contains("func repairMenuBarHealth(reason: String = \"manual\") async") &&
                profileSource.contains("func setLayoutMode(_ mode: SaneBarSettings.LayoutMode, reason: String = \"manual\") async"),
            "Layout Rescue should use the existing layout snapshot and recovery primitives"
        )
        XCTAssertTrue(
            wizardSource.contains("final class HealthWizardController") &&
                wizardSource.contains("FirstRunHealthWizardView") &&
                wizardSource.contains("showIfNeeded()") &&
                wizardSource.contains("createLayoutRescueRestorePoint(reason: \"health-wizard\")") &&
                !wizardSource.contains(".onAppear {\n            if menuBarManager.settings.layoutRescueRestorePoint == nil"),
            "First-run Health Wizard should expose rescue creation without blindly saving an unproven restore point on appearance"
        )
        XCTAssertTrue(
            onboardingSource.contains("HealthWizardController.shared.showIfNeeded()") &&
                startupSource.contains("else if !manager.settings.hasCompletedHealthWizard") &&
                startupSource.contains("HealthWizardController.shared.showIfNeeded()"),
            "Completing onboarding and already-onboarded pending states should both be able to show the Health Wizard"
        )
    }

    func testProfilesDoNotOverwriteHealthWizardOrLayoutRescueState() throws {
        let preservationURL = projectRootURL().appendingPathComponent("Core/Models/SaneBarSettings+ProfilePreservation.swift")
        let source = try String(contentsOf: preservationURL, encoding: .utf8)

        XCTAssertTrue(
            source.contains("func preservingLocalLifecycleState(from current: SaneBarSettings)") &&
                source.contains("next.hasCompletedHealthWizard = current.hasCompletedHealthWizard") &&
                source.contains("next.layoutRescueRestorePoint = current.layoutRescueRestorePoint") &&
                source.contains("next.layoutRescueRestorePointCreatedAt = current.layoutRescueRestorePointCreatedAt"),
            "Applying profiles should not erase wizard completion or the user's layout rescue restore point"
        )
    }

    func testImportsCreateRollbackPointAndPreserveLocalWizardState() throws {
        let generalSource = try generalSettingsSource()
        let settingsControllerURL = projectRootURL().appendingPathComponent("Core/Controllers/SettingsController.swift")
        let settingsControllerSource = try String(contentsOf: settingsControllerURL, encoding: .utf8)

        XCTAssertTrue(
            generalSource.contains("createLayoutRescueRestorePoint(reason: \"pre-import\")") &&
                generalSource.contains("settings.preservingLocalLifecycleState(from: menuBarManager.settings)"),
            "Settings import should save a pre-change rollback point and preserve local wizard/rescue state"
        )
        XCTAssertTrue(
            settingsControllerSource.contains("preserveHealthWizard") &&
                settingsControllerSource.contains("preserveLayoutRescueRestorePoint") &&
                settingsControllerSource.contains("preserveLayoutRescueRestorePointCreatedAt"),
            "Reset to defaults should not silently erase Health Wizard completion or the user's rescue point"
        )
    }
}
