import Foundation

struct SaneBarCustomIconSnapshot: Codable, Equatable {
    /// Raw PNG payload for the current custom icon asset.
    /// `nil` means the snapshot was taken with no saved custom icon file.
    var pngData: Data?
}

struct SaneBarLayoutSnapshot: Codable, Equatable {
    struct DisplayBackup: Codable, Equatable {
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

struct SaneBarSettingsArchive: Codable {
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

enum SaneBarSettingsImportPayload {
    case archive(SaneBarSettingsArchive)
    case legacySettings(SaneBarSettings)
}

struct SaneBarImportPreviewPlan: Identifiable, Equatable {
    enum SourceKind: String, Equatable {
        case saneBarArchive = "SaneBar Archive"
        case saneBarLegacySettings = "SaneBar Settings"
        case bartender = "Bartender"
    }

    let id: UUID
    var sourceKind: SourceKind
    var fileName: String
    var showItemIds: [String]
    var hideItemIds: [String]
    var alwaysHideItemIds: [String]
    var hideAllOtherItems: Bool
    var missingItemIds: [String]
    var skippedItemIds: [String]
    var behavioralSettings: [String]
    var savedProfileCount: Int
    var includesLayoutSnapshot: Bool
    var includesCustomIconSnapshot: Bool

    init(
        id: UUID = UUID(),
        sourceKind: SourceKind,
        fileName: String,
        showItemIds: [String] = [],
        hideItemIds: [String] = [],
        alwaysHideItemIds: [String] = [],
        hideAllOtherItems: Bool = false,
        missingItemIds: [String] = [],
        skippedItemIds: [String] = [],
        behavioralSettings: [String] = [],
        savedProfileCount: Int = 0,
        includesLayoutSnapshot: Bool = false,
        includesCustomIconSnapshot: Bool = false
    ) {
        self.id = id
        self.sourceKind = sourceKind
        self.fileName = fileName
        self.showItemIds = showItemIds
        self.hideItemIds = hideItemIds
        self.alwaysHideItemIds = alwaysHideItemIds
        self.hideAllOtherItems = hideAllOtherItems
        self.missingItemIds = missingItemIds
        self.skippedItemIds = skippedItemIds
        self.behavioralSettings = behavioralSettings
        self.savedProfileCount = savedProfileCount
        self.includesLayoutSnapshot = includesLayoutSnapshot
        self.includesCustomIconSnapshot = includesCustomIconSnapshot
    }
}

enum SaneBarSettingsImportError: LocalizedError {
    case invalidArchive(underlying: Error)
    case invalidLegacySettings(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .invalidArchive:
            "The SaneBar settings archive is damaged or incomplete."
        case .invalidLegacySettings:
            "The selected file is not a valid SaneBar settings export."
        }
    }
}

extension SaneBarSettingsArchive {
    static func decodeImportPayload(
        from data: Data,
        using decoder: JSONDecoder
    ) throws -> SaneBarSettingsImportPayload {
        if looksLikeArchivePayload(data) {
            do {
                return try .archive(decoder.decode(SaneBarSettingsArchive.self, from: data))
            } catch {
                throw SaneBarSettingsImportError.invalidArchive(underlying: error)
            }
        }

        do {
            return try .legacySettings(decoder.decode(SaneBarSettings.self, from: data))
        } catch {
            throw SaneBarSettingsImportError.invalidLegacySettings(underlying: error)
        }
    }

    private static func looksLikeArchivePayload(_ data: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: data, options: []),
              let dictionary = object as? [String: Any]
        else {
            return false
        }

        return dictionary["settings"] != nil ||
            dictionary["layoutSnapshot"] != nil ||
            dictionary["customIconSnapshot"] != nil ||
            dictionary["savedProfiles"] != nil ||
            dictionary["exportedAt"] != nil ||
            dictionary["version"] != nil
    }
}

extension SaneBarSettingsImportPayload {
    func previewPlan(fileName: String) -> SaneBarImportPreviewPlan {
        switch self {
        case let .archive(archive):
            SaneBarImportPreviewPlan(
                sourceKind: .saneBarArchive,
                fileName: fileName,
                showItemIds: archive.settings.hideAllOtherVisibleItemIds,
                hideAllOtherItems: archive.settings.hideAllOtherMenuBarItems,
                behavioralSettings: Self.behavioralSettings(from: archive.settings),
                savedProfileCount: archive.savedProfiles.count,
                includesLayoutSnapshot: archive.layoutSnapshot != nil,
                includesCustomIconSnapshot: archive.customIconSnapshot?.pngData != nil
            )
        case let .legacySettings(settings):
            SaneBarImportPreviewPlan(
                sourceKind: .saneBarLegacySettings,
                fileName: fileName,
                showItemIds: settings.hideAllOtherVisibleItemIds,
                hideAllOtherItems: settings.hideAllOtherMenuBarItems,
                behavioralSettings: Self.behavioralSettings(from: settings)
            )
        }
    }

    private static func behavioralSettings(from settings: SaneBarSettings) -> [String] {
        var changes: [String] = []
        if settings.scriptTriggerEnabled {
            let path = settings.scriptTriggerPath.trimmingCharacters(in: .whitespacesAndNewlines)
            changes.append(path.isEmpty ? "Script trigger: on" : "Script trigger: \(path)")
        }
        return changes
    }
}

// MARK: - SaneBarProfile

/// A saved configuration profile
struct SaneBarProfile: Codable, Identifiable {
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
        createdAt = Date()
        modifiedAt = Date()
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
