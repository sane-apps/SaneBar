import Foundation
import AppKit

// MARK: - AppleScript Commands

/// Base class for SaneBar AppleScript commands
class SaneBarScriptCommand: NSScriptCommand {
    @MainActor
    var menuBarManager: MenuBarManager {
        MenuBarManager.shared
    }
}

// MARK: - Toggle Command

/// AppleScript command: tell application "SaneBar" to toggle
@objc(ToggleCommand)
final class ToggleCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            MenuBarManager.shared.toggleHiddenItems()
        }
        return nil
    }
}

// MARK: - Show Command

/// AppleScript command: tell application "SaneBar" to show
@objc(ShowCommand)
final class ShowCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            MenuBarManager.shared.showHiddenItems()
        }
        return nil
    }
}

// MARK: - Hide Command

/// AppleScript command: tell application "SaneBar" to hide
@objc(HideCommand)
final class HideCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            MenuBarManager.shared.hideHiddenItems()
        }
        return nil
    }
}
