import AppKit
import Foundation
import os.log
import ServiceManagement

private let logger = Logger(subsystem: "com.sanebar.app", category: "BartenderImport")

// MARK: - BartenderImportService

/// Handles importing Bartender plist configurations into SaneBar's zone layout.
enum BartenderImportService {
    // MARK: - Types

    struct ParsedItem: Hashable {
        let raw: String
    }

    struct ResolvedItem {
        let raw: String
        let bundleId: String
        let menuExtraId: String?
        let statusItemIndex: Int?
    }

    struct Profile {
        let hide: [String]
        let show: [String]
        let alwaysHide: [String]
    }

    struct ResolutionContext {
        let availableByBundle: [String: [AccessibilityService.MenuBarItemPosition]]
        let availableByMenuExtraId: [String: AccessibilityService.MenuBarItemPosition]
        let availableByMenuExtraIdLower: [String: AccessibilityService.MenuBarItemPosition]
        let availableByBundleAndName: [String: AccessibilityService.MenuBarItemPosition]
    }

    struct BundleMatch {
        let bundleId: String
        let token: String?
        let matchedRunning: Bool
    }

    struct ImportSummary {
        var movedHidden = 0
        var movedVisible = 0
        var failedMoves = 0
        var skippedNotRunning = 0
        var skippedAmbiguous = 0
        var skippedUnsupported = 0
        var skippedDuplicates = 0
        var behavioralSettings: [String] = []

        var totalMoved: Int { movedHidden + movedVisible }

        var description: String {
            var lines = [
                "Hidden: \(movedHidden)",
                "Visible: \(movedVisible)",
                "Failed moves: \(failedMoves)",
                "Skipped (not running): \(skippedNotRunning)",
                "Skipped (ambiguous): \(skippedAmbiguous)",
                "Skipped (unsupported): \(skippedUnsupported)",
                "Skipped (duplicates): \(skippedDuplicates)"
            ]
            if !behavioralSettings.isEmpty {
                lines.append("")
                lines.append("Settings imported:")
                lines.append(contentsOf: behavioralSettings.map { "  \($0)" })
            }
            return lines.joined(separator: "\n")
        }
    }

    enum ImportError: LocalizedError {
        case accessibilityRequired
        case emptyProfile
        case authRequired

        var errorDescription: String? {
            switch self {
            case .accessibilityRequired:
                "Enable Accessibility in System Settings to import Bartender positions."
            case .emptyProfile:
                "No Hide or Show entries found in the Bartender profile."
            case .authRequired:
                "Authentication was required to reveal hidden icons."
            }
        }
    }

    // MARK: - Import

    @MainActor
    static func importSettings(from url: URL, menuBarManager: MenuBarManager) async throws -> ImportSummary {
        logger.log("🍸 Importing Bartender settings from \(url.lastPathComponent, privacy: .public)")

        guard AccessibilityService.shared.requestAccessibility() else {
            throw ImportError.accessibilityRequired
        }

        let data = try Data(contentsOf: url)
        let (profile, root) = try parseProfile(from: data)

        // Import behavioral settings before icon layout
        var summary = ImportSummary()
        importBehavioralSettings(from: root, to: menuBarManager, summary: &summary)

        let hideRaw = profile.hide + profile.alwaysHide
        let showRaw = profile.show

        if hideRaw.isEmpty, showRaw.isEmpty, summary.behavioralSettings.isEmpty {
            throw ImportError.emptyProfile
        }
        let parsedHide = hideRaw.compactMap(parseItem)
        let parsedShow = showRaw.compactMap(parseItem)

        var seen = Set<String>()
        let uniqueHide = parsedHide.filter { item in
            let inserted = seen.insert(item.raw).inserted
            if !inserted { summary.skippedDuplicates += 1 }
            return inserted
        }
        let uniqueShow = parsedShow.filter { item in
            let inserted = seen.insert(item.raw).inserted
            if !inserted { summary.skippedDuplicates += 1 }
            return inserted
        }

        let context = await buildResolutionContext()

        let wasHidden = menuBarManager.hidingState == .hidden
        if wasHidden {
            let revealed = await menuBarManager.showHiddenItemsNow(trigger: .settingsButton)
            if !revealed, menuBarManager.hidingState == .hidden {
                throw ImportError.authRequired
            }
        }

        for item in uniqueHide {
            if let resolved = resolveItem(item, context: context, summary: &summary) {
                let didMove = await menuBarManager.moveIconAndWait(
                    bundleID: resolved.bundleId,
                    menuExtraId: resolved.menuExtraId,
                    statusItemIndex: resolved.statusItemIndex,
                    toHidden: true
                )
                if didMove {
                    summary.movedHidden += 1
                } else {
                    summary.failedMoves += 1
                }
            }
        }

        for item in uniqueShow {
            if let resolved = resolveItem(item, context: context, summary: &summary) {
                let didMove = await menuBarManager.moveIconAndWait(
                    bundleID: resolved.bundleId,
                    menuExtraId: resolved.menuExtraId,
                    statusItemIndex: resolved.statusItemIndex,
                    toHidden: false
                )
                if didMove {
                    summary.movedVisible += 1
                } else {
                    summary.failedMoves += 1
                }
            }
        }

        if wasHidden {
            menuBarManager.hideHiddenItems()
        }

        logger.log("🍸 Bartender import complete. \(summary.totalMoved) moved. Not running: \(summary.skippedNotRunning)")
        return summary
    }

