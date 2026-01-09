import Testing
import Foundation
import AppKit
@testable import SaneBar

// MARK: - IconHotkeysServiceTests

@Suite("IconHotkeysService Tests")
@MainActor
struct IconHotkeysServiceTests {

    // MARK: - Shortcut Name Generation Tests

    @Test("shortcutName generates unique name per bundleID")
    func testShortcutNameUnique() {
        let name1 = IconHotkeysService.shortcutName(for: "com.apple.Safari")
        let name2 = IconHotkeysService.shortcutName(for: "com.apple.mail")
        let name3 = IconHotkeysService.shortcutName(for: "com.apple.Safari")

        #expect(name1.rawValue != name2.rawValue, "Different apps should have different names")
        #expect(name1.rawValue == name3.rawValue, "Same app should get same name")
    }

    @Test("shortcutName includes bundleID in raw value")
    func testShortcutNameContainsBundleID() {
        let bundleID = "com.example.app"
        let name = IconHotkeysService.shortcutName(for: bundleID)

        #expect(name.rawValue.contains(bundleID), "Name should contain bundleID")
    }

    @Test("shortcutName has consistent prefix")
    func testShortcutNamePrefix() {
        let name = IconHotkeysService.shortcutName(for: "com.test.app")

        #expect(name.rawValue.hasPrefix("iconHotkey-"), "Name should have iconHotkey- prefix")
    }

    // MARK: - KeyboardShortcutData Tests

    @Test("KeyboardShortcutData stores keyCode and modifiers")
    func testKeyboardShortcutDataStorage() {
        let data = KeyboardShortcutData(keyCode: 0, modifiers: 256) // 0 = 'a', 256 = Cmd

        #expect(data.keyCode == 0)
        #expect(data.modifiers == 256)
    }

    @Test("KeyboardShortcutData is Codable")
    func testKeyboardShortcutDataCodable() throws {
        let original = KeyboardShortcutData(keyCode: 49, modifiers: 1048840) // Space + Cmd+Shift

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(KeyboardShortcutData.self, from: data)

        #expect(decoded.keyCode == original.keyCode)
        #expect(decoded.modifiers == original.modifiers)
    }

    @Test("KeyboardShortcutData is Equatable")
    func testKeyboardShortcutDataEquatable() {
        let data1 = KeyboardShortcutData(keyCode: 0, modifiers: 256)
        let data2 = KeyboardShortcutData(keyCode: 0, modifiers: 256)
        let data3 = KeyboardShortcutData(keyCode: 1, modifiers: 256)

        #expect(data1 == data2, "Same values should be equal")
        #expect(data1 != data3, "Different keyCode should not be equal")
    }

    // MARK: - Icon Hotkeys Dictionary Tests

    @Test("SaneBarSettings iconHotkeys dictionary works correctly")
    func testIconHotkeysDictionary() {
        var settings = SaneBarSettings()

        // Add hotkeys
        settings.iconHotkeys["com.apple.Safari"] = KeyboardShortcutData(keyCode: 1, modifiers: 256)
        settings.iconHotkeys["com.apple.mail"] = KeyboardShortcutData(keyCode: 2, modifiers: 512)

        #expect(settings.iconHotkeys.count == 2)
        #expect(settings.iconHotkeys["com.apple.Safari"]?.keyCode == 1)
        #expect(settings.iconHotkeys["com.apple.mail"]?.modifiers == 512)
    }

    @Test("Removing hotkey from dictionary works")
    func testRemoveHotkey() {
        var settings = SaneBarSettings()
        settings.iconHotkeys["com.test.app"] = KeyboardShortcutData(keyCode: 5, modifiers: 256)

        #expect(settings.iconHotkeys.count == 1)

        settings.iconHotkeys.removeValue(forKey: "com.test.app")

        #expect(settings.iconHotkeys.count == 0)
        #expect(settings.iconHotkeys["com.test.app"] == nil)
    }

    @Test("Empty iconHotkeys dictionary is default")
    func testEmptyHotkeysDefault() {
        let settings = SaneBarSettings()

        #expect(settings.iconHotkeys.isEmpty, "Default should have no hotkeys")
    }

