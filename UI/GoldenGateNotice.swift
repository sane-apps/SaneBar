import AppKit
import ServiceManagement
import SwiftUI

enum GoldenGateNotice {
    static let menuBarSettingsURL = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")!
    static let thawURL = URL(string: "https://github.com/thaw-app/Thaw")!

    static var applies: Bool {
        let env = ProcessInfo.processInfo.environment
        guard env["XCTestConfigurationFilePath"] == nil else { return false }
        return ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27
            || env["SANEBAR_SHOW_MACOS27_NOTICE"] == "1"
    }

    static func hiddenAppNames(settingsURL: URL? = nil) -> [String] {
        let url = settingsURL ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("SaneBar/settings.json")
        guard let url, let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ids = json["alwaysHiddenPinnedItemIds"] as? [String] else { return [] }
        var names: [String] = []
        for raw in ids where !raw.hasPrefix("com.apple.menuextra.") {
            let bundleId = raw.components(separatedBy: "::").first ?? raw
            guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) else { continue }
            let name = appURL.deletingPathExtension().lastPathComponent
            if !names.contains(name) {
                names.append(name)
            }
        }
        return names.sorted()
    }

    @MainActor
    static func openMenuBarSettings() -> Bool {
        let fallback = ProcessInfo.processInfo.environment["SANEBAR_SETTINGS_FALLBACK_TEST"]
        if fallback == nil, NSWorkspace.shared.open(menuBarSettingsURL) {
            return true
        }
        guard fallback != "none",
              let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") else { return false }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
}

@MainActor
final class GoldenGateNoticeDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        let view = GoldenGateNoticeView(hiddenApps: GoldenGateNotice.hiddenAppNames())
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = "SaneBar"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(host.view.fittingSize)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_: Notification) {
        try? SMAppService.mainApp.unregister()
    }
}

struct GoldenGateNoticeView: View {
    let hiddenApps: [String]
    @State private var openFailed = false
    @State private var opened = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                Text("SaneBar can't hide icons on macOS 27")
                    .font(.system(size: 20, weight: .semibold))
            }
            Text("macOS 27 changed how the menu bar works, and SaneBar can no longer move or hide icons. macOS can now hide them itself.")
            Text("Open System Settings, choose Menu Bar, and switch off each app you don't want to see. Its icon stays out of the menu bar until you switch it back on.")
            if !hiddenApps.isEmpty {
                Text("In SaneBar you kept these hidden: \(ListFormatter.localizedString(byJoining: hiddenApps)).")
            }
            if openFailed {
                Text("System Settings didn't open. Open it from the Apple menu, then choose Menu Bar.")
                    .foregroundStyle(.yellow)
            }
            HStack(spacing: 12) {
                Button(opened ? "Open Menu Bar Settings Again" : "Open Menu Bar Settings") {
                    openFailed = !GoldenGateNotice.openMenuBarSettings()
                    opened = !openFailed
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                Button("Quit SaneBar") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
            .padding(.top, 4)
            Text("Want a hidden section you open with a click? [Thaw](\(GoldenGateNotice.thawURL.absoluteString)) is free and open source.")
            Text("SaneBar still works on macOS 26 and earlier. On this Mac it will stop opening at login.")
        }
        .font(.system(size: 14))
        .foregroundStyle(.white)
        .tint(.cyan)
        .padding(24)
        .frame(width: 500, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