    // MARK: - Parsing

    private static func parseProfile(from data: Data) throws -> (Profile, [String: Any]) {
        var format = PropertyListSerialization.PropertyListFormat.xml
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        guard let root = plist as? [String: Any] else {
            throw NSError(domain: "SaneBar", code: 10, userInfo: [
                NSLocalizedDescriptionKey: "Unexpected Bartender plist format."
            ])
        }
        guard let profileSettings = root["ProfileSettings"] as? [String: Any],
              let activeProfile = profileSettings["activeProfile"] as? [String: Any]
        else {
            throw NSError(domain: "SaneBar", code: 11, userInfo: [
                NSLocalizedDescriptionKey: "Bartender profile not found."
            ])
        }

        let hide = activeProfile["Hide"] as? [String] ?? []
        let show = activeProfile["Show"] as? [String] ?? []
        let alwaysHide = activeProfile["AlwaysHide"] as? [String] ?? []
        return (Profile(hide: hide, show: show, alwaysHide: alwaysHide), root)
    }

    // MARK: - Behavioral Settings

    @MainActor
    private static func importBehavioralSettings(
        from root: [String: Any],
        to menuBarManager: MenuBarManager,
        summary: inout ImportSummary
    ) {
        var settings = menuBarManager.settings

        // MouseExitDelay → hoverDelay (clamp to SaneBar's supported range)
        if let delay = root["MouseExitDelay"] as? Double, delay >= 0.05, delay <= 1.0 {
            settings.hoverDelay = delay
            summary.behavioralSettings.append("Hover delay: \(String(format: "%.1f", delay))s")
        }

        // ShowAllItemsWhenDragging → showOnUserDrag
        if let showOnDrag = root["ShowAllItemsWhenDragging"] as? Bool {
            settings.showOnUserDrag = showOnDrag
            summary.behavioralSettings.append("Show on drag: \(showOnDrag ? "on" : "off")")
        }

        // HideItemsWhenShowingOthers → rehideOnAppChange
        if let hideWhenShowing = root["HideItemsWhenShowingOthers"] as? Bool {
            settings.rehideOnAppChange = hideWhenShowing
            summary.behavioralSettings.append("Rehide on app change: \(hideWhenShowing ? "on" : "off")")
        }

        // launchAtLogin.isEnabled → SMAppService
        if let launchAtLogin = root["launchAtLogin.isEnabled"] as? Bool, launchAtLogin {
            do {
                try SMAppService.mainApp.register()
                summary.behavioralSettings.append("Launch at login: on")
            } catch {
                logger.warning("Failed to set launch at login: \(error.localizedDescription)")
            }
        }

        menuBarManager.settings = settings
        menuBarManager.saveSettings()
    }

