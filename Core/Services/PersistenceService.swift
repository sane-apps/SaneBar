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

    /// Bundle IDs of apps that should always be visible (not hidden)
    /// User must Cmd+drag these icons to the right of the separator
    var alwaysVisibleApps: [String] = []

    /// Per-icon hotkey configurations: bundleID -> shortcut key data
    /// When triggered, shows hidden items and activates the app
    var iconHotkeys: [String: KeyboardShortcutData] = [:]

    /// Show hidden items when battery drops to low level
    var showOnLowBattery: Bool = false

    /// Whether the user has completed first-launch onboarding
    var hasCompletedOnboarding: Bool = false

    // MARK: - Backwards-compatible decoding

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        autoRehide = try container.decodeIfPresent(Bool.self, forKey: .autoRehide) ?? true
        rehideDelay = try container.decodeIfPresent(TimeInterval.self, forKey: .rehideDelay) ?? 3.0
        spacerCount = try container.decodeIfPresent(Int.self, forKey: .spacerCount) ?? 0
        showOnAppLaunch = try container.decodeIfPresent(Bool.self, forKey: .showOnAppLaunch) ?? false
        triggerApps = try container.decodeIfPresent([String].self, forKey: .triggerApps) ?? []
        alwaysVisibleApps = try container.decodeIfPresent([String].self, forKey: .alwaysVisibleApps) ?? []
        iconHotkeys = try container.decodeIfPresent([String: KeyboardShortcutData].self, forKey: .iconHotkeys) ?? [:]
        showOnLowBattery = try container.decodeIfPresent(Bool.self, forKey: .showOnLowBattery) ?? false
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case autoRehide, rehideDelay, spacerCount, showOnAppLaunch, triggerApps, alwaysVisibleApps, iconHotkeys, showOnLowBattery, hasCompletedOnboarding
    }
}

// MARK: - KeyboardShortcutData

/// Serializable representation of a keyboard shortcut
struct KeyboardShortcutData: Codable, Sendable, Hashable {
    var keyCode: UInt16
    var modifiers: UInt

    init(keyCode: UInt16, modifiers: UInt) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }
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
        let appSupport = paths.first!.appendingPathComponent("SaneBar", isDirectory: true)

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
        let data = try encoder.encode(profile)
        let url = profileFileURL(for: profile.id)
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

    var errorDescription: String? {
        switch self {
        case .profileNotFound:
            return "Profile not found"
        }
    }
}
