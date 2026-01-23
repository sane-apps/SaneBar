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
        case slash          // / (Default)
        case backslash      // \
        case pipe           // |
        case pipeThin       // ❘
        case dot            // •
    }

    /// User-created icon group for organizing menu bar apps
    struct IconGroup: Codable, Sendable, Equatable, Identifiable {
        var id: UUID = UUID()
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
    var spacerCount: Int = 2  // Default to 2 dividers for immediate value discovery

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
    var menuBarAppearance: MenuBarAppearanceSettings = MenuBarAppearanceSettings()

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

    /// When true, reveal all icons while user is ⌘+dragging to rearrange (Ice-style)
    var showOnUserDrag: Bool = true

    /// When true, auto-hide when the focused app changes (Ice-style "focusedApp" strategy)
    var rehideOnAppChange: Bool = false

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

    // MARK: - Backwards-compatible decoding

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoRehide = try container.decodeIfPresent(Bool.self, forKey: .autoRehide) ?? true
        rehideDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .rehideDelay) ?? 5.0
        findIconRehideDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .findIconRehideDelay) ?? 15.0
        spacerCount = try container.decodeIfPresent(Int.self, forKey: .spacerCount) ?? 2
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
        showOnClick = try container.decodeIfPresent(Bool.self, forKey: .showOnClick) ?? true
        gestureToggles = try container.decodeIfPresent(Bool.self, forKey: .gestureToggles) ?? false
        useDirectionalScroll = try container.decodeIfPresent(Bool.self, forKey: .useDirectionalScroll) ?? false
        showOnUserDrag = try container.decodeIfPresent(Bool.self, forKey: .showOnUserDrag) ?? true
        rehideOnAppChange = try container.decodeIfPresent(Bool.self, forKey: .rehideOnAppChange) ?? false
        menuBarSpacing = try container.decodeIfPresent(Int.self, forKey: .menuBarSpacing)
        menuBarSelectionPadding = try container.decodeIfPresent(Int.self, forKey: .menuBarSelectionPadding)
        checkForUpdatesAutomatically = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdatesAutomatically) ?? true
        lastUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        hideMainIcon = try container.decodeIfPresent(Bool.self, forKey: .hideMainIcon) ?? false
        dividerStyle = try container.decodeIfPresent(DividerStyle.self, forKey: .dividerStyle) ?? .slash
    }

    private enum CodingKeys: String, CodingKey {
        case autoRehide, rehideDelay, findIconRehideDelay, spacerCount, spacerStyle, spacerWidth, showOnAppLaunch, triggerApps
        case iconHotkeys, iconGroups, showOnLowBattery, hasCompletedOnboarding
        case menuBarAppearance, showOnNetworkChange, triggerNetworks, showDockIcon
        case showOnFocusModeChange, triggerFocusModes
        case requireAuthToShowHiddenIcons
        case showOnHover, hoverDelay, showOnScroll, showOnClick, gestureToggles
        case useDirectionalScroll, showOnUserDrag, rehideOnAppChange
        case menuBarSpacing, menuBarSelectionPadding
        case checkForUpdatesAutomatically, lastUpdateCheck
        case hideMainIcon, dividerStyle
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

    private let fileManager = FileManager.default

    private var appSupportDirectory: URL {
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

    func saveSettings(_ settings: SaneBarSettings) throws {
        let data = try encoder.encode(settings)
        try data.write(to: settingsFileURL, options: .atomic)
    }

    func loadSettings() throws -> SaneBarSettings {
        guard fileManager.fileExists(atPath: settingsFileURL.path) else {
            return SaneBarSettings()
        }

        let data = try Data(contentsOf: settingsFileURL)
        return try decoder.decode(SaneBarSettings.self, from: data)
    }

    // MARK: - Clear All

    func clearAll() throws {
        try? fileManager.removeItem(at: settingsFileURL)
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
            return "Profile not found"
        case .limitReached:
            return "Profile limit reached (max 50). Please delete some profiles first."
        }
    }
}
