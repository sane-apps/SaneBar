import AppKit
import Combine
import IOKit.ps

// MARK: - TriggerService

/// Service that monitors system events and triggers menu bar visibility
@MainActor
final class TriggerService: ObservableObject {

    // MARK: - Dependencies

    private weak var menuBarManager: MenuBarManager?
    private var cancellables = Set<AnyCancellable>()
    private var batteryCheckTimer: Timer?
    private var lastBatteryWarningLevel: IOPSLowBatteryWarningLevel = kIOPSLowBatteryWarningNone

    // MARK: - Initialization

    init() {
        setupAppLaunchObserver()
        setupBatteryMonitor()
    }

    // MARK: - Configuration

    func configure(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
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
              let bundleID = app.bundleIdentifier else {
            return
        }

        // Check if this app is in our trigger list
        if manager.settings.triggerApps.contains(bundleID) {
            print("[SaneBar] App trigger: \(bundleID) launched, showing hidden items")
            manager.showHiddenItems()
        }
    }

    // MARK: - Battery Monitor

    private func setupBatteryMonitor() {
        // Check battery level periodically (every 30 seconds)
        batteryCheckTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkBatteryLevel()
            }
        }
    }

    private func checkBatteryLevel() {
        guard let manager = menuBarManager else { return }
        guard manager.settings.showOnLowBattery else { return }

        let currentLevel = IOPSGetBatteryWarningLevel()

        // Trigger only on transition TO low battery (not every check)
        if currentLevel != kIOPSLowBatteryWarningNone && lastBatteryWarningLevel == kIOPSLowBatteryWarningNone {
            print("[SaneBar] Battery trigger: low battery detected, showing hidden items")
            manager.showHiddenItems()
        }

        lastBatteryWarningLevel = currentLevel
    }

    /// Call to clean up timer before deallocation
    func stopMonitoring() {
        batteryCheckTimer?.invalidate()
        batteryCheckTimer = nil
    }
}
