import AppKit
import Foundation
import os.log

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
