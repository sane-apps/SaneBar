import AppKit
import Foundation
import OSLog

// MARK: - DiagnosticsServiceProtocol

/// @mockable
protocol DiagnosticsServiceProtocol: Sendable {
    /// Collect diagnostic information for issue reporting
    func collectDiagnostics() async -> DiagnosticReport
}

// MARK: - DiagnosticReport

/// Contains all diagnostic information for issue reporting
struct DiagnosticReport: Sendable {
    let appVersion: String
    let buildNumber: String
    let macOSVersion: String
    let hardwareModel: String
    let recentLogs: [LogEntry]
    let settingsSummary: String
    let collectedAt: Date

    struct LogEntry: Sendable {
        let timestamp: Date
        let level: String
        let message: String
    }

    /// Generate markdown-formatted report for GitHub issue
    func toMarkdown(userDescription: String) -> String {
        var md = """
        ## Issue Description
        \(userDescription)

        ---

        ## Environment
        | Property | Value |
        |----------|-------|
        | App Version | \(appVersion) (\(buildNumber)) |
        | macOS | \(macOSVersion) |
        | Hardware | \(hardwareModel) |
        | Collected | \(ISO8601DateFormatter().string(from: collectedAt)) |

        """

        if !recentLogs.isEmpty {
            md += """

            ## Recent Logs (last 5 minutes)
            ```
            \(formattedLogs)
            ```

            """
        }

        md += """

        ## Settings Summary
        ```
        \(settingsSummary)
        ```

        ---
        *Submitted via SaneBar's in-app feedback*
        """

        return md
    }

    private var formattedLogs: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"

        return recentLogs.prefix(50).map { entry in
            "[\(formatter.string(from: entry.timestamp))] [\(entry.level)] \(entry.message)"
        }.joined(separator: "\n")
    }
}

// MARK: - DiagnosticsService

final class DiagnosticsService: DiagnosticsServiceProtocol, @unchecked Sendable {
    static let shared = DiagnosticsService()

    private let subsystem = "com.sanebar.app"

    func collectDiagnostics() async -> DiagnosticReport {
        async let logs = collectRecentLogs()
        async let settings = collectSettingsSummary()

        return await DiagnosticReport(
            appVersion: appVersion,
            buildNumber: buildNumber,
            macOSVersion: macOSVersion,
            hardwareModel: hardwareModel,
            recentLogs: logs,
            settingsSummary: settings,
            collectedAt: Date()
        )
    }

