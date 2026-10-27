import AppKit
import Combine
import IOKit.ps
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "TriggerService")


@MainActor
protocol TriggerServiceProtocol {
    func configure(menuBarManager: MenuBarManager)
    func stopMonitoring()
}


@MainActor
final class TriggerService: ObservableObject, TriggerServiceProtocol {

    private weak var menuBarManager: MenuBarManager?
    private var cancellables = Set<AnyCancellable>()
    private var batteryCheckTimer: Timer?
    private var wasBelowThreshold: Bool = false


    init() {
        setupAppLaunchObserver()
    }


    func configure(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
        if menuBarManager.settings.showOnLowBattery {
            startBatteryMonitor()
        }
    }

    func updateBatteryMonitoring(enabled: Bool) {
        if enabled {
            startBatteryMonitor()
        } else {
            stopBatteryMonitor()
        }
    }

    private func startBatteryMonitor() {
        guard batteryCheckTimer == nil else { return }
        logger.info("Starting battery monitor")
        batteryCheckTimer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkBatteryLevel()
            }
        }
    }

    private func stopBatteryMonitor() {
        batteryCheckTimer?.invalidate()
        batteryCheckTimer = nil
        logger.info("Stopped battery monitor")
    }


    private func setupAppLaunchObserver() {
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didLaunchApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.handleAppLaunch(notification)
            }
            .store(in: &cancellables)
    }

    private func handleAppLaunch(_ notification: Notification) {
        guard let manager = menuBarManager else { return }
        guard manager.settings.showOnAppLaunch else { return }

        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier
        else {
            return
        }

        if manager.settings.triggerApps.contains(bundleID) {
            logger.info("App trigger: \(bundleID) launched")
            manager.profileWorkflow.runTriggerAction(
                manager.settings.appLaunchTriggerAction,
                profileId: manager.settings.appLaunchTriggerProfileId,
                reason: "app-launch:\(bundleID)"
            )
        }
    }


    private func checkBatteryLevel() {
        guard let manager = menuBarManager else { return }
        guard manager.settings.showOnLowBattery else { return }

        let percentage = currentBatteryPercentage()
        guard percentage >= 0 else { return }

        let threshold = manager.settings.batteryThreshold
        let isBelowThreshold = percentage <= threshold

        if isBelowThreshold, !wasBelowThreshold {
            logger.info("Battery trigger: \(percentage)% <= \(threshold)% threshold")
            manager.profileWorkflow.runTriggerAction(
                manager.settings.batteryTriggerAction,
                profileId: manager.settings.batteryTriggerProfileId,
                reason: "battery"
            )
        }

        wasBelowThreshold = isBelowThreshold
    }

    private func currentBatteryPercentage() -> Int {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [Any],
              let first = sources.first
        else {
            return -1
        }
        guard let description = IOPSGetPowerSourceDescription(snapshot, first as CFTypeRef)?.takeUnretainedValue() as? [String: Any],
              let currentCapacity = description[kIOPSCurrentCapacityKey as String] as? Int,
              let maxCapacity = description[kIOPSMaxCapacityKey as String] as? Int,
              maxCapacity > 0
        else {
            return -1
        }
        return (currentCapacity * 100) / maxCapacity
    }

    func stopMonitoring() {
        stopBatteryMonitor()
    }
}
