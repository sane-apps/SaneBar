import SwiftUI
import AppKit

/// Manages the onboarding window lifecycle
@MainActor
final class OnboardingController {
    static let shared = OnboardingController()
    
    private var window: NSWindow?
    
    func show() {
        if let window = window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        
        // DON'T force .regular here - windows work fine in .accessory mode
        // The dock icon visibility should only be controlled by the user's showDockIcon setting
        NSApp.activate(ignoringOtherApps: true)
        
        let welcomeView = WelcomeView { [weak self] in
            self?.dismiss()
        }
        
        let hostingController = NSHostingController(rootView: welcomeView)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        
        // Standard window behaviors
        window.isMovable = true
        
        self.window = window
        window.makeKeyAndOrderFront(nil)
    }
    
    func dismiss() {
        window?.close()
        window = nil
        
        // Mark as complete
        MenuBarManager.shared.settings.hasCompletedOnboarding = true
        MenuBarManager.shared.saveSettings()
        
        // Restore accessory policy (hide Dock icon)
        ActivationPolicyManager.restorePolicy()
    }
}
