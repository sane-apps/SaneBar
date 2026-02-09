import AppKit
import Foundation

// MARK: - PersistenceServiceProtocol

/// @mockable
protocol PersistenceServiceProtocol: Sendable {
    func saveSettings(_ settings: SaneBarSettings) throws
    func loadSettings() throws -> SaneBarSettings
    func clearAll() throws
}

// MARK: - SaneBarSettings

/// Global app settings
struct SaneBarSettings: Codable, Sendable, Equatable {
    enum SpacerStyle: String, Codable, CaseIterable, Sendable {
        case line
        case dot
    }

    enum SpacerWidth: String, Codable, CaseIterable, Sendable {
        case compact
        case normal
        case wide
    }

    enum DividerStyle: String, Codable, CaseIterable, Sendable {
        case slash // / (Default)
        case backslash // \
        case pipe // |
        case pipeThin // ❘
        case dot // •
    }

    enum MenuBarIconStyle: String, Codable, CaseIterable, Sendable {
        case filter // line.3.horizontal.decrease (Default)
        case dots // ellipsis
        case lines // line.3.horizontal
        case chevron // chevron.up.chevron.down
        case coin // circle.circle
        case custom // User-uploaded image

        var sfSymbolName: String? {
            switch self {
            case .filter: "line.3.horizontal.decrease"
            case .dots: "ellipsis"
            case .lines: "line.3.horizontal"
            case .chevron: "chevron.up.chevron.down"
            case .coin: "circle.circle"
            case .custom: nil
            }
        }
    }

    /// Simplified gesture behavior mode (replaces gestureToggles + useDirectionalScroll)
    enum GestureMode: String, Codable, CaseIterable, Sendable {
        case showOnly = "Show only"
        case showAndHide = "Show and hide"
    }

    /// User-created icon group for organizing menu bar apps
    struct IconGroup: Codable, Sendable, Equatable, Identifiable {
        var id: UUID = .init()
        var name: String
        var appBundleIds: [String] = []

        init(name: String, appBundleIds: [String] = []) {
            self.name = name
            self.appBundleIds = appBundleIds
        }
    }

    /// Whether hidden items auto-hide after a delay
    var autoRehide: Bool = true

    /// Delay before auto-rehiding in seconds
    var rehideDelay: TimeInterval = 5.0

    /// Delay before rehiding after Find Icon search (seconds)
    /// Longer than regular rehide to allow browsing opened menus
    var findIconRehideDelay: TimeInterval = 15.0

    /// Number of spacers to show (0-12)
    var spacerCount: Int = 0 // Clean by default — users add spacers if they want them

    /// Global visual style for spacers
    var spacerStyle: SpacerStyle = .line

    /// Global width preset for spacers
    var spacerWidth: SpacerWidth = .normal

    /// Show hidden items when specific apps launch
    var showOnAppLaunch: Bool = false

    /// Bundle IDs of apps that trigger showing hidden items
    var triggerApps: [String] = []

    /// Per-icon hotkey configurations: bundleID -> shortcut key data
    /// When triggered, shows hidden items and activates the app
    var iconHotkeys: [String: KeyboardShortcutData] = [:]

    /// User-created icon groups for organizing menu bar apps in Find Icon
    var iconGroups: [IconGroup] = []

    /// Show hidden items when battery drops to low level
    var showOnLowBattery: Bool = false

    /// Whether the user has completed first-launch onboarding
    var hasCompletedOnboarding: Bool = false

    // MARK: - Privacy (Advanced)

    /// If enabled, showing hidden icons requires Touch ID / password.
    /// This is a UX safety feature (prevents casual snooping), not a perfect security boundary.
    var requireAuthToShowHiddenIcons: Bool = false

    /// Menu bar appearance/tint settings
    var menuBarAppearance: MenuBarAppearanceSettings = .init()

    /// Show hidden items when connecting to specific WiFi networks
    var showOnNetworkChange: Bool = false

    /// WiFi network SSIDs that trigger showing hidden items
    var triggerNetworks: [String] = []

    /// Show Dock icon (default: false for backward compatibility)
    /// When false, app uses .accessory mode (no Dock icon)
    /// When true, app uses .regular mode (Dock icon visible)
    var showDockIcon: Bool = false

