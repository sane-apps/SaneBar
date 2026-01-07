import SwiftUI
import AppKit
import KeyboardShortcuts
import os.log

@main
struct SaneBarApp: App {
    @StateObject private var menuBarManager = MenuBarManager.shared

    var body: some Scene {
        Settings {
            SettingsView()
                .onDisappear {
                    // Return to appropriate mode based on user setting when settings closes
                    ActivationPolicyManager.restorePolicy()
                }
        }
    }

    init() {
        _ = MenuBarManager.shared

        let shortcutsService = KeyboardShortcutsService.shared
        shortcutsService.configure(with: MenuBarManager.shared)
        shortcutsService.setDefaultsIfNeeded()
        
        // Set initial activation policy based on user settings
        ActivationPolicyManager.applyInitialPolicy()
    }
}

// MARK: - Settings Opener

/// Opens Settings window programmatically
enum SettingsOpener {
    @MainActor private static var settingsWindow: NSWindow?
    @MainActor private static var windowDelegate: SettingsWindowDelegate?

    @MainActor static func open() {
        // Always switch to regular app mode so settings window can appear
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Reuse existing window if it exists
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }

        // Create a new Settings window with NSHostingController
        let settingsView = SettingsView()
        let hostingController = NSHostingController(rootView: settingsView)

        let window = NSWindow(contentViewController: hostingController)
        window.title = "SaneBar Settings"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 450, height: 400))
        window.center()
        window.isReleasedWhenClosed = false

        // Set delegate to handle window close
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
        // Return to appropriate mode based on user setting when settings window closes
        ActivationPolicyManager.restorePolicy()
    }
}

// MARK: - ActivationPolicyManager

/// Manages the app's activation policy based on user settings
enum ActivationPolicyManager {
    
    private static let logger = Logger(subsystem: "com.sanebar.app", category: "ActivationPolicyManager")
    
    /// Apply the initial activation policy when app launches
    @MainActor
    static func applyInitialPolicy() {
        let settings = loadSettings()
        let policy: NSApplication.ActivationPolicy = settings.showDockIcon ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
    }
    
    /// Restore the policy after settings window closes
    @MainActor
    static func restorePolicy() {
        let settings = loadSettings()
        let policy: NSApplication.ActivationPolicy = settings.showDockIcon ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
    }
    
    /// Apply policy change when user toggles the setting
    @MainActor
    static func applyPolicy(showDockIcon: Bool) {
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        NSApp.setActivationPolicy(policy)
        
        if showDockIcon {
            // Activate the app so Dock icon is immediately visible
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    /// Load settings to determine current Dock icon preference
    private static func loadSettings() -> SaneBarSettings {
        do {
            return try PersistenceService.shared.loadSettings()
        } catch {
            // On error, log and return defaults (Dock icon hidden for backward compatibility)
            logger.warning("Failed to load settings for activation policy: \(error.localizedDescription). Using defaults.")
            return SaneBarSettings()
        }
    }
}

