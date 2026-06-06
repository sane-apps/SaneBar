import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "AppleScriptCommands")

// MARK: - Hide Icon Command

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
        let completed = ScriptResultBox(false)

        Task { @MainActor in
            let manager = MenuBarManager.shared

            // Find the icon in current menu bar items
            let items = await AccessibilityService.shared.listMenuBarItemsWithPositions()
            let match = items.first { item in
                item.app.uniqueId == trimmedId || item.app.bundleId == trimmedId
            }

            if let match {
                manager.alwaysHiddenPinWorkflow.pin(app: match.app)
                manager.saveSettings()
                // Trigger enforcement to physically move the icon
                await manager.alwaysHiddenPinWorkflow.enforce(
                    reason: "AppleScript hide icon",
                    mode: .repairWithPhysicalMoves,
                    physicalMoveOrigin: .appleScriptUserAction
                )
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

        if !box.value {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Icon '\(trimmedId)' not found. Use 'list icons' to see available identifiers."
        }

        return box.value
    }
}

// MARK: - Show Icon Command

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
        let completed = ScriptResultBox(false)

        Task { @MainActor in
            let manager = MenuBarManager.shared

            let startZones = zonesForScriptMoveResolution(trimmedId)
            guard let source = resolveScriptIcon(trimmedId, from: startZones),
                  source.zone == .alwaysHidden else {
                completed.value = true
                semaphore.signal()
                return
            }

            let moved = await manager.moveQueueWorkflow.moveIconAlwaysHiddenAndWait(
                bundleID: source.app.bundleId,
                menuExtraId: source.app.menuExtraIdentifier,
                statusItemIndex: source.app.statusItemIndex,
                preferredCenterX: source.app.preferredCenterX,
                toAlwaysHidden: false,
                physicalMoveOrigin: .appleScriptUserAction
            )
            guard moved else {
                completed.value = true
                semaphore.signal()
                return
            }

            let removedPin = manager.alwaysHiddenPinWorkflow.unpin(
                bundleID: source.app.bundleId,
                menuExtraId: source.app.menuExtraIdentifier,
                statusItemIndex: source.app.statusItemIndex
            ) || (!source.app.bundleId.hasPrefix("com.apple.controlcenter") &&
                manager.alwaysHiddenPinWorkflow.unpin(bundleID: source.app.bundleId))
            if removedPin {
                manager.saveSettings()
            }

            box.value = true
            completed.value = true
            semaphore.signal()
        }

        _ = semaphore.wait(timeout: .now() + 10.0)

        guard completed.value else {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Operation timed out. SaneBar may be busy — try again."
            return false
        }

        if !box.value {
            scriptErrorNumber = errOSAGeneralError
            scriptErrorString = "Icon '\(trimmedId)' is not in the always-hidden section."
        }

        return box.value
    }
}

// MARK: - Move Icon Commands

/// Shared move-icon implementation for AppleScript commands.
class MoveIconScriptCommand: SaneBarScriptCommand {
    private enum MoveFailure {
        case notFound
        case timedOut
        case failed
    }

    private struct MoveOutcome {
        var succeeded: Bool
        var skipZoneWait: Bool = false
        var failure: MoveFailure?
    }

    var targetZone: ScriptIconZone { .visible }

    override func performDefaultImplementation() -> Any? {
        guard let trimmedId = parseIconIdentifier(directParameter) else {
            scriptErrorIconIdMissing(self)
            return false
        }

        guard checkIsProUnlocked() else {
            setProRequiredError()
            return false
        }

        guard checkAccessibilityTrusted() else {
            setAccessibilityError()
            return false
        }
        let targetZone = self.targetZone
        let outcome: MoveOutcome = if Thread.isMainThread {
            MainActor.assumeIsolated {
                Self.performMove(trimmedId: trimmedId, targetZone: targetZone)
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    Self.performMove(trimmedId: trimmedId, targetZone: targetZone)
                }
            }
        }

        guard outcome.succeeded else {
            if outcome.failure == .notFound {
                scriptErrorIconNotFound(self, iconId: trimmedId)
            } else if outcome.failure == .timedOut {
                scriptErrorOperationTimedOut(self)
            } else {
                scriptErrorMoveFailed(self, iconId: trimmedId, target: targetZone)
            }
            return false
        }

        if outcome.skipZoneWait {
            return true
        }

