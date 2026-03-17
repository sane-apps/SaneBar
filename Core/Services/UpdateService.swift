import AppKit
import Foundation
import UserNotifications
import os.log
import SaneUI
#if !SETAPP
    @preconcurrency import Sparkle
#endif

private let logger = Logger(subsystem: "com.sanebar.app", category: "UpdateService")

enum UpdateCheckFrequency: String, CaseIterable, Identifiable {
    case daily
    case weekly

    var id: String { rawValue }

    var title: String {
        switch self {
        case .daily: "Daily"
        case .weekly: "Weekly"
        }
    }

    var interval: TimeInterval {
        switch self {
        case .daily: 60 * 60 * 24
        case .weekly: 60 * 60 * 24 * 7
        }
    }

    static func resolve(updateCheckInterval: TimeInterval) -> Self {
        let threshold = (Self.daily.interval + Self.weekly.interval) / 2
        return updateCheckInterval >= threshold ? .weekly : .daily
    }

    static func normalizedInterval(from updateCheckInterval: TimeInterval) -> TimeInterval {
        resolve(updateCheckInterval: updateCheckInterval).interval
    }
}

#if !SETAPP

    /// Wrapper around Sparkle's SPUStandardUpdaterController.
    /// Handles app updates securely and privately.
    @MainActor
    class UpdateService: NSObject, ObservableObject {

    // MARK: - Properties

    nonisolated static let releaseBundleIdentifier = "com.sanebar.app"
    nonisolated static let scheduledUpdateReminderNotificationID = "com.sanebar.app.sparkle.scheduled-update"

    private var updaterController: SPUStandardUpdaterController?
    private let updateChannelEnabled: Bool
    private var scheduledUpdateReminderActive = false

    // MARK: - Initialization

    override init() {
        self.updateChannelEnabled = Self.supportsSparkleUpdates(bundleIdentifier: Bundle.main.bundleIdentifier)
        super.init()

        guard updateChannelEnabled else {
            let bundleID = Bundle.main.bundleIdentifier ?? "unknown"
            logger.info("Sparkle disabled for non-release bundle id: \(bundleID, privacy: .public)")
            return
        }

        // SPUStandardUpdaterController must be retained by the app.
        // startingUpdater: true starts the scheduled checks logic immediately.
        self.updaterController = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        normalizeUpdateCheckFrequency()

        logger.info("Sparkle updater initialized")

        // Privacy check (Sanity check for developers)
        if let profiling = Bundle.main.object(forInfoDictionaryKey: "SUEnableSystemProfiling") as? Bool, profiling == true {
            logger.fault("CRITICAL: SUEnableSystemProfiling is ENABLED. This violates the privacy policy.")
        }
    }

    // MARK: - Public API

    /// Trigger a user-initiated update check.
    /// This shows the Sparkle UI (Standard User Driver).
    func checkForUpdates() {
        guard updateChannelEnabled else {
            logger.info("Ignoring Check for Updates on non-release build")
            NSSound.beep()
            return
        }
        clearScheduledUpdateReminder(reason: "manual_check")
        logger.info("User triggered check for updates")
        updaterController?.checkForUpdates(nil)
    }

    /// Check if updates are handled automatically (just a pass-through property for UI if needed)
    var automaticallyChecksForUpdates: Bool {
        get { updateChannelEnabled && (updaterController?.updater.automaticallyChecksForUpdates ?? false) }
        set {
            guard updateChannelEnabled else { return }
            updaterController?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var updateCheckFrequency: UpdateCheckFrequency {
        get {
            let interval = updaterController?.updater.updateCheckInterval ?? UpdateCheckFrequency.daily.interval
            return UpdateCheckFrequency.resolve(updateCheckInterval: interval)
        }
        set {
            guard updateChannelEnabled else { return }
            updaterController?.updater.updateCheckInterval = newValue.interval
        }
    }

    var isUpdateChannelEnabled: Bool { updateChannelEnabled }

    nonisolated static func supportsSparkleUpdates(bundleIdentifier: String?) -> Bool {
        #if APP_STORE
            false
        #else
            bundleIdentifier == releaseBundleIdentifier
        #endif
    }

    nonisolated static func shouldShowScheduledUpdateDockBadge(showDockIcon: Bool) -> Bool {
        showDockIcon
    }

    private func normalizeUpdateCheckFrequency() {
        guard let updater = updaterController?.updater else { return }
        updater.updateCheckInterval = UpdateCheckFrequency.normalizedInterval(from: updater.updateCheckInterval)
    }

    private func presentScheduledUpdateReminder(for update: SUAppcastItem) {
        guard !scheduledUpdateReminderActive else { return }
        scheduledUpdateReminderActive = true

        if Self.shouldShowScheduledUpdateDockBadge(showDockIcon: MenuBarManager.shared.settings.showDockIcon) {
            NSApp.setActivationPolicy(.regular)
            NSApp.dockTile.badgeLabel = "1"
        } else {
            NSApp.dockTile.badgeLabel = nil
        }

        Task {
            let center = UNUserNotificationCenter.current()
            let granted = try? await center.requestAuthorization(options: [.alert, .sound])
            guard granted == true else { return }

            let content = UNMutableNotificationContent()
            content.title = "SaneBar update ready"
            content.body = "Version \(update.displayVersionString) is ready to install."
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: Self.scheduledUpdateReminderNotificationID,
                content: content,
                trigger: nil
            )
            try? await center.add(request)
        }
    }

    private func clearScheduledUpdateReminder(reason: StaticString) {
        guard scheduledUpdateReminderActive else { return }
        scheduledUpdateReminderActive = false
        NSApp.dockTile.badgeLabel = nil
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [Self.scheduledUpdateReminderNotificationID])
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.scheduledUpdateReminderNotificationID])
        SaneActivationPolicy.restorePolicy(showDockIcon: MenuBarManager.shared.settings.showDockIcon)
        logger.info("Cleared scheduled update reminder: \(reason)")
    }
}

extension UpdateService: @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(_: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        guard !state.userInitiated else {
            clearScheduledUpdateReminder(reason: "user_initiated")
            return
        }

        if handleShowingUpdate {
            clearScheduledUpdateReminder(reason: "sparkle_showing")
        } else {
            presentScheduledUpdateReminder(for: update)
        }
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate _: SUAppcastItem) {
        clearScheduledUpdateReminder(reason: "user_attention")
    }

    func standardUserDriverWillFinishUpdateSession() {
        clearScheduledUpdateReminder(reason: "session_finished")
    }
}

#else

    @MainActor
    class UpdateService: NSObject, ObservableObject {
        nonisolated static let releaseBundleIdentifier = "com.sanebar.app"
        nonisolated static let scheduledUpdateReminderNotificationID = "com.sanebar.app.sparkle.scheduled-update"

        override init() {
            super.init()
            logger.info("Sparkle updater disabled in Setapp build")
        }

        func checkForUpdates() {
            NSSound.beep()
        }

        var automaticallyChecksForUpdates: Bool {
            get { false }
            set {}
        }

        var updateCheckFrequency: UpdateCheckFrequency {
            get { .daily }
            set {}
        }

        var isUpdateChannelEnabled: Bool { false }

        nonisolated static func supportsSparkleUpdates(bundleIdentifier _: String?) -> Bool {
            false
        }

        nonisolated static func shouldShowScheduledUpdateDockBadge(showDockIcon _: Bool) -> Bool {
            false
        }
    }

#endif
