import AppKit
import Foundation
import os.log

private struct ScriptIconGeometryFields {
    let x: String
    let width: String
    let centerX: String
    let dragSourceSafety: String
}

private func scriptIconGeometryFields(for item: ScriptZonedIcon) -> ScriptIconGeometryFields {
    guard let xPosition = item.app.xPosition,
          xPosition.isFinite else {
        return ScriptIconGeometryFields(
            x: "unknown",
            width: "unknown",
            centerX: "unknown",
            dragSourceSafety: "unknown"
        )
    }

    let resolvedWidth = max(item.app.width ?? 22, 1)
    let centerX = xPosition + (resolvedWidth / 2)
    guard let screen = NSScreen.screens.first(where: { screen in
        centerX >= screen.frame.minX - 2 && centerX <= screen.frame.maxX + 2
    }) else {
        return ScriptIconGeometryFields(
            x: String(format: "%.2f", Double(xPosition)),
            width: String(format: "%.2f", Double(resolvedWidth)),
            centerX: String(format: "%.2f", Double(centerX)),
            dragSourceSafety: "offscreen"
        )
    }
    let screenFrame = screen.frame
    let menuBandHeight = max(24, screen.safeAreaInsets.top + 24)
    let sourceFrame = CGRect(
        x: xPosition,
        y: screenFrame.maxY - menuBandHeight,
        width: resolvedWidth,
        height: menuBandHeight
    )
    let safeDragPoint = AccessibilityInteractionPolicy.notchSafeMenuBarDragPoint(
        for: sourceFrame,
        preferredScreenFrame: screen.frame,
        screens: NSScreen.screens
    )

    return ScriptIconGeometryFields(
        x: String(format: "%.2f", Double(xPosition)),
        width: String(format: "%.2f", Double(resolvedWidth)),
        centerX: String(format: "%.2f", Double(centerX)),
        dragSourceSafety: safeDragPoint == nil ? "unsafe" : "safe"
    )
}

// MARK: - List Icons Command

@objc(ListIconsCommand)
final class ListIconsCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard checkAccessibilityTrusted() else {
            setAccessibilityError()
            return nil
        }

        let apps: [RunningApp]? =
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    runScriptRead(timeoutSeconds: 15.0) {
                        await SearchService.shared.refreshMenuBarApps()
                    }
                }
            } else {
                DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        runScriptRead(timeoutSeconds: 15.0) {
                            await SearchService.shared.refreshMenuBarApps()
                        }
                    }
                }
            }

        guard let apps else {
            scriptErrorOperationTimedOut(self)
            return nil
        }

        let lines = apps.map { app in
            "\(app.uniqueId)\t\(app.name)"
        }
        return lines.joined(separator: "\n")
    }
}

// MARK: - List Icon Zones Command

@objc(ListIconZonesCommand)
final class ListIconZonesCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard checkAccessibilityTrusted() else {
            setAccessibilityError()
            return nil
        }

        let zones: [ScriptZonedIcon] = if Thread.isMainThread {
            MainActor.assumeIsolated {
                return scriptListingZonesForCommand()
            }
        } else {
            DispatchQueue.main.sync {
                return scriptListingZonesForCommand()
            }
        }

        let lines = zones.map { item in
            let movable = item.app.isUnmovableSystemItem ? "false" : "true"
            return "\(item.zone.rawValue)\t\(movable)\t\(item.app.bundleId)\t\(item.app.uniqueId)\t\(item.app.name)"
        }
        return lines.joined(separator: "\n")
    }
}

@objc(ListAuthoritativeIconZonesCommand)
final class ListAuthoritativeIconZonesCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard checkAccessibilityTrusted() else {
            setAccessibilityError()
            return nil
        }

        let zones: [ScriptZonedIcon] = if Thread.isMainThread {
            MainActor.assumeIsolated {
                return authoritativeScriptListingZonesForCommand()
            }
        } else {
            DispatchQueue.main.sync {
                return authoritativeScriptListingZonesForCommand()
            }
        }

        let lines = zones.map { item in
            let movable = item.app.isUnmovableSystemItem ? "false" : "true"
            return "\(item.zone.rawValue)\t\(movable)\t\(item.app.bundleId)\t\(item.app.uniqueId)\t\(item.app.name)"
        }
        return lines.joined(separator: "\n")
    }
}

@objc(ListIconZoneGeometryCommand)
final class ListIconZoneGeometryCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        guard checkAccessibilityTrusted() else {
            setAccessibilityError()
            return nil
        }

        let zones: [ScriptZonedIcon] = if Thread.isMainThread {
            MainActor.assumeIsolated {
                return authoritativeScriptListingZonesForCommand()
            }
        } else {
            DispatchQueue.main.sync {
                return authoritativeScriptListingZonesForCommand()
            }
        }

        let lines = zones.map { item in
            let movable = item.app.isUnmovableSystemItem ? "false" : "true"
            let geometry = scriptIconGeometryFields(for: item)
            return [
                item.zone.rawValue,
                movable,
                item.app.bundleId,
                item.app.uniqueId,
                geometry.x,
                geometry.width,
                geometry.centerX,
                geometry.dragSourceSafety,
                item.app.name
            ].joined(separator: "\t")
        }
        return lines.joined(separator: "\n")
    }
}
