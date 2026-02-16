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
    private var lastBatteryWarningLevel: IOPSLowBatteryWarningLevel = kIOPSLowBatteryWarningNone

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

        let currentLevel = IOPSGetBatteryWarningLevel()

        // Trigger only on transition TO low battery (not every check)
        if currentLevel != kIOPSLowBatteryWarningNone, lastBatteryWarningLevel == kIOPSLowBatteryWarningNone {
            logger.info("Battery trigger: low battery detected, showing hidden items")
            manager.showHiddenItems()
        }

        lastBatteryWarningLevel = currentLevel
    }

    /// Call to clean up timer before deallocation
    func stopMonitoring() {
        stopBatteryMonitor()
    }
}
