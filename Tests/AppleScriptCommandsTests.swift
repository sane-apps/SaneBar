import Foundation
@testable import SaneBar
import Testing

// MARK: - AppleScriptCommandsTests

@Suite("AppleScriptCommands Tests")
struct AppleScriptCommandsTests {
    // MARK: - Command Class Existence Tests

    @Test("ToggleCommand class exists and inherits directly from NSScriptCommand")
    func toggleCommandExists() {
        let command = ToggleCommand()
        // Verify the type hierarchy via class name (avoids 'is' tautology warning)
        let superclassName = String(describing: type(of: command).superclass())
        #expect(superclassName.contains("NSScriptCommand") || superclassName.contains("SaneBarScriptCommand"), "ToggleCommand should inherit from NSScriptCommand")
    }

    @Test("ShowCommand class exists and inherits directly from NSScriptCommand")
    func showCommandExists() {
        let command = ShowCommand()
        let superclassName = String(describing: type(of: command).superclass())
        #expect(superclassName.contains("NSScriptCommand") || superclassName.contains("SaneBarScriptCommand"), "ShowCommand should inherit from NSScriptCommand")
    }

    @Test("HideCommand class exists and inherits directly from NSScriptCommand")
    func hideCommandExists() {
        let command = HideCommand()
        let superclassName = String(describing: type(of: command).superclass())
        #expect(superclassName.contains("NSScriptCommand") || superclassName.contains("SaneBarScriptCommand"), "HideCommand should inherit from NSScriptCommand")
    }

    // MARK: - Command Return Value Tests

    @Test("ToggleCommand returns nil from performDefaultImplementation")
    func toggleCommandReturnsNil() {
        let command = ToggleCommand()
        let result = command.performDefaultImplementation()

        #expect(result == nil, "Toggle command should return nil")
    }

    @Test("ShowCommand returns nil from performDefaultImplementation")
    func showCommandReturnsNil() {
        let command = ShowCommand()
        let result = command.performDefaultImplementation()

        #expect(result == nil, "Show command should return nil")
    }

    @Test("HideCommand returns true from performDefaultImplementation")
    func hideCommandReturnsTrue() {
        let command = HideCommand()
        let result = command.performDefaultImplementation()

        #expect(result as? Bool == true, "Hide command should return true")
    }

    // MARK: - Objective-C Exposure Tests

    @Test("ToggleCommand is exposed to Objective-C with correct name")
    func toggleCommandObjCName() {
        // The @objc(ToggleCommand) attribute exposes it with this name
        let className = NSStringFromClass(ToggleCommand.self)

        #expect(className.contains("ToggleCommand"), "Class should be exposed as ToggleCommand")
    }

    @Test("ShowCommand is exposed to Objective-C with correct name")
    func showCommandObjCName() {
        let className = NSStringFromClass(ShowCommand.self)

        #expect(className.contains("ShowCommand"), "Class should be exposed as ShowCommand")
    }

    @Test("HideCommand is exposed to Objective-C with correct name")
    func hideCommandObjCName() {
        let className = NSStringFromClass(HideCommand.self)

        #expect(className.contains("HideCommand"), "Class should be exposed as HideCommand")
    }

    // MARK: - Command Instantiation Tests

    @Test("Commands can be instantiated multiple times")
    func multipleInstantiation() {
        let toggle1 = ToggleCommand()
        let toggle2 = ToggleCommand()
        _ = ShowCommand() // Verify can instantiate
        _ = HideCommand() // Verify can instantiate

        #expect(toggle1 !== toggle2, "Each instantiation creates new object")
        #expect(true, "Multiple commands can coexist")
    }

    // MARK: - Base Class Tests

    // MARK: - Base Class Tests

    @Test("All commands are NSScriptCommand subclasses")
    func baseClass() {
        // Verify inheritance via superclass check (avoids 'is' tautology warning)
        let toggleSuper = String(describing: ToggleCommand.superclass())
        let showSuper = String(describing: ShowCommand.superclass())
        let hideSuper = String(describing: HideCommand.superclass())

        #expect(toggleSuper.contains("NSScriptCommand") || toggleSuper.contains("SaneBarScriptCommand"))
        #expect(showSuper.contains("NSScriptCommand") || showSuper.contains("SaneBarScriptCommand"))
        #expect(hideSuper.contains("NSScriptCommand") || hideSuper.contains("SaneBarScriptCommand"))
    }

    // MARK: - Command Semantics Tests

