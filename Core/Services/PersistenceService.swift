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
    /// Whether hidden items auto-hide after a delay
    var autoRehide: Bool = true

    /// Delay before auto-rehiding in seconds
    var rehideDelay: TimeInterval = 3.0

    /// Number of spacers to show (0-3)
    var spacerCount: Int = 0

    /// Show hidden items when specific apps launch
    var showOnAppLaunch: Bool = false

    /// Bundle IDs of apps that trigger showing hidden items
    var triggerApps: [String] = []

    /// Per-icon hotkey configurations: bundleID -> shortcut key data
    /// When triggered, shows hidden items and activates the app
    var iconHotkeys: [String: KeyboardShortcutData] = [:]

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

    // MARK: - Hover & Gesture Triggers

    /// Show hidden icons when hovering near the menu bar
    var showOnHover: Bool = false

    /// Delay before hover triggers reveal (in seconds)
    var hoverDelay: TimeInterval = 0.15

    /// Show hidden icons when scrolling up in the menu bar
    var showOnScroll: Bool = false

    // MARK: - Update Checking

    /// Automatically check for updates on launch (off by default for privacy)
    var checkForUpdatesAutomatically: Bool = false

    /// Last time we checked for updates (for rate limiting)
    var lastUpdateCheck: Date?

    // MARK: - Backwards-compatible decoding

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoRehide = try container.decodeIfPresent(Bool.self, forKey: .autoRehide) ?? true
        rehideDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .rehideDelay) ?? 3.0
        spacerCount = try container.decodeIfPresent(Int.self, forKey: .spacerCount) ?? 0
        showOnAppLaunch = try container.decodeIfPresent(Bool.self, forKey: .showOnAppLaunch) ?? false
        triggerApps = try container.decodeIfPresent([String].self, forKey: .triggerApps) ?? []
        iconHotkeys = try container.decodeIfPresent([String: KeyboardShortcutData].self, forKey: .iconHotkeys) ?? [:]
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
        showOnHover = try container.decodeIfPresent(Bool.self, forKey: .showOnHover) ?? false
        hoverDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .hoverDelay) ?? 0.15
        showOnScroll = try container.decodeIfPresent(Bool.self, forKey: .showOnScroll) ?? false
        checkForUpdatesAutomatically = try container.decodeIfPresent(Bool.self, forKey: .checkForUpdatesAutomatically) ?? false
        lastUpdateCheck = try container.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
    }

    private enum CodingKeys: String, CodingKey {
        case autoRehide, rehideDelay, spacerCount, showOnAppLaunch, triggerApps
        case iconHotkeys, showOnLowBattery, hasCompletedOnboarding
        case menuBarAppearance, showOnNetworkChange, triggerNetworks, showDockIcon
        case requireAuthToShowHiddenIcons
        case showOnHover, hoverDelay, showOnScroll
        case checkForUpdatesAutomatically, lastUpdateCheck
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