    // MARK: - Focus Mode Triggers

    /// Show hidden items when Focus Mode changes to a trigger mode
    var showOnFocusModeChange: Bool = false

    /// Focus Mode names that trigger showing hidden items (e.g., "Work", "Personal")
    /// Also supports special value "(Focus Off)" to trigger when Focus turns off
    var triggerFocusModes: [String] = []

    // MARK: - Hover & Gesture Triggers

    /// Show hidden icons when hovering near the menu bar
    var showOnHover: Bool = false

    /// Delay before hover triggers reveal (in seconds)
    var hoverDelay: TimeInterval = 0.25

    /// Show hidden icons when scrolling up in the menu bar
    var showOnScroll: Bool = false

    /// Show hidden icons when clicking in the menu bar
    var showOnClick: Bool = false

    /// When true, scroll/click gestures toggle visibility (hide if visible, show if hidden)
    /// When false, gestures only reveal (default behavior)
    var gestureToggles: Bool = false

    /// When true, scroll direction matters: up=show, down=hide (Ice-style)
    /// Only applies when gestureToggles is false
    var useDirectionalScroll: Bool = false

    /// Simplified gesture mode - maps to gestureToggles + useDirectionalScroll
    /// "Show only": gestures only reveal icons
    /// "Show and hide": click toggles, scroll is directional (Ice-style)
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

    /// When true, reveal all icons while user is ⌘+dragging to rearrange (Ice-style)
    var showOnUserDrag: Bool = true

    /// When true, auto-hide when the focused app changes (Ice-style "focusedApp" strategy)
    var rehideOnAppChange: Bool = false

    /// When true, SaneBar won't hide icons when the mouse is on an external monitor
    /// (External monitors have plenty of space, no need to hide)
    var disableOnExternalMonitor: Bool = false

    // MARK: - System Icon Spacing

    /// System-wide spacing between menu bar icons (1-10, nil = system default)
    /// Uses macOS private API: NSStatusItemSpacing
    var menuBarSpacing: Int?

    /// System-wide click-area padding for menu bar icons (1-10, nil = system default)
    /// Uses macOS private API: NSStatusItemSelectionPadding
    var menuBarSelectionPadding: Int?

    // MARK: - Update Checking

    /// Automatically check for updates on launch
    var checkForUpdatesAutomatically: Bool = true

    /// Last time we checked for updates (for rate limiting)
    var lastUpdateCheck: Date?

    // MARK: - Icon Visibility

    /// Hide the main SaneBar icon (show only divider)
    var hideMainIcon: Bool = false

    /// Style of the main divider (/, \, |, etc.)
    var dividerStyle: DividerStyle = .slash

    /// Style of the main SaneBar menu bar icon
    var menuBarIconStyle: MenuBarIconStyle = .filter

    // MARK: - Hiding

    /// Enable a second separator for an always-hidden zone.
    var alwaysHiddenSectionEnabled: Bool = false

    /// Show hidden icons in a dropdown panel below the menu bar instead of expanding the separator.
    var useDropdownPanel: Bool = false

    /// Menu bar item IDs that should be kept in the always-hidden section across launches.
    /// Stored as `RunningApp.uniqueId` values (best-effort).
    var alwaysHiddenPinnedItemIds: [String] = []

    // MARK: - Script Trigger

    /// Run a user-defined shell script on a timer to control visibility.
    /// Exit code 0 = show hidden items, non-zero = hide.
    var scriptTriggerEnabled: Bool = false

    /// Path to the shell script to execute
    var scriptTriggerPath: String = ""

    /// Interval in seconds between script executions (min: 1)
    var scriptTriggerInterval: TimeInterval = 10.0

