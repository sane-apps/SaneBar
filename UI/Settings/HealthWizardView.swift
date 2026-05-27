import AppKit
import SaneUI
import SwiftUI

@MainActor
final class HealthWizardController: NSObject, NSWindowDelegate {
    static let shared = HealthWizardController()

    private var window: NSWindow?

    func showIfNeeded() {
        guard !MenuBarManager.shared.settings.hasCompletedHealthWizard else { return }
        show()
    }

    func show() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }

        NSApp.activate()

        let wizardView = FirstRunHealthWizardView { [weak self] in
            self?.dismiss()
        }
        let hostingController = NSHostingController(rootView: wizardView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 430),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.appearance = NSAppearance(named: .darkAqua)
        window.title = "SaneBar Health"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.contentMinSize = NSSize(width: 520, height: 380)
        window.contentViewController = hostingController
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self

        self.window = window
        window.makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        window?.close()
    }

    func windowWillClose(_: Notification) {
        guard window != nil else { return }
        window = nil
        MenuBarManager.shared.profileWorkflow.completeHealthWizard()
        SaneActivationPolicy.restorePolicy(showDockIcon: MenuBarManager.shared.settings.showDockIcon)
    }
}

private struct FirstRunHealthWizardView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @ObservedObject private var accessibilityService = AccessibilityService.shared
    @State private var rescuePointSaved = false
    @State private var repairRan = false
    @State private var rescueMessage = ""
    let onComplete: () -> Void

    var body: some View {
        ZStack {
            Color(red: 0.04, green: 0.07, blue: 0.10).ignoresSafeArea()

            VStack(alignment: .leading, spacing: 18) {
                header
                statusSection
                actionBar
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear {
            rescuePointSaved = menuBarManager.settings.layoutRescueRestorePoint != nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SaneBar Health")
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.white)
            Text("Finish setup with a permission check and a saved layout restore point.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.94))
        }
    }

    private var statusSection: some View {
        CompactSection("First Run Check", icon: "stethoscope", iconColor: .green) {
            CompactRow("Accessibility") {
                StatusBadge(
                    accessibilityService.isGranted ? "OK" : "Needs Action",
                    color: accessibilityService.isGranted ? .green : .orange,
                    icon: accessibilityService.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .saneHelp(accessibilityHelp)
            }
            CompactDivider()
            CompactRow("Layout Restore Point") {
                StatusBadge(
                    rescuePointSaved || menuBarManager.settings.layoutRescueRestorePoint != nil ? "Saved" : "Not Saved",
                    color: rescuePointSaved || menuBarManager.settings.layoutRescueRestorePoint != nil ? .green : .orange,
                    icon: "lifepreserver"
                )
                .saneHelp("The first restore point lets SaneBar return to the current known-good layout later.")
            }
            CompactDivider()
            CompactRow("Repair Check") {
                StatusBadge(
                    repairRan ? "Run" : "Ready",
                    color: repairRan ? .green : .cyan,
                    icon: "wrench.and.screwdriver"
                )
                .saneHelp("Arrange Now uses the same layout rescue path available later in Health.")
            }
            if !rescueMessage.isEmpty {
                CompactDivider()
                Text(rescueMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.94))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button("Open Accessibility") {
                openAccessibilitySettings()
            }
            .buttonStyle(ChromeActionButtonStyle())
            .saneHelp("Opens macOS Privacy & Security > Accessibility.")

            Button("Save Restore Point") {
                saveRestorePoint()
            }
            .buttonStyle(ChromeActionButtonStyle(prominent: rescuePointSaved))
            .saneHelp("Saves the current menu bar layout as SaneBar's first rescue point.")

            Button("Arrange Now") {
                Task { @MainActor in
                    _ = await menuBarManager.profileWorkflow.repairMenuBarHealth(reason: "health-wizard")
                    repairRan = true
                }
            }
            .buttonStyle(ChromeActionButtonStyle())
            .saneHelp("Runs an immediate layout repair check.")

            Spacer(minLength: 0)

            Button("Done") {
                onComplete()
            }
            .buttonStyle(ChromeActionButtonStyle(prominent: true))
        }
    }

    private var accessibilityHelp: String {
        accessibilityService.isGranted
            ? "SaneBar can inspect and arrange menu bar items."
            : "Open Accessibility settings and grant SaneBar before using Browse Icons or Arrange Now."
    }

    private func saveRestorePoint() {
        rescuePointSaved = menuBarManager.profileWorkflow.createLayoutRescueRestorePoint(reason: "health-wizard")
        rescueMessage = rescuePointSaved
            ? "Restore point saved."
            : "Run Arrange Now after Accessibility is granted, then save a restore point."
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: AccessibilityService.accessibilitySettingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }
}
