import AppKit
import KeyboardShortcuts
import os.log
import SaneUI
import SwiftUI

private let appLogger = Logger(subsystem: "com.sanebar.app", category: "App")

// MARK: - AppDelegate

// CLEAN: Single initialization path - only MenuBarManager creates status items

class SaneBarAppDelegate: NSObject, NSApplicationDelegate {
    enum DuplicateLaunchResolution: Equatable {
        case noConflict
        case waitForHandoff
        case terminateCurrent
    }

    static let duplicateLaunchGraceNanoseconds: UInt64 = 2_000_000_000
    static let automaticTerminationReason = "SaneBar must stay active as a menu bar app"
    private var keepAliveActivity: NSObjectProtocol?

    static func duplicateLaunchResolution(othersAtLaunch: Int, othersAfterGrace: Int?) -> DuplicateLaunchResolution {
        guard othersAtLaunch > 0 else { return .noConflict }
        guard let othersAfterGrace else { return .waitForHandoff }
        return othersAfterGrace > 0 ? .terminateCurrent : .noConflict
    }

    // No @main - using main.swift instead

    func applicationDidFinishLaunching(_: Notification) {
        appLogger.info("🏁 applicationDidFinishLaunching START")

        // Near-instant tooltips (default is ~1000ms)
        UserDefaults.standard.set(100, forKey: "NSInitialToolTipDelay")

        // Keep the menu bar process alive across idle periods.
        keepAliveActivity = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: Self.automaticTerminationReason
        )
        ProcessInfo.processInfo.disableAutomaticTermination(Self.automaticTerminationReason)
        ProcessInfo.processInfo.disableSuddenTermination()

        // Guard against accidental duplicate launches of the same bundle.
        // Use a handoff grace window so update relaunches do not self-terminate.
        scheduleDuplicateInstanceTerminationCheckIfNeeded()

        // Move to /Applications if running from Downloads or other location (Release only)
        #if !DEBUG && !APP_STORE && !SETAPP
            if SaneAppMover.moveToApplicationsFolderIfNeeded() { return }
        #endif

        // CRITICAL: Set activation policy to accessory BEFORE creating status items!
        // This ensures NSStatusItem windows are created at the correct window layer (25).
        NSApp.setActivationPolicy(.accessory)

        // Load cached Pro state before the menu bar runtime creates any
        // license-gated status items. Otherwise launch can briefly create and
        // tear down the always-hidden separator while `isPro` catches up.
        LicenseService.shared.checkCachedLicense()

        // Initialize MenuBarManager (creates status items) - MUST be after activation policy is set
        _ = MenuBarManager.shared
        MenuBarManager.shared.normalizeLicenseDependentDefaults()

        // Configure keyboard shortcuts
        let shortcutsService = KeyboardShortcutsService.shared
        shortcutsService.configure(with: MenuBarManager.shared)
        shortcutsService.setDefaultsIfNeeded()

        // Apply user's preferred policy (may override to .regular if dock icon enabled)
        SaneActivationPolicy.applyInitialPolicy(showDockIcon: MenuBarManager.shared.settings.showDockIcon)
        SetappIntegration.logPurchaseType()
        SetappIntegration.showReleaseNotesIfNeeded(delay: 1.5)

