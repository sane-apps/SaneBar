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

        // Move to /Applications if running from Downloads or other location (Release only)
        #if !DEBUG
            if moveToApplicationsFolderIfNeeded() { return }
        #endif

        // CRITICAL: Set activation policy to accessory BEFORE creating status items!
        // This ensures NSStatusItem windows are created at the correct window layer (25).
        NSApp.setActivationPolicy(.accessory)

        // Initialize MenuBarManager (creates status items) - MUST be after activation policy is set
        _ = MenuBarManager.shared

        // Configure keyboard shortcuts
        let shortcutsService = KeyboardShortcutsService.shared
        shortcutsService.configure(with: MenuBarManager.shared)
        shortcutsService.setDefaultsIfNeeded()

        // Apply user's preferred policy (may override to .regular if dock icon enabled)
        ActivationPolicyManager.applyInitialPolicy()

        appLogger.info("🏁 applicationDidFinishLaunching complete")
    }

    func application(_: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        appLogger.log("🌐 URL open request: \(url.absoluteString, privacy: .public)")
        handleURL(url)
    }

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        let menu = NSMenu()

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
    @objc private func openSettingsFromDock(_: Any?) {
        SettingsOpener.open()
    }

    @MainActor
    @objc private func quitFromDock(_: Any?) {
        NSApplication.shared.terminate(nil)
    }

    /// Returns true if the app is being moved (caller should return early).
    private func moveToApplicationsFolderIfNeeded() -> Bool {
        let appPath = Bundle.main.bundlePath
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "SaneBar"

        // Already in /Applications — nothing to do
        if appPath.hasPrefix("/Applications") { return false }

        // Activate so the alert is visible (app starts as .accessory)
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Move to Applications?"
        alert.informativeText = "\(appName) works best from your Applications folder. Move it there now?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")

        let response = alert.runModal()

        // Restore accessory policy if user declines
        guard response == .alertFirstButtonReturn else {
            NSApp.setActivationPolicy(.accessory)
            return false
        }

        let destPath = "/Applications/\(appName).app"
        let fm = FileManager.default

        do {
            if fm.fileExists(atPath: destPath) {
                try fm.removeItem(atPath: destPath)
            }
            try fm.moveItem(atPath: appPath, toPath: destPath)

            // Relaunch from /Applications
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            task.arguments = [destPath]
            try task.run()

            NSApp.terminate(nil)
            return true
        } catch {
            appLogger.error("Failed to move to Applications: \(error.localizedDescription)")
            let errorAlert = NSAlert()
            errorAlert.messageText = "Couldn't Move \(appName)"
            errorAlert.informativeText = "Please drag \(appName) to your Applications folder manually.\n\nError: \(error.localizedDescription)"
            errorAlert.alertStyle = .warning
            errorAlert.runModal()
            NSApp.setActivationPolicy(.accessory)
            return false
        }
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
