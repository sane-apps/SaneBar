import AppKit
import Foundation
import os.log

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
    /// Set AppleScript error when a command requires Pro.
    func setProRequiredError() {
        scriptErrorNumber = errOSAGeneralError
        scriptErrorString = "This command requires SaneBar Pro. Basic can browse and click icons, but moving icons is Pro-only."
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
    /// Check whether Pro is unlocked (main-thread safe).
    func checkIsProUnlocked() -> Bool {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                LicenseService.shared.isPro
            }
        } else {
            DispatchQueue.main.sync {
                LicenseService.shared.isPro
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

enum ScriptSnapshotPathPolicy {
    enum ValidationError: LocalizedError {
        case empty
        case unsupportedExtension
        case outsideAllowedRoots(String)
        case invalidExistingTarget

        var errorDescription: String? {
            switch self {
            case .empty:
                "Expected a filesystem path string."
            case .unsupportedExtension:
                "Snapshot path must end in .png."
            case let .outsideAllowedRoots(roots):
                "Snapshot path must be under one of: \(roots)."
            case .invalidExistingTarget:
                "Snapshot target must not be a directory or symlink."
            }
        }
    }

    static func validatedOutputPath(from rawPath: String) throws -> String {
        let path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { throw ValidationError.empty }
        guard URL(fileURLWithPath: path).pathExtension.lowercased() == "png" else {
            throw ValidationError.unsupportedExtension
        }

        let fileManager = FileManager.default
        let expandedPath = (path as NSString).expandingTildeInPath
        let outputURL = URL(fileURLWithPath: expandedPath)
        let parentURL = outputURL.deletingLastPathComponent()

        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: outputURL.path, isDirectory: &isDirectory) {
            guard !isDirectory.boolValue else { throw ValidationError.invalidExistingTarget }
            if (try? fileManager.destinationOfSymbolicLink(atPath: outputURL.path)) != nil {
                throw ValidationError.invalidExistingTarget
            }
            let attributes = try fileManager.attributesOfItem(atPath: outputURL.path)
            guard attributes[.type] as? FileAttributeType != .typeSymbolicLink else {
                throw ValidationError.invalidExistingTarget
            }
        }

        let resolvedParent = parentURL.resolvingSymlinksInPath().standardizedFileURL.path
        let roots = allowedRoots().map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
        guard roots.contains(where: { resolvedParent == $0 || resolvedParent.hasPrefix("\($0)/") }) else {
            throw ValidationError.outsideAllowedRoots(roots.joined(separator: ", "))
        }

        return outputURL.standardizedFileURL.path
    }

    private static func allowedRoots() -> [URL] {
        [
            URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/Screenshots", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Caches/com.sanebar.app", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("SaneApps/apps/SaneBar/outputs/customer-ui", isDirectory: true)
        ]
    }
}

private extension SaneBarScriptCommand {
    func validatedSnapshotPath() -> String? {
        guard let rawPath = directParameter as? String else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Expected a filesystem path string."
            return nil
        }

        do {
            return try ScriptSnapshotPathPolicy.validatedOutputPath(from: rawPath)
        } catch {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = error.localizedDescription
            return nil
        }
    }
}

@MainActor
func runScriptRead<T>(
    timeoutSeconds: TimeInterval = 15.0,
    operation: @escaping @MainActor () async -> T
) -> T? {
    let box = ScriptResultBox<T?>(nil)
    Task { @MainActor in
        box.value = await operation()
    }

    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while box.value == nil, Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }

    return box.value
}

// MARK: - Toggle Command
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
            MenuBarManager.shared.visibilityWorkflow.toggleHiddenItems()
        }
        return nil
    }
}
// MARK: - Show Command
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
            MenuBarManager.shared.visibilityWorkflow.showHiddenItems()
        }
        return nil
    }
}
// MARK: - Hide Command
@objc(HideCommand)
final class HideCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            MenuBarManager.shared.visibilityWorkflow.hideHiddenItems()
        }
        return true
    }
}
// MARK: - Browse Panel Commands
@objc(ShowIconPanelCommand)
final class ShowIconPanelCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        if checkAuthRequired(), checkIsHidden() {
            setAuthBlockedError()
            return nil
        }
        Task { @MainActor in
            let manager = MenuBarManager.shared
            _ = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .search)
            SearchWindowController.shared.show(mode: .findIcon)
        }
        return true
    }
}

