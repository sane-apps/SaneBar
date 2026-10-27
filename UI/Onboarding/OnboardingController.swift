import AppKit
import SaneUI
import SwiftUI

@MainActor
final class OnboardingController: NSObject, NSWindowDelegate {
    static let shared = OnboardingController()

    private var window: NSWindow?

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        NSApp.activate()

        let welcomeView = WelcomeView { [weak self] in
            self?.dismiss()
        }

        let hostingController = NSHostingController(rootView: welcomeView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.appearance = NSAppearance(named: .darkAqua)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        window.isMovable = true

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        window?.close()
    }


    func windowWillClose(_: Notification) {
        guard window != nil else { return }
        window = nil

        MenuBarManager.shared.settings.hasCompletedOnboarding = true
        MenuBarManager.shared.saveSettings()

        SaneActivationPolicy.restorePolicy(showDockIcon: MenuBarManager.shared.settings.showDockIcon)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            HealthWizardController.shared.showIfNeeded()
        }
    }
}
