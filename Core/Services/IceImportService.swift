import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "IceImport")

// MARK: - IceImportService

/// Handles importing Ice menu bar manager settings into SaneBar.
///
/// Ice stores settings in `~/Library/Preferences/com.jordanbaird.Ice.plist` as flat
/// key-value pairs. Unlike Bartender, Ice does NOT persist per-icon section assignments
/// (it uses runtime position tracking with control items), so we can only import
/// behavioral settings — not icon layout.
enum IceImportService {
    // MARK: - Types

    struct ImportedSettings {
        var showOnHover: Bool?
        var showOnScroll: Bool?
        var autoRehide: Bool?
        var rehideDelay: TimeInterval?
        var hoverDelay: TimeInterval?
        var menuBarSpacing: Int?
        var showOnUserDrag: Bool?
        var alwaysHiddenSectionEnabled: Bool?
        var showSectionDividers: Bool?
    }

    struct ImportSummary {
        var applied: [String] = []
        var skipped: [String] = []

        var description: String {
            var lines: [String] = []
            if !applied.isEmpty {
                lines.append("Applied:")
                lines.append(contentsOf: applied.map { "  \($0)" })
            }
            if !skipped.isEmpty {
                lines.append("Skipped (no SaneBar equivalent):")
                lines.append(contentsOf: skipped.map { "  \($0)" })
            }
            if applied.isEmpty {
                lines.append("No matching settings found in Ice plist.")
            }
            lines.append("")
            lines.append("Note: Ice doesn't store icon positions, so you'll need to")
            lines.append("drag icons left of the divider to hide them.")
            return lines.joined(separator: "\n")
        }
    }

    enum ImportError: LocalizedError {
        case invalidFormat
        case fileNotFound

        var errorDescription: String? {
            switch self {
            case .invalidFormat:
                "Not a valid Ice preferences file."
            case .fileNotFound:
                "Ice preferences file not found."
            }
        }
    }

    // MARK: - Import

    @MainActor
    static func importSettings(from url: URL, menuBarManager: MenuBarManager) throws -> ImportSummary {
        logger.log("🧊 Importing Ice settings from \(url.lastPathComponent, privacy: .public)")

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ImportError.fileNotFound
        }

        let data = try Data(contentsOf: url)
        let root = try parsePlist(from: data)
        let parsed = parseSettings(from: root)
        let summary = applySettings(parsed, to: menuBarManager, iceRoot: root)

        logger.log("🧊 Ice import complete. Applied \(summary.applied.count) settings")
        return summary
    }

    // MARK: - Parsing

    private static func parsePlist(from data: Data) throws -> [String: Any] {
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        guard let root = plist as? [String: Any] else {
            throw ImportError.invalidFormat
        }
        return root
    }

    private static func parseSettings(from root: [String: Any]) -> ImportedSettings {
        ImportedSettings(
            showOnHover: root["ShowOnHover"] as? Bool,
            showOnScroll: root["ShowOnScroll"] as? Bool,
            autoRehide: root["AutoRehide"] as? Bool,
            rehideDelay: root["RehideInterval"] as? TimeInterval,
            hoverDelay: root["ShowOnHoverDelay"] as? TimeInterval,
            menuBarSpacing: root["ItemSpacingOffset"] as? Int,
            showOnUserDrag: root["ShowAllSectionsOnUserDrag"] as? Bool,
            alwaysHiddenSectionEnabled: root["EnableAlwaysHiddenSection"] as? Bool,
            showSectionDividers: root["ShowSectionDividers"] as? Bool
        )
    }

    // MARK: - Apply

    @MainActor
    private static func applySettings(
        _ parsed: ImportedSettings,
        to menuBarManager: MenuBarManager,
        iceRoot: [String: Any]
    ) -> ImportSummary {
        var summary = ImportSummary()
        var settings = menuBarManager.settings

        if let value = parsed.showOnHover {
            settings.showOnHover = value
            summary.applied.append("Show on hover: \(value ? "on" : "off")")
        }

        if let value = parsed.showOnScroll {
            settings.showOnScroll = value
            summary.applied.append("Show on scroll: \(value ? "on" : "off")")
        }

        if let value = parsed.autoRehide {
            settings.autoRehide = value
            summary.applied.append("Auto-rehide: \(value ? "on" : "off")")
        }

        if let value = parsed.rehideDelay, value >= 1, value <= 60 {
            settings.rehideDelay = value
            summary.applied.append("Rehide delay: \(Int(value))s")
        }

        if let value = parsed.hoverDelay, value >= 0.05, value <= 1.0 {
            settings.hoverDelay = value
            summary.applied.append("Hover delay: \(String(format: "%.2f", value))s")
        }

        if let value = parsed.menuBarSpacing, value >= 1, value <= 10 {
            settings.menuBarSpacing = value
            summary.applied.append("Item spacing: \(value)")
        }

        if let value = parsed.showOnUserDrag {
            settings.showOnUserDrag = value
            summary.applied.append("Show on drag: \(value ? "on" : "off")")
        }

        if let value = parsed.alwaysHiddenSectionEnabled {
            settings.alwaysHiddenSectionEnabled = value
            summary.applied.append("Always-hidden section: \(value ? "on" : "off")")
        }

        if let value = parsed.showSectionDividers, value {
            // Ice has dividers enabled — SaneBar always shows dividers, so nothing to change
            summary.applied.append("Section dividers: on (matches SaneBar default)")
        }

        // Track settings we recognized but can't import
        if iceRoot["HideApplicationMenus"] is Bool {
            summary.skipped.append("Hide application menus")
        }
        if iceRoot["Hotkeys"] != nil {
            summary.skipped.append("Hotkeys (incompatible format)")
        }
        if iceRoot["MenuBarAppearanceConfigurationV2"] != nil {
            summary.skipped.append("Menu bar appearance customization")
        }
        if iceRoot["UseIceBar"] as? Bool == true {
            summary.skipped.append("Ice Bar panel mode")
        }

        menuBarManager.settings = settings
        menuBarManager.saveSettings()

        return summary
    }
}