        return true
    }

    @MainActor
    private static func performMove(trimmedId: String, targetZone: ScriptIconZone) -> MoveOutcome {
        let manager = MenuBarManager.shared
        let startZones = zonesForScriptMoveResolution(trimmedId)
        guard let source = resolveScriptIcon(trimmedId, from: startZones) else {
            return MoveOutcome(succeeded: false, failure: .notFound)
        }

        let icon = source.app
        let sourceZone = source.zone
        logger.info(
            "AppleScript move request id=\(trimmedId, privacy: .private) sourceZone=\(sourceZone.rawValue, privacy: .public) targetZone=\(targetZone.rawValue, privacy: .public)"
        )

        if sourceZone == targetZone {
            if targetZone == .alwaysHidden {
                if !manager.settings.alwaysHiddenSectionEnabled {
                    manager.settings.alwaysHiddenSectionEnabled = true
                }
                manager.alwaysHiddenPinWorkflow.pin(app: icon)
                manager.saveSettings()
            }
            return MoveOutcome(succeeded: true, skipZoneWait: true)
        }

        guard let moved = performMove(icon: icon, from: sourceZone, to: targetZone, manager: manager) else {
            return MoveOutcome(succeeded: false, failure: .timedOut)
        }

        return MoveOutcome(succeeded: moved, failure: moved ? nil : .failed)
    }

    @MainActor
    private static func performMove(
        icon: RunningApp,
        from sourceZone: ScriptIconZone,
        to targetZone: ScriptIconZone,
        manager: MenuBarManager
    ) -> Bool? {
        switch targetZone {
        case .alwaysHidden:
            if !manager.settings.alwaysHiddenSectionEnabled {
                manager.settings.alwaysHiddenSectionEnabled = true
            }
            manager.saveSettings()
            return runScriptMove {
                await manager.moveQueueWorkflow.moveIconAlwaysHiddenAndWait(
                    bundleID: icon.bundleId,
                    menuExtraId: icon.menuExtraIdentifier,
                    statusItemIndex: icon.statusItemIndex,
                    preferredCenterX: icon.preferredCenterX,
                    toAlwaysHidden: true,
                    physicalMoveOrigin: .appleScriptUserAction
                )
            }

        case .hidden:
            switch sourceZone {
            case .alwaysHidden:
                return runScriptMove {
                    await manager.moveQueueWorkflow.moveIconFromAlwaysHiddenToHiddenAndWait(
                        bundleID: icon.bundleId,
                        menuExtraId: icon.menuExtraIdentifier,
                        statusItemIndex: icon.statusItemIndex,
                        preferredCenterX: icon.preferredCenterX,
                        physicalMoveOrigin: .appleScriptUserAction
                    )
                }
            case .visible:
                return runScriptMove {
                    await manager.moveQueueWorkflow.moveIconAndWait(
                        bundleID: icon.bundleId,
                        menuExtraId: icon.menuExtraIdentifier,
                        statusItemIndex: icon.statusItemIndex,
                        preferredCenterX: icon.preferredCenterX,
                        toHidden: true,
                        physicalMoveOrigin: .appleScriptUserAction
                    )
                }
            case .hidden:
                return true
            }

        case .visible:
            switch sourceZone {
            case .alwaysHidden:
                return runScriptMove {
                    await manager.moveQueueWorkflow.moveIconAlwaysHiddenAndWait(
                        bundleID: icon.bundleId,
                        menuExtraId: icon.menuExtraIdentifier,
                        statusItemIndex: icon.statusItemIndex,
                        preferredCenterX: icon.preferredCenterX,
                        toAlwaysHidden: false,
                        physicalMoveOrigin: .appleScriptUserAction
                    )
                }
            case .hidden:
                return runScriptMove {
                    await manager.moveQueueWorkflow.moveIconAndWait(
                        bundleID: icon.bundleId,
                        menuExtraId: icon.menuExtraIdentifier,
                        statusItemIndex: icon.statusItemIndex,
                        preferredCenterX: icon.preferredCenterX,
                        toHidden: false,
                        physicalMoveOrigin: .appleScriptUserAction
                    )
                }
            case .visible:
                return true
            }
        }
    }
}

@objc(MoveIconToHiddenCommand)
final class MoveIconToHiddenCommand: MoveIconScriptCommand {
    override var targetZone: ScriptIconZone { .hidden }
}

@objc(MoveIconToVisibleCommand)
final class MoveIconToVisibleCommand: MoveIconScriptCommand {
    override var targetZone: ScriptIconZone { .visible }
}

@objc(MoveIconToAlwaysHiddenCommand)
final class MoveIconToAlwaysHiddenCommand: MoveIconScriptCommand {
    override var targetZone: ScriptIconZone { .alwaysHidden }
}
