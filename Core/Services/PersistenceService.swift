import AppKit
import Foundation


protocol PersistenceServiceProtocol: Sendable {
    func saveSettings(_ settings: SaneBarSettings) throws
    func loadSettings() throws -> SaneBarSettings
    func clearAll() throws
}


struct SaneBarSettings: Codable, Equatable {
    enum SpacerStyle: String, Codable, CaseIterable {
        case line
        case dot
    }

    enum SpacerWidth: String, Codable, CaseIterable {
        case compact
        case normal
        case wide
    }

    enum DividerStyle: String, Codable, CaseIterable {
        case slash
        case backslash
        case pipe
        case pipeThin
        case dot
    }

    enum MenuBarIconStyle: String, Codable, CaseIterable {
        case filter
        case sliders
        case dots
        case lines
        case chevron
        case coin
        case custom

        var sfSymbolName: String? {
            switch self {
            case .filter: "line.3.horizontal.decrease"
            case .sliders: "slider.horizontal.3"
            case .dots: "ellipsis"
            case .lines: "line.3.horizontal"
            case .chevron: "chevron.up.chevron.down"
            case .coin: "circle.circle"
            case .custom: nil
            }
        }
    }

    enum GestureMode: String, Codable, CaseIterable {
        case showOnly = "Show only"
        case showAndHide = "Show and hide"
    }

    enum LayoutMode: String, Codable, CaseIterable {
        case stability = "Stability"
        case live = "Live"
    }

    enum TriggerAction: String, Codable, CaseIterable {
        case showIcons = "Show Icons"
        case applyProfile = "Apply Profile"
    }

    struct IconGroup: Codable, Equatable, Identifiable {
        var id: UUID = .init()
        var name: String
        var appBundleIds: [String] = []

        init(name: String, appBundleIds: [String] = []) {
            self.name = name
            self.appBundleIds = appBundleIds
        }
    }

    var autoRehide: Bool = true

    var rehideDelay: TimeInterval = 5.0

    var findIconRehideDelay: TimeInterval = 15.0

    var spacerCount: Int = 0

    var spacerStyle: SpacerStyle = .line

    var spacerWidth: SpacerWidth = .normal

    var showOnAppLaunch: Bool = false

    var triggerApps: [String] = []

    var appLaunchTriggerAction: TriggerAction = .showIcons

    var appLaunchTriggerProfileId: UUID?

    var iconHotkeys: [String: KeyboardShortcutData] = [:]

    var iconGroups: [IconGroup] = []

    var showOnLowBattery: Bool = false

    var batteryThreshold: Int = 20

    var batteryTriggerAction: TriggerAction = .showIcons

    var batteryTriggerProfileId: UUID?

    var hasCompletedOnboarding: Bool = false

    var hasSeenFreemiumIntro: Bool = false


    var requireAuthToShowHiddenIcons: Bool = false

    var menuBarAppearance: MenuBarAppearanceSettings = .init()

    var showOnNetworkChange: Bool = false

    var triggerNetworks: [String] = []

    var networkTriggerAction: TriggerAction = .showIcons

    var networkTriggerProfileId: UUID?

    var showDockIcon: Bool = false


    var showOnFocusModeChange: Bool = false

    var triggerFocusModes: [String] = []

    var focusTriggerAction: TriggerAction = .showIcons

    var focusTriggerProfileId: UUID?


    var showOnSchedule: Bool = false

    var scheduleWeekdays: [Int] = [2, 3, 4, 5, 6]

    var scheduleTriggerAction: TriggerAction = .showIcons

    var scheduleTriggerProfileId: UUID?

    var scheduleStartHour: Int = 9
    var scheduleStartMinute: Int = 0

    var scheduleEndHour: Int = 17
    var scheduleEndMinute: Int = 0


    var showOnHover: Bool = false

    var hoverDelay: TimeInterval = 2.0

    var showOnScroll: Bool = false

    var showOnClick: Bool = false

    var hideApplicationMenusOnInlineReveal: Bool = true

