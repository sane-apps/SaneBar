import AppKit
import Combine

// MARK: - TriggerService

/// Service that monitors system events and triggers menu bar visibility
@MainActor
final class TriggerService: ObservableObject {

    // MARK: - Dependencies

    private weak var menuBarManager: MenuBarManager?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init() {
        setupAppLaunchObserver()
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
}
