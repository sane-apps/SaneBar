import AppKit
import Darwin
import KeyboardShortcuts
import os.log
import SaneUI
@preconcurrency import ScreenCaptureKit
import SwiftUI

private let appLogger = Logger(subsystem: "com.sanebar.app", category: "App")

extension Notification.Name {
    static let saneBarExplicitTerminationRequested = Notification.Name("SaneBarExplicitTerminationRequested")
}

private enum SaneBarSettingsWindowMetrics {
    static let idealWidth: CGFloat = SaneSettingsWindowDefaults.idealWidth
    static let idealHeight: CGFloat = SaneSettingsWindowDefaults.idealHeight
}



class SaneBarAppDelegate: NSObject, NSApplicationDelegate {
    enum DuplicateLaunchResolution: Equatable {
        case noConflict
        case waitForHandoff
        case terminateCurrent
        case terminateOthers
    }

    static let duplicateLaunchGraceNanoseconds: UInt64 = 2_000_000_000
    static let automaticTerminationReason = "SaneBar must stay active as a menu bar app"
    static let automationLifecycleBreadcrumbPath = "/tmp/sanebar_lifecycle_breadcrumb.log"
    static let automationQuitTokenEnvironmentKey = "SANEBAR_AUTOMATION_QUIT_TOKEN"
    static let automationExplicitTerminationMarkerPath = "/tmp/sanebar_explicit_termination.token"
    private var keepAliveActivity: NSObjectProtocol?
    private var explicitTerminationRequested = false

    static func duplicateLaunchResolution(
        othersAtLaunch: Int,
        othersAfterGrace: Int?,
        currentBuild: Int? = nil,
        maxSurvivingBuild: Int? = nil
    ) -> DuplicateLaunchResolution {
        guard othersAtLaunch > 0 else { return .noConflict }
        guard let othersAfterGrace else { return .waitForHandoff }
        guard othersAfterGrace > 0 else { return .noConflict }

        if let currentBuild, let maxSurvivingBuild {
            return currentBuild > maxSurvivingBuild ? .terminateOthers : .terminateCurrent
        }
        return .terminateCurrent
    }

