import AppKit
import Darwin
import KeyboardShortcuts
import os.log
import SaneUI
#if !SETAPP
    @preconcurrency import ScreenCaptureKit
#endif
import SwiftUI

private let appLogger = Logger(subsystem: "com.sanebar.app", category: "App")

extension Notification.Name {
    static let saneBarExplicitTerminationRequested = Notification.Name("SaneBarExplicitTerminationRequested")
}

private enum SaneBarSettingsWindowMetrics {
    static let idealWidth: CGFloat = 600
    static let idealHeight: CGFloat = 560
}

// MARK: - AppDelegate

// CLEAN: Single initialization path - only MenuBarManager creates status items

class SaneBarAppDelegate: NSObject, NSApplicationDelegate {
    enum DuplicateLaunchResolution: Equatable {
        case noConflict
        case waitForHandoff
        case terminateCurrent
        /// The current launch is a strictly newer build than every surviving
        /// instance, so the stale copies are terminated and the current one
        /// stays. This is the update path: a Sparkle relaunch must win over a
        /// slow-quitting or wedged older instance instead of being killed by it.
        case terminateOthers
    }

    static let duplicateLaunchGraceNanoseconds: UInt64 = 2_000_000_000
    static let automaticTerminationReason = "SaneBar must stay active as a menu bar app"
    static let automationLifecycleBreadcrumbPath = "/tmp/sanebar_lifecycle_breadcrumb.log"
    static let automationQuitTokenEnvironmentKey = "SANEBAR_AUTOMATION_QUIT_TOKEN"
    static let automationExplicitTerminationMarkerPath = "/tmp/sanebar_explicit_termination.token"
    private var keepAliveActivity: NSObjectProtocol?
    private var explicitTerminationRequested = false

    /// Decide what a freshly launched instance should do when other instances of
    /// the same bundle are alive.
    ///
    /// `currentBuild` / `maxSurvivingBuild` are the `CFBundleVersion` integers of
    /// this process and the newest surviving instance. When both are known and a
    /// conflict remains after the grace window, the NEWEST build wins: if this
    /// launch is strictly newer it terminates the stale survivors
    /// (`.terminateOthers`); otherwise it yields (`.terminateCurrent`). This is
    /// what makes a Sparkle update relaunch survive a slow-quitting or wedged old
    /// instance instead of being killed by it — the bug where a customer stayed
    /// stuck on the previous version and updates appeared to apply one at a time.
    /// With no version info it preserves the original first-wins behavior.
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

    /// Parse a bundle's `CFBundleVersion` into a comparable integer. SaneBar's
    /// build numbers are monotonic integers (e.g. `2180`, `2181`), so a numeric
    /// compare is the correct "which build is newer" test. Returns nil when the
    /// value is missing or non-numeric, which makes the caller fall back to the
    /// version-blind first-wins path rather than guessing.
    static func bundleBuildNumber(_ bundle: Bundle?) -> Int? {
        guard let raw = bundle?.infoDictionary?["CFBundleVersion"] as? String else { return nil }
        return Int(raw.trimmingCharacters(in: .whitespaces))
    }

    /// Pure selection of which already-running instance to bring forward before the
    /// just-launched duplicate exits. Picking the oldest survivor (lowest pid is a stable,
    /// dependency-free proxy for "launched first") keeps the choice deterministic when more
    /// than one prior instance is somehow alive, and excludes the current process so the
    /// copy that is about to terminate never tries to activate itself.
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

    // No @main - using main.swift instead

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

        // Near-instant tooltips (default is ~1000ms)
        UserDefaults.standard.set(100, forKey: "NSInitialToolTipDelay")
        #if !DEBUG
            if Self.shouldUpdateAppShortcutParameters() {
                SaneBarAppShortcuts.updateAppShortcutParameters()
            }
        #endif

        // Keep the menu bar process alive across idle periods.
        keepAliveActivity = ProcessInfo.processInfo.beginActivity(
            options: [.automaticTerminationDisabled, .suddenTerminationDisabled],
            reason: Self.automaticTerminationReason
        )
        ProcessInfo.processInfo.disableAutomaticTermination(Self.automaticTerminationReason)
        ProcessInfo.processInfo.disableSuddenTermination()

