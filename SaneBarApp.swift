import AppKit
import KeyboardShortcuts
import os.log
import SwiftUI

private let appLogger = Logger(subsystem: "com.sanebar.app", category: "App")

// MARK: - AppDelegate

// CLEAN: Single initialization path - only MenuBarManager creates status items

class SaneBarAppDelegate: NSObject, NSApplicationDelegate {
    // No @main - using main.swift instead

    func applicationDidFinishLaunching(_: Notification) {
        appLogger.info("🏁 applicationDidFinishLaunching START")

        // Near-instant tooltips (default is ~1000ms)
        UserDefaults.standard.set(100, forKey: "NSInitialToolTipDelay")

        // Guard against accidental duplicate launches of the same bundle.
        // Duplicate status items can cause unstable menu anchoring behavior.
        if terminateIfDuplicateInstanceRunning() {
            return
        }

        // Move to /Applications if running from Downloads or other location (Release only)
        #if !DEBUG
            if SaneAppMover.moveToApplicationsFolderIfNeeded() { return }
        #endif

        // CRITICAL: Set activation policy to accessory BEFORE creating status items!
        // This ensures NSStatusItem windows are created at the correct window layer (25).
        NSApp.setActivationPolicy(.accessory)

        // Initialize MenuBarManager (creates status items) - MUST be after activation policy is set
        _ = MenuBarManager.shared

        // Check cached Pro license (Keychain)
        LicenseService.shared.checkCachedLicense()

        // Configure keyboard shortcuts
        let shortcutsService = KeyboardShortcutsService.shared
        shortcutsService.configure(with: MenuBarManager.shared)
        shortcutsService.setDefaultsIfNeeded()

        // Apply user's preferred policy (may override to .regular if dock icon enabled)
        ActivationPolicyManager.applyInitialPolicy()

        appLogger.info("🏁 applicationDidFinishLaunching complete")
    }

    @MainActor
    private func terminateIfDuplicateInstanceRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }

        guard !others.isEmpty else { return false }
        appLogger.error("Duplicate instance detected for bundle \(bundleID, privacy: .public). Terminating current launch.")
        NSApp.terminate(nil)
        return true
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

        menu.addItem(NSMenuItem.separator())

        let checkUpdatesItem = NSMenuItem(
            title: "Check for Updates...",
            action: #selector(checkForUpdatesFromDock(_:)),
            keyEquivalent: ""
        )
        checkUpdatesItem.target = self
        menu.addItem(checkUpdatesItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(
            title: "Settings...",
            action: #selector(openSettingsFromDock(_:)),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

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
        NSApp.activate(ignoringOtherApps: true)

        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "SaneBar Settings"
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
        ActivationPolicyManager.restorePolicy()
    }
}

// MARK: - ActivationPolicyManager

/// Manages the app's activation policy based on user settings
enum ActivationPolicyManager {
    private static let logger = Logger(subsystem: "com.sanebar.app", category: "ActivationPolicyManager")

    @MainActor
    private static var didFinishLaunchingObserver: Any?

    @MainActor
    static func applyInitialPolicy() {
        guard !isHeadlessEnvironment() else { return }

        if didFinishLaunchingObserver == nil {
            didFinishLaunchingObserver = NotificationCenter.default.addObserver(
                forName: NSApplication.didFinishLaunchingNotification,
                object: nil,
                queue: .main
            ) { _ in
                Task { @MainActor in
                    enforcePolicy(retries: 6)
                }
            }
        }

        DispatchQueue.main.async {
            Task { @MainActor in
                enforcePolicy(retries: 10)
            }
        }
    }

    @MainActor
    private static func enforcePolicy(retries: Int) {
        guard let app = NSApp else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Task { @MainActor in
                    enforcePolicy(retries: max(0, retries - 1))
                }
            }
            return
        }

        let settings = MenuBarManager.shared.settings
        let policy: NSApplication.ActivationPolicy = settings.showDockIcon ? .regular : .accessory

        if app.activationPolicy() != policy {
            app.setActivationPolicy(policy)
            logger.info("Applied activation policy: \(policy == .regular ? "regular" : "accessory")")
        }

        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            Task { @MainActor in
                guard let app = NSApp else { return }
                if app.activationPolicy() != policy {
                    app.setActivationPolicy(policy)
                }
                enforcePolicy(retries: retries - 1)
            }
        }
    }

    private static func isHeadlessEnvironment() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if env["CI"] != nil || env["GITHUB_ACTIONS"] != nil { return true }
        if let bundleID = Bundle.main.bundleIdentifier,
           bundleID.hasSuffix("Tests") || bundleID.contains("xctest") { return true }
        if NSClassFromString("XCTestCase") != nil { return true }
        return false
    }

    @MainActor
    static func restorePolicy() {
        guard !isHeadlessEnvironment() else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Task { @MainActor in
                enforcePolicy(retries: 4)
            }
        }
    }

    @MainActor
    static func applyPolicy(showDockIcon: Bool) {
        guard !isHeadlessEnvironment() else { return }
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        NSApp.setActivationPolicy(policy)

        if showDockIcon {
            NSApp.activate(ignoringOtherApps: false)
        }
    }
}
