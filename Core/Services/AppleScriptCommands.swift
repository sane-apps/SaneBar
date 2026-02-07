import AppKit
import Foundation

// MARK: - AppleScript Commands

/// Base class for SaneBar AppleScript commands
class SaneBarScriptCommand: NSScriptCommand {
    /// Set AppleScript error when auth blocks the command
    func setAuthBlockedError() {
        scriptErrorNumber = errOSAGeneralError
        scriptErrorString = "Touch ID protection is enabled. Use the SaneBar menu bar icon to authenticate first."
    }

    /// Set AppleScript error when Accessibility permission is missing
    func setAccessibilityError() {
        scriptErrorNumber = errOSAGeneralError
        scriptErrorString = "Accessibility permission is required. Grant SaneBar access in System Settings > Privacy & Security > Accessibility."
    }

    /// Check if Accessibility permission is granted (safe to call from any thread)
    func checkAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Check if auth is required (main-thread safe without capturing self)
    func checkAuthRequired() -> Bool {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                MenuBarManager.shared.settings.requireAuthToShowHiddenIcons
            }
        } else {
            DispatchQueue.main.sync {
                MenuBarManager.shared.settings.requireAuthToShowHiddenIcons
            }
        }
    }

    /// Check if hidden items are currently hidden (main-thread safe)
    func checkIsHidden() -> Bool {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                MenuBarManager.shared.hidingService.state == .hidden
            }
        } else {
            DispatchQueue.main.sync {
                MenuBarManager.shared.hidingService.state == .hidden
            }
        }
    }
}

// MARK: - Toggle Command

/// AppleScript command: tell application "SaneBar" to toggle
@objc(ToggleCommand)
final class ToggleCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // Block if auth is required AND we'd be showing (expanding from hidden)
        // AppleScript can't prompt Touch ID, so we must block entirely
        if checkAuthRequired(), checkIsHidden() {
            setAuthBlockedError()
            return nil
        }
        Task { @MainActor in
            MenuBarManager.shared.toggleHiddenItems()
        }
        return nil
    }
}

// MARK: - Show Command

/// AppleScript command: tell application "SaneBar" to show hidden
@objc(ShowCommand)
final class ShowCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        // Only block if auth is required AND icons are currently hidden
        // (no need to block if they're already visible)
        if checkAuthRequired(), checkIsHidden() {
            setAuthBlockedError()
            return nil
        }
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
        return true
    }
}

// MARK: - Thread-Safe Box

/// Thread-safe box for passing values between Task closures and synchronous code.
/// The semaphore provides the synchronization guarantee.
private final class ScriptResultBox<T>: @unchecked Sendable {
    var value: T
    init(_ initial: T) { value = initial }
}

// MARK: - List Icons Command

/// AppleScript command: tell application "SaneBar" to list icons
/// Returns a newline-separated list of "uniqueId\tname" for each detected menu bar icon.
@objc(ListIconsCommand)
final class ListIconsCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard checkAccessibilityTrusted() else {
            setAccessibilityError()
            return nil
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ScriptResultBox("")

        Task { @MainActor in
            let items = await AccessibilityService.shared.listMenuBarItemsWithPositions()
            let lines = items.map { item in
                "\(item.app.uniqueId)\t\(item.app.name)"
            }
            box.value = lines.joined(separator: "\n")
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 5.0)
        return box.value
    }
}

// MARK: - Hide Icon Command

/// AppleScript command: tell application "SaneBar" to hide icon "com.example.app"
/// Pins the icon to the always-hidden section. Requires always-hidden section to be enabled.
@objc(HideIconCommand)
final class HideIconCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let iconId = directParameter as? String else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Expected an icon identifier string."
            return false
        }

        let trimmedId = iconId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Icon identifier cannot be empty."
            return false
        }

        guard checkAccessibilityTrusted() else {
            setAccessibilityError()
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ScriptResultBox(false)
        let alwaysHiddenEnabled = ScriptResultBox(false)
        let completed = ScriptResultBox(false)

        Task { @MainActor in
            let manager = MenuBarManager.shared
            alwaysHiddenEnabled.value = manager.settings.alwaysHiddenSectionEnabled

            guard manager.settings.alwaysHiddenSectionEnabled else {
                completed.value = true
                semaphore.signal()
                return
            }

            // Find the icon in current menu bar items
            let items = await AccessibilityService.shared.listMenuBarItemsWithPositions()
            let match = items.first { item in
                item.app.uniqueId == trimmedId || item.app.bundleId == trimmedId
            }

            if let match {
                manager.pinAlwaysHidden(app: match.app)
                manager.saveSettings()
                // Trigger enforcement to physically move the icon
                await manager.enforceAlwaysHiddenPinnedItems(reason: "AppleScript hide icon")
                box.value = true
            }

            completed.value = true
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10.0)

        guard completed.value else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Operation timed out. SaneBar may be busy — try again."
            return false
        }

        if !alwaysHiddenEnabled.value {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Always-hidden section is not enabled. Turn it on in SaneBar Settings > Advanced first."
            return false
        }

        if !box.value {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Icon '\(trimmedId)' not found. Use 'list icons' to see available identifiers."
        }

        return box.value
    }
}

// MARK: - Show Icon Command

/// AppleScript command: tell application "SaneBar" to show icon "com.example.app"
/// Unpins the icon from always-hidden so it returns to the normal hidden/visible section.
@objc(ShowIconCommand)
final class ShowIconCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let iconId = directParameter as? String else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Expected an icon identifier string."
            return false
        }

        let trimmedId = iconId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedId.isEmpty else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Icon identifier cannot be empty."
            return false
        }

        guard checkAccessibilityTrusted() else {
            setAccessibilityError()
            return false
        }

        let semaphore = DispatchSemaphore(value: 0)
        let box = ScriptResultBox(false)

        Task { @MainActor in
            let manager = MenuBarManager.shared

            // Check if this ID is currently pinned
            let pinnedIds = manager.settings.alwaysHiddenPinnedItemIds
            let matchedPin = pinnedIds.first { pinId in
                pinId == trimmedId || pinId.hasPrefix(trimmedId)
            }

            if let matchedPin {
                // Remove the pin
                manager.settings.alwaysHiddenPinnedItemIds = pinnedIds.filter { $0 != matchedPin }
                manager.saveSettings()

                // Move the icon to the visible zone
                let items = await AccessibilityService.shared.listMenuBarItemsWithPositions()
                if let match = items.first(where: { $0.app.uniqueId == matchedPin || $0.app.bundleId == trimmedId }) {
                    _ = await manager.moveIconAndWait(
                        bundleID: match.app.bundleId,
                        menuExtraId: match.app.menuExtraIdentifier,
                        statusItemIndex: match.app.statusItemIndex,
                        toHidden: false
                    )
                }
                box.value = true
            }

            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10.0)

        if !box.value {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Icon '\(trimmedId)' is not in the always-hidden section."
        }

        return box.value
    }
}
