import AppKit
import Combine
import IOKit.ps
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "TriggerService")

// MARK: - TriggerServiceProtocol

/// @mockable
@MainActor
protocol TriggerServiceProtocol {
    func configure(menuBarManager: MenuBarManager)
    func stopMonitoring()
}

// MARK: - TriggerService

/// Service that monitors system events and triggers menu bar visibility
@MainActor
final class TriggerService: ObservableObject, TriggerServiceProtocol {
    // MARK: - Dependencies

    private weak var menuBarManager: MenuBarManager?
    private var cancellables = Set<AnyCancellable>()
    private var batteryCheckTimer: Timer?
    private var wasBelowThreshold: Bool = false

    // MARK: - Initialization

    init() {
        setupAppLaunchObserver()
        // Note: Battery monitor is started lazily when settings enable it
    }

    // MARK: - Configuration

    func configure(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
        // Start battery monitoring only if enabled in settings
        if menuBarManager.settings.showOnLowBattery {
            startBatteryMonitor()
        }
    }

    /// Start or stop battery monitoring based on settings
    func updateBatteryMonitoring(enabled: Bool) {
        if enabled {
            startBatteryMonitor()
        } else {
            stopBatteryMonitor()
        }
    }

    private func startBatteryMonitor() {
        guard batteryCheckTimer == nil else { return } // Already running
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

    // MARK: - App Launch Observer

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

        // Get the launched app's bundle ID
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let bundleID = app.bundleIdentifier
        else {
            return
        }

        // Check if this app is in our trigger list
        if manager.settings.triggerApps.contains(bundleID) {
            logger.info("App trigger: \(bundleID) launched, showing hidden items")
            manager.showHiddenItems()
        }
    }

    // MARK: - Battery Monitor

    private func checkBatteryLevel() {
        guard let manager = menuBarManager else { return }
        guard manager.settings.showOnLowBattery else { return }

        let percentage = currentBatteryPercentage()
        guard percentage >= 0 else { return } // No battery info available

        let threshold = manager.settings.batteryThreshold
        let isBelowThreshold = percentage <= threshold

        // Trigger only on transition to below threshold (not every check)
        if isBelowThreshold, !wasBelowThreshold {
            logger.info("Battery trigger: \(percentage)% <= \(threshold)% threshold, showing hidden items")
            manager.showHiddenItems()
        }

        wasBelowThreshold = isBelowThreshold
    }

    /// Returns the current battery percentage (0-100), or -1 if unavailable.
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

    /// Call to clean up timer before deallocation
    func stopMonitoring() {
        stopBatteryMonitor()
    }
}