        // Guard against accidental duplicate launches of the same bundle.
        // Use a handoff grace window so update relaunches do not self-terminate.
        scheduleDuplicateInstanceTerminationCheckIfNeeded()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(explicitTerminationWasRequested(_:)),
            name: .saneBarExplicitTerminationRequested,
            object: nil
        )

        // Move to /Applications if running from Downloads or other location (Release only)
        #if !DEBUG && !APP_STORE && !SETAPP
            if SaneAppMover.moveToApplicationsFolderIfNeeded(prompt: .init(
                messageText: "Move to Applications?",
                informativeText: "{appName} works best from your Applications folder. Move it there now? You may be asked for your password.",
                moveButtonTitle: "Move to Applications",
                cancelButtonTitle: "Not Now"
            )) { return }
        #endif

        // CRITICAL: Set activation policy to accessory BEFORE creating status items!
        // This ensures NSStatusItem windows are created at the correct window layer (25).
        NSApp.setActivationPolicy(.accessory)

        // Load cached Pro state before the menu bar runtime creates any
        // license-gated status items. Otherwise launch can briefly create and
        // tear down the always-hidden separator while `isPro` catches up.
        LicenseService.shared.checkCachedLicense()

        // Initialize MenuBarManager (creates status items) - MUST be after activation policy is set
        _ = MenuBarManager.shared
        MenuBarManager.shared.actionWorkflow.normalizeLicenseDependentDefaults()

        // Configure keyboard shortcuts
        let shortcutsService = KeyboardShortcutsService.shared
        shortcutsService.configure(with: MenuBarManager.shared)
        shortcutsService.setDefaultsIfNeeded()

        // Apply user's preferred policy (may override to .regular if dock icon enabled)
        SaneActivationPolicy.applyInitialPolicy(showDockIcon: MenuBarManager.shared.settings.showDockIcon)
        SetappIntegration.logPurchaseType()
        SetappIntegration.showReleaseNotesIfNeeded(delay: 1.5)

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

    /// Highest `CFBundleVersion` among a set of running instances, or nil when
    /// none expose a numeric build (caller then falls back to first-wins).
    @MainActor
    private static func maxBuildNumber(among apps: [NSRunningApplication]) -> Int? {
        apps.compactMap { bundleBuildNumber(Bundle(url: $0.bundleURL ?? URL(fileURLWithPath: "/"))) }.max()
    }

    /// Gracefully terminate stale older-build instances so the newer current
    /// launch becomes the single live instance. `terminate()` posts a normal quit
    /// (the stale instances are not the keep-alive survivor), leaving the update
    /// running. Never called against the current process — `runningDuplicateInstances`
    /// already excludes self.
    @MainActor
    private func terminateStaleInstances(_ apps: [NSRunningApplication]) {
        for app in apps {
            app.terminate()
        }
    }

    /// Bring the already-running SaneBar instance forward so a customer who double-launched
    /// (login-item instance + a freshly downloaded copy) sees the app respond instead of the
    /// new copy silently vanishing. Side-effect-free on the normal single-launch path: this
    /// only runs inside the `.terminateCurrent` branch, which requires another live instance.
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
            whatsNewAction: LicenseService.shared.usesSetappDistribution
                ? #selector(showReleaseNotesFromDock(_:))
                : nil,
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
    @objc private func showReleaseNotesFromDock(_: Any?) {
        SetappIntegration.showReleaseNotes()
    }

    @MainActor
    @objc private func quitFromDock(_ sender: Any?) {
        requestExplicitTermination(reason: "dock-menu")
        NSApp.terminate(sender)
    }

    /// SaneBar is a menu-bar (agent) app — the status item is the entry point, so
    /// relaunching from Finder/Dock normally has nothing to open. But when the
    /// status item is missing or stuck off-screen (the #157 failure where macOS
    /// won't place it), doing nothing left the user with an invisible, unreachable
    /// app: no icon, no window, no way to repair or even export a diagnostic. Always
    /// give them a window — Health when the items aren't live (repair + report live
    /// there), Settings otherwise — so the app is never a dead end.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows: Bool) -> Bool {
        let itemsValid = MenuBarManager.shared.currentRuntimeSnapshot().startupItemsValid
        if itemsValid {
            if !hasVisibleWindows {
                SettingsOpener.open()
            }
        } else {
            appLogger.error("Reopen while status items are invalid — surfacing Health so the user can recover (#157)")
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            SettingsOpener.open(tab: .health)
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

// MARK: - Settings Opener

/// Opens Settings window programmatically
enum SettingsOpener {
    @MainActor private static var settingsWindow: NSWindow?
    @MainActor private static var windowDelegate: SettingsWindowDelegate?

    @MainActor static func open(tab: SettingsView.SettingsTab? = nil) {
        // DON'T force .regular here - respect the user's showDockIcon setting
        // An .accessory app CAN have visible windows (the dock icon just won't show)
        // This fixes the bug where dock icon appears when Settings opens despite setting being OFF
        NSApp.activate()

        let window: NSWindow
        if let existingWindow = settingsWindow {
            if let tab {
                existingWindow.contentViewController = NSHostingController(rootView: SettingsView(defaultTab: tab))
            }
            enforceUsableWindowSize(existingWindow, preferIdealSize: false)
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

        let window = SaneSettingsWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "SaneBar Settings"
        window.appearance = NSAppearance(named: .darkAqua)
        enforceUsableWindowSize(window, preferIdealSize: true)
        window.center()
        window.isReleasedWhenClosed = false

        let delegate = SettingsWindowDelegate()
        window.delegate = delegate
        windowDelegate = delegate
        settingsWindow = window
        return window
    }

    @MainActor private static func enforceUsableWindowSize(_ window: NSWindow, preferIdealSize: Bool) {
        let minimumSize = NSSize(
            width: SaneSettingsWindowDefaults.minWidth,
            height: SaneSettingsWindowDefaults.minHeight
        )
        window.contentMinSize = minimumSize

        let contentSize = window.contentLayoutRect.size
        guard preferIdealSize || contentSize.width < minimumSize.width || contentSize.height < minimumSize.height else {
            return
        }

        let targetSize = if preferIdealSize {
            NSSize(
                width: max(SaneBarSettingsWindowMetrics.idealWidth, minimumSize.width),
                height: max(SaneBarSettingsWindowMetrics.idealHeight, minimumSize.height)
            )
        } else {
            NSSize(
                width: max(contentSize.width, minimumSize.width),
                height: max(contentSize.height, minimumSize.height)
            )
        }
        window.setContentSize(targetSize)
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
        #if SETAPP
            _ = window
            return nil
        #else
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
        #endif
    }
}

/// Handles settings window lifecycle events
private class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    func windowWillClose(_: Notification) {
        SaneActivationPolicy.restorePolicy(showDockIcon: MenuBarManager.shared.settings.showDockIcon)
    }
}
