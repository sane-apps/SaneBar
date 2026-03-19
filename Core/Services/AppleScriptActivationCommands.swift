import AppKit
import Foundation

@MainActor
func scriptCombinedDiagnosticsSnapshot() -> String {
    let activation = SearchService.shared.diagnosticsSnapshot()
    let browse = SearchWindowController.shared.diagnosticsSnapshot()
    return "\(activation)\n\(browse)"
}

@MainActor
private func performScriptActivation(
    app: RunningApp,
    isRightClick: Bool,
    activationOrigin: SearchService.ActivationOrigin
) async {
    await SearchService.shared.activate(
        app: app,
        isRightClick: isRightClick,
        origin: activationOrigin
    )
}

private enum ScriptActivationOutcome: Sendable {
    case success(String)
    case notFound
}

@MainActor
private func runScriptActivation(
    timeoutSeconds: TimeInterval = 20.0,
    operation: @escaping @MainActor () async -> ScriptActivationOutcome
) -> ScriptActivationOutcome? {
    let box = ScriptResultBox<ScriptActivationOutcome?>(nil)
    Task { @MainActor in
        box.value = await operation()
    }

    let deadline = Date().addingTimeInterval(timeoutSeconds)
    while box.value == nil, Date() < deadline {
        _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    return box.value
}

// MARK: - Activation Diagnostics Commands

@objc(ActivationDiagnosticsCommand)
final class ActivationDiagnosticsCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                SearchService.shared.diagnosticsSnapshot()
            }
        }

        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                SearchService.shared.diagnosticsSnapshot()
            }
        }
    }
}

@objc(BrowsePanelDiagnosticsCommand)
final class BrowsePanelDiagnosticsCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                SearchWindowController.shared.diagnosticsSnapshot()
            }
        }

        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                SearchWindowController.shared.diagnosticsSnapshot()
            }
        }
    }
}

// MARK: - Activate Icon Commands

class ActivateIconScriptCommand: SaneBarScriptCommand {
    var isRightClick: Bool { false }
    var activationOrigin: SearchService.ActivationOrigin { .automation }

    override func performDefaultImplementation() -> Any? {
        guard let trimmedId = parseIconIdentifier(directParameter) else {
            scriptErrorIconIdMissing(self)
            return nil
        }

        guard checkAccessibilityTrusted() else {
            setAccessibilityError()
            return nil
        }
        let isRightClick = self.isRightClick
        let activationOrigin = self.activationOrigin
        let result: ScriptActivationOutcome? =
            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    runScriptActivation {
                        let zones = zonesForScriptResolution(trimmedId)
                        guard let match = resolveScriptIcon(trimmedId, from: zones) else {
                            return .notFound
                        }

                        await performScriptActivation(
                            app: match.app,
                            isRightClick: isRightClick,
                            activationOrigin: activationOrigin
                        )
                        return .success(scriptCombinedDiagnosticsSnapshot())
                    }
                }
            } else {
                DispatchQueue.main.sync {
                    MainActor.assumeIsolated {
                        runScriptActivation {
                        let zones = zonesForScriptResolution(trimmedId)
                        guard let match = resolveScriptIcon(trimmedId, from: zones) else {
                            return .notFound
                        }

                        await performScriptActivation(
                            app: match.app,
                            isRightClick: isRightClick,
                            activationOrigin: activationOrigin
                        )
                        return .success(scriptCombinedDiagnosticsSnapshot())
                    }
                }
            }
            }

        guard let result else {
            scriptErrorOperationTimedOut(self)
            return nil
        }

        switch result {
        case .success(let diagnostics):
            return diagnostics
        case .notFound:
            scriptErrorIconNotFound(self, iconId: trimmedId)
            return nil
        }
    }
}

@objc(ActivateIconCommand)
final class ActivateIconCommand: ActivateIconScriptCommand {}

@objc(RightClickIconCommand)
final class RightClickIconCommand: ActivateIconScriptCommand {
    override var isRightClick: Bool { true }
}

@objc(ActivateBrowseIconCommand)
final class ActivateBrowseIconCommand: ActivateIconScriptCommand {
    override var activationOrigin: SearchService.ActivationOrigin { .browsePanel }
}

@objc(RightClickBrowseIconCommand)
final class RightClickBrowseIconCommand: ActivateIconScriptCommand {
    override var isRightClick: Bool { true }
    override var activationOrigin: SearchService.ActivationOrigin { .browsePanel }
}
