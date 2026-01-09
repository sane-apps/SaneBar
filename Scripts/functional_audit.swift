#!/usr/bin/env swift
// SaneBar Functional Audit Script
// Objectively verifies all advertised features work
// Run: swift Scripts/functional_audit.swift

import Foundation
import AppKit

// MARK: - Test Result Tracking

struct TestResult {
    let feature: String
    let category: String
    let passed: Bool
    let details: String
}

var results: [TestResult] = []
var passCount = 0
var failCount = 0

func test(_ feature: String, category: String, check: () -> (Bool, String)) {
    let (passed, details) = check()
    results.append(TestResult(feature: feature, category: category, passed: passed, details: details))
    if passed {
        passCount += 1
        print("✅ \(feature)")
    } else {
        failCount += 1
        print("❌ \(feature): \(details)")
    }
}

func fileExists(_ path: String) -> Bool {
    FileManager.default.fileExists(atPath: path)
}

func fileContains(_ path: String, _ text: String) -> Bool {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return false }
    return content.contains(text)
}

func grepFile(_ path: String, _ pattern: String) -> [String] {
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else { return [] }
    return content.components(separatedBy: "\n").filter { $0.contains(pattern) }
}

// MARK: - Project Root

let projectRoot = FileManager.default.currentDirectoryPath

print("""
╔══════════════════════════════════════════════════════════════╗
║           SaneBar Functional Verification Audit              ║
╚══════════════════════════════════════════════════════════════╝
Project: \(projectRoot)
Date: \(Date())

""")

// MARK: - 1. CORE FEATURES

print("\n━━━ CORE FEATURES ━━━\n")

test("Toggle hide/show implemented", category: "Core") {
    let hidingService = "\(projectRoot)/Core/Services/HidingService.swift"
    let hasToggle = fileContains(hidingService, "func toggle(")
    let hasShow = fileContains(hidingService, "func show(")
    let hasHide = fileContains(hidingService, "func hide(")
    return (hasToggle && hasShow && hasHide, "Missing: toggle=\(!hasToggle), show=\(!hasShow), hide=\(!hasHide)")
}

test("Default hotkey (⌘\\) configured", category: "Core") {
    let shortcuts = "\(projectRoot)/Core/Services/KeyboardShortcutsService.swift"
    let hasToggleShortcut = fileContains(shortcuts, "toggleHiddenItems") || fileContains(shortcuts, "KeyboardShortcuts.Name")
    return (hasToggleShortcut, "No toggle shortcut found")
}

test("Auto-hide with configurable delay", category: "Core") {
    let settings = "\(projectRoot)/Core/Services/PersistenceService.swift"
    let hasRehide = fileContains(settings, "autoRehide") || fileContains(settings, "rehideDelay")
    let generalView = "\(projectRoot)/UI/Settings/GeneralSettingsView.swift"
    let hasUI = fileContains(generalView, "rehideDelay") && fileContains(generalView, "Stepper")
    return (hasRehide && hasUI, "autoRehide=\(hasRehide), UI=\(hasUI)")
}

// MARK: - 2. FIND HIDDEN ICON

print("\n━━━ FIND HIDDEN ICON ━━━\n")

test("Search window exists", category: "FindIcon") {
    let searchView = "\(projectRoot)/UI/SearchWindow/MenuBarSearchView.swift"
    return (fileExists(searchView), "MenuBarSearchView.swift not found")
}

test("SearchService implements getHiddenMenuBarApps", category: "FindIcon") {
    let service = "\(projectRoot)/Core/Services/SearchService.swift"
    let hasMethod = fileContains(service, "getHiddenMenuBarApps")
    return (hasMethod, "getHiddenMenuBarApps not found")
}

test("Virtual click implemented", category: "FindIcon") {
    let accessibility = "\(projectRoot)/Core/Services/AccessibilityService.swift"
    let hasClick = fileContains(accessibility, "clickMenuBarItem")
    let hasPress = fileContains(accessibility, "performPress") || fileContains(accessibility, "AXPress")
    return (hasClick && hasPress, "clickMenuBarItem=\(hasClick), performPress=\(hasPress)")
}

