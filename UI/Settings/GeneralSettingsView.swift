import SwiftUI
import ServiceManagement
import LocalAuthentication
import AppKit
import os.log

private let settingsLogger = Logger(subsystem: "com.sanebar.app", category: "Settings")

struct GeneralSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var launchAtLogin = false
    @State private var isAuthenticating = false  // Prevent duplicate auth prompts
    @State private var isCheckingForUpdates = false  // Debounce update checks

    // Profiles Logic
    @State private var savedProfiles: [SaneBarProfile] = []
    @State private var showingSaveProfileAlert = false
    @State private var newProfileName = ""
    @State private var showingResetAlert = false

    private struct SettingsExport: Codable {
        let version: Int
        let exportedAt: Date
        let settings: SaneBarSettings
    }

    private struct BartenderParsedItem: Hashable {
        let raw: String
    }

    private struct BartenderResolvedItem {
        let raw: String
        let bundleId: String
        let menuExtraId: String?
        let statusItemIndex: Int?
    }

    private struct BartenderProfile {
        let hide: [String]
        let show: [String]
        let alwaysHide: [String]
    }

    private struct BartenderResolutionContext {
        let availableByBundle: [String: [AccessibilityService.MenuBarItemPosition]]
        let availableByMenuExtraId: [String: AccessibilityService.MenuBarItemPosition]
        let availableByMenuExtraIdLower: [String: AccessibilityService.MenuBarItemPosition]
        let availableByBundleAndName: [String: AccessibilityService.MenuBarItemPosition]
    }

    private struct BartenderBundleMatch {
        let bundleId: String
        let token: String?
        let matchedRunning: Bool
    }

    private struct BartenderImportSummary {
        var movedHidden = 0
        var movedVisible = 0
        var failedMoves = 0
        var skippedNotRunning = 0
        var skippedAmbiguous = 0
        var skippedUnsupported = 0
        var skippedDuplicates = 0

        var totalMoved: Int { movedHidden + movedVisible }
    }

    private var showDockIconBinding: Binding<Bool> {
        Binding(
            get: { menuBarManager.settings.showDockIcon },
            set: { newValue in
                menuBarManager.settings.showDockIcon = newValue
                ActivationPolicyManager.applyPolicy(showDockIcon: newValue)
            }
        )
    }

    /// Custom binding that requires auth to DISABLE the security setting
    private var requireAuthBinding: Binding<Bool> {
        Binding(
            get: { menuBarManager.settings.requireAuthToShowHiddenIcons },
            set: { newValue in
                let currentValue = menuBarManager.settings.requireAuthToShowHiddenIcons

                // Enabling: allow immediately
                if newValue == true && currentValue == false {
                    menuBarManager.settings.requireAuthToShowHiddenIcons = true
                    return
                }

                // Disabling: require auth first (if currently enabled)
                // Guard against duplicate auth requests
                if currentValue == true && newValue == false && !isAuthenticating {
                    isAuthenticating = true
                    Task {
                        let authenticated = await authenticateToDisable()
                        await MainActor.run {
                            if authenticated {
                                menuBarManager.settings.requireAuthToShowHiddenIcons = false
                            }
                            isAuthenticating = false
                        }
                    }
                }
            }
        )
    }

    private func authenticateToDisable() async -> Bool {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        let policy: LAPolicy = context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
            ? .deviceOwnerAuthentication
            : .deviceOwnerAuthenticationWithBiometrics

        return await withCheckedContinuation { continuation in
            context.evaluatePolicy(policy, localizedReason: "Disable password protection for hidden icons") { success, _ in
                continuation.resume(returning: success)
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Startup Status
                CompactSection("Startup") {
                    CompactToggle(label: "Start automatically at login", isOn: Binding(
                        get: { launchAtLogin },
                        set: { newValue in
                            launchAtLogin = newValue
                            setLaunchAtLogin(newValue)
                        }
                    ))
                    .help("Launch SaneBar when you log in to your Mac")
                    CompactDivider()
                    CompactToggle(label: "Show app in Dock", isOn: showDockIconBinding)
                    .help("Show SaneBar icon in the Dock (menu bar icon always visible)")
                }

                // 2. Privacy (Auth)
                CompactSection("Security") {
                    CompactToggle(label: "Require password to show icons", isOn: requireAuthBinding)
                    .help("Require Touch ID or password to reveal hidden menu bar icons")
                }
                
                // 3. Updates
                CompactSection("Software Updates") {
                    CompactToggle(label: "Check for updates automatically", isOn: $menuBarManager.settings.checkForUpdatesAutomatically)
                    .help("Periodically check for new versions of SaneBar")
                    CompactDivider()
                    CompactRow("Actions") {
                        Button(isCheckingForUpdates ? "Checking…" : "Check Now") {
                            guard !isCheckingForUpdates else { return }
                            isCheckingForUpdates = true
                            menuBarManager.userDidClickCheckForUpdates()
                            // Re-enable after 5 seconds (debounce)
                            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                isCheckingForUpdates = false
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isCheckingForUpdates)
                        .help("Check for updates right now")
                    }
                }
                
                // 4. Profiles
                CompactSection("Saved Profiles") {
                    if savedProfiles.isEmpty {
                        CompactRow("Saved") {
                            Text("No saved profiles")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        ForEach(savedProfiles) { profile in
                            CompactRow(profile.name) {
                                HStack {
                                    Text(profile.modifiedAt.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    
                                    Button("Load") { loadProfile(profile) }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                    
                                    Button {
                                        deleteProfile(profile)
                                    } label: {
                                        Image(systemName: "trash")
                                        .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            CompactDivider()
                        }
                    }
                    
                    CompactDivider()
                    
                    CompactRow("Current Settings") {
                        Button("Save as Profile…") {
                            newProfileName = SaneBarProfile.generateName(basedOn: savedProfiles.map(\.name))
                            showingSaveProfileAlert = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Save all current settings as a named profile")
                    }
                }

                // 5. Data
                CompactSection("Data") {
                    CompactRow("Settings") {
                        Button("Export Settings...") {
                            exportSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Import Settings...") {
                            importSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    CompactDivider()

                    CompactRow("Migration") {
                        Button("Import Bartender...") {
                            importBartenderSettings()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }

                // 6. Troubleshooting
                CompactSection("Maintenance") {
                    CompactRow("Reset App") {
                        Button("Reset to Defaults…") {
                            showingResetAlert = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .foregroundStyle(.red)
                        .help("Reset all settings to factory defaults")
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            checkLaunchAtLogin()
            loadProfiles()
        }
        .alert("Save Profile", isPresented: $showingSaveProfileAlert) {
            TextField("Name", text: $newProfileName)
            Button("Save") { saveCurrentProfile() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Save your current configuration to restore later.")
        }
        .alert("Reset Settings?", isPresented: $showingResetAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                menuBarManager.resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their defaults. This cannot be undone.")
        }
    }

    // MARK: - Startup Helpers
    
    /// Whether this build is running from a proper install location (not DerivedData).
    /// Debug builds from Xcode run from DerivedData and should never register as login items,
    /// because that pollutes the Background Task Management database with stale paths.
    private var isProperInstall: Bool {
        let path = Bundle.main.bundlePath
        return !path.contains("DerivedData")
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        guard isProperInstall else {
            print("[SaneBar] Skipping login item registration — running from DerivedData")
            launchAtLogin = false
            return
        }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to set launch at login: \(error)")
            launchAtLogin = !launchAtLogin
        }
    }

    private func checkLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = (status == .enabled)
    }
    
    // MARK: - Profile Helpers
    
    private func loadProfiles() {
        do {
            savedProfiles = try PersistenceService.shared.listProfiles()
        } catch {
            print("[SaneBar] Failed to load profiles: \(error)")
        }
    }

    private func saveCurrentProfile() {
        guard !newProfileName.isEmpty else { return }
        var profile = SaneBarProfile(name: newProfileName, settings: menuBarManager.settings)
        profile.modifiedAt = Date()
        do {
            try PersistenceService.shared.saveProfile(profile)
            loadProfiles()
        } catch {
            print("[SaneBar] Failed to save profile: \(error)")
        }
    }

    private func loadProfile(_ profile: SaneBarProfile) {
        let currentAuthEnabled = menuBarManager.settings.requireAuthToShowHiddenIcons
        let profileAuthEnabled = profile.settings.requireAuthToShowHiddenIcons

        // SECURITY: If current auth is ON and profile would turn it OFF, require auth first
        if currentAuthEnabled && !profileAuthEnabled && !isAuthenticating {
            isAuthenticating = true
            Task {
                let authenticated = await authenticateToDisable()
                await MainActor.run {
                    if authenticated {
                        menuBarManager.settings = profile.settings
                        menuBarManager.saveSettings()
                    }
                    isAuthenticating = false
                }
            }
        } else {
            // No auth needed - either auth is off, or profile keeps it on
            menuBarManager.settings = profile.settings
            menuBarManager.saveSettings()
        }
    }

    private func deleteProfile(_ profile: SaneBarProfile) {
        do {
            try PersistenceService.shared.deleteProfile(id: profile.id)
            loadProfiles()
        } catch {
            print("[SaneBar] Failed to delete profile: \(error)")
        }
    }

    // MARK: - Export / Import

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "SaneBar-settings.json"
        panel.title = "Export Settings"

        guard panel.runModal() == .OK, let url = panel.url else {
            settingsLogger.log("📤 Export cancelled")
            return
        }

        let export = SettingsExport(version: 1, exportedAt: Date(), settings: menuBarManager.settings)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(export)
            try data.write(to: url)
            settingsLogger.log("📤 Exported settings to \(url.lastPathComponent, privacy: .public)")
        } catch {
            settingsLogger.error("📤 Export failed: \(error.localizedDescription, privacy: .public)")
            showError(title: "Export Failed", error: error)
        }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Settings"

        guard panel.runModal() == .OK, let url = panel.url else {
            settingsLogger.log("📥 Import cancelled")
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            if let export = try? decoder.decode(SettingsExport.self, from: data) {
                settingsLogger.log("📥 Importing wrapped settings from \(url.lastPathComponent, privacy: .public)")
                applyImportedSettings(export.settings)
            } else {
                settingsLogger.log("📥 Importing raw settings from \(url.lastPathComponent, privacy: .public)")
                let settings = try decoder.decode(SaneBarSettings.self, from: data)
                applyImportedSettings(settings)
            }
        } catch {
            settingsLogger.error("📥 Import failed: \(error.localizedDescription, privacy: .public)")
            showError(title: "Import Failed", error: error)
        }
    }

    private func applyImportedSettings(_ settings: SaneBarSettings) {
        let currentAuthEnabled = menuBarManager.settings.requireAuthToShowHiddenIcons
        let importedAuthEnabled = settings.requireAuthToShowHiddenIcons

        if currentAuthEnabled && !importedAuthEnabled && !isAuthenticating {
            isAuthenticating = true
            Task {
                let authenticated = await authenticateToDisable()
                await MainActor.run {
                    if authenticated {
                        menuBarManager.settings = settings
                        menuBarManager.saveSettings()
                        settingsLogger.log("📥 Imported settings applied after auth")
                    } else {
                        settingsLogger.log("📥 Import blocked by auth (no changes applied)")
                    }
                    isAuthenticating = false
                }
            }
        } else {
            menuBarManager.settings = settings
            menuBarManager.saveSettings()
            settingsLogger.log("📥 Imported settings applied")
        }
    }

    // MARK: - Bartender Import

    private func importBartenderSettings() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.propertyList]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Bartender Settings"
        panel.message = "Choose your Bartender .plist file"
        panel.prompt = "Import"
        if let prefsURL = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first?.appendingPathComponent("Preferences") {
            panel.directoryURL = prefsURL
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            settingsLogger.log("🍸 Bartender import cancelled")
            return
        }

        Task { @MainActor in
            await importBartenderSettings(from: url)
        }
    }

    @MainActor
    private func importBartenderSettings(from url: URL) async {
        settingsLogger.log("🍸 Importing Bartender settings from \(url.lastPathComponent, privacy: .public)")

        guard AccessibilityService.shared.requestAccessibility() else {
            showError(
                title: "Accessibility Required",
                error: NSError(domain: "SaneBar", code: 1, userInfo: [
                    NSLocalizedDescriptionKey: "Enable Accessibility in System Settings to import Bartender positions."
                ])
            )
            return
        }

        let profile: BartenderProfile
        do {
            let data = try Data(contentsOf: url)
            profile = try parseBartenderProfile(from: data)
        } catch {
            settingsLogger.error("🍸 Bartender import failed: \(error.localizedDescription, privacy: .public)")
            showError(title: "Bartender Import Failed", error: error)
            return
        }

        let hideRaw = profile.hide + profile.alwaysHide
        let showRaw = profile.show

        if hideRaw.isEmpty && showRaw.isEmpty {
            showError(
                title: "Bartender Import Failed",
                error: NSError(domain: "SaneBar", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "No Hide or Show entries found in the Bartender profile."
                ])
            )
            return
        }

        var summary = BartenderImportSummary()
        let parsedHide = hideRaw.compactMap(parseBartenderItem)
        let parsedShow = showRaw.compactMap(parseBartenderItem)

        var seen = Set<String>()
        let uniqueHide = parsedHide.filter { item in
            let inserted = seen.insert(item.raw).inserted
            if !inserted { summary.skippedDuplicates += 1 }
            return inserted
        }
        let uniqueShow = parsedShow.filter { item in
            let inserted = seen.insert(item.raw).inserted
            if !inserted { summary.skippedDuplicates += 1 }
            return inserted
        }

        let availableItems = await AccessibilityService.shared.listMenuBarItemsWithPositions()
        let availableByBundle = Dictionary(grouping: availableItems, by: { $0.app.bundleId })
        var availableByMenuExtraId: [String: AccessibilityService.MenuBarItemPosition] = [:]
        var availableByMenuExtraIdLower: [String: AccessibilityService.MenuBarItemPosition] = [:]
        var availableByBundleAndName: [String: AccessibilityService.MenuBarItemPosition] = [:]

        for item in availableItems {
            if let id = item.app.menuExtraIdentifier, availableByMenuExtraId[id] == nil {
                availableByMenuExtraId[id] = item
                availableByMenuExtraIdLower[id.lowercased()] = item
            }
            let key = "\(item.app.bundleId)|\(normalizeLabel(item.app.name))"
            if availableByBundleAndName[key] == nil {
                availableByBundleAndName[key] = item
            }
        }
        let context = BartenderResolutionContext(
            availableByBundle: availableByBundle,
            availableByMenuExtraId: availableByMenuExtraId,
            availableByMenuExtraIdLower: availableByMenuExtraIdLower,
            availableByBundleAndName: availableByBundleAndName
        )

        let wasHidden = menuBarManager.hidingState == .hidden
        if wasHidden {
            let revealed = await menuBarManager.showHiddenItemsNow(trigger: .settingsButton)
            if !revealed && menuBarManager.hidingState == .hidden {
                showError(
                    title: "Bartender Import Cancelled",
                    error: NSError(domain: "SaneBar", code: 3, userInfo: [
                        NSLocalizedDescriptionKey: "Authentication was required to reveal hidden icons."
                    ])
                )
                return
            }
        }

        for item in uniqueHide {
            if let resolved = resolveBartenderItem(item, context: context, summary: &summary) {
                let didMove = await menuBarManager.moveIconAndWait(
                    bundleID: resolved.bundleId,
                    menuExtraId: resolved.menuExtraId,
                    statusItemIndex: resolved.statusItemIndex,
                    toHidden: true
                )
                if didMove {
                    summary.movedHidden += 1
                } else {
                    summary.failedMoves += 1
                }
            }
        }

        for item in uniqueShow {
            if let resolved = resolveBartenderItem(item, context: context, summary: &summary) {
                let didMove = await menuBarManager.moveIconAndWait(
                    bundleID: resolved.bundleId,
                    menuExtraId: resolved.menuExtraId,
                    statusItemIndex: resolved.statusItemIndex,
                    toHidden: false
                )
                if didMove {
                    summary.movedVisible += 1
                } else {
                    summary.failedMoves += 1
                }
            }
        }

        if wasHidden {
            menuBarManager.hideHiddenItems()
        }

        let message = """
        Hidden: \(summary.movedHidden)
        Visible: \(summary.movedVisible)
        Failed moves: \(summary.failedMoves)
        Skipped (not running): \(summary.skippedNotRunning)
        Skipped (ambiguous): \(summary.skippedAmbiguous)
        Skipped (unsupported): \(summary.skippedUnsupported)
        Skipped (duplicates): \(summary.skippedDuplicates)
        """
        settingsLogger.log("🍸 Bartender import complete. \(summary.totalMoved) moved. Not running: \(summary.skippedNotRunning)")
        showInfo(title: "Bartender Import Complete", message: message)
    }

    private func parseBartenderProfile(from data: Data) throws -> BartenderProfile {
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        guard let root = plist as? [String: Any] else {
            throw NSError(domain: "SaneBar", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected Bartender plist format."
            ])
        }
        guard let profileSettings = root["ProfileSettings"] as? [String: Any],
              let activeProfile = profileSettings["activeProfile"] as? [String: Any] else {
            throw NSError(domain: "SaneBar", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "Bartender profile not found."
            ])
        }

        let hide = activeProfile["Hide"] as? [String] ?? []
        let show = activeProfile["Show"] as? [String] ?? []
        let alwaysHide = activeProfile["AlwaysHide"] as? [String] ?? []
        return BartenderProfile(hide: hide, show: show, alwaysHide: alwaysHide)
    }

    private func parseBartenderItem(_ raw: String) -> BartenderParsedItem? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        return BartenderParsedItem(raw: trimmed)
    }

    private func parseStatusItemIndex(from token: String?) -> Int? {
        guard let token, let range = token.range(of: "Item-", options: .backwards) else { return nil }
        let suffix = token[range.upperBound...]
        guard !suffix.isEmpty, suffix.allSatisfy({ $0.isNumber }) else { return nil }
        return Int(suffix)
    }

    private func resolveBundleIdAndToken(from raw: String, availableBundles: Set<String>) -> BartenderBundleMatch? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if availableBundles.contains(trimmed) {
            return BartenderBundleMatch(bundleId: trimmed, token: nil, matchedRunning: true)
        }

        let candidates = availableBundles.filter { trimmed.hasPrefix($0 + "-") }
        if let bundleId = candidates.max(by: { $0.count < $1.count }) {
            let tokenStart = trimmed.index(trimmed.startIndex, offsetBy: bundleId.count + 1)
            let token = String(trimmed[tokenStart...])
            return BartenderBundleMatch(bundleId: bundleId, token: token, matchedRunning: true)
        }

        if let dashIndex = trimmed.firstIndex(of: "-") {
            let bundleId = String(trimmed[..<dashIndex])
            let token = String(trimmed[trimmed.index(after: dashIndex)...])
            return BartenderBundleMatch(bundleId: bundleId, token: token.isEmpty ? nil : token, matchedRunning: false)
        }

        return BartenderBundleMatch(bundleId: trimmed, token: nil, matchedRunning: availableBundles.contains(trimmed))
    }

    private func resolveBartenderItem(
        _ item: BartenderParsedItem,
        context: BartenderResolutionContext,
        summary: inout BartenderImportSummary
    ) -> BartenderResolvedItem? {
        if item.raw.hasPrefix("com.surteesstudios.Bartender") {
            summary.skippedUnsupported += 1
            return nil
        }

        let availableBundles = Set(context.availableByBundle.keys)
        guard let bundleMatch = resolveBundleIdAndToken(from: item.raw, availableBundles: availableBundles) else {
            summary.skippedAmbiguous += 1
            return nil
        }

        guard bundleMatch.matchedRunning else {
            summary.skippedNotRunning += 1
            return nil
        }

        let bundleId = bundleMatch.bundleId
        guard let runningItems = context.availableByBundle[bundleId], !runningItems.isEmpty else {
            summary.skippedNotRunning += 1
            return nil
        }

        if let statusItemIndex = parseStatusItemIndex(from: bundleMatch.token) {
            return BartenderResolvedItem(raw: item.raw, bundleId: bundleId, menuExtraId: nil, statusItemIndex: statusItemIndex)
        }

        if let token = bundleMatch.token, let candidate = menuExtraIdCandidate(from: token) {
            if let match = context.availableByMenuExtraId[candidate] {
                return BartenderResolvedItem(raw: item.raw, bundleId: bundleId, menuExtraId: match.app.menuExtraIdentifier, statusItemIndex: match.app.statusItemIndex)
            }
            if let match = context.availableByMenuExtraIdLower[candidate.lowercased()] {
                return BartenderResolvedItem(raw: item.raw, bundleId: bundleId, menuExtraId: match.app.menuExtraIdentifier, statusItemIndex: match.app.statusItemIndex)
            }
            if runningItems.count == 1 {
                let match = runningItems[0].app
                return BartenderResolvedItem(raw: item.raw, bundleId: bundleId, menuExtraId: match.menuExtraIdentifier, statusItemIndex: match.statusItemIndex)
            }
            summary.skippedAmbiguous += 1
            return nil
        }

        if let token = bundleMatch.token {
            let key = "\(bundleId)|\(normalizeLabel(token))"
            if let match = context.availableByBundleAndName[key] {
                let app = match.app
                return BartenderResolvedItem(raw: item.raw, bundleId: bundleId, menuExtraId: app.menuExtraIdentifier, statusItemIndex: app.statusItemIndex)
            }
        }

        if runningItems.count == 1 {
            let match = runningItems[0].app
            return BartenderResolvedItem(raw: item.raw, bundleId: bundleId, menuExtraId: match.menuExtraIdentifier, statusItemIndex: match.statusItemIndex)
        }

        summary.skippedAmbiguous += 1
        return nil
    }

    private func menuExtraIdCandidate(from token: String) -> String? {
        if let range = token.range(of: "com.apple.menuextra.") {
            return String(token[range.lowerBound...])
        }
        if token.contains(".") {
            return token
        }
        return nil
    }

    private func normalizeLabel(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private func showInfo(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    private func showError(title: String, error: Error) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.runModal()
    }
}
