import SwiftUI
import KeyboardShortcuts

@main
struct SaneBarApp: App {
    @StateObject private var menuBarManager = MenuBarManager.shared

    var body: some Scene {
        // Hidden window MUST come before Settings scene (macOS Tahoe workaround)
        Window("Hidden", id: "HiddenWindow") {
            SettingsOpenerView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1, height: 1)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView()
                .onDisappear {
                    // Return to accessory mode when settings closes
                    NSApp.setActivationPolicy(.accessory)
                }
        }
    }

    init() {
        _ = MenuBarManager.shared

        let shortcutsService = KeyboardShortcutsService.shared
        shortcutsService.configure(with: MenuBarManager.shared)
        shortcutsService.setDefaultsIfNeeded()
    }
}

// MARK: - Settings Opener (macOS Tahoe workaround)

/// Hidden view that provides SwiftUI context for opening Settings
struct SettingsOpenerView: View {
    @Environment(\.openSettings) private var openSettings

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    var body: some View {
        // Use EmptyView during tests to avoid constraint issues
        if isRunningTests {
            EmptyView()
        } else {
            Color.clear
                .frame(width: 0, height: 0)
                .onReceive(NotificationCenter.default.publisher(for: .openSaneBarSettings)) { _ in
                    Task { @MainActor in
                        // Switch to regular app to allow window focus
                        NSApp.setActivationPolicy(.regular)
                        try? await Task.sleep(for: .milliseconds(50))

                        NSApp.activate(ignoringOtherApps: true)
                        openSettings()

                        // Ensure settings window comes to front
                        try? await Task.sleep(for: .milliseconds(100))
                        if let window = NSApp.windows.first(where: {
                            $0.identifier?.rawValue == "com_apple_SwiftUI_Settings_window" ||
                            $0.title.contains("Settings")
                        }) {
                            window.makeKeyAndOrderFront(nil)
                            window.orderFrontRegardless()
                        }
                    }
                }
        }
    }
}

// MARK: - Notification

extension Notification.Name {
    static let openSaneBarSettings = Notification.Name("openSaneBarSettings")
}