    // MARK: - Backwards-compatible decoding

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
        iconHotkeys = try container.decodeIfPresent([String: KeyboardShortcutData].self, forKey: .iconHotkeys) ?? [:]
        iconGroups = try container.decodeIfPresent([IconGroup].self, forKey: .iconGroups) ?? []
        showOnLowBattery = try container.decodeIfPresent(Bool.self, forKey: .showOnLowBattery) ?? false
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        requireAuthToShowHiddenIcons = try container.decodeIfPresent(Bool.self, forKey: .requireAuthToShowHiddenIcons) ?? false
        menuBarAppearance = try container.decodeIfPresent(
            MenuBarAppearanceSettings.self,
            forKey: .menuBarAppearance
        ) ?? MenuBarAppearanceSettings()
        showOnNetworkChange = try container.decodeIfPresent(Bool.self, forKey: .showOnNetworkChange) ?? false
        triggerNetworks = try container.decodeIfPresent([String].self, forKey: .triggerNetworks) ?? []
        showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
        showOnFocusModeChange = try container.decodeIfPresent(Bool.self, forKey: .showOnFocusModeChange) ?? false
        triggerFocusModes = try container.decodeIfPresent([String].self, forKey: .triggerFocusModes) ?? []
        showOnHover = try container.decodeIfPresent(Bool.self, forKey: .showOnHover) ?? false
        hoverDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .hoverDelay) ?? 0.25
        showOnScroll = try container.decodeIfPresent(Bool.self, forKey: .showOnScroll) ?? true
        // showOnClick removed in v1.0.17 — global click monitor interfered with visible items.
        // Force to false for existing users; decode to discard old value silently.
        _ = try container.decodeIfPresent(Bool.self, forKey: .showOnClick)
        showOnClick = false
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
        scriptTriggerEnabled = try container.decodeIfPresent(Bool.self, forKey: .scriptTriggerEnabled) ?? false
        scriptTriggerPath = try container.decodeIfPresent(String.self, forKey: .scriptTriggerPath) ?? ""
        scriptTriggerInterval = try container.decodeIfPresent(TimeInterval.self, forKey: .scriptTriggerInterval) ?? 10.0
        useDropdownPanel = try container.decodeIfPresent(Bool.self, forKey: .useDropdownPanel) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case autoRehide, rehideDelay, findIconRehideDelay, spacerCount, spacerStyle, spacerWidth, showOnAppLaunch, triggerApps
        case iconHotkeys, iconGroups, showOnLowBattery, hasCompletedOnboarding
        case menuBarAppearance, showOnNetworkChange, triggerNetworks, showDockIcon
        case showOnFocusModeChange, triggerFocusModes
        case requireAuthToShowHiddenIcons
        case showOnHover, hoverDelay, showOnScroll, showOnClick, gestureToggles
        case useDirectionalScroll, showOnUserDrag, rehideOnAppChange, disableOnExternalMonitor
        case menuBarSpacing, menuBarSelectionPadding
        case checkForUpdatesAutomatically, lastUpdateCheck
        case hideMainIcon, dividerStyle, menuBarIconStyle
        case alwaysHiddenSectionEnabled, alwaysHiddenPinnedItemIds, useDropdownPanel
        case scriptTriggerEnabled, scriptTriggerPath, scriptTriggerInterval
    }
}

// MARK: - KeyboardShortcutData

/// Serializable representation of a keyboard shortcut
struct KeyboardShortcutData: Codable, Sendable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt
}

// MARK: - PersistenceService

/// Service for persisting SaneBar configuration to disk
final class PersistenceService: PersistenceServiceProtocol, @unchecked Sendable {
    // MARK: - Singleton

    static let shared = PersistenceService()

    // MARK: - File Paths

    private let fileManager: FileManager
    private let keychain: KeychainServiceProtocol
    private let appSupportDirectoryOverride: URL?

    init(
        fileManager: FileManager = FileManager.default,
        keychain: KeychainServiceProtocol = KeychainService.shared,
        appSupportDirectoryOverride: URL? = nil
    ) {
        self.fileManager = fileManager
        self.keychain = keychain
        self.appSupportDirectoryOverride = appSupportDirectoryOverride
    }

    private var appSupportDirectory: URL {
        if let override = appSupportDirectoryOverride {
            if !fileManager.fileExists(atPath: override.path) {
                try? fileManager.createDirectory(at: override, withIntermediateDirectories: true)
            }
            return override
        }

        let paths = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        // Be defensive: this should exist on macOS, but avoid crashing if it doesn't.
        let base = paths.first ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let appSupport = base.appendingPathComponent("SaneBar", isDirectory: true)

        // Create directory if needed
        if !fileManager.fileExists(atPath: appSupport.path) {
            try? fileManager.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }

        return appSupport
    }