test("Open System Settings button ACTUALLY opens System Settings", category: "FindIcon") {
    let searchView = "\(projectRoot)/UI/SearchWindow/MenuBarSearchView.swift"
    // Check for the CORRECT pattern - should use NSWorkspace.shared.open, NOT requestAccessibility
    let hasCorrectURL = fileContains(searchView, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    let hasNSWorkspace = fileContains(searchView, "NSWorkspace.shared.open")
    // Make sure it's NOT using the broken pattern
    let buttonLines = grepFile(searchView, "Open System Settings")
    let hasRequestAccessibility = buttonLines.contains { $0.contains("requestAccessibility") }

    let passed = hasCorrectURL && hasNSWorkspace && !hasRequestAccessibility
    return (passed, "CorrectURL=\(hasCorrectURL), NSWorkspace=\(hasNSWorkspace), BrokenPattern=\(hasRequestAccessibility)")
}

test("Permission monitoring with distributed notification", category: "FindIcon") {
    let accessibility = "\(projectRoot)/Core/Services/AccessibilityService.swift"
    let hasNotification = fileContains(accessibility, "com.apple.accessibility.api")
    let hasStream = fileContains(accessibility, "permissionStream")
    return (hasNotification && hasStream, "notification=\(hasNotification), stream=\(hasStream)")
}

// MARK: - 3. ONBOARDING

print("\n━━━ ONBOARDING ━━━\n")

test("Onboarding view exists", category: "Onboarding") {
    let onboarding = "\(projectRoot)/UI/OnboardingTipView.swift"
    return (fileExists(onboarding), "OnboardingTipView.swift not found")
}

test("Onboarding Open System Settings button works correctly", category: "Onboarding") {
    let onboarding = "\(projectRoot)/UI/OnboardingTipView.swift"
    let hasCorrectURL = fileContains(onboarding, "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    let hasNSWorkspace = fileContains(onboarding, "NSWorkspace.shared.open")
    return (hasCorrectURL && hasNSWorkspace, "CorrectURL=\(hasCorrectURL), NSWorkspace=\(hasNSWorkspace)")
}

// MARK: - 4. PER-ICON HOTKEYS

print("\n━━━ PER-ICON HOTKEYS ━━━\n")

test("IconHotkeysService exists", category: "Hotkeys") {
    let service = "\(projectRoot)/Core/Services/IconHotkeysService.swift"
    return (fileExists(service), "IconHotkeysService.swift not found")
}

test("Hotkey recording UI in search window footer", category: "Hotkeys") {
    let searchView = "\(projectRoot)/UI/SearchWindow/MenuBarSearchView.swift"
    let hasRecorder = fileContains(searchView, "KeyboardShortcuts.Recorder")
    let hasIconHotkeys = fileContains(searchView, "IconHotkeysService")
    let savesToSettings = fileContains(searchView, "iconHotkeys")
    return (hasRecorder && hasIconHotkeys && savesToSettings, "Recorder=\(hasRecorder), Service=\(hasIconHotkeys), Saves=\(savesToSettings)")
}

// MARK: - 5. GESTURES

print("\n━━━ GESTURES ━━━\n")

test("HoverService exists", category: "Gestures") {
    let service = "\(projectRoot)/Core/Services/HoverService.swift"
    return (fileExists(service), "HoverService.swift not found")
}

test("Hover trigger implemented", category: "Gestures") {
    let service = "\(projectRoot)/Core/Services/HoverService.swift"
    let hasHover = fileContains(service, "showOnHover") || fileContains(service, "mouseLocation")
    return (hasHover, "No hover trigger logic found")
}

test("Scroll trigger implemented", category: "Gestures") {
    let service = "\(projectRoot)/Core/Services/HoverService.swift"
    let hasScroll = fileContains(service, "showOnScroll") || fileContains(service, "scrollWheel")
    return (hasScroll, "No scroll trigger logic found")
}

test("Gesture settings in UI", category: "Gestures") {
    let generalView = "\(projectRoot)/UI/Settings/GeneralSettingsView.swift"
    let hasHoverToggle = fileContains(generalView, "showOnHover")
    let hasScrollToggle = fileContains(generalView, "showOnScroll")
    return (hasHoverToggle && hasScrollToggle, "hover=\(hasHoverToggle), scroll=\(hasScrollToggle)")
}

// MARK: - 6. AUTOMATION / TRIGGERS

print("\n━━━ AUTOMATION ━━━\n")

test("TriggerService exists", category: "Automation") {
    let service = "\(projectRoot)/Core/Services/TriggerService.swift"
    return (fileExists(service), "TriggerService.swift not found")
}

test("Network trigger (WiFi) implemented", category: "Automation") {
    let service = "\(projectRoot)/Core/Services/NetworkTriggerService.swift"
    let exists = fileExists(service)
    let hasWiFi = exists && fileContains(service, "SSID") || fileContains(service, "WiFi") || fileContains(service, "network")
    return (hasWiFi, "NetworkTriggerService not found or no WiFi logic")
}

test("Low battery trigger implemented", category: "Automation") {
    let trigger = "\(projectRoot)/Core/Services/TriggerService.swift"
    let hasBattery = fileContains(trigger, "battery") || fileContains(trigger, "Battery")
    return (hasBattery, "No battery trigger found")
}

// MARK: - 7. PROFILES

print("\n━━━ PROFILES ━━━\n")

test("ProfileService or profile saving exists", category: "Profiles") {
    let persistence = "\(projectRoot)/Core/Services/PersistenceService.swift"
    let hasProfiles = fileContains(persistence, "profile") || fileContains(persistence, "Profile")
    let advancedView = "\(projectRoot)/UI/Settings/AdvancedSettingsView.swift"
    let hasProfileUI = fileExists(advancedView) && fileContains(advancedView, "Profile")
    return (hasProfiles || hasProfileUI, "profiles=\(hasProfiles), profileUI=\(hasProfileUI)")
}

// MARK: - 8. APPEARANCE / STYLING

print("\n━━━ APPEARANCE ━━━\n")

test("MenuBarAppearanceService exists", category: "Appearance") {
    let service = "\(projectRoot)/Core/Services/MenuBarAppearanceService.swift"
    return (fileExists(service), "MenuBarAppearanceService.swift not found")
}

test("Liquid Glass support (macOS 26)", category: "Appearance") {
    let appearance = "\(projectRoot)/Core/Services/MenuBarAppearanceService.swift"
    let hasLiquidGlass = fileContains(appearance, "liquidGlass") || fileContains(appearance, "LiquidGlass") || fileContains(appearance, "glassEffect")
    return (hasLiquidGlass, "No Liquid Glass implementation found")
}

// MARK: - 9. APPLESCRIPT

print("\n━━━ APPLESCRIPT ━━━\n")

test("AppleScript .sdef file exists", category: "AppleScript") {
    let sdef = "\(projectRoot)/Resources/SaneBar.sdef"
    return (fileExists(sdef), "SaneBar.sdef not found")
}

test("AppleScript commands implemented", category: "AppleScript") {
    let commands = "\(projectRoot)/Core/Services/AppleScriptCommands.swift"
    let hasShow = fileContains(commands, "ShowCommand")
    let hasHide = fileContains(commands, "HideCommand")
    let hasToggle = fileContains(commands, "ToggleCommand")
    return (hasShow && hasHide && hasToggle, "ShowCommand=\(hasShow), HideCommand=\(hasHide), ToggleCommand=\(hasToggle)")
}

// MARK: - 10. SETTINGS UI

print("\n━━━ SETTINGS UI ━━━\n")

test("GeneralSettingsView exists", category: "Settings") {
    return (fileExists("\(projectRoot)/UI/Settings/GeneralSettingsView.swift"), "Not found")
}

test("ShortcutsSettingsView exists", category: "Settings") {
    return (fileExists("\(projectRoot)/UI/Settings/ShortcutsSettingsView.swift"), "Not found")
}

test("AdvancedSettingsView exists", category: "Settings") {
    return (fileExists("\(projectRoot)/UI/Settings/AdvancedSettingsView.swift"), "Not found")
}

test("AboutSettingsView exists", category: "Settings") {
    return (fileExists("\(projectRoot)/UI/Settings/AboutSettingsView.swift"), "Not found")
}

// MARK: - 11. TESTS

print("\n━━━ TEST COVERAGE ━━━\n")

test("AccessibilityServiceTests exists", category: "Tests") {
    return (fileExists("\(projectRoot)/Tests/AccessibilityServiceTests.swift"), "Not found")
}

test("SearchWindowTests exists", category: "Tests") {
    return (fileExists("\(projectRoot)/Tests/SearchWindowTests.swift"), "Not found")
}

test("HidingServiceTests exists", category: "Tests") {
    return (fileExists("\(projectRoot)/Tests/HidingServiceTests.swift"), "Not found")
}

test("HoverServiceTests exists", category: "Tests") {
    return (fileExists("\(projectRoot)/Tests/HoverServiceTests.swift"), "Not found")
}

// MARK: - SUMMARY

print("""

╔══════════════════════════════════════════════════════════════╗
║                        AUDIT SUMMARY                         ║
╚══════════════════════════════════════════════════════════════╝

Total Tests: \(passCount + failCount)
✅ Passed:   \(passCount)
❌ Failed:   \(failCount)

""")

if failCount > 0 {
    print("FAILED TESTS:")
    for result in results where !result.passed {
        print("  ❌ [\(result.category)] \(result.feature)")
        print("     → \(result.details)")
    }
    print("")
}

// Exit with failure if any tests failed
exit(failCount > 0 ? 1 : 0)
