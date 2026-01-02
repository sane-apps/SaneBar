import Foundation
import AppKit

// MARK: - StatusItemModel

/// Represents a menu bar status item discovered via Accessibility API
struct StatusItemModel: Identifiable, Codable, Hashable {
    let id: UUID
    var bundleIdentifier: String?
    var title: String?
    var iconHash: String?
    var position: Int
    var section: ItemSection
    var isVisible: Bool

    // MARK: - Position Tracking

    /// Screen X position of the item's center (for drag operations)
    var screenX: CGFloat?

    /// Original position index before any hiding operations
    var originalPosition: Int?

    /// Width of the status item in points
    var width: CGFloat?

    // MARK: - Usage Analytics

    /// Number of times this item has been clicked
    var clickCount: Int = 0

    /// Last time this item was clicked
    var lastClickDate: Date?

    /// Last time this item was shown (for smart suggestions)
    var lastShownDate: Date?

    /// The section determines where the item appears
    enum ItemSection: String, Codable, CaseIterable {
        case alwaysVisible  // Never hidden
        case hidden         // Behind SaneBar icon
        case collapsed      // Only on trigger/shortcut

        var displayName: String {
            switch self {
            case .alwaysVisible: return "Always Visible"
            case .hidden: return "Hidden"
            case .collapsed: return "Collapsed"
            }
        }

        var systemImage: String {
            switch self {
            case .alwaysVisible: return "eye"
            case .hidden: return "eye.slash"
            case .collapsed: return "eye.trianglebadge.exclamationmark"
            }
        }
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        bundleIdentifier: String? = nil,
        title: String? = nil,
        iconHash: String? = nil,
        position: Int = 0,
        section: ItemSection = .alwaysVisible,
        isVisible: Bool = true,
        screenX: CGFloat? = nil,
        originalPosition: Int? = nil,
        width: CGFloat? = nil,
        clickCount: Int = 0,
        lastClickDate: Date? = nil,
        lastShownDate: Date? = nil
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.iconHash = iconHash
        self.position = position
        self.section = section
        self.isVisible = isVisible
        self.screenX = screenX
        self.originalPosition = originalPosition
        self.width = width
        self.clickCount = clickCount
        self.lastClickDate = lastClickDate
        self.lastShownDate = lastShownDate
    }

    // MARK: - Display Helpers

    /// Display name for the item (title, bundle ID, or fallback)
    var displayName: String {
        if let title, !title.isEmpty {
            return title
        }
        if let bundleId = bundleIdentifier {
            // Extract app name from bundle ID (e.g., "com.apple.controlcenter" -> "controlcenter")
            return bundleId.components(separatedBy: ".").last?.capitalized ?? bundleId
        }
        return "Unknown Item"
    }

    /// Creates a composite identifier for matching items across scans
    /// Uses multiple properties since menu bar items lack stable IDs
    var compositeKey: String {
        let parts = [
            bundleIdentifier ?? "",
            title ?? "",
            iconHash ?? ""
        ]
        return parts.joined(separator: "|")
    }
}

// MARK: - Icon Hash Helper

extension StatusItemModel {
    /// Generate a hash from NSImage data for icon comparison
    static func hashIcon(_ image: NSImage?) -> String? {
        guard let image else { return nil }
        guard let tiffData = image.tiffRepresentation else { return nil }

        // Use a simple hash of the image data
        var hasher = Hasher()
        hasher.combine(tiffData)
        return String(hasher.finalize())
    }
}

// MARK: - Sample Data (for previews/testing)

extension StatusItemModel {
    static let sampleItems: [StatusItemModel] = [
        StatusItemModel(
            bundleIdentifier: "com.apple.controlcenter",
            title: "Control Center",
            position: 0,
            section: .alwaysVisible
        ),
        StatusItemModel(
            bundleIdentifier: "com.apple.Spotlight",
            title: "Spotlight",
            position: 1,
            section: .alwaysVisible
        ),
        StatusItemModel(
            bundleIdentifier: "com.1password.1password",
            title: "1Password",
            position: 2,
            section: .hidden
        ),
        StatusItemModel(
            bundleIdentifier: "com.apple.battery",
            title: "Battery",
            position: 3,
            section: .alwaysVisible
        )
    ]
}