    var gestureToggles: Bool = false

    var useDirectionalScroll: Bool = false

    var gestureMode: GestureMode {
        get {
            gestureToggles ? .showAndHide : .showOnly
        }
        set {
            switch newValue {
            case .showOnly:
                gestureToggles = false
                useDirectionalScroll = false
            case .showAndHide:
                gestureToggles = true
                useDirectionalScroll = true
            }
        }
    }

    var showOnUserDrag: Bool = true

    var rehideOnAppChange: Bool = false

    var disableOnExternalMonitor: Bool = false


    var menuBarSpacing: Int?

    var menuBarSelectionPadding: Int?


    var checkForUpdatesAutomatically: Bool = true

    var lastUpdateCheck: Date?


    var hideMainIcon: Bool = false

    var dividerStyle: DividerStyle = .slash

    var menuBarIconStyle: MenuBarIconStyle = .filter


    var alwaysHiddenSectionEnabled: Bool = false

    var useSecondMenuBar: Bool = false

    var secondMenuBarShowVisible: Bool = true

    var secondMenuBarShowAlwaysHidden: Bool = false

    var leftClickOpensBrowseIcons: Bool = false

    var alwaysHiddenPinnedItemIds: [String] = []

    var hideAllOtherMenuBarItems: Bool = false

    var hideAllOtherVisibleItemIds: [String] = []

    var layoutMode: LayoutMode = .stability

    var hasCompletedHealthWizard: Bool = false

    var layoutRescueRestorePoint: SaneBarLayoutSnapshot?

    var layoutRescueRestorePointCreatedAt: Date?


    var scriptTriggerEnabled: Bool = false

    var scriptTriggerPath: String = ""