@objc(QuickSearchCommand)
final class QuickSearchCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let query = (directParameter as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if checkAuthRequired(), checkIsHidden() {
            setAuthBlockedError()
            return nil
        }
        Task { @MainActor in
            let manager = MenuBarManager.shared
            _ = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .search)
            SearchWindowController.shared.show(mode: .findIcon, prefill: query?.isEmpty == false ? query : nil)
        }
        return true
    }
}

@objc(ShowSecondMenuBarCommand)
final class ShowSecondMenuBarCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        if checkAuthRequired(), checkIsHidden() {
            setAuthBlockedError()
            return nil
        }
        Task { @MainActor in
            let manager = MenuBarManager.shared
            _ = await manager.visibilityWorkflow.showHiddenItemsNow(trigger: .search)
            SearchWindowController.shared.show(mode: .secondMenuBar)
        }
        return true
    }
}
@objc(CloseBrowsePanelCommand)
final class CloseBrowsePanelCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            SearchWindowController.shared.close()
        }
        return true
    }
}

@objc(OpenSettingsWindowCommand)
final class OpenSettingsWindowCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            SettingsOpener.open()
        }
        return true
    }
}

@objc(CloseSettingsWindowCommand)
final class CloseSettingsWindowCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        Task { @MainActor in
            SettingsOpener.close()
        }
        return true
    }
}

@objc(CaptureBrowsePanelSnapshotCommand)
final class CaptureBrowsePanelSnapshotCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let path = validatedSnapshotPath() else { return nil }

        let didCapture: Bool = if Thread.isMainThread {
            MainActor.assumeIsolated {
                SearchWindowController.shared.captureBrowsePanelSnapshotPNG(to: path)
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    SearchWindowController.shared.captureBrowsePanelSnapshotPNG(to: path)
                }
            }
        }

        guard didCapture else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Browse panel snapshot failed. Make sure the panel is visible first."
            return nil
        }

        return true
    }
}

@objc(CaptureSettingsWindowSnapshotCommand)
final class CaptureSettingsWindowSnapshotCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let path = validatedSnapshotPath() else { return nil }

        let didCapture: Bool = if Thread.isMainThread {
            MainActor.assumeIsolated {
                let box = ScriptResultBox<Bool?>(nil)
                Task { @MainActor in
                    box.value = await SettingsOpener.captureSnapshotPNG(to: path)
                }

                let deadline = Date().addingTimeInterval(20.0)
                while box.value == nil, Date() < deadline {
                    _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                }

                return box.value ?? false
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    let box = ScriptResultBox<Bool?>(nil)
                    Task { @MainActor in
                        box.value = await SettingsOpener.captureSnapshotPNG(to: path)
                    }

                    let deadline = Date().addingTimeInterval(20.0)
                    while box.value == nil, Date() < deadline {
                        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
                    }

                    return box.value ?? false
                }
            }
        }

        guard didCapture else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Settings snapshot failed. Make sure the settings window is visible first."
            return nil
        }

        return true
    }
}

@objc(CaptureAppearanceOverlaySnapshotCommand)
final class CaptureAppearanceOverlaySnapshotCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let path = validatedSnapshotPath() else { return nil }

        let didCapture: Bool = if Thread.isMainThread {
            MainActor.assumeIsolated {
                MenuBarManager.shared.appearanceService.captureSnapshotPNG(to: path)
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    MenuBarManager.shared.appearanceService.captureSnapshotPNG(to: path)
                }
            }
        }

        guard didCapture else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Appearance overlay snapshot failed. Make sure the custom appearance overlay is visible first."
            return nil
        }

        return true
    }
}

@objc(QueueBrowsePanelSnapshotCommand)
final class QueueBrowsePanelSnapshotCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let path = validatedSnapshotPath() else { return nil }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            _ = SearchWindowController.shared.captureBrowsePanelSnapshotPNG(to: path)
        }
        return true
    }
}

@objc(QueueSettingsWindowSnapshotCommand)
final class QueueSettingsWindowSnapshotCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard let path = validatedSnapshotPath() else { return nil }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            _ = await SettingsOpener.captureSnapshotPNG(to: path)
        }
        return true
    }
}
// MARK: - Thread-Safe Box
/// Thread-safe box for passing values between Task closures and synchronous code.
/// The semaphore provides the synchronization guarantee.
final class ScriptResultBox<T>: @unchecked Sendable {
    var value: T
    init(_ initial: T) { value = initial }
}
