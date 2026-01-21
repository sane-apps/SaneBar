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

        return DiagnosticReport(
            appVersion: appVersion,
            buildNumber: buildNumber,
            macOSVersion: macOSVersion,
            hardwareModel: hardwareModel,
            recentLogs: await logs,
            settingsSummary: await settings,
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
        let modelString = String(cString: model)

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

                let level: String
                switch logEntry.level {
                case .debug: level = "DEBUG"
                case .info: level = "INFO"
                case .notice: level = "NOTICE"
                case .error: level = "ERROR"
                case .fault: level = "FAULT"
                default: level = "LOG"
                }

                return DiagnosticReport.LogEntry(
                    timestamp: logEntry.date,
                    level: level,
                    message: sanitize(logEntry.composedMessage)
                )
            }
        } catch {
            return [DiagnosticReport.LogEntry(
                timestamp: Date(),
                level: "ERROR",
                message: "Failed to collect logs: \(error.localizedDescription)"
            )]
        }
    }

    // MARK: - Settings Summary

    private func collectSettingsSummary() async -> String {
        await MainActor.run {
            let settings = MenuBarManager.shared.settings

            // Only include non-sensitive settings
            return """
            autoRehide: \(settings.autoRehide)
            rehideDelay: \(settings.rehideDelay)s
            findIconRehideDelay: \(settings.findIconRehideDelay)s
            showOnHover: \(settings.showOnHover)
            showOnScroll: \(settings.showOnScroll)
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
            """
        }
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
            URLQueryItem(name: "body", value: body),
            URLQueryItem(name: "labels", value: "bug,user-reported")
        ]

        return components?.url
    }
}
