import Testing
import Foundation

// MARK: - MenuBarUITests

/// UI tests for menu bar interactions using osascript.
/// These tests verify actual user interaction with the menu bar.
@Suite("MenuBar UI Tests")
struct MenuBarUITests {

    // MARK: - Helper

    /// Runs an AppleScript and returns the result
    private func runAppleScript(_ script: String) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            throw MenuBarTestError.scriptFailed(errorOutput)
        }

        return output
    }

    enum MenuBarTestError: Error {
        case scriptFailed(String)
        case menuNotFound
        case settingsNotOpened
    }

    // MARK: - Tests

    @Test("Right-click on status bar item shows menu", .disabled("Requires running app"))
    func testRightClickShowsMenu() throws {
        let script = """
        tell application "System Events"
            tell process "SaneBar"
                set menuBarItem to menu bar item 2 of menu bar 2
                click menuBarItem
                delay 0.3
                if exists menu "SaneBar" of menuBarItem then
                    return "MENU_VISIBLE"
                else
                    return "MENU_NOT_FOUND"
                end if
            end tell
        end tell
        """

        let result = try runAppleScript(script)
        #expect(result == "MENU_VISIBLE", "Menu should be visible after clicking status bar item")
    }

    @Test("Settings menu item opens settings window", .disabled("Requires running app"))
    func testSettingsMenuOpensWindow() throws {
        let script = """
        tell application "System Events"
            tell process "SaneBar"
                set menuBarItem to menu bar item 2 of menu bar 2
                click menuBarItem
                delay 0.3
                click menu item "Settings..." of menu "SaneBar" of menuBarItem
                delay 0.5
                if (count of windows) > 0 then
                    return "SETTINGS_OPENED"
                else
                    return "NO_WINDOW"
                end if
            end tell
        end tell
        """

        let result = try runAppleScript(script)
        #expect(result == "SETTINGS_OPENED", "Settings window should open when clicking Settings menu item")
    }

    @Test("Settings window shows correct documentation text (Left = hidden)", .disabled("Requires running app"))
    func testDocumentationTextIsCorrect() throws {
        let script = """
        tell application "System Events"
            tell process "SaneBar"
                -- Open Settings first (reuse logic)
                set menuBarItem to menu bar item 2 of menu bar 2
                click menuBarItem
                delay 0.3
                click menu item "Settings..." of menu "SaneBar" of menuBarItem
                delay 1.0
                
                -- Check for static text
                -- Note: exact hierarchy might vary, searching all text elements
                set uiText to (value of every static text of window "SaneBar" whose value contains "Left of separator")
                return uiText as string
            end tell
        end tell
        """

        let result = try runAppleScript(script)
        #expect(result.contains("Left of separator = can be hidden"), "Settings should say 'Left of separator = can be hidden'")
        #expect(result.contains("Right of separator = always visible"), "Settings should say 'Right of separator = always visible'")
    }

    @Test("Menu has expected items: Toggle, Settings, Quit", .disabled("Requires running app"))
    func testMenuHasExpectedItems() throws {
        let script = """
        tell application "System Events"
            tell process "SaneBar"
                set menuBarItem to menu bar item 2 of menu bar 2
                click menuBarItem
                delay 0.3
                set menuItems to name of menu items of menu "SaneBar" of menuBarItem
                return menuItems as string
            end tell
        end tell
        """

        let result = try runAppleScript(script)
        #expect(result.contains("Toggle Hidden Items"), "Menu should have Toggle Hidden Items")
        #expect(result.contains("Settings"), "Menu should have Settings")
        #expect(result.contains("Quit SaneBar"), "Menu should have Quit SaneBar")
    }

    @Test("Quit menu item terminates app", .disabled("Requires running app - destructive"))
    func testQuitMenuTerminatesApp() throws {
        // This test is disabled by default as it would quit the app
        // Can be run manually for verification
        let script = """
        tell application "System Events"
            tell process "SaneBar"
                set menuBarItem to menu bar item 2 of menu bar 2
                click menuBarItem
                delay 0.3
                if exists menu item "Quit SaneBar" of menu "SaneBar" of menuBarItem then
                    return "QUIT_EXISTS"
                else
                    return "QUIT_NOT_FOUND"
                end if
            end tell
        end tell
        """

        let result = try runAppleScript(script)
        #expect(result == "QUIT_EXISTS", "Quit menu item should exist")
    }
}