    static func bundleBuildNumber(_ bundle: Bundle?) -> Int? {
        guard let raw = bundle?.infoDictionary?["CFBundleVersion"] as? String else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespaces))
    }

    static func activationTargetPID(amongOtherPIDs otherPIDs: [pid_t], currentPID: pid_t) -> pid_t? {
        otherPIDs
            .filter { $0 != currentPID }
            .min()
    }

    nonisolated static func shouldSkipDuplicateTerminationForAutomation(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        environment["SANEAPPS_DISABLE_KEYCHAIN"] == "1" ||
            arguments.contains("--sane-no-keychain")
    }

    nonisolated static func shouldCancelUnexpectedTerminationForAutomation(
        explicitTerminationRequested: Bool,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments,
        automationExplicitTerminationRequested: Bool? = nil
    ) -> Bool {
        guard !explicitTerminationRequested else { return false }
        if automationExplicitTerminationRequested ?? hasMatchingAutomationQuitMarker(environment: environment) {
            return false
        }
        return shouldSkipDuplicateTerminationForAutomation(environment: environment, arguments: arguments)
    }

    nonisolated static func shouldInstallNoKeychainAutomationSignalGuard(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> Bool {
        shouldSkipDuplicateTerminationForAutomation(environment: environment, arguments: arguments)
    }

    static func installNoKeychainAutomationSignalGuardIfNeeded(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) {
        guard shouldInstallNoKeychainAutomationSignalGuard(environment: environment, arguments: arguments) else { return }

        _ = signal(SIGTERM, SIG_IGN)
    }

    nonisolated static func hasMatchingAutomationQuitMarker(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        markerContents: String? = nil
    ) -> Bool {
        let token = environment[automationQuitTokenEnvironmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !token.isEmpty else { return false }

        let contents = markerContents ?? (try? String(contentsOfFile: automationExplicitTerminationMarkerPath, encoding: .utf8))
        return contents?.trimmingCharacters(in: .whitespacesAndNewlines) == token
    }


    nonisolated static func shouldUpdateAppShortcutParameters(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        isRunningTests: Bool = NSClassFromString("XCTestCase") != nil
    ) -> Bool {
        guard environment["XCTestConfigurationFilePath"] == nil else { return false }
        guard !isRunningTests else { return false }
        return true
    }

    func applicationDidFinishLaunching(_: Notification) {
        appLogger.info("🏁 applicationDidFinishLaunching START")
        writeAutomationLifecycleBreadcrumb("applicationDidFinishLaunching start")

        UserDefaults.standard.set(100, forKey: "NSInitialToolTipDelay")
        #if !DEBUG
            if Self.shouldUpdateAppShortcutParameters() {
                SaneBarAppShortcuts.updateAppShortcutParameters()
            }
        #endif

        keepAliveActivity = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: Self.automaticTerminationReason
        )
        ProcessInfo.processInfo.disableAutomaticTermination(Self.automaticTerminationReason)
        ProcessInfo.processInfo.disableSuddenTermination()

        scheduleDuplicateInstanceTerminationCheckIfNeeded()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(explicitTerminationWasRequested(_:)),
            name: .saneBarExplicitTerminationRequested,
            object: nil
        )

        #if !DEBUG
            if SaneApplicationMover.moveToApplicationsFolderIfNeeded(prompt: .init(
                messageText: "Move to Applications?",
                informativeText: "{appName} works best from your Applications folder. Move it there now? You may be asked for your password.",
                moveButtonTitle: "Move to Applications",
                cancelButtonTitle: "Not Now"
            )) { return }
        #endif

        NSApp.setActivationPolicy(.accessory)

        LicenseService.shared.checkCachedLicense()

        _ = MenuBarManager.shared
        MenuBarManager.shared.actionWorkflow.normalizeLicenseDependentDefaults()

        let shortcutsService = KeyboardShortcutsService.shared
        shortcutsService.configure(with: MenuBarManager.shared)
        shortcutsService.setDefaultsIfNeeded()

        SaneActivationPolicy.applyInitialPolicy(showDockIcon: MenuBarManager.shared.settings.showDockIcon)

        let launchTier = LicenseService.shared.isPro ? "pro" : "free"
        Task.detached {
            await EventTracker.log("app_launch_\(launchTier)", tier: launchTier)
        }

        appLogger.info("🏁 applicationDidFinishLaunching complete")
        writeAutomationLifecycleBreadcrumb("applicationDidFinishLaunching complete")
    }

    func applicationShouldTerminate(_: NSApplication) -> NSApplication.TerminateReply {
        let automationExplicitTerminationRequested = Self.consumeMatchingAutomationQuitMarker()
        if Self.shouldCancelUnexpectedTerminationForAutomation(
            explicitTerminationRequested: explicitTerminationRequested,
            automationExplicitTerminationRequested: automationExplicitTerminationRequested
        ) {
            appLogger.error("Cancelling unexpected termination request during no-keychain automation.")
            writeAutomationLifecycleBreadcrumb("applicationShouldTerminate cancel unexpected")
            return .terminateCancel
        }
        if automationExplicitTerminationRequested, !explicitTerminationRequested {
            requestExplicitTermination(reason: "automation-marker")
        }

        writeAutomationLifecycleBreadcrumb("applicationShouldTerminate allow explicit=\(explicitTerminationRequested)")
        return .terminateNow
    }

    func applicationWillTerminate(_: Notification) {
        writeAutomationLifecycleBreadcrumb("applicationWillTerminate explicit=\(explicitTerminationRequested)")
        NotificationCenter.default.removeObserver(self, name: .saneBarExplicitTerminationRequested, object: nil)
        if let keepAliveActivity {
            ProcessInfo.processInfo.endActivity(keepAliveActivity)
            self.keepAliveActivity = nil
        }
        ProcessInfo.processInfo.enableAutomaticTermination(Self.automaticTerminationReason)
        ProcessInfo.processInfo.enableSuddenTermination()
    }

    @objc private func explicitTerminationWasRequested(_: Notification) {
        requestExplicitTermination(reason: "notification")
    }

    private func requestExplicitTermination(reason: String) {
        explicitTerminationRequested = true
        writeAutomationLifecycleBreadcrumb("explicitTerminationRequested reason=\(reason)")
    }

    private static func consumeMatchingAutomationQuitMarker(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        guard hasMatchingAutomationQuitMarker(environment: environment) else { return false }
        try? FileManager.default.removeItem(atPath: automationExplicitTerminationMarkerPath)
        return true
    }

    private func writeAutomationLifecycleBreadcrumb(_ message: String) {
        guard Self.shouldSkipDuplicateTerminationForAutomation() else { return }

        let line = "\(ISO8601DateFormatter().string(from: Date())) pid=\(ProcessInfo.processInfo.processIdentifier) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        let url = URL(fileURLWithPath: Self.automationLifecycleBreadcrumbPath)
        if (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil {
            return
        }
        if FileManager.default.fileExists(atPath: url.path),
           let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try? data.write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    @MainActor
    private func runningDuplicateInstances(bundleID: String, currentPID: pid_t) -> [NSRunningApplication] {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != currentPID }
    }

    @MainActor
    private func scheduleDuplicateInstanceTerminationCheckIfNeeded() {
        guard !Self.shouldSkipDuplicateTerminationForAutomation() else {
            appLogger.info("Skipping duplicate-instance termination guard for no-keychain automation launch.")
            return
        }
        guard let bundleID = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let initialOthers = runningDuplicateInstances(bundleID: bundleID, currentPID: currentPID)
        let initialResolution = Self.duplicateLaunchResolution(
            othersAtLaunch: initialOthers.count,
            othersAfterGrace: nil
        )

        guard initialResolution == .waitForHandoff else { return }

        appLogger.warning(
            "Duplicate launch detected for bundle \(bundleID, privacy: .public). Waiting \(Self.duplicateLaunchGraceNanoseconds / 1_000_000_000)s for handoff before termination."
        )

        let currentBuild = Self.bundleBuildNumber(Bundle.main)

        Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.duplicateLaunchGraceNanoseconds)
            let remainingOthers = runningDuplicateInstances(bundleID: bundleID, currentPID: currentPID)
            let maxSurvivingBuild = Self.maxBuildNumber(among: remainingOthers)
            let finalResolution = Self.duplicateLaunchResolution(
                othersAtLaunch: initialOthers.count,
                othersAfterGrace: remainingOthers.count,
                currentBuild: currentBuild,
                maxSurvivingBuild: maxSurvivingBuild
            )

            switch finalResolution {
            case .noConflict:
                appLogger.info("Duplicate launch handoff resolved; keeping current instance alive.")
            case .waitForHandoff:
                break
            case .terminateOthers:
                appLogger.error(
                    "This launch (build \(currentBuild ?? -1, privacy: .public)) is newer than the surviving instance(s) (build \(maxSurvivingBuild ?? -1, privacy: .public)) for bundle \(bundleID, privacy: .public). Terminating the stale instance(s) and keeping the update."
                )
                terminateStaleInstances(remainingOthers)
            case .terminateCurrent:
                appLogger.error(
                    "Duplicate instance still running after grace period for bundle \(bundleID, privacy: .public). Activating existing instance and terminating current launch."
                )
                activateSurvivingInstance(among: remainingOthers, currentPID: currentPID)
                NSApp.terminate(nil)
            }
        }
    }

    @MainActor
    private static func maxBuildNumber(among apps: [NSRunningApplication]) -> Int? {
        apps.compactMap { bundleBuildNumber(Bundle(url: $0.bundleURL ?? URL(fileURLWithPath: "/"))) }.max()
    }

    @MainActor
    private func terminateStaleInstances(_ apps: [NSRunningApplication]) {
        for app in apps {
            app.terminate()
        }
    }

    @MainActor
    private func activateSurvivingInstance(among others: [NSRunningApplication], currentPID: pid_t) {
        let targetPID = Self.activationTargetPID(
            amongOtherPIDs: others.map(\.processIdentifier),
            currentPID: currentPID
        )
        guard let targetPID,
              let target = others.first(where: { $0.processIdentifier == targetPID })
        else {
            return
        }
        target.activate(options: [.activateAllWindows])
    }

    func application(_: NSApplication, open urls: [URL]) {
        guard let url = urls.first else { return }
        appLogger.log("🌐 URL open request received")
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

        SaneStandardMenu.addCoreUtilityItems(
            to: menu,
            appName: "SaneBar",
            target: self,
            settingsAction: #selector(openSettingsFromDock(_:)),
            licenseAction: #selector(openLicenseFromDock(_:)),
            checkForUpdatesAction: LicenseService.shared.distributionChannel.supportsInAppUpdates
                ? #selector(checkForUpdatesFromDock(_:))
                : nil,
            aboutAndBugReportAction: #selector(openAboutFromDock(_:)),
            whatsNewAction: nil,
            quitTarget: self,
            quitAction: #selector(quitFromDock(_:)),
            settingsKeyEquivalent: ","
        )

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
        MenuBarManager.shared.actionWorkflow.userDidClickCheckForUpdates()
    }

    @MainActor
    @objc private func openSettingsFromDock(_: Any?) {
        SettingsOpener.open()
    }

    @MainActor
    @objc private func openLicenseFromDock(_: Any?) {
        SettingsOpener.open(tab: .license)
    }

    @MainActor
    @objc private func openAboutFromDock(_: Any?) {
        SettingsOpener.open(tab: .about)
    }

    @MainActor
    @objc private func quitFromDock(_ sender: Any?) {
        requestExplicitTermination(reason: "dock-menu")
        NSApp.terminate(sender)
    }

    @MainActor
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if MenuBarManager.shared.currentRuntimeSnapshot().likelySystemSuppressedStatusItems {
            appLogger.error("Reopen while the status item looks system-suppressed — surfacing Health so the user can recover (#157)")
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            SettingsOpener.open(tab: .health)
        } else if !hasVisibleWindows {
            SettingsOpener.open()
        }
        return true
    }

    private func handleURL(_ url: URL) {
        guard url.scheme?.lowercased() == "sanebar" else { return }

        let rawCommand = (url.host?.isEmpty == false) ? url.host : url.path.split(separator: "/").first.map(String.init)
        let command = rawCommand?.lowercased() ?? ""
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        let searchQuery = queryItems?.first(where: { $0.name == "q" })?.value

        appLogger.log("🌐 URL command: \(command, privacy: .public) queryPresent: \(searchQuery != nil, privacy: .public)")

        Task { @MainActor in
            switch command {
            case "toggle":
                MenuBarManager.shared.visibilityWorkflow.toggleHiddenItems()
            case "show":
                MenuBarManager.shared.visibilityWorkflow.showHiddenItems()
            case "hide":
                MenuBarManager.shared.visibilityWorkflow.hideHiddenItems()
            case "search":
                if MenuBarManager.shared.settings.requireAuthToShowHiddenIcons {
                    let ok = await MenuBarManager.shared.visibilityWorkflow.authenticate(reason: "Unlock hidden icons")
                    guard ok else {
                        appLogger.log("🌐 URL command blocked by auth: search")
                        return
                    }
                }
                _ = await MenuBarManager.shared.visibilityWorkflow.showHiddenItemsNow(trigger: .search)
                SearchWindowController.shared.show(mode: .findIcon, prefill: searchQuery)
            case "settings":
                SettingsOpener.open()
            case "health":
                SettingsOpener.open(tab: .health)
            case "repair":
                SettingsOpener.open(tab: .health)
                _ = await MenuBarManager.shared.profileWorkflow.repairMenuBarHealth(reason: "url-repair")
            default:
                appLogger.log("🌐 Unknown URL command: \(command, privacy: .public)")
            }
        }
    }
}


