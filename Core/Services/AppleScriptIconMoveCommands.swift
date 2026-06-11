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

        if !moved, moveVerifiedByFreshExactZone(trimmedId: trimmedId, targetZone: targetZone) {
            return MoveOutcome(succeeded: true)
        }

        return MoveOutcome(succeeded: moved, failure: moved ? nil : .failed)
    }

    @MainActor
    private static func moveVerifiedByFreshExactZone(trimmedId: String, targetZone: ScriptIconZone) -> Bool {
        let zones = freshZonesForScriptMoveVerification(timeoutSeconds: 2.5)
        guard let resolved = resolveScriptIcon(trimmedId, from: zones) else {
            logger.warning("AppleScript move fallback could not resolve exact icon after failed move")
            return false
        }
        guard resolved.zone == targetZone else {
            logger.warning(
                "AppleScript move fallback exact-zone check failed: expected=\(targetZone.rawValue, privacy: .public) actual=\(resolved.zone.rawValue, privacy: .public)"
            )
            return false
        }

        logger.info("AppleScript move fallback accepted fresh exact-zone verification for target=\(targetZone.rawValue, privacy: .public)")
        return true
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
            let moved = runScriptMove {
                await manager.moveQueueWorkflow.moveIconAlwaysHiddenAndWait(
                    bundleID: icon.bundleId,
                    menuExtraId: icon.menuExtraIdentifier,
                    statusItemIndex: icon.statusItemIndex,
                    preferredCenterX: icon.preferredCenterX,
                    toAlwaysHidden: true,
                    physicalMoveOrigin: .appleScriptUserAction
                )
            }
            if moved == true {
                return true
            }

            logger.warning("AppleScript move-to-always-hidden direct drag failed; falling back to exact pin enforcement")
            _ = manager.alwaysHiddenPinWorkflow.pin(
                bundleID: icon.bundleId,
                menuExtraId: icon.menuExtraIdentifier,
                statusItemIndex: icon.statusItemIndex
            )
            manager.saveSettings()
            return runScriptMove {
                await manager.alwaysHiddenPinWorkflow.enforce(
                    reason: "AppleScript move icon to always hidden fallback",
                    filterBundleId: icon.bundleId,
                    mode: .repairWithPhysicalMoves,
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

// MARK: - Reorder Icon Commands

/// Shared target-relative reorder implementation for AppleScript commands.
class ReorderIconScriptCommand: SaneBarScriptCommand {
    private enum ReorderFailure {
        case sourceNotFound
        case targetNotFound
        case sameIcon
        case crossZone
        case timedOut
        case failed
    }

    private struct ReorderOutcome {
        var succeeded: Bool
        var failure: ReorderFailure?
    }

    var placeAfterTarget: Bool { false }

    override func performDefaultImplementation() -> Any? {
        guard let sourceId = parseIconIdentifier(directParameter) else {
            scriptErrorIconIdMissing(self)
            return false
        }

        guard let targetId = parseScriptReorderTargetIdentifier(from: self) else {
            scriptErrorTargetIconIdMissing(self)
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

        let placeAfterTarget = self.placeAfterTarget
        let outcome: ReorderOutcome = if Thread.isMainThread {
            MainActor.assumeIsolated {
                Self.performReorder(
                    sourceId: sourceId,
                    targetId: targetId,
                    placeAfterTarget: placeAfterTarget
                )
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    Self.performReorder(
                        sourceId: sourceId,
                        targetId: targetId,
                        placeAfterTarget: placeAfterTarget
                    )
                }
            }
        }

        guard outcome.succeeded else {
            switch outcome.failure {
            case .sourceNotFound:
                scriptErrorIconNotFound(self, iconId: sourceId)
            case .targetNotFound:
                scriptErrorTargetIconNotFound(self, iconId: targetId)
            case .sameIcon:
                scriptErrorSameSourceAndTargetIcon(self, iconId: sourceId)
            case .crossZone:
                scriptErrorCrossZoneReorder(self, sourceId: sourceId, targetId: targetId)
            case .timedOut:
                scriptErrorOperationTimedOut(self)
            case .failed, nil:
                scriptErrorReorderFailed(
                    self,
                    sourceId: sourceId,
                    targetId: targetId,
                    placeAfterTarget: placeAfterTarget
                )
            }
            return false
        }

        return true
    }

    @MainActor
    private static func performReorder(
        sourceId: String,
        targetId: String,
        placeAfterTarget: Bool
    ) -> ReorderOutcome {
        let manager = MenuBarManager.shared
        let startZones = zonesForScriptMoveResolution(sourceId)
        guard let source = resolveScriptIcon(sourceId, from: startZones) else {
            return ReorderOutcome(succeeded: false, failure: .sourceNotFound)
        }

        let targetZones = resolveScriptIcon(targetId, from: startZones) == nil
            ? zonesForScriptMoveResolution(targetId)
            : startZones
        guard let target = resolveScriptIcon(targetId, from: targetZones) else {
            return ReorderOutcome(succeeded: false, failure: .targetNotFound)
        }

        guard !scriptIconsReferToSameItem(source.app, target.app) else {
            return ReorderOutcome(succeeded: false, failure: .sameIcon)
        }
        guard source.zone == target.zone else {
            return ReorderOutcome(succeeded: false, failure: .crossZone)
        }

        logger.info(
            "AppleScript reorder request source=\(sourceId, privacy: .private) target=\(targetId, privacy: .private) relation=\(placeAfterTarget ? "after" : "before", privacy: .public)"
        )

        guard let moved = runScriptMove(operation: {
            guard let task = manager.moveQueueWorkflow.queueReorderIcon(
                sourceBundleID: source.app.bundleId,
                sourceMenuExtraID: source.app.menuExtraIdentifier,
                sourceStatusItemIndex: source.app.statusItemIndex,
                targetBundleID: target.app.bundleId,
                targetMenuExtraID: target.app.menuExtraIdentifier,
                targetStatusItemIndex: target.app.statusItemIndex,
                placeAfterTarget: placeAfterTarget,
                physicalMoveOrigin: .appleScriptUserAction
            ) else {
                return false
            }
            return await task.value
        }) else {
            return ReorderOutcome(succeeded: false, failure: .timedOut)
        }

        if !moved {
            logger.warning("AppleScript reorder task reported failure before fresh order verification")
        }

        if reorderVerifiedByFreshRelativeOrder(
            sourceId: sourceId,
            targetId: targetId,
            placeAfterTarget: placeAfterTarget
        ) {
            return ReorderOutcome(succeeded: true)
        }

        return ReorderOutcome(succeeded: false, failure: .failed)
    }

    @MainActor
    private static func reorderVerifiedByFreshRelativeOrder(
        sourceId: String,
        targetId: String,
        placeAfterTarget: Bool
    ) -> Bool {
        let zones = sortedScriptZones(freshZonesForScriptMoveVerification(timeoutSeconds: 2.5))
        guard let source = resolveScriptIcon(sourceId, from: zones),
              let target = resolveScriptIcon(targetId, from: zones) else {
            logger.warning("AppleScript reorder verification could not resolve fresh source/target")
            return false
        }
        guard source.zone == target.zone else {
            logger.warning("AppleScript reorder verification found source/target in different zones")
            return false
        }

        let sameZone = zones.filter { $0.zone == source.zone }
        guard let sourceIndex = sameZone.firstIndex(where: { scriptIconsReferToSameItem($0.app, source.app) }),
              let targetIndex = sameZone.firstIndex(where: { scriptIconsReferToSameItem($0.app, target.app) }) else {
            logger.warning("AppleScript reorder verification could not find fresh source/target indexes")
            return false
        }

        let expectedSourceIndex = placeAfterTarget ? targetIndex + 1 : targetIndex - 1
        let isAdjacent = sourceIndex == expectedSourceIndex
        if !isAdjacent {
            logger.warning(
                "AppleScript reorder verification failed sourceIndex=\(sourceIndex, privacy: .public) targetIndex=\(targetIndex, privacy: .public) relation=\(placeAfterTarget ? "after" : "before", privacy: .public)"
            )
        }
        return isAdjacent
    }
}

@objc(MoveIconBeforeCommand)
final class MoveIconBeforeCommand: ReorderIconScriptCommand {
    override var placeAfterTarget: Bool { false }
}

@objc(MoveIconAfterCommand)
final class MoveIconAfterCommand: ReorderIconScriptCommand {
    override var placeAfterTarget: Bool { true }
}