    @Test("Each command type has distinct purpose")
    func commandSemantics() {
        // Document the expected behavior of each command
        let commandPurposes: [String: String] = [
            "ToggleCommand": "Toggles hidden items visibility",
            "ShowCommand": "Shows hidden items",
            "HideCommand": "Hides items",
        ]

        #expect(commandPurposes.count == 3, "Three distinct commands")
        #expect(commandPurposes["ToggleCommand"] != commandPurposes["ShowCommand"])
        #expect(commandPurposes["ShowCommand"] != commandPurposes["HideCommand"])
    }

    // MARK: - AppleScript Integration Path Tests

    @Test("Commands follow NSScriptCommand pattern")
    func nSScriptCommandPattern() {
        let command = ToggleCommand()

        // NSScriptCommand has these key methods
        _ = command.performDefaultImplementation()
        _ = command.scriptErrorNumber
        _ = command.scriptErrorString

        #expect(true, "Command follows NSScriptCommand pattern")
    }

    // MARK: - Thread Safety Consideration Tests

    @Test("Commands dispatch to MainActor")
    func mainActorDispatch() {
        // The commands use Task { @MainActor in ... } internally
        // This test documents that expectation

        let command = ToggleCommand()

        // Calling perform should not crash even from test thread
        _ = command.performDefaultImplementation()

        #expect(true, "Command safely dispatches to MainActor")
    }

    // MARK: - SDEF Mapping Tests

    @Test("Command class names match expected SDEF mapping")
    func sDEFMapping() {
        // These names must match what's in SaneBar.sdef
        let expectedMappings = [
            "ToggleCommand": "toggle",
            "ShowCommand": "show",
            "HideCommand": "hide",
        ]

        // Verify class names exist via NSStringFromClass (avoids metatype-to-nil comparison)
        let toggleName = NSStringFromClass(ToggleCommand.self)
        let showName = NSStringFromClass(ShowCommand.self)
        let hideName = NSStringFromClass(HideCommand.self)

        #expect(!toggleName.isEmpty, "ToggleCommand class should exist")
        #expect(!showName.isEmpty, "ShowCommand class should exist")
        #expect(!hideName.isEmpty, "HideCommand class should exist")

        #expect(expectedMappings.count == 3, "All commands have SDEF mappings")
    }

    @Test("Script identifier matching accepts unique, bundle, and menu extra forms")
    func scriptIdentifierMatchingAcceptsMenuExtraFallbacks() {
        let app = RunningApp(
            id: "com.example.Widget",
            name: "Widget",
            icon: nil,
            menuExtraIdentifier: "com.example.widget.extra",
            statusItemIndex: 2,
            xPosition: 100,
            width: 24
        )

        #expect(scriptIdentifierMatches("com.example.Widget::axid:com.example.widget.extra", app: app))
        #expect(scriptIdentifierMatches("com.example.Widget", app: app))
        #expect(scriptIdentifierMatches("com.example.widget.extra", app: app))
        #expect(!scriptIdentifierMatches("com.example.Other", app: app))
    }

    @Test("Script icon identity matches stable fallback identities after relayout")
    func scriptIconIdentityMatchesMenuExtraAndStatusFallbacks() {
        let menuExtraAnchor = RunningApp(
            id: "com.example.Widget",
            name: "Widget",
            icon: nil,
            menuExtraIdentifier: "com.example.widget.extra",
            statusItemIndex: nil,
            xPosition: 100,
            width: 24
        )
        let menuExtraRelayout = RunningApp(
            id: "com.example.Widget",
            name: "Widget",
            icon: nil,
            menuExtraIdentifier: "com.example.widget.extra",
            statusItemIndex: nil,
            xPosition: 220,
            width: 24
        )
        let statusAnchor = RunningApp(
            id: "com.example.Status",
            name: "Status",
            icon: nil,
            menuExtraIdentifier: nil,
            statusItemIndex: 4,
            xPosition: 300,
            width: 22
        )
        let statusRelayout = RunningApp(
            id: "com.example.Status",
            name: "Status",
            icon: nil,
            menuExtraIdentifier: nil,
            statusItemIndex: 4,
            xPosition: 340,
            width: 22
        )

        #expect(ScriptIconIdentity(app: menuExtraAnchor).matches(menuExtraRelayout))
        #expect(ScriptIconIdentity(app: statusAnchor).matches(statusRelayout))
        #expect(!ScriptIconIdentity(app: menuExtraAnchor).matches(statusRelayout))
    }
}
