import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "FocusMode")


@MainActor
final class FocusModeService: NSObject {

    private var isMonitoring = false
    private weak var menuBarManager: MenuBarManager?
    private var monitoringTask: Task<Void, Never>?
    private var lastKnownFocusMode: String?

    private let assertionsPath = NSString("~/Library/DoNotDisturb/DB/Assertions.json").expandingTildeInPath

    private let configurationsPath = NSString("~/Library/DoNotDisturb/DB/ModeConfigurations.json").expandingTildeInPath

    var currentFocusMode: String? {
        readCurrentFocusModeName()
    }

    var isFocusModeActive: Bool {
        currentFocusMode != nil
    }


    func configure(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
    }


    func startMonitoring() {
        guard !isMonitoring else { return }

        isMonitoring = true
        let startingMode = currentFocusMode ?? "none"
        lastKnownFocusMode = currentFocusMode
        logger.info("Started Focus Mode monitoring. Current mode: \(startingMode)")

        monitoringTask = Task { [weak self] in
            let center = DistributedNotificationCenter.default()

            let dndNotifications = center.notifications(named: NSNotification.Name("com.apple.donotdisturb.stateChanged"))

            for await _ in dndNotifications {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    self?.handleFocusModeChange()
                }
            }
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        monitoringTask?.cancel()
        monitoringTask = nil

        isMonitoring = false
        logger.info("Stopped Focus Mode monitoring")
    }


    private func readCurrentFocusModeName() -> String? {
        guard let assertionsData = FileManager.default.contents(atPath: assertionsPath),
              let assertions = try? JSONSerialization.jsonObject(with: assertionsData) as? [[String: Any]],
              let firstAssertion = assertions.first,
              let details = firstAssertion["assertionDetails"] as? [String: Any],
              let modeIdentifier = details["assertionDetailsModeIdentifier"] as? String
        else {
            return nil
        }

        guard let configData = FileManager.default.contents(atPath: configurationsPath),
              let configurations = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
              let modeConfig = configurations[modeIdentifier] as? [String: Any],
              let mode = modeConfig["mode"] as? [String: Any],
              let modeName = mode["name"] as? String
        else {
            logger.debug("Found Focus identifier but couldn't resolve name: \(modeIdentifier)")
            return modeIdentifier
        }

        return modeName
    }


    private func handleFocusModeChange() {
        guard let manager = menuBarManager else { return }

        guard manager.settings.showOnFocusModeChange else { return }

        let newFocusMode = currentFocusMode

        guard newFocusMode != lastKnownFocusMode else {
            logger.debug("Focus notification received but mode unchanged")
            return
        }

        let oldMode = lastKnownFocusMode ?? "none"
        let newMode = newFocusMode ?? "none"
        lastKnownFocusMode = newFocusMode

        logger.info("Focus Mode changed: \(oldMode) → \(newMode)")

        let triggerModes = manager.settings.triggerFocusModes

        if let mode = newFocusMode, triggerModes.contains(mode) {
            logger.info("Focus '\(mode)' is in trigger list")
            manager.profileWorkflow.runTriggerAction(
                manager.settings.focusTriggerAction,
                profileId: manager.settings.focusTriggerProfileId,
                reason: "focus:\(mode)"
            )
        } else if newFocusMode == nil, triggerModes.contains("(Focus Off)") {
            logger.info("Focus turned off and '(Focus Off)' is in trigger list")
            manager.profileWorkflow.runTriggerAction(
                manager.settings.focusTriggerAction,
                profileId: manager.settings.focusTriggerProfileId,
                reason: "focus-off"
            )
        } else {
            logger.debug("Focus '\(newMode)' not in trigger list: \(triggerModes)")
        }
    }


    func getAvailableFocusModes() -> [String] {
        guard let configData = FileManager.default.contents(atPath: configurationsPath),
              let configurations = try? JSONSerialization.jsonObject(with: configData) as? [String: Any]
        else {
            return []
        }

        var modes: [String] = []
        for (_, value) in configurations {
            if let modeConfig = value as? [String: Any],
               let mode = modeConfig["mode"] as? [String: Any],
               let name = mode["name"] as? String {
                modes.append(name)
            }
        }

        return modes.sorted()
    }
}