    var scriptTriggerInterval: TimeInterval = 10.0


    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoRehide = try container.decodeIfPresent(Bool.self, forKey: .autoRehide) ?? true
        rehideDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .rehideDelay) ?? 5.0
        findIconRehideDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .findIconRehideDelay) ?? 15.0
        spacerCount = try container.decodeIfPresent(Int.self, forKey: .spacerCount) ?? 0
        spacerStyle = try container.decodeIfPresent(SpacerStyle.self, forKey: .spacerStyle) ?? .line
        spacerWidth = try container.decodeIfPresent(SpacerWidth.self, forKey: .spacerWidth) ?? .normal
        showOnAppLaunch = try container.decodeIfPresent(Bool.self, forKey: .showOnAppLaunch) ?? false
        triggerApps = try container.decodeIfPresent([String].self, forKey: .triggerApps) ?? []
        appLaunchTriggerAction = try container.decodeIfPresent(TriggerAction.self, forKey: .appLaunchTriggerAction) ?? .showIcons
        appLaunchTriggerProfileId = try container.decodeIfPresent(UUID.self, forKey: .appLaunchTriggerProfileId)
        iconHotkeys = try container.decodeIfPresent([String: KeyboardShortcutData].self, forKey: .iconHotkeys) ?? [:]
        iconGroups = try container.decodeIfPresent([IconGroup].self, forKey: .iconGroups) ?? []
        showOnLowBattery = try container.decodeIfPresent(Bool.self, forKey: .showOnLowBattery) ?? false
        batteryThreshold = try container.decodeIfPresent(Int.self, forKey: .batteryThreshold) ?? 20
        batteryTriggerAction = try container.decodeIfPresent(TriggerAction.self, forKey: .batteryTriggerAction) ?? .showIcons
        batteryTriggerProfileId = try container.decodeIfPresent(UUID.self, forKey: .batteryTriggerProfileId)
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        hasSeenFreemiumIntro = try container.decodeIfPresent(Bool.self, forKey: .hasSeenFreemiumIntro) ?? false
        requireAuthToShowHiddenIcons = try container.decodeIfPresent(Bool.self, forKey: .requireAuthToShowHiddenIcons) ?? false
        menuBarAppearance = try container.decodeIfPresent(
            MenuBarAppearanceSettings.self,
            forKey: .menuBarAppearance
        ) ?? MenuBarAppearanceSettings()
        showOnNetworkChange = try container.decodeIfPresent(Bool.self, forKey: .showOnNetworkChange) ?? false
        triggerNetworks = try container.decodeIfPresent([String].self, forKey: .triggerNetworks) ?? []
        networkTriggerAction = try container.decodeIfPresent(TriggerAction.self, forKey: .networkTriggerAction) ?? .showIcons
        networkTriggerProfileId = try container.decodeIfPresent(UUID.self, forKey: .networkTriggerProfileId)
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
        showOnFocusModeChange = try container.decodeIfPresent(Bool.self, forKey: .showOnFocusModeChange) ?? false
        triggerFocusModes = try container.decodeIfPresent([String].self, forKey: .triggerFocusModes) ?? []
        focusTriggerAction = try container.decodeIfPresent(TriggerAction.self, forKey: .focusTriggerAction) ?? .showIcons
        focusTriggerProfileId = try container.decodeIfPresent(UUID.self, forKey: .focusTriggerProfileId)
        showOnSchedule = try container.decodeIfPresent(Bool.self, forKey: .showOnSchedule) ?? false
        scheduleWeekdays = try container.decodeIfPresent([Int].self, forKey: .scheduleWeekdays) ?? [2, 3, 4, 5, 6]
        scheduleTriggerAction = try container.decodeIfPresent(TriggerAction.self, forKey: .scheduleTriggerAction) ?? .showIcons
        scheduleTriggerProfileId = try container.decodeIfPresent(UUID.self, forKey: .scheduleTriggerProfileId)
        scheduleStartHour = try min(max(container.decodeIfPresent(Int.self, forKey: .scheduleStartHour) ?? 9, 0), 23)
        scheduleStartMinute = try min(max(container.decodeIfPresent(Int.self, forKey: .scheduleStartMinute) ?? 0, 0), 59)
        scheduleEndHour = try min(max(container.decodeIfPresent(Int.self, forKey: .scheduleEndHour) ?? 17, 0), 23)
        scheduleEndMinute = try min(max(container.decodeIfPresent(Int.self, forKey: .scheduleEndMinute) ?? 0, 0), 59)
        showOnHover = try container.decodeIfPresent(Bool.self, forKey: .showOnHover) ?? false
        hoverDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .hoverDelay) ?? 2.0
        showOnScroll = try container.decodeIfPresent(Bool.self, forKey: .showOnScroll) ?? false
        _ = try container.decodeIfPresent(Bool.self, forKey: .showOnClick)
        showOnClick = false
        hideApplicationMenusOnInlineReveal = try container.decodeIfPresent(Bool.self, forKey: .hideApplicationMenusOnInlineReveal) ?? true
        gestureToggles = try container.decodeIfPresent(Bool.self, forKey: .gestureToggles) ?? false
        useDirectionalScroll = try container.decodeIfPresent(Bool.self, forKey: .useDirectionalScroll) ?? false
        showOnUserDrag = try container.decodeIfPresent(Bool.self, forKey: .showOnUserDrag) ?? true
        rehideOnAppChange = try container.decodeIfPresent(Bool.self, forKey: .rehideOnAppChange) ?? false
        disableOnExternalMonitor = try container.decodeIfPresent(Bool.self, forKey: .disableOnExternalMonitor) ?? false
        menuBarSpacing = try container.decodeIfPresent(Int.self, forKey: .menuBarSpacing)
        menuBarSelectionPadding = try container.decodeIfPresent(Int.self, forKey: .menuBarSelectionPadding)
        checkForUpdatesAutomatically = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdatesAutomatically) ?? true
        lastUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        hideMainIcon = try container.decodeIfPresent(Bool.self, forKey: .hideMainIcon) ?? false
        dividerStyle = try container.decodeIfPresent(DividerStyle.self, forKey: .dividerStyle) ?? .slash
        menuBarIconStyle = try container.decodeIfPresent(MenuBarIconStyle.self, forKey: .menuBarIconStyle) ?? .filter
        alwaysHiddenSectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .alwaysHiddenSectionEnabled) ?? false
        alwaysHiddenPinnedItemIds = try container.decodeIfPresent([String].self, forKey: .alwaysHiddenPinnedItemIds) ?? []
        hideAllOtherMenuBarItems = try container.decodeIfPresent(Bool.self, forKey: .hideAllOtherMenuBarItems) ?? false
        hideAllOtherVisibleItemIds = try container.decodeIfPresent([String].self, forKey: .hideAllOtherVisibleItemIds) ?? []
        layoutMode = try container.decodeIfPresent(LayoutMode.self, forKey: .layoutMode) ?? .stability
        hasCompletedHealthWizard = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedHealthWizard) ?? false
        layoutRescueRestorePoint = try container.decodeIfPresent(SaneBarLayoutSnapshot.self, forKey: .layoutRescueRestorePoint)
        layoutRescueRestorePointCreatedAt = try container.decodeIfPresent(Date.self, forKey: .layoutRescueRestorePointCreatedAt)
        scriptTriggerEnabled = try container.decodeIfPresent(Bool.self, forKey: .scriptTriggerEnabled) ?? false
        scriptTriggerPath = try container.decodeIfPresent(String.self, forKey: .scriptTriggerPath) ?? ""
        scriptTriggerInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .scriptTriggerInterval) ?? 10.0
        let legacyContainer = try decoder.container(keyedBy: LegacyCodingKeys.self)
        let legacyDropdownPanel = try legacyContainer.decodeIfPresent(Bool.self, forKey: .useDropdownPanel)
        useSecondMenuBar = try container.decodeIfPresent(Bool.self, forKey: .useSecondMenuBar)
            ?? legacyDropdownPanel
            ?? false
        secondMenuBarShowVisible = try container.decodeIfPresent(Bool.self, forKey: .secondMenuBarShowVisible) ?? true
        secondMenuBarShowAlwaysHidden = try container.decodeIfPresent(Bool.self, forKey: .secondMenuBarShowAlwaysHidden) ?? false
        leftClickOpensBrowseIcons = try container.decodeIfPresent(Bool.self, forKey: .leftClickOpensBrowseIcons) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case autoRehide, rehideDelay, findIconRehideDelay, spacerCount, spacerStyle, spacerWidth, showOnAppLaunch, triggerApps
        case appLaunchTriggerAction, appLaunchTriggerProfileId
        case iconHotkeys, iconGroups, showOnLowBattery, batteryThreshold, batteryTriggerAction, batteryTriggerProfileId
        case hasCompletedOnboarding, hasSeenFreemiumIntro
        case menuBarAppearance, showOnNetworkChange, triggerNetworks, networkTriggerAction, networkTriggerProfileId, showDockIcon
        case showOnFocusModeChange, triggerFocusModes, focusTriggerAction, focusTriggerProfileId
        case showOnSchedule, scheduleWeekdays, scheduleTriggerAction, scheduleTriggerProfileId
        case scheduleStartHour, scheduleStartMinute, scheduleEndHour, scheduleEndMinute
        case requireAuthToShowHiddenIcons
        case showOnHover, hoverDelay, showOnScroll, showOnClick, hideApplicationMenusOnInlineReveal, gestureToggles
        case useDirectionalScroll, showOnUserDrag, rehideOnAppChange, disableOnExternalMonitor
        case menuBarSpacing, menuBarSelectionPadding
        case checkForUpdatesAutomatically, lastUpdateCheck
        case hideMainIcon, dividerStyle, menuBarIconStyle
        case alwaysHiddenSectionEnabled, alwaysHiddenPinnedItemIds, useSecondMenuBar, secondMenuBarShowVisible, secondMenuBarShowAlwaysHidden, leftClickOpensBrowseIcons
        case hideAllOtherMenuBarItems, hideAllOtherVisibleItemIds, layoutMode
        case hasCompletedHealthWizard, layoutRescueRestorePoint, layoutRescueRestorePointCreatedAt
        case scriptTriggerEnabled, scriptTriggerPath, scriptTriggerInterval
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case useDropdownPanel
    }
}