    private var settingsFileURL: URL {
        appSupportDirectory.appendingPathComponent("settings.json")
    }

    // MARK: - JSON Encoder/Decoder

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private let decoder = JSONDecoder()

    // MARK: - Settings

    private enum KeychainKeys {
        static let requireAuthToShowHiddenIcons = "settings.requireAuthToShowHiddenIcons"
    }

    func saveSettings(_ settings: SaneBarSettings) throws {
        try persistRequireAuthSetting(settings.requireAuthToShowHiddenIcons)
        let data = try encoder.encode(settings)
        let sanitized = try stripTopLevelKey("requireAuthToShowHiddenIcons", from: data)
        try sanitized.write(to: settingsFileURL, options: .atomic)
    }

    func loadSettings() throws -> SaneBarSettings {
        guard fileManager.fileExists(atPath: settingsFileURL.path) else {
            var settings = SaneBarSettings()
            settings.requireAuthToShowHiddenIcons = (try? keychain.bool(forKey: KeychainKeys.requireAuthToShowHiddenIcons)) ?? false
            return settings
        }

        let data = try Data(contentsOf: settingsFileURL)
        let legacy = legacyRequireAuthInfo(from: data)
        var settings = try decoder.decode(SaneBarSettings.self, from: data)

        let keychainValue = try? keychain.bool(forKey: KeychainKeys.requireAuthToShowHiddenIcons)
        if let keychainValue {
            settings.requireAuthToShowHiddenIcons = keychainValue
        } else if legacy.present {
            try persistRequireAuthSetting(legacy.value)
            settings.requireAuthToShowHiddenIcons = legacy.value
        }

        // If the legacy key existed, strip it to avoid drift / confusion.
        if legacy.present {
            let rewritten = try stripTopLevelKey("requireAuthToShowHiddenIcons", from: encoder.encode(settings))
            try rewritten.write(to: settingsFileURL, options: .atomic)
        }

        return settings
    }

    // MARK: - Clear All

    func clearAll() throws {
        try? fileManager.removeItem(at: settingsFileURL)
        try? keychain.delete(KeychainKeys.requireAuthToShowHiddenIcons)
    }

    private func persistRequireAuthSetting(_ value: Bool) throws {
        if value {
            try keychain.set(true, forKey: KeychainKeys.requireAuthToShowHiddenIcons)
        } else {
            try keychain.delete(KeychainKeys.requireAuthToShowHiddenIcons)
        }
    }

    private func legacyRequireAuthInfo(from data: Data) -> (present: Bool, value: Bool) {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dict = object as? [String: Any],
              let raw = dict["requireAuthToShowHiddenIcons"]
        else {
            return (false, false)
        }
        return (true, (raw as? Bool) ?? false)
    }

    private func stripTopLevelKey(_ key: String, from data: Data) throws -> Data {
        let object = try JSONSerialization.jsonObject(with: data, options: [])
        guard var dict = object as? [String: Any] else { return data }
        dict.removeValue(forKey: key)
        return try JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Custom Icon

    private var customIconURL: URL {
        appSupportDirectory.appendingPathComponent("custom_icon.png")
    }

    /// Save a user-provided image as the custom menu bar icon
    func saveCustomIcon(_ image: NSImage) throws {
        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            return
        }
        try pngData.write(to: customIconURL, options: .atomic)
    }

    /// Load the custom menu bar icon, if one has been saved
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

    /// Remove the custom icon file
    func removeCustomIcon() {
        try? fileManager.removeItem(at: customIconURL)
    }

    // MARK: - Profiles

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

    /// Save a profile to disk
    func saveProfile(_ profile: SaneBarProfile) throws {
        // Check limit if creating a new profile (by checking if file exists)
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

    /// Load a specific profile
    func loadProfile(id: UUID) throws -> SaneBarProfile {
        let url = profileFileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else {
            throw PersistenceError.profileNotFound
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(SaneBarProfile.self, from: data)
    }

    /// List all saved profiles
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

    /// Delete a profile
    func deleteProfile(id: UUID) throws {
        let url = profileFileURL(for: id)
        try fileManager.removeItem(at: url)
    }
}

// MARK: - PersistenceError

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