        appLogger.info("🏁 applicationDidFinishLaunching complete")
    }

    func applicationWillTerminate(_: Notification) {
        if let keepAliveActivity {
            ProcessInfo.processInfo.endActivity(keepAliveActivity)
            self.keepAliveActivity = nil
        }
        ProcessInfo.processInfo.enableAutomaticTermination(Self.automaticTerminationReason)
        ProcessInfo.processInfo.enableSuddenTermination()
    }

    @MainActor
    private func runningDuplicateInstances(bundleID: String, currentPID: pid_t) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }
    }

    @MainActor
    private func scheduleDuplicateInstanceTerminationCheckIfNeeded() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let initialOthers = runningDuplicateInstances(bundleID: bundleID, currentPID: currentPID)
        let initialResolution = Self.duplicateLaunchResolution(
            othersAtLaunch: initialOthers.count,
            othersAfterGrace: nil
        )

        guard initialResolution == .waitForHandoff else { return }

        appLogger.warning(
            "Duplicate launch detected for bundle \(bundleID, privacy: .public). Waiting \(Self.duplicateLaunchGraceNanoseconds / 1_000_000_000)s for handoff before termination."
        )

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.duplicateLaunchGraceNanoseconds)
            let remainingOthers = runningDuplicateInstances(bundleID: bundleID, currentPID: currentPID).count
            let finalResolution = Self.duplicateLaunchResolution(
                othersAtLaunch: initialOthers.count,
                othersAfterGrace: remainingOthers
            )

            switch finalResolution {
            case .noConflict:
                appLogger.info("Duplicate launch handoff resolved; keeping current instance alive.")
            case .waitForHandoff:
                break
            case .terminateCurrent:
                appLogger.error(
                    "Duplicate instance still running after grace period for bundle \(bundleID, privacy: .public). Terminating current launch."
                )
                NSApp.terminate(nil)
            }
        }
    }

    func application(_: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        appLogger.log("🌐 URL open request: \(url.absoluteString, privacy: .public)")
        handleURL(url)
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()

        let showAllItem = NSMenuItem(
            title: "Show All Icons",
            action: #selector(showAllIconsFromDock(_:)),
            keyEquivalent: ""
        )
        showAllItem.target = self
        menu.addItem(showAllItem)

        if LicenseService.shared.distributionChannel.supportsInAppUpdates {
            menu.addItem(NSMenuItem.separator())

            let checkUpdatesItem = NSMenuItem(
                title: "Check for Updates...",
                action: #selector(checkForUpdatesFromDock(_:)),
                keyEquivalent: ""
            )
            checkUpdatesItem.target = self
            menu.addItem(checkUpdatesItem)
        }

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettingsFromDock(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        if LicenseService.shared.usesSetappDistribution {
            let whatsNewItem = NSMenuItem(
                title: "What's New...",
                action: #selector(showReleaseNotesFromDock(_:)),
                keyEquivalent: ""
            )
            whatsNewItem.target = self
            menu.addItem(whatsNewItem)
            menu.addItem(NSMenuItem.separator())
        } else {
            menu.addItem(NSMenuItem.separator())
        }

        let quitItem = NSMenuItem(
            title: "Quit SaneBar",
            action: #selector(quitFromDock(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        return menu
    }

    @MainActor
    @objc private func showAllIconsFromDock(_: Any?) {
        Task {
            await MenuBarManager.shared.hidingService.showAll()
        }
    }

    @MainActor
    @objc private func checkForUpdatesFromDock(_: Any?) {
        MenuBarManager.shared.userDidClickCheckForUpdates()
    }

    @MainActor
    @objc private func openSettingsFromDock(_: Any?) {
        SettingsOpener.open()
    }

    @MainActor
    @objc private func showReleaseNotesFromDock(_: Any?) {
        SetappIntegration.showReleaseNotes()
    }

    @MainActor
    @objc private func quitFromDock(_: Any?) {
        NSApplication.shared.terminate(nil)
    }

    private func handleURL(_ url: URL) {
        guard url.scheme?.lowercased() == "sanebar" else { return }

        let rawCommand = (url.host?.isEmpty == false) ? url.host : url.path.split(separator: "/").first.map(String.init)
        let command = rawCommand?.lowercased() ?? ""
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let searchQuery = queryItems?.first(where: { $0.name == "q" })?.value

        appLogger.log("🌐 URL command: \(command, privacy: .public) query: \(searchQuery ?? "", privacy: .public)")

        Task { @MainActor in
            switch command {
            case "toggle":
                MenuBarManager.shared.toggleHiddenItems()
            case "show":
                MenuBarManager.shared.showHiddenItems()
            case "hide":
                MenuBarManager.shared.hideHiddenItems()
            case "search":
                if MenuBarManager.shared.settings.requireAuthToShowHiddenIcons {
                    let ok = await MenuBarManager.shared.authenticate(reason: "Unlock hidden icons")
                    guard ok else {
                        appLogger.log("🌐 URL command blocked by auth: search")
                        return
                    }
                }
                SearchWindowController.shared.show(mode: .findIcon, prefill: searchQuery)
            case "settings":
                SettingsOpener.open()
            default:
                appLogger.log("🌐 Unknown URL command: \(command, privacy: .public)")
            }
        }
    }
}

// MARK: - Settings Opener

/// Opens Settings window programmatically
enum SettingsOpener {
    @MainActor private static var settingsWindow: NSWindow?
    @MainActor private static var windowDelegate: SettingsWindowDelegate?

    @MainActor static func open() {
        // DON'T force .regular here - respect the user's showDockIcon setting
        // An .accessory app CAN have visible windows (the dock icon just won't show)
        // This fixes the bug where dock icon appears when Settings opens despite setting being OFF
        NSApp.activate()

        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "SaneBar Settings"
        window.appearance = NSAppearance(named: .darkAqua)
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 450, height: 400))
        window.center()
        window.isReleasedWhenClosed = false

        let delegate = SettingsWindowDelegate()
        window.delegate = delegate
        windowDelegate = delegate

        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        settingsWindow = window
    }
}

/// Handles settings window lifecycle events
private class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_: Notification) {
        SaneActivationPolicy.restorePolicy(showDockIcon: MenuBarManager.shared.settings.showDockIcon)
    }
}