struct KeyboardShortcutData: Codable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt
}


final class PersistenceService: PersistenceServiceProtocol, @unchecked Sendable {

    static let shared = PersistenceService()


    private let fileManager: FileManager
    private let keychain: KeychainServiceProtocol
    private let appSupportDirectoryOverride: URL?
    private let userDefaults: UserDefaults

    init(
        fileManager: FileManager = FileManager.default,
        keychain: KeychainServiceProtocol = KeychainService.shared,
        appSupportDirectoryOverride: URL? = nil,
        userDefaults: UserDefaults = .standard
    ) {
        self.fileManager = fileManager
        self.keychain = keychain
        self.appSupportDirectoryOverride = appSupportDirectoryOverride
        self.userDefaults = userDefaults
    }

    private var appSupportDirectory: URL {
        if let override = appSupportDirectoryOverride {
            if !fileManager.fileExists(atPath: override.path) {
                try? fileManager.createDirectory(at: override, withIntermediateDirectories: true)
            }
            return override
        }

        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let base = paths.first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let appSupport = base.appendingPathComponent("SaneBar", isDirectory: true)

        if !fileManager.fileExists(atPath: appSupport.path) {
            try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }

        return appSupport
    }

    private var settingsFileURL: URL {
        appSupportDirectory.appendingPathComponent("settings.json")
    }


    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()


