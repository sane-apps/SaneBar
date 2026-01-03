import Foundation

// MARK: - SaneBarProfile

/// A saved configuration profile
struct SaneBarProfile: Codable, Identifiable, Sendable {
    /// Unique identifier
    let id: UUID

    /// User-friendly name for the profile
    var name: String

    /// The settings for this profile
    var settings: SaneBarSettings

    /// When the profile was created
    let createdAt: Date

    /// When the profile was last modified
    var modifiedAt: Date

    init(id: UUID = UUID(), name: String, settings: SaneBarSettings) {
        self.id = id
        self.name = name
        self.settings = settings
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
