import Foundation

struct SaneBarCustomIconSnapshot: Codable, Sendable, Equatable {
    /// Raw PNG payload for the current custom icon asset.
    /// `nil` means the snapshot was taken with no saved custom icon file.
    var pngData: Data?
}

struct SaneBarLayoutSnapshot: Codable, Sendable, Equatable {
    struct DisplayBackup: Codable, Sendable, Equatable {
        var widthBucket: Int
        var mainPosition: Double?
        var separatorPosition: Double?
    }

    var mainPosition: Double?
    var separatorPosition: Double?
    var alwaysHiddenSeparatorPosition: Double?
    var spacerPositions: [Int: Double] = [:]
    var calibratedScreenWidth: Double?
    var displayBackups: [DisplayBackup] = []
}

struct SaneBarSettingsArchive: Codable, Sendable {
    let version: Int
    let exportedAt: Date
    let settings: SaneBarSettings
    let layoutSnapshot: SaneBarLayoutSnapshot?
    let customIconSnapshot: SaneBarCustomIconSnapshot?
    let savedProfiles: [SaneBarProfile]

    init(
        version: Int,
        exportedAt: Date,
        settings: SaneBarSettings,
        layoutSnapshot: SaneBarLayoutSnapshot?,
        customIconSnapshot: SaneBarCustomIconSnapshot?,
        savedProfiles: [SaneBarProfile]
    ) {
        self.version = version
        self.exportedAt = exportedAt
        self.settings = settings
        self.layoutSnapshot = layoutSnapshot
        self.customIconSnapshot = customIconSnapshot
        self.savedProfiles = savedProfiles
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        exportedAt = try container.decodeIfPresent(Date.self, forKey: .exportedAt) ?? Date()
        settings = try container.decode(SaneBarSettings.self, forKey: .settings)
        layoutSnapshot = try container.decodeIfPresent(SaneBarLayoutSnapshot.self, forKey: .layoutSnapshot)
        customIconSnapshot = try container.decodeIfPresent(SaneBarCustomIconSnapshot.self, forKey: .customIconSnapshot)
        savedProfiles = try container.decodeIfPresent([SaneBarProfile].self, forKey: .savedProfiles) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case exportedAt
        case settings
        case layoutSnapshot
        case customIconSnapshot
        case savedProfiles
    }
}

// MARK: - SaneBarProfile

/// A saved configuration profile
struct SaneBarProfile: Codable, Identifiable, Sendable {
    /// Unique identifier
    let id: UUID

    /// User-friendly name for the profile
    var name: String

    /// The settings for this profile
    var settings: SaneBarSettings

    /// Saved layout positions for menu bar items and spacers.
    var layoutSnapshot: SaneBarLayoutSnapshot?

    /// Saved custom icon asset state for this profile.
    var customIconSnapshot: SaneBarCustomIconSnapshot?

    /// When the profile was created
    let createdAt: Date

    /// When the profile was last modified
    var modifiedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        settings: SaneBarSettings,
        layoutSnapshot: SaneBarLayoutSnapshot? = nil,
        customIconSnapshot: SaneBarCustomIconSnapshot? = nil
    ) {
        self.id = id
        self.name = name
        self.settings = settings
        self.layoutSnapshot = layoutSnapshot
        self.customIconSnapshot = customIconSnapshot
        self.createdAt = Date()
        self.modifiedAt = Date()
    }
}

// MARK: - Profile Name

extension SaneBarProfile {
    /// Generate a unique profile name
    static func generateName(basedOn existing: [String]) -> String {
        let baseName = "Profile"
        var counter = 1

        while existing.contains("\(baseName) \(counter)") {
            counter += 1
        }

        return "\(baseName) \(counter)"
    }
}