    private enum LegacyKeychainKeys {
        static let requireAuthToShowHiddenIcons = "settings.requireAuthToShowHiddenIcons"
    }

    func saveSettings(_ settings: SaneBarSettings) throws {
        let data = try encoder.encode(settings)
        try data.write(to: settingsFileURL, options: .atomic)
    }

    func loadSettings() throws -> SaneBarSettings {
        guard fileManager.fileExists(atPath: settingsFileURL.path) else {
            var settings = SaneBarSettings()
            if let legacy = try? keychain.bool(forKey: LegacyKeychainKeys.requireAuthToShowHiddenIcons) {
                settings.requireAuthToShowHiddenIcons = legacy
            }
            return settings
        }

        let data = try Data(contentsOf: settingsFileURL)
        var settings = try decoder.decode(SaneBarSettings.self, from: data)
        var shouldRewriteJSON = false

        let hasOnboardingKey = hasTopLevelKey("hasCompletedOnboarding", in: data)
        if !hasOnboardingKey {
            settings.hasCompletedOnboarding = true
            shouldRewriteJSON = true
        }

        let hasHealthWizardKey = hasTopLevelKey("hasCompletedHealthWizard", in: data)
        if !hasHealthWizardKey {
            settings.hasCompletedHealthWizard = settings.hasCompletedOnboarding
            shouldRewriteJSON = true
        }

        let hasAuthKey = hasTopLevelKey("requireAuthToShowHiddenIcons", in: data)
        if !hasAuthKey,
           let legacy = try? keychain.bool(forKey: LegacyKeychainKeys.requireAuthToShowHiddenIcons) {
            settings.requireAuthToShowHiddenIcons = legacy
            shouldRewriteJSON = true
            try? keychain.delete(LegacyKeychainKeys.requireAuthToShowHiddenIcons)
        }

        let revealDwellMigrationKey = "SaneBar_didMigrateRevealDwell_v1"
        if !userDefaults.bool(forKey: revealDwellMigrationKey) {
            if settings.hoverDelay == 0.25 {
                settings.hoverDelay = 2.0
                shouldRewriteJSON = true
            }
            userDefaults.set(true, forKey: revealDwellMigrationKey)
        }

        if shouldRewriteJSON {
            let rewritten = try encoder.encode(settings)
            try rewritten.write(to: settingsFileURL, options: .atomic)
        }

        return settings
    }