enum SettingsOpener {
    @MainActor private static var settingsWindow: NSWindow?
    @MainActor private static var windowDelegate: SettingsWindowDelegate?

    @MainActor static func open(tab: SettingsView.SettingsTab? = nil) {
        NSApp.activate()

        let window: NSWindow
        if let existingWindow = settingsWindow {
            if let tab {
                let hostingController = NSHostingController(rootView: SettingsView(defaultTab: tab))
                hostingController.saneIgnoreIntrinsicWindowSize()
                existingWindow.contentViewController = hostingController
            }
            existingWindow.saneApplySettingsChrome(preferIdealSize: false)
            window = existingWindow
        } else {
            window = makeWindow(defaultTab: tab ?? .control)
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    @MainActor static func close() {
        settingsWindow?.close()
    }

    @MainActor static func captureSnapshotPNG(to path: String) async -> Bool {
        guard let window = settingsWindow,
              window.isVisible,
              let outputURL = snapshotOutputURL(for: path)
        else {
            return false
        }

        guard let pngData = await captureWindowPNGData(window: window) ?? captureContentPNGData(window: window) else {
            return false
        }

        do {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try pngData.write(to: outputURL, options: .atomic)
            return true
        } catch {
            appLogger.error("Failed to write settings snapshot: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    @MainActor private static func makeWindow(defaultTab: SettingsView.SettingsTab = .control) -> NSWindow {
        let settingsView = SettingsView(defaultTab: defaultTab)
        let hostingController = NSHostingController(rootView: settingsView)
        hostingController.saneIgnoreIntrinsicWindowSize()

        let window = SaneSettingsWindow(
            contentRect: NSRect(
                x: 0,
                y: 0,
                width: SaneSettingsWindowDefaults.idealWidth,
                height: SaneBarSettingsWindowMetrics.idealHeight
            ),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.contentMinSize = NSSize(width: SaneSettingsWindowDefaults.minWidth, height: SaneSettingsWindowDefaults.minHeight)
        window.title = "SaneBar Settings"
        window.appearance = NSAppearance(named: .darkAqua)
        window.saneApplySettingsChrome(preferIdealSize: true)
        window.center()
        window.isReleasedWhenClosed = false

        let delegate = SettingsWindowDelegate()
        window.delegate = delegate
        windowDelegate = delegate
        settingsWindow = window
        return window
    }

    private static func snapshotOutputURL(for path: String) -> URL? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed).standardizedFileURL
    }

    @MainActor private static func captureWindowPNGData(window: NSWindow) async -> Data? {
        guard #available(macOS 14.4, *),
              let cgImage = await captureWindowImage(window: window)
        else {
            return nil
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        return bitmap.representation(using: .png, properties: [:])
    }

    @MainActor private static func captureContentPNGData(window: NSWindow) -> Data? {
        guard let contentView = window.contentView else { return nil }

        contentView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()

        let bounds = contentView.bounds.integral
        guard bounds.width > 0,
              bounds.height > 0,
              let bitmap = contentView.bitmapImageRepForCachingDisplay(in: bounds)
        else {
            return nil
        }

        bitmap.size = bounds.size
        contentView.cacheDisplay(in: bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }

    @available(macOS 14.4, *)
    @MainActor private static func captureWindowImage(window: NSWindow) async -> CGImage? {
        do {
            let shareableContent = try await SCShareableContent.currentProcess
            guard let shareableWindow = shareableContent.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) }) else {
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: shareableWindow)
            let config = SCStreamConfiguration()
            let scale = window.screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            config.width = max(1, Int(window.frame.width * scale))
            config.height = max(1, Int(window.frame.height * scale))

            return try await withCheckedThrowingContinuation { continuation in
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { image, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else {
                        continuation.resume(returning: image)
                    }
                }
            }
        } catch {
            appLogger.error("Failed to capture settings window via ScreenCaptureKit: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
}

private class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_: Notification) {
        SaneActivationPolicy.restorePolicy(showDockIcon: MenuBarManager.shared.settings.showDockIcon)
    }
}
