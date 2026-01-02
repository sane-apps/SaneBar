import Foundation

// MARK: - PersistenceServiceProtocol

/// @mockable
protocol PersistenceServiceProtocol: Sendable {
    func saveItemConfigurations(_ items: [StatusItemModel]) throws
    func loadItemConfigurations() throws -> [StatusItemModel]
    func saveSettings(_ settings: SaneBarSettings) throws
    func loadSettings() throws -> SaneBarSettings
    func saveProfiles(_ profiles: [Profile]) throws
    func loadProfiles() throws -> [Profile]
    func clearAll() throws
    func mergeWithSaved(scannedItems: [StatusItemModel], savedItems: [StatusItemModel]) -> [StatusItemModel]
    func exportConfiguration() throws -> Data
    func importConfiguration(from data: Data) throws -> (items: [StatusItemModel], settings: SaneBarSettings)
}

// MARK: - SaneBarSettings

/// Global app settings
struct SaneBarSettings: Codable, Sendable, Equatable {
    /// Whether hidden items auto-hide after a delay
    var autoRehide: Bool = true

    /// Delay before auto-rehiding in seconds
    var rehideDelay: TimeInterval = 3.0

    /// Whether to show hidden items on hover
    var showOnHover: Bool = true

    /// Hover delay before showing hidden items
    var hoverDelay: TimeInterval = 0.3

    /// Whether to show separator between sections
    var showSeparator: Bool = true

    /// Active profile ID (nil = default)
    var activeProfileId: UUID?

    /// Global keyboard shortcut for toggling hidden items
    var toggleShortcut: KeyboardShortcutData?

    /// Whether usage analytics are enabled
    var analyticsEnabled: Bool = true

    /// Whether smart suggestions are enabled
    var smartSuggestionsEnabled: Bool = true
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

// MARK: - Profile

/// A named configuration profile (e.g., "Work", "Home")
struct Profile: Codable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var itemSections: [String: StatusItemModel.ItemSection] // compositeKey -> section
    var isTimeBasedProfile: Bool = false
    var startTime: Date?
    var endTime: Date?
    var activeDays: Set<Int> = [] // 1 = Sunday, 7 = Saturday

    init(
        id: UUID = UUID(),
        name: String,
        itemSections: [String: StatusItemModel.ItemSection] = [:],
        isTimeBasedProfile: Bool = false,
        startTime: Date? = nil,
        endTime: Date? = nil,
        activeDays: Set<Int> = []
    ) {
        self.id = id
        self.name = name
        self.itemSections = itemSections
        self.isTimeBasedProfile = isTimeBasedProfile
        self.startTime = startTime
        self.endTime = endTime
        self.activeDays = activeDays
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

    private var itemsFileURL: URL {
        appSupportDirectory.appendingPathComponent("items.json")
    }

    private var settingsFileURL: URL {
        appSupportDirectory.appendingPathComponent("settings.json")
    }

    private var profilesFileURL: URL {
        appSupportDirectory.appendingPathComponent("profiles.json")
    }

    // MARK: - JSON Encoder/Decoder

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    // MARK: - Item Configurations

    func saveItemConfigurations(_ items: [StatusItemModel]) throws {
        let data = try encoder.encode(items)
        try data.write(to: itemsFileURL, options: .atomic)
    }

    func loadItemConfigurations() throws -> [StatusItemModel] {
        guard fileManager.fileExists(atPath: itemsFileURL.path) else {
            return []
        }

        let data = try Data(contentsOf: itemsFileURL)
        return try decoder.decode([StatusItemModel].self, from: data)
    }

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

    // MARK: - Profiles

    func saveProfiles(_ profiles: [Profile]) throws {
        let data = try encoder.encode(profiles)
        try data.write(to: profilesFileURL, options: .atomic)
    }

    func loadProfiles() throws -> [Profile] {
        guard fileManager.fileExists(atPath: profilesFileURL.path) else {
            // Return default profile
            return [Profile(name: "Default")]
        }

        let data = try Data(contentsOf: profilesFileURL)
        return try decoder.decode([Profile].self, from: data)
    }

    // MARK: - Clear All

    func clearAll() throws {
        try? fileManager.removeItem(at: itemsFileURL)
        try? fileManager.removeItem(at: settingsFileURL)
        try? fileManager.removeItem(at: profilesFileURL)
    }

    // MARK: - Merge Helpers

    /// Merge saved configurations with freshly scanned items
    /// Preserves user's section assignments while updating positions
    func mergeWithSaved(scannedItems: [StatusItemModel], savedItems: [StatusItemModel]) -> [StatusItemModel] {
        var result = scannedItems

        // Use reduce to handle potential duplicate keys gracefully (keep last occurrence)
        let savedByKey = savedItems.reduce(into: [String: StatusItemModel]()) { dict, item in
            dict[item.compositeKey] = item
        }

        for index in result.indices {
            let key = result[index].compositeKey
            if let saved = savedByKey[key] {
                // Preserve user's section assignment and analytics
                result[index].section = saved.section
                result[index].originalPosition = saved.originalPosition ?? result[index].position
                result[index].clickCount = saved.clickCount
                result[index].lastClickDate = saved.lastClickDate
                result[index].lastShownDate = saved.lastShownDate
            } else {
                // New item - store its original position
                result[index].originalPosition = result[index].position
            }
        }

        return result
    }

    // MARK: - Import/Export

    /// Export configuration bundle for items and settings
    struct ExportBundle: Codable {
        let version: Int
        let items: [StatusItemModel]
        let settings: SaneBarSettings
        let exportDate: Date

        static let currentVersion = 1
    }

    /// Export all configuration as a single Data blob
    func exportConfiguration() throws -> Data {
        let items = try loadItemConfigurations()
        let settings = try loadSettings()

        let bundle = ExportBundle(
            version: ExportBundle.currentVersion,
            items: items,
            settings: settings,
            exportDate: Date()
        )

        return try encoder.encode(bundle)
    }

    /// Import configuration from a Data blob
    func importConfiguration(from data: Data) throws -> (items: [StatusItemModel], settings: SaneBarSettings) {
        let bundle = try decoder.decode(ExportBundle.self, from: data)

        // Validate version
        guard bundle.version <= ExportBundle.currentVersion else {
            throw ImportError.unsupportedVersion(bundle.version)
        }

        return (bundle.items, bundle.settings)
    }

    enum ImportError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return "Unsupported configuration version: \(version). Please update SaneBar."
            }
        }
    }
}
