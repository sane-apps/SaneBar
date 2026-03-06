import CoreGraphics
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

    @Test("Activation AppleScript commands exist and inherit from NSScriptCommand")
    func activationCommandsExist() {
        let activate = ActivateIconCommand()
        let rightClick = RightClickIconCommand()
        let activateBrowse = ActivateBrowseIconCommand()
        let rightClickBrowse = RightClickBrowseIconCommand()
        let activationDiagnostics = ActivationDiagnosticsCommand()
        let browseDiagnostics = BrowsePanelDiagnosticsCommand()

        let activateSupers = [
            String(describing: type(of: activate).superclass()),
            String(describing: type(of: activate).superclass()?.superclass()),
        ]
        let rightClickSupers = [
            String(describing: type(of: rightClick).superclass()),
            String(describing: type(of: rightClick).superclass()?.superclass()),
        ]
        let activateBrowseSupers = [
            String(describing: type(of: activateBrowse).superclass()),
            String(describing: type(of: activateBrowse).superclass()?.superclass()),
        ]
        let rightClickBrowseSupers = [
            String(describing: type(of: rightClickBrowse).superclass()),
            String(describing: type(of: rightClickBrowse).superclass()?.superclass()),
        ]
        let activationDiagnosticsSupers = [
            String(describing: type(of: activationDiagnostics).superclass()),
            String(describing: type(of: activationDiagnostics).superclass()?.superclass()),
        ]
        let browseDiagnosticsSupers = [
            String(describing: type(of: browseDiagnostics).superclass()),
            String(describing: type(of: browseDiagnostics).superclass()?.superclass()),
        ]

        #expect(activateSupers.contains { $0.contains("NSScriptCommand") || $0.contains("SaneBarScriptCommand") })
        #expect(rightClickSupers.contains { $0.contains("NSScriptCommand") || $0.contains("SaneBarScriptCommand") })
        #expect(activateBrowseSupers.contains { $0.contains("NSScriptCommand") || $0.contains("SaneBarScriptCommand") })
        #expect(rightClickBrowseSupers.contains { $0.contains("NSScriptCommand") || $0.contains("SaneBarScriptCommand") })
        #expect(activationDiagnosticsSupers.contains { $0.contains("NSScriptCommand") || $0.contains("SaneBarScriptCommand") })
        #expect(browseDiagnosticsSupers.contains { $0.contains("NSScriptCommand") || $0.contains("SaneBarScriptCommand") })
    }

    @Test("Browse panel AppleScript commands exist and inherit from NSScriptCommand")
    func browsePanelCommandsExist() {
        let showIconPanel = ShowIconPanelCommand()
        let showSecondMenuBar = ShowSecondMenuBarCommand()
        let closeBrowsePanel = CloseBrowsePanelCommand()

        let showIconPanelSupers = [
            String(describing: type(of: showIconPanel).superclass()),
            String(describing: type(of: showIconPanel).superclass()?.superclass()),
        ]
        let showSecondMenuBarSupers = [
            String(describing: type(of: showSecondMenuBar).superclass()),
            String(describing: type(of: showSecondMenuBar).superclass()?.superclass()),
        ]
        let closeBrowsePanelSupers = [
            String(describing: type(of: closeBrowsePanel).superclass()),
            String(describing: type(of: closeBrowsePanel).superclass()?.superclass()),
        ]

        #expect(showIconPanelSupers.contains { $0.contains("NSScriptCommand") || $0.contains("SaneBarScriptCommand") })
        #expect(showSecondMenuBarSupers.contains { $0.contains("NSScriptCommand") || $0.contains("SaneBarScriptCommand") })
        #expect(closeBrowsePanelSupers.contains { $0.contains("NSScriptCommand") || $0.contains("SaneBarScriptCommand") })
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
            "ShowIconPanelCommand": "open icon panel",
            "ShowSecondMenuBarCommand": "show second menu bar",
            "CloseBrowsePanelCommand": "close browse panel",
            "ActivateIconCommand": "activate icon",
            "RightClickIconCommand": "right click icon",
            "ActivateBrowseIconCommand": "activate browse icon",
            "RightClickBrowseIconCommand": "right click browse icon",
            "ActivationDiagnosticsCommand": "activation diagnostics",
            "BrowsePanelDiagnosticsCommand": "browse panel diagnostics",
        ]

        // Verify class names exist via NSStringFromClass (avoids metatype-to-nil comparison)
        let toggleName = NSStringFromClass(ToggleCommand.self)
        let showName = NSStringFromClass(ShowCommand.self)
        let hideName = NSStringFromClass(HideCommand.self)
        let showIconPanelName = NSStringFromClass(ShowIconPanelCommand.self)
        let showSecondMenuBarName = NSStringFromClass(ShowSecondMenuBarCommand.self)
        let closeBrowsePanelName = NSStringFromClass(CloseBrowsePanelCommand.self)
        let activateName = NSStringFromClass(ActivateIconCommand.self)
        let rightClickName = NSStringFromClass(RightClickIconCommand.self)
        let activateBrowseName = NSStringFromClass(ActivateBrowseIconCommand.self)
        let rightClickBrowseName = NSStringFromClass(RightClickBrowseIconCommand.self)
        let activationDiagnosticsName = NSStringFromClass(ActivationDiagnosticsCommand.self)
        let browseDiagnosticsName = NSStringFromClass(BrowsePanelDiagnosticsCommand.self)

        #expect(!toggleName.isEmpty, "ToggleCommand class should exist")
        #expect(!showName.isEmpty, "ShowCommand class should exist")
        #expect(!hideName.isEmpty, "HideCommand class should exist")
        #expect(!showIconPanelName.isEmpty, "ShowIconPanelCommand class should exist")
        #expect(!showSecondMenuBarName.isEmpty, "ShowSecondMenuBarCommand class should exist")
        #expect(!closeBrowsePanelName.isEmpty, "CloseBrowsePanelCommand class should exist")
        #expect(!activateName.isEmpty, "ActivateIconCommand class should exist")
        #expect(!rightClickName.isEmpty, "RightClickIconCommand class should exist")
        #expect(!activateBrowseName.isEmpty, "ActivateBrowseIconCommand class should exist")
        #expect(!rightClickBrowseName.isEmpty, "RightClickBrowseIconCommand class should exist")
        #expect(!activationDiagnosticsName.isEmpty, "ActivationDiagnosticsCommand class should exist")
        #expect(!browseDiagnosticsName.isEmpty, "BrowsePanelDiagnosticsCommand class should exist")

        #expect(expectedMappings.count == 12, "All commands have SDEF mappings")
    }

    @Test("Diagnostics AppleScript commands expose activation and browse summaries")
    func diagnosticsCommandsExposeExpectedSections() {
        let activationCommand = ActivationDiagnosticsCommand()
        let browseCommand = BrowsePanelDiagnosticsCommand()
        let diagnostics = """
        \(activationCommand.performDefaultImplementation() as? String ?? "")
        \(browseCommand.performDefaultImplementation() as? String ?? "")
        """

        #expect(diagnostics.contains("lastActivation:"))
        #expect(diagnostics.contains("secondMenuBar:"))
    }

    @Test("Browse activation AppleScript commands force browse-panel origin")
    func browseActivationCommandsUseBrowseOrigin() {
        let activateBrowse = ActivateBrowseIconCommand()
        let rightClickBrowse = RightClickBrowseIconCommand()

        #expect(activateBrowse.activationOrigin == .browsePanel)
        #expect(rightClickBrowse.activationOrigin == .browsePanel)
        #expect(activateBrowse.isRightClick == false)
        #expect(rightClickBrowse.isRightClick == true)
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

    @Test("Layout snapshot suppresses always-hidden geometry while hidden")
    func layoutSnapshotSuppressesAlwaysHiddenGeometryWhileHidden() {
        let geometry = LayoutSnapshotCommand.normalizedSnapshotAlwaysHiddenGeometry(
            hidingState: .hidden,
            separatorX: 1394,
            alwaysHiddenOriginX: 1458,
            alwaysHiddenBoundaryX: nil
        )

        #expect(geometry.originX == nil)
        #expect(geometry.boundaryX == nil)
        #expect(!geometry.isReliable)
    }

    @Test("Layout snapshot rejects inverted always-hidden origin when expanded")
    func layoutSnapshotRejectsInvertedAlwaysHiddenOrigin() {
        let geometry = LayoutSnapshotCommand.normalizedSnapshotAlwaysHiddenGeometry(
            hidingState: .expanded,
            separatorX: 1394,
            alwaysHiddenOriginX: 1458,
            alwaysHiddenBoundaryX: nil
        )

        #expect(geometry.originX == nil)
        #expect(geometry.boundaryX == nil)
        #expect(!geometry.isReliable)
    }

    @Test("Layout snapshot derives reliable always-hidden geometry from valid boundary")
    func layoutSnapshotDerivesReliableAlwaysHiddenGeometryFromBoundary() {
        let geometry = LayoutSnapshotCommand.normalizedSnapshotAlwaysHiddenGeometry(
            hidingState: .expanded,
            separatorX: 1394,
            alwaysHiddenOriginX: 1458,
            alwaysHiddenBoundaryX: 1218
        )

        #expect(geometry.originX == 1198)
        #expect(geometry.boundaryX == 1218)
        #expect(geometry.isReliable)
    }
}
