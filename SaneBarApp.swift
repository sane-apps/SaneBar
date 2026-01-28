import SwiftUI
import AppKit
import KeyboardShortcuts
import os.log

private let appLogger = Logger(subsystem: "com.sanebar.app", category: "App")

// MARK: - AppDelegate
// CLEAN: Single initialization path - only MenuBarManager creates status items

class SaneBarAppDelegate: NSObject, NSApplicationDelegate {
    // No @main - using main.swift instead

    func applicationDidFinishLaunching(_ notification: Notification) {
        appLogger.info("🏁 applicationDidFinishLaunching START")

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

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
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
    @objc private func openSettingsFromDock(_ sender: Any?) {
        SettingsOpener.open()
    }

    @MainActor
    @objc private func quitFromDock(_ sender: Any?) {
        NSApplication.shared.terminate(nil)
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
    func windowWillClose(_ notification: Notification) {
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
