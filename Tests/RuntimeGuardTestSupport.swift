@testable import SaneBar
import XCTest

@MainActor
class RuntimeGuardTestCase: XCTestCase {
    func projectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // project root
    }

    func saneAppsRootURL() -> URL {
        projectRootURL()
            .deletingLastPathComponent() // apps/
            .deletingLastPathComponent() // SaneApps/
    }

    func readShared(_ relativePath: String) throws -> String {
        let fileURL = saneAppsRootURL().appendingPathComponent(relativePath)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw XCTSkip("Shared SaneApps checkout is not available at \(fileURL.path)")
        }
        return try String(contentsOf: fileURL, encoding: .utf8)
    }

    func scriptSource(entrypoint: String, partialPrefix: String) throws -> String {
        let root = projectRootURL().appendingPathComponent("Scripts")
        var urls = [root.appendingPathComponent(entrypoint)]
        let libURL = root.appendingPathComponent("lib")
        if let enumerator = FileManager.default.enumerator(
            at: libURL,
            includingPropertiesForKeys: nil
        ) {
            let partials = enumerator
                .compactMap { $0 as? URL }
                .filter { $0.lastPathComponent.hasPrefix("\(partialPrefix)_") && $0.pathExtension == "rb" }
                .sorted { $0.path < $1.path }
            urls.append(contentsOf: partials)
        }
        return try urls.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }

    func appleScriptCommandSource() throws -> String {
        try [
            "Core/Services/AppleScriptCommands.swift",
            "Core/Services/AppleScriptIconSupport.swift",
            "Core/Services/AppleScriptIconListingCommands.swift",
            "Core/Services/LayoutSnapshotCommand.swift",
            "Core/Services/AppleScriptIconMoveCommands.swift"
        ]
        .map { try String(contentsOf: projectRootURL().appendingPathComponent($0), encoding: .utf8) }
        .joined(separator: "\n")
    }

    func generalSettingsSource() throws -> String {
        try [
            "UI/Settings/GeneralSettingsView.swift",
            "UI/Settings/GeneralSettingsBrowseModels.swift",
            "UI/Settings/GeneralSettingsBrowseSection.swift",
            "UI/Settings/GeneralSettingsHidingSection.swift"
        ]
        .map { try String(contentsOf: projectRootURL().appendingPathComponent($0), encoding: .utf8) }
        .joined(separator: "\n")
    }

    func welcomeOnboardingSource() throws -> String {
        try [
            "UI/Onboarding/WelcomeView.swift",
            "UI/Onboarding/WelcomeOnboardingStyle.swift",
            "UI/Onboarding/WelcomeActionPage.swift",
            "UI/Onboarding/WelcomeWorkflowPages.swift",
            "UI/Onboarding/WelcomePermissionPage.swift",
            "UI/Onboarding/WelcomePlanPage.swift",
            "UI/Onboarding/WelcomePromisePage.swift",
            "UI/Onboarding/WelcomeViewPreviews.swift"
        ]
        .map { try String(contentsOf: projectRootURL().appendingPathComponent($0), encoding: .utf8) }
        .joined(separator: "\n")
    }

    func secondMenuBarSource() throws -> String {
        try [
            "UI/SearchWindow/SecondMenuBarView.swift",
            "UI/SearchWindow/SecondMenuBarSupport.swift",
            "UI/SearchWindow/SecondMenuBarPanelIconTile.swift"
        ]
        .map { try String(contentsOf: projectRootURL().appendingPathComponent($0), encoding: .utf8) }
        .joined(separator: "\n")
    }

    func diagnosticsSource() throws -> String {
        let diagnosticsURL = projectRootURL().appendingPathComponent("Core/Services/SearchServiceSupport.swift")
        return try String(contentsOf: diagnosticsURL, encoding: .utf8)
    }

}