    // MARK: - App Info

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown"
    }

    // MARK: - System Info

    private var macOSVersion: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }

    private var hardwareModel: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let modelString = String(bytes: model.prefix(while: { $0 != 0 }).map(UInt8.init), encoding: .utf8) ?? "Unknown"

        // Add architecture info
        #if arch(arm64)
            return "\(modelString) (Apple Silicon)"
        #else
            return "\(modelString) (Intel)"
        #endif
    }

    // MARK: - Log Collection

    private func collectRecentLogs() async -> [DiagnosticReport.LogEntry] {
        // OSLogStore requires macOS 15+ (which SaneBar already requires)
        guard #available(macOS 15.0, *) else {
            return []
        }

        do {
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let fiveMinutesAgo = Date().addingTimeInterval(-5 * 60)
            let position = store.position(date: fiveMinutesAgo)

            let predicate = NSPredicate(format: "subsystem == %@", subsystem)
            let entries = try store.getEntries(at: position, matching: predicate)

            return entries.compactMap { entry -> DiagnosticReport.LogEntry? in
                guard let logEntry = entry as? OSLogEntryLog else { return nil }

                let level = switch logEntry.level {
                case .debug: "DEBUG"
                case .info: "INFO"
                case .notice: "NOTICE"
                case .error: "ERROR"
                case .fault: "FAULT"
                default: "LOG"
                }

                return DiagnosticReport.LogEntry(
                    timestamp: logEntry.date,
                    level: level,
                    message: sanitize(logEntry.composedMessage)
                )
            }
        } catch {
            return [
                DiagnosticReport.LogEntry(
                    timestamp: Date(),
                    level: "ERROR",
                    message: "Failed to collect logs: \(error.localizedDescription)"
                ),
                DiagnosticReport.LogEntry(
                    timestamp: Date(),
                    level: "INFO",
                    message: "Tip: paste logs manually by running in Terminal: log show --predicate 'subsystem == \"com.sanebar.app\"' --last 5m --style compact"
                )
            ]
        }
    }

    // MARK: - Settings Summary

    private func collectSettingsSummary() async -> String {
        let base = await MainActor.run { () -> String in
            let manager = MenuBarManager.shared
            let settings = manager.settings

            // Only include non-sensitive settings + non-sensitive runtime state.
            let mainButton = manager.mainStatusItem?.button
            let separatorButton = manager.separatorItem?.button
            let alwaysHiddenButton = manager.alwaysHiddenSeparatorItem?.button

            let mainPreferred = UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)")
            let separatorPreferred = UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)")
            let alwaysHiddenPreferred = UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position \(StatusBarController.alwaysHiddenSeparatorAutosaveName)")

            func formatSelector(_ action: Selector?) -> String {
                guard let action else { return "nil" }
                return NSStringFromSelector(action)
            }

            func formatRect(_ rect: CGRect?) -> String {
                guard let rect else { return "nil" }
                return String(format: "x=%.1f y=%.1f w=%.1f h=%.1f", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
            }

            func formatCGFloat(_ value: CGFloat?) -> String {
                guard let value else { return "nil" }
                return String(format: "%.2f", value)
            }

            return """
            hidingState: \(manager.hidingService.state.rawValue)
            isAnimating: \(manager.hidingService.isAnimating)
            delimiterConfigured: \(manager.hidingService.isConfigured)
            delimiterLength: \(formatCGFloat(manager.hidingService.delimiterLength))
            isMenuOpen: \(manager.isMenuOpen)
            isRevealPinned: \(manager.isRevealPinned)
            shouldSkipHideForExternalMonitor: \(manager.shouldSkipHideForExternalMonitor)
            hasNotch: \(manager.hasNotch)
            isOnExternalMonitor: \(manager.isOnExternalMonitor)
            accessibilityGranted: \(AccessibilityService.shared.isGranted)

            separatorOriginX: \(formatCGFloat(manager.getSeparatorOriginX()))
            alwaysHiddenSeparatorOriginX: \(formatCGFloat(manager.getAlwaysHiddenSeparatorOriginX()))
            mainIconLeftEdgeX: \(formatCGFloat(manager.getMainStatusItemLeftEdgeX()))

            mainStatusItemVisible: \(manager.mainStatusItem?.isVisible ?? false)
            statusMenuItemCount: \(manager.statusMenu?.items.count ?? 0)

            mainButton:
              identifier: \(mainButton?.identifier?.rawValue ?? "nil")
              action: \(formatSelector(mainButton?.action))
              hasTarget: \(mainButton?.target != nil)
              windowFrame: \(formatRect(mainButton?.window?.frame))
              screen: \(mainButton?.window?.screen?.localizedName ?? "nil")

            separatorButton:
              identifier: \(separatorButton?.identifier?.rawValue ?? "nil")
              action: \(formatSelector(separatorButton?.action))
              hasTarget: \(separatorButton?.target != nil)
              windowFrame: \(formatRect(separatorButton?.window?.frame))

            alwaysHiddenSeparatorButton:
              identifier: \(alwaysHiddenButton?.identifier?.rawValue ?? "nil")
              action: \(formatSelector(alwaysHiddenButton?.action))
              hasTarget: \(alwaysHiddenButton?.target != nil)
              windowFrame: \(formatRect(alwaysHiddenButton?.window?.frame))

            nsStatusItemPreferredPositions:
              main: \(mainPreferred.map { String(describing: $0) } ?? "nil")
              separator: \(separatorPreferred.map { String(describing: $0) } ?? "nil")
              alwaysHiddenSeparator: \(alwaysHiddenPreferred.map { String(describing: $0) } ?? "nil")

            settings:
              autoRehide: \(settings.autoRehide)
              rehideDelay: \(settings.rehideDelay)s
              findIconRehideDelay: \(settings.findIconRehideDelay)s
              showOnHover: \(settings.showOnHover)
              showOnScroll: \(settings.showOnScroll)
              showOnClick: \(settings.showOnClick)
              showOnUserDrag: \(settings.showOnUserDrag)
              showOnLowBattery: \(settings.showOnLowBattery)
              showOnAppLaunch: \(settings.showOnAppLaunch)
              showOnNetworkChange: \(settings.showOnNetworkChange)
              requireAuthToShowHiddenIcons: \(settings.requireAuthToShowHiddenIcons)
              showDockIcon: \(settings.showDockIcon)
              hideMainIcon: \(settings.hideMainIcon)
              dividerStyle: \(settings.dividerStyle.rawValue)
              menuBarSpacing: \(settings.menuBarSpacing.map { String($0) } ?? "default")
              iconGroups: \(settings.iconGroups.count)
              iconHotkeys: \(settings.iconHotkeys.count)
              disableOnExternalMonitor: \(settings.disableOnExternalMonitor)
              useSecondMenuBar: \(settings.useSecondMenuBar)
              alwaysHiddenSectionEnabled: \(settings.alwaysHiddenSectionEnabled)
              alwaysHiddenPinnedItemCount: \(settings.alwaysHiddenPinnedItemIds.count)
            """
        }

        let menuBarClassification = await collectMenuBarClassificationSummary()
        return "\(base)\n\n\(menuBarClassification)"
    }

    private func collectMenuBarClassificationSummary() async -> String {
        let isGranted = await MainActor.run { AccessibilityService.shared.isGranted }
        guard isGranted else {
            return """
            menuBarItems:
              accessibility: not granted
            """
        }

        let separatorOriginX = await MainActor.run { MenuBarManager.shared.getSeparatorOriginX() }
        let alwaysHiddenSeparatorOriginX = await MainActor.run { MenuBarManager.shared.getAlwaysHiddenSeparatorOriginX() }
        let screenFrame = await MainActor.run { () -> CGRect? in
            if let screen = MenuBarManager.shared.mainStatusItem?.button?.window?.screen {
                return screen.frame
            }
            return NSScreen.main?.frame
        }

        let items = await AccessibilityService.shared.refreshMenuBarItemsWithPositions()

        let margin: CGFloat = 6
        let offscreenCount: Int = {
            guard let screenFrame else {
                return items.filter { $0.x < 0 }.count
            }
            return items.filter { $0.x < (screenFrame.minX - margin) || $0.x > (screenFrame.maxX + margin) }.count
        }()

        guard let separatorOriginX else {
            let hiddenCount = items.filter { $0.x < 0 }.count
            return """
            menuBarItems:
              total: \(items.count)
              classification: separatorOriginX unavailable (fallback x < 0)
              offscreenCount: \(offscreenCount)
              hiddenCount: \(hiddenCount)
            """
        }

        enum Zone: String {
            case visible
            case hidden
            case alwaysHidden
        }

        func classify(itemX: CGFloat, itemWidth: CGFloat?) -> Zone {
            let width = max(1, itemWidth ?? 22)
            let midX = itemX + (width / 2)

            if let alwaysHiddenSeparatorOriginX, midX < (alwaysHiddenSeparatorOriginX - margin) {
                return .alwaysHidden
            }
            return midX < (separatorOriginX - margin) ? .hidden : .visible
        }

        var visibleCount = 0
        var hiddenCount = 0
        var alwaysHiddenCount = 0

        for item in items {
            switch classify(itemX: item.x, itemWidth: item.app.width) {
            case .visible:
                visibleCount += 1
            case .hidden:
                hiddenCount += 1
            case .alwaysHidden:
                alwaysHiddenCount += 1
            }
        }

        return """
        menuBarItems:
          total: \(items.count)
          offscreenCount: \(offscreenCount)
          visibleCount: \(visibleCount)
          hiddenCount: \(hiddenCount)
          alwaysHiddenCount: \(alwaysHiddenCount)
        """
    }

    // MARK: - Privacy

    /// Remove potentially sensitive information from log messages
    private func sanitize(_ message: String) -> String {
        var sanitized = message

        // Redact file paths containing username
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        sanitized = sanitized.replacingOccurrences(of: homeDir, with: "~")

        // Redact common sensitive patterns
        let patterns = [
            // Email-like patterns
            "[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}",
            // Potential API keys/tokens (long alphanumeric strings)
            "\\b[A-Za-z0-9]{32,}\\b"
        ]

        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern) {
                sanitized = regex.stringByReplacingMatches(
                    in: sanitized,
                    range: NSRange(sanitized.startIndex..., in: sanitized),
                    withTemplate: "[REDACTED]"
                )
            }
        }

        return sanitized
    }
}

// MARK: - GitHub Issue URL Generation

extension DiagnosticReport {
    /// Generate a URL that opens a pre-filled GitHub issue
    func gitHubIssueURL(title: String, userDescription: String) -> URL? {
        let body = toMarkdown(userDescription: userDescription)

        var components = URLComponents(string: "https://github.com/sane-apps/SaneBar/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "title", value: title),
            URLQueryItem(name: "body", value: body)
        ]

        return components?.url
    }
}