    func clearAll() throws {
        try? fileManager.removeItem(at: settingsFileURL)
        try? keychain.delete(LegacyKeychainKeys.requireAuthToShowHiddenIcons)
    }

    private func hasTopLevelKey(_ key: String, in data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = object as? [String: Any]
        else {
            return false
        }
        return dict.keys.contains(key)
    }


    private var customIconURL: URL {
        appSupportDirectory.appendingPathComponent("custom_icon.png")
    }

    func saveCustomIcon(_ image: NSImage) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return
        }
        try pngData.write(to: customIconURL, options: .atomic)
    }

    func loadCustomIcon() -> NSImage? {
        guard fileManager.fileExists(atPath: customIconURL.path),
              let image = NSImage(contentsOf: customIconURL)
        else {
            return nil
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    func loadCustomIconData() -> Data? {
        guard fileManager.fileExists(atPath: customIconURL.path) else {
            return nil
        }
        return try? Data(contentsOf: customIconURL)
    }

    func saveCustomIconData(_ data: Data) throws {
        try data.write(to: customIconURL, options: .atomic)
    }

    func applyCustomIconSnapshot(_ snapshot: SaneBarCustomIconSnapshot) throws {
        if let pngData = snapshot.pngData {
            try saveCustomIconData(pngData)
        } else {
            removeCustomIcon()
        }
    }

    func makeCustomIconSnapshot() -> SaneBarCustomIconSnapshot {
        SaneBarCustomIconSnapshot(pngData: loadCustomIconData())
    }

    func removeCustomIcon() {
        try? fileManager.removeItem(at: customIconURL)
    }


    private var profilesDirectory: URL {
        let profiles = appSupportDirectory.appendingPathComponent("profiles", isDirectory: true)

        if !fileManager.fileExists(atPath: profiles.path) {
            try? fileManager.createDirectory(at: profiles, withIntermediateDirectories: true)
        }

        return profiles
    }

    private func profileFileURL(for id: UUID) -> URL {
        profilesDirectory.appendingPathComponent("\(id.uuidString).json")
    }

    func saveProfile(_ profile: SaneBarProfile) throws {
        let url = profileFileURL(for: profile.id)
        if !fileManager.fileExists(atPath: url.path) {
            let existingProfiles = try listProfiles()
            if existingProfiles.count >= 50 {
                throw PersistenceError.limitReached
            }
        }

        let data = try encoder.encode(profile)
        try data.write(to: url, options: .atomic)
    }

    func loadProfile(id: UUID) throws -> SaneBarProfile {
        let url = profileFileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw PersistenceError.profileNotFound
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(SaneBarProfile.self, from: data)
    }

    func listProfiles() throws -> [SaneBarProfile] {
        let contents = try fileManager.contentsOfDirectory(
            at: profilesDirectory,
            includingPropertiesForKeys: nil
        )

        return contents.compactMap { url -> SaneBarProfile? in
            guard url.pathExtension == "json" else { return nil }
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? decoder.decode(SaneBarProfile.self, from: data)
        }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func upsertProfiles(_ profiles: [SaneBarProfile]) throws {
        guard !profiles.isEmpty else { return }

        let existingProfiles = try listProfiles()
        var profilesByID = Dictionary(uniqueKeysWithValues: existingProfiles.map { ($0.id, $0) })
        for profile in profiles {
            profilesByID[profile.id] = profile
        }

        guard profilesByID.count <= 50 else {
            throw PersistenceError.limitReached
        }

        for profile in profiles {
            try saveProfile(profile)
        }
    }

    func deleteProfile(id: UUID) throws {
        let url = profileFileURL(for: id)
        try fileManager.removeItem(at: url)
    }
}


enum PersistenceError: Error, LocalizedError {
    case profileNotFound
    case limitReached

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            "Profile not found"
        case .limitReached:
            "Profile limit reached (max 50). Please delete some profiles first."
        }
    }
}
