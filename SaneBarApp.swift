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

    @MainActor
    private static var didFinishLaunchingObserver: Any?
    
    /// Apply the initial activation policy when app launches
    @MainActor
    static func applyInitialPolicy() {
        guard !isHeadlessEnvironment() else { return }

        // macOS (especially Login Items / fast boot) can override activation policy
        // after launch as scenes/windows are established. Re-assert a few times.
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

        // Defer policy application to ensure NSApp is fully initialized
        // In SwiftUI @main apps, App.init() runs before NSApplicationMain() completes
        // Use more retries for login items where macOS aggressively sets .regular
        DispatchQueue.main.async {
            Task { @MainActor in
                enforcePolicy(retries: 10)
            }
        }
    }

    /// Apply and re-apply the activation policy for a short window until it sticks.
    @MainActor
    private static func enforcePolicy(retries: Int) {
        guard let app = NSApp else {
            logger.warning("NSApp not available yet, deferring activation policy")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                Task { @MainActor in
                    enforcePolicy(retries: max(0, retries - 1))
                }
            }
            return
        }

        // Use MenuBarManager's already-loaded settings to avoid race conditions
        let settings = MenuBarManager.shared.settings
        let policy: NSApplication.ActivationPolicy = settings.showDockIcon ? .regular : .accessory

        // Apply immediately (only if needed to avoid unnecessary flips)
        if app.activationPolicy() != policy {
            app.setActivationPolicy(policy)
            logger.info("Applied activation policy: \(policy == .regular ? "regular (dock visible)" : "accessory (dock hidden)")")
        }

        // Re-assert a few times in case macOS flips it during launch.
        guard retries > 0 else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            Task { @MainActor in
                guard let app = NSApp else { return }
                if app.activationPolicy() != policy {
                    app.setActivationPolicy(policy)
                    logger.debug("Re-applied activation policy (was overridden)")
                }
                enforcePolicy(retries: retries - 1)
            }
        }
    }

    /// Check if running in headless/test environment
    private static func isHeadlessEnvironment() -> Bool {
        let env = ProcessInfo.processInfo.environment
        if env["CI"] != nil || env["GITHUB_ACTIONS"] != nil { return true }
        if let bundleID = Bundle.main.bundleIdentifier,
           bundleID.hasSuffix("Tests") || bundleID.contains("xctest") { return true }
        if NSClassFromString("XCTestCase") != nil { return true }
        return false
    }
    
    /// Restore the policy after settings window closes
    /// Uses retry logic because macOS can override the policy after a window closes
    @MainActor
    static func restorePolicy() {
        guard !isHeadlessEnvironment() else { return }

        // Small delay to let window fully close before changing policy
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            Task { @MainActor in
                enforcePolicy(retries: 4)  // Retry a few times to ensure it sticks
            }
        }
    }

    /// Apply policy change when user toggles the setting
    @MainActor
    static func applyPolicy(showDockIcon: Bool) {
        guard !isHeadlessEnvironment() else { return }
        let policy: NSApplication.ActivationPolicy = showDockIcon ? .regular : .accessory
        NSApp.setActivationPolicy(policy)

        if showDockIcon {
            NSApp.activate(ignoringOtherApps: false)
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
