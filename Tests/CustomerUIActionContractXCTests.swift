import Foundation
import XCTest

final class CustomerUIActionContractXCTests: XCTestCase {
    private func projectRootURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func saneAppsRootURL() -> URL {
        projectRootURL()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func read(_ relativePath: String) throws -> String {
        try String(
            contentsOf: projectRootURL().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func readShared(_ relativePath: String) throws -> String {
        try String(
            contentsOf: saneAppsRootURL().appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }

    private func contract() throws -> String {
        try read("Tests/CustomerUIActions.yml")
    }

    private func normalizedContract(_ source: String) -> String {
        source
            .replacingOccurrences(
                of: #"(?m)^- id:"#,
                with: "  - id:",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"\n {4,}"#,
                with: " ",
                options: .regularExpression
            )
    }

    func testContractEnumeratesAllCustomerFacingActionFamilies() throws {
        let source = normalizedContract(try contract())
        let requiredIDs = [
            "status-item-click-routes",
            "status-menu-command-actions",
            "dock-menu-command-actions",
            "browse-icons-search-navigation",
            "browse-icons-icon-context-actions",
            "second-menu-bar-actions",
            "icon-zone-move-reorder-always-hidden",
            "icon-hotkeys-and-groups",
            "settings-shell-tabs-render",
            "control-settings-actions",
            "profiles-save-load-delete-apply",
            "rules-trigger-actions",
            "appearance-customization-actions",
            "shortcuts-and-automation-actions",
            "health-repair-rescue-diagnostics",
            "data-import-export-reset-actions",
            "onboarding-basic-pro-permission-actions",
            "license-about-support-actions",
            "pro-basic-gating-actions",
            "startup-wake-appearance-recovery"
        ]

        for id in requiredIDs {
            XCTAssertTrue(
                source.contains("- id: \(id)"),
                "Customer UI release contract must include \(id)"
            )
        }

        let actionCount = source.components(separatedBy: "\n  - id: ").count - 1
        XCTAssertGreaterThanOrEqual(
            actionCount,
            requiredIDs.count,
            "The release contract must stay expanded beyond broad smoke-test buckets"
        )
    }

    func testContractTracksShippedMenuAndAutomationSurfaces() throws {
        let contract = try contract()
        let statusMenuSource = try read("Core/Controllers/StatusBarController.swift")
        let appSource = try read("SaneBarApp.swift")
        let intentsSource = try read("Core/AppIntents/SaneBarAppIntents.swift")
        let sdefSource = try read("Resources/SaneBar.sdef")

        for title in ["Browse Icons...", "Show / Hide Icons", "Arrange Now", "Help / Repair..."] {
            XCTAssertTrue(statusMenuSource.contains(title), "Expected shipped menu item \(title)")
        }
        XCTAssertTrue(contract.contains("What's New when present"), "Contract must cover conditional What's New menu items")
        XCTAssertTrue(contract.contains("status-menu-command-actions"))

        for urlCase in ["toggle", "show", "hide", "search", "settings", "health"] {
            XCTAssertTrue(appSource.contains("case \"\(urlCase)\""), "Expected URL route \(urlCase)")
        }
        XCTAssertTrue(contract.contains("shortcuts-and-automation-actions"))

        for intent in ["ToggleHiddenItemsIntent", "ShowHiddenItemsIntent", "HideHiddenItemsIntent", "ApplySaneBarProfileIntent", "QuickSearchSaneBarIntent"] {
            XCTAssertTrue(intentsSource.contains(intent), "Expected shipped App Intent \(intent)")
        }
        XCTAssertTrue(contract.contains("App Intents"))

        for command in ["toggle", "show hidden", "hide items", "open icon panel", "quick search", "show second menu bar", "list icon zones", "activate browse icon", "move icon to always hidden"] {
            XCTAssertTrue(sdefSource.contains("command name=\"\(command)\""), "Expected AppleScript command \(command)")
        }
        XCTAssertTrue(contract.contains("AppleScript"))
    }

    func testContractTracksSettingsTabsAndRiskyActions() throws {
        let contract = try contract()
        let settingsSource = try read("UI/SettingsView.swift")
        let generalSource = try read("UI/Settings/GeneralSettingsView.swift")
        let rulesSource = try read("UI/Settings/RulesSettingsView.swift")
        let appearanceSource = try read("UI/Settings/AppearanceSettingsView.swift")
        let shortcutsSource = try read("UI/Settings/ShortcutsSettingsView.swift")
        let healthSource = try read("UI/Settings/HealthSettingsView.swift")

        for tab in ["Control", "Rules", "Appearance", "Shortcuts", "Health", "License", "About"] {
            XCTAssertTrue(settingsSource.contains(tab), "Expected Settings tab \(tab)")
            XCTAssertTrue(contract.contains("\(tab) tab"), "Contract must require evidence for Settings \(tab)")
        }

        for label in ["Export Settings...", "Import Settings...", "Import Bartender...", "Import Ice...", "Reset to Defaults"] {
            XCTAssertTrue(generalSource.contains(label), "Expected shipped data action \(label)")
            XCTAssertTrue(contract.contains(label.replacingOccurrences(of: "...", with: "")) || contract.contains(label), "Contract must name \(label)")
        }

        for marker in ["showOnLowBattery", "showOnAppLaunch", "showOnSchedule", "showOnNetworkChange", "showOnFocusModeChange", "scriptTriggerEnabled"] {
            XCTAssertTrue(rulesSource.contains(marker), "Expected Rules control \(marker)")
        }
        XCTAssertTrue(contract.contains("rules-trigger-actions"))

        for label in ["Menu Bar Icon", "Custom Appearance", "Reduce space between icons", "Click Area"] {
            XCTAssertTrue(appearanceSource.contains(label), "Expected Appearance control \(label)")
        }
        XCTAssertTrue(contract.contains("appearance-customization-actions"))

        for label in ["Browse Icons", "Show / Hide icons", "Automation", "Copy"] {
            XCTAssertTrue(shortcutsSource.contains(label), "Expected Shortcuts control \(label)")
        }
        XCTAssertTrue(contract.contains("shortcuts-and-automation-actions"))

        for label in ["Save Current Layout", "Restore Last Good Layout", "Arrange Now", "Copy Report"] {
            XCTAssertTrue(healthSource.contains(label), "Expected Health action \(label)")
            XCTAssertTrue(contract.contains(label), "Contract must name \(label)")
        }
    }

    func testContractTracksBrowseContextOnboardingAndSharedSaneUI() throws {
        let contract = normalizedContract(try contract())
        let tileSource = try read("UI/SearchWindow/MenuBarAppTile.swift")
        let searchSource = try read("UI/SearchWindow/MenuBarSearchView.swift")
        let secondMenuBarSource = try read("UI/SearchWindow/SecondMenuBarView.swift")
        let onboardingSource = try read("UI/Onboarding/WelcomeView.swift")
        let saneUICatalog = try readShared("infra/SaneUI/Sources/SaneUICatalog/SaneUICatalogApp.swift")
        let aboutSource = try readShared("infra/SaneUI/Sources/SaneUI/Components/SaneAboutView.swift")
        let licenseSource = try readShared("infra/SaneUI/Sources/SaneUI/License/LicenseSettingsView.swift")

        for label in ["Left-Click", "Right-Click", "Set Hotkey", "Copy Icon ID", "Move to Visible", "Move to Hidden", "Move to Always Hidden", "Remove from Group"] {
            XCTAssertTrue(tileSource.contains(label) || secondMenuBarSource.contains(label), "Expected icon context action \(label)")
            XCTAssertTrue(contract.contains(label), "Contract must name icon context action \(label)")
        }
        XCTAssertTrue(
            contract.contains("delayed post-move settle window") &&
                contract.contains("Moved items stay in the requested zone after delayed reconciliation runs"),
            "Customer UI contract must require post-settle zone stability, not only immediate move success"
        )

        for label in ["How Browse Icons works", "Open Accessibility Settings", "Try Again"] {
            XCTAssertTrue(searchSource.contains(label) || secondMenuBarSource.contains(label), "Expected Browse/Second Menu Bar action \(label)")
        }

        for label in ["Import Layout", "Import Settings", "Open Accessibility Settings", "Unlock Pro", "Restore Purchases"] {
            XCTAssertTrue(onboardingSource.contains(label), "Expected onboarding action \(label)")
            XCTAssertTrue(contract.contains(label), "Contract must name onboarding action \(label)")
        }

        XCTAssertTrue(saneUICatalog.contains("SaneSettingsContainer"), "Shared SaneUI catalog should remain the settings source of truth")
        for label in ["Licenses", "Report a Bug"] {
            XCTAssertTrue(aboutSource.contains(label), "Expected shared About action \(label)")
            XCTAssertTrue(contract.contains(label), "Contract must name shared About action \(label)")
        }
        for label in ["Restore Purchases", "Unlock Pro"] {
            XCTAssertTrue(licenseSource.contains(label), "Expected shared License action \(label)")
            XCTAssertTrue(contract.contains(label), "Contract must name shared License action \(label)")
        }
    }

    func testEveryReleaseRequiredActionNamesMiniEvidence() throws {
        let source = normalizedContract(try contract())
        let sections = source.components(separatedBy: "\n  - id: ").dropFirst()
        XCTAssertFalse(sections.isEmpty)

        for section in sections {
            let id = section.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? "unknown"
            XCTAssertTrue(section.contains("steps:"), "\(id) must describe click/interaction steps")
            XCTAssertTrue(section.contains("assertions:"), "\(id) must describe customer-visible assertions")
            XCTAssertTrue(section.contains("evidence:"), "\(id) must require evidence")
            XCTAssertTrue(section.contains("Mini"), "\(id) must require Mini-side evidence")
            XCTAssertFalse(section.contains("required_proof_level: fixture_completion"), "\(id) must not ship with fixture-only proof")
            XCTAssertTrue(section.contains("required_proof_level: full_runtime_completion"), "\(id) must require full runtime completion")
        }
    }

    func testReceiptRecordsEvidencePerCustomerAction() throws {
        let receiptURL = projectRootURL().appendingPathComponent(".sane/customer_ui_action_receipt.json")
        let data = try Data(contentsOf: receiptURL)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let actionResults = try XCTUnwrap(json["action_results"] as? [String: Any])
        let source = normalizedContract(try contract())
        let actionIDs = source.components(separatedBy: "\n  - id: ")
            .dropFirst()
            .compactMap { section in section.split(separator: "\n", maxSplits: 1).first.map(String.init) }

        for id in actionIDs {
            let result = try XCTUnwrap(actionResults[id] as? [String: Any], "\(id) must have per-action receipt evidence")
            XCTAssertEqual(result["status"] as? String, "passed", "\(id) must be marked passed in the receipt")
            XCTAssertFalse((result["proof_level"] as? String ?? "").isEmpty, "\(id) must record the proof level used for release")
            XCTAssertNotNil(result["functional_state"] as? [String: Any], "\(id) must prove the required app/user state was established")
            XCTAssertFalse((result["inputs"] as? [String] ?? []).isEmpty, "\(id) must record exercised user inputs")
            XCTAssertFalse((result["output_assertions"] as? [String] ?? []).isEmpty, "\(id) must record output assertions")
            XCTAssertNotNil(result["workflow"] as? [String: Any], "\(id) must include structured workflow proof")
            let evidence = try XCTUnwrap(result["evidence"] as? [[String: Any]], "\(id) must have structured evidence")
            XCTAssertFalse(evidence.isEmpty, "\(id) must not rely on a coarse smoke bucket")
            let evidenceTypes = Set(evidence.compactMap { $0["type"] as? String })
            for requiredType in requiredEvidenceTypes(in: source, id: id) {
                XCTAssertTrue(evidenceTypes.contains(requiredType), "\(id) receipt must include required evidence type \(requiredType)")
            }
            for item in evidence {
                let type = item["type"] as? String ?? ""
                let detail = item["detail"] as? String ?? ""
                XCTAssertFalse(type.isEmpty, "\(id) evidence must name its type")
                XCTAssertFalse(detail.isEmpty, "\(id) evidence must include detail")
                assertPathBackedEvidenceHasArtifact(item, type: type, actionID: id)
                assertStrictMiniEvidenceIsReal(type: type, detail: detail, actionID: id)
            }
        }
    }

    private func requiredEvidenceTypes(in source: String, id: String) -> [String] {
        guard let section = source.components(separatedBy: "\n  - id: \(id)\n").dropFirst().first else {
            return []
        }
        guard let requiredBlock = section.components(separatedBy: "required_evidence_types:").dropFirst().first else {
            return []
        }

        return requiredBlock
            .split(separator: "\n")
            .prefix { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                return trimmed.hasPrefix("- ")
            }
            .map { line in
                line.trimmingCharacters(in: .whitespaces)
                    .replacingOccurrences(of: "- ", with: "")
            }
    }

    private func assertStrictMiniEvidenceIsReal(type: String, detail: String, actionID: String) {
        let strictTypes: Set<String> = ["mini_click", "mini_automation", "mini_ax", "mini_url_route", "mini_runtime"]
        guard strictTypes.contains(type) else { return }

        let lowercasedDetail = detail.lowercased()
        for placeholder in ["verified by source", "source-verified", "source guard", "guard fixture", "covered by", "without performing", "not opened during"] {
            XCTAssertFalse(lowercasedDetail.contains(placeholder), "\(actionID) \(type) evidence is a placeholder: \(detail)")
        }

        let allowedPrefixesByType: [String: [String]] = [
            "mini_click": ["/tmp/sanebar_runtime_", "applescript=", "settings_ax_tab_index=", "settings_tab=", "icon_hotkeys_groups_", "url_route=", "runtime_visual="],
            "mini_automation": ["applescript=", "url_route=", "settings_ax_tab_index=", "icon_hotkeys_groups_"],
            "mini_ax": ["settings_ax_tab_index="],
            "mini_url_route": ["url_route="],
            "mini_runtime": ["/tmp/sanebar_runtime_"]
        ]
        let allowedPrefixes = allowedPrefixesByType[type] ?? []
        XCTAssertTrue(
            allowedPrefixes.contains { detail.hasPrefix($0) },
            "\(actionID) \(type) evidence must come from Mini runtime output, not prose: \(detail)"
        )
    }

    private func assertPathBackedEvidenceHasArtifact(_ item: [String: Any], type: String, actionID: String) {
        let pathBackedTypes: Set<String> = [
            "actual_output", "api_response", "automation_transcript", "file_state", "fixture", "log",
            "mini_automation", "mini_ax", "mini_click", "mini_runtime", "mini_screenshots",
            "mini_screenshot", "mini_url_route", "model_response", "screenshot", "state_receipt",
            "support_report", "visual_screenshot", "visual_smoke"
        ]
        guard pathBackedTypes.contains(type) else { return }

        let directPath = (item["path"] as? String)?.isEmpty == false ||
            (item["artifact"] as? String)?.isEmpty == false ||
            (item["file"] as? String)?.isEmpty == false
        let artifactList = (item["artifacts"] as? [String] ?? []).contains { !$0.isEmpty }
        XCTAssertTrue(directPath || artifactList, "\(actionID) \(type) evidence must point at a real artifact, not prose-only notes")
    }
}