    // MARK: - Registration Logic Tests

    @Test("unregisterAllHotkeys is safe when no hotkeys registered")
    func testUnregisterEmpty() {
        let service = IconHotkeysService.shared

        // Should not crash when nothing is registered
        service.unregisterAllHotkeys()

        #expect(true, "Unregister with no hotkeys should be safe")
    }

    @Test("registerHotkeys with empty settings is safe")
    func testRegisterEmptySettings() {
        let service = IconHotkeysService.shared
        let settings = SaneBarSettings() // No hotkeys

        service.registerHotkeys(from: settings)

        #expect(true, "Register with no hotkeys should be safe")
    }

    // MARK: - BundleID Validation Tests

    @Test("BundleID format validation examples")
    func testBundleIDFormats() {
        // Valid bundle ID formats
        let valid = [
            "com.apple.Safari",
            "com.example.myapp",
            "org.mozilla.firefox",
            "io.github.project"
        ]

        for bundleID in valid {
            #expect(bundleID.contains("."), "Valid bundleID has dots: \(bundleID)")
        }
    }

    @Test("Empty bundleID handling")
    func testEmptyBundleID() {
        let name = IconHotkeysService.shortcutName(for: "")

        #expect(name.rawValue == "iconHotkey-", "Empty bundleID creates name with just prefix")
    }

    // MARK: - Modifier Flags Tests

    @Test("Common modifier flag values")
    func testModifierFlagValues() {
        // These are the raw values used by NSEvent.ModifierFlags
        let command = NSEvent.ModifierFlags.command.rawValue
        let shift = NSEvent.ModifierFlags.shift.rawValue
        let option = NSEvent.ModifierFlags.option.rawValue
        let control = NSEvent.ModifierFlags.control.rawValue

        #expect(command > 0, "Command modifier has non-zero value")
        #expect(shift > 0, "Shift modifier has non-zero value")
        #expect(option > 0, "Option modifier has non-zero value")
        #expect(control > 0, "Control modifier has non-zero value")

        // Combined modifiers
        let cmdShift = command | shift
        #expect(cmdShift != command, "Combined differs from single")
        #expect(cmdShift != shift, "Combined differs from single")
    }

    @Test("Modifier flags can be combined and separated")
    func testModifierFlagCombination() {
        let command = NSEvent.ModifierFlags.command
        let shift = NSEvent.ModifierFlags.shift

        let combined = command.union(shift)

        #expect(combined.contains(.command))
        #expect(combined.contains(.shift))
        #expect(!combined.contains(.option))
    }

    // MARK: - Integration Logic Tests

    @Test("Hotkey trigger flow logic")
    func testHotkeyTriggerLogic() {
        // Simulating the flow without actual KeyboardShortcuts library
        let bundleID = "com.apple.Safari"
        let hotkeys: [String: KeyboardShortcutData] = [
            bundleID: KeyboardShortcutData(keyCode: 1, modifiers: 256)
        ]

        // Check if bundleID has a registered hotkey
        let hasHotkey = hotkeys[bundleID] != nil
        #expect(hasHotkey, "Safari should have a hotkey")

        let noHotkey = hotkeys["com.other.app"] != nil
        #expect(!noHotkey, "Unknown app should not have a hotkey")
    }

    // MARK: - Persistence Tests

    @Test("iconHotkeys persist through encode/decode cycle")
    func testIconHotkeysPersistence() throws {
        var settings = SaneBarSettings()
        settings.iconHotkeys["com.test.app1"] = KeyboardShortcutData(keyCode: 10, modifiers: 100)
        settings.iconHotkeys["com.test.app2"] = KeyboardShortcutData(keyCode: 20, modifiers: 200)

        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SaneBarSettings.self, from: data)

        #expect(decoded.iconHotkeys.count == 2)
        #expect(decoded.iconHotkeys["com.test.app1"]?.keyCode == 10)
        #expect(decoded.iconHotkeys["com.test.app2"]?.modifiers == 200)
    }
}