    private static func parseItem(_ raw: String) -> ParsedItem? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return ParsedItem(raw: trimmed)
    }

    // MARK: - Resolution

    private static func buildResolutionContext() async -> ResolutionContext {
        let availableItems = await AccessibilityService.shared.listMenuBarItemsWithPositions()
        let availableByBundle = Dictionary(grouping: availableItems, by: { $0.app.bundleId })
        var availableByMenuExtraId: [String: AccessibilityService.MenuBarItemPosition] = [:]
        var availableByMenuExtraIdLower: [String: AccessibilityService.MenuBarItemPosition] = [:]
        var availableByBundleAndName: [String: AccessibilityService.MenuBarItemPosition] = [:]

        for item in availableItems {
            if let id = item.app.menuExtraIdentifier, availableByMenuExtraId[id] == nil {
                availableByMenuExtraId[id] = item
                availableByMenuExtraIdLower[id.lowercased()] = item
            }
            let key = "\(item.app.bundleId)|\(normalizeLabel(item.app.name))"
            if availableByBundleAndName[key] == nil {
                availableByBundleAndName[key] = item
            }
        }

        return ResolutionContext(
            availableByBundle: availableByBundle,
            availableByMenuExtraId: availableByMenuExtraId,
            availableByMenuExtraIdLower: availableByMenuExtraIdLower,
            availableByBundleAndName: availableByBundleAndName
        )
    }

    private static func resolveItem(
        _ item: ParsedItem,
        context: ResolutionContext,
        summary: inout ImportSummary
    ) -> ResolvedItem? {
        if item.raw.hasPrefix("com.surteesstudios.Bartender") {
            summary.skippedUnsupported += 1
            return nil
        }

        let availableBundles = Set(context.availableByBundle.keys)
        guard let bundleMatch = resolveBundleIdAndToken(from: item.raw, availableBundles: availableBundles) else {
            summary.skippedAmbiguous += 1
            return nil
        }

        guard bundleMatch.matchedRunning else {
            summary.skippedNotRunning += 1
            return nil
        }

        let bundleId = bundleMatch.bundleId
        guard let runningItems = context.availableByBundle[bundleId], !runningItems.isEmpty else {
            summary.skippedNotRunning += 1
            return nil
        }

        if let statusItemIndex = parseStatusItemIndex(from: bundleMatch.token) {
            return ResolvedItem(raw: item.raw, bundleId: bundleId, menuExtraId: nil, statusItemIndex: statusItemIndex)
        }

        if let token = bundleMatch.token, let candidate = menuExtraIdCandidate(from: token) {
            if let match = context.availableByMenuExtraId[candidate] {
                return ResolvedItem(raw: item.raw, bundleId: bundleId, menuExtraId: match.app.menuExtraIdentifier, statusItemIndex: match.app.statusItemIndex)
            }
            if let match = context.availableByMenuExtraIdLower[candidate.lowercased()] {
                return ResolvedItem(raw: item.raw, bundleId: bundleId, menuExtraId: match.app.menuExtraIdentifier, statusItemIndex: match.app.statusItemIndex)
            }
            if runningItems.count == 1 {
                let match = runningItems[0].app
                return ResolvedItem(raw: item.raw, bundleId: bundleId, menuExtraId: match.menuExtraIdentifier, statusItemIndex: match.statusItemIndex)
            }
            summary.skippedAmbiguous += 1
            return nil
        }

        if let token = bundleMatch.token {
            let key = "\(bundleId)|\(normalizeLabel(token))"
            if let match = context.availableByBundleAndName[key] {
                let app = match.app
                return ResolvedItem(raw: item.raw, bundleId: bundleId, menuExtraId: app.menuExtraIdentifier, statusItemIndex: app.statusItemIndex)
            }
        }

        if runningItems.count == 1 {
            let match = runningItems[0].app
            return ResolvedItem(raw: item.raw, bundleId: bundleId, menuExtraId: match.menuExtraIdentifier, statusItemIndex: match.statusItemIndex)
        }

        summary.skippedAmbiguous += 1
        return nil
    }

    private static func resolveBundleIdAndToken(from raw: String, availableBundles: Set<String>) -> BundleMatch? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if availableBundles.contains(trimmed) {
            return BundleMatch(bundleId: trimmed, token: nil, matchedRunning: true)
        }

        let candidates = availableBundles.filter { trimmed.hasPrefix($0 + "-") }
        if let bundleId = candidates.max(by: { $0.count < $1.count }) {
            let tokenStart = trimmed.index(trimmed.startIndex, offsetBy: bundleId.count + 1)
            let token = String(trimmed[tokenStart...])
            return BundleMatch(bundleId: bundleId, token: token, matchedRunning: true)
        }

        if let dashIndex = trimmed.firstIndex(of: "-") {
            let bundleId = String(trimmed[..<dashIndex])
            let token = String(trimmed[trimmed.index(after: dashIndex)...])
            return BundleMatch(bundleId: bundleId, token: token.isEmpty ? nil : token, matchedRunning: false)
        }

        return BundleMatch(bundleId: trimmed, token: nil, matchedRunning: availableBundles.contains(trimmed))
    }

    private static func parseStatusItemIndex(from token: String?) -> Int? {
        guard let token, let range = token.range(of: "Item-", options: .backwards) else { return nil }
        let suffix = token[range.upperBound...]
        guard !suffix.isEmpty, suffix.allSatisfy(\.isNumber) else { return nil }
        return Int(suffix)
    }

    private static func menuExtraIdCandidate(from token: String) -> String? {
        if let range = token.range(of: "com.apple.menuextra.") {
            return String(token[range.lowerBound...])
        }
        if token.contains(".") {
            return token
        }
        return nil
    }

    private static func normalizeLabel(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}
