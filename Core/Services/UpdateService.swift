import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "UpdateService")

// MARK: - UpdateResult

/// Result of checking for updates
enum UpdateResult: Sendable, Equatable {
    case upToDate
    case updateAvailable(version: String, releaseURL: URL)
    case error(String)
}

// MARK: - UpdateServiceProtocol

/// @mockable
protocol UpdateServiceProtocol: Sendable {
    func checkForUpdates() async -> UpdateResult
}

// MARK: - UpdateService

/// Privacy-respecting update checker that queries GitHub releases.
///
/// Privacy guarantees:
/// - No user identifiers sent
/// - No cookies or tracking
/// - No analytics or telemetry
/// - Only public GitHub API is accessed
/// - User must explicitly trigger the check
///
/// The service compares the current app version against the latest
/// GitHub release tag and returns the result.
actor UpdateService: UpdateServiceProtocol {

    // MARK: - Constants

    private static let repoOwner = "stephanjoseph"
    private static let repoName = "SaneBar"
    private static let releasesURL = "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest"

    // MARK: - Dependencies

    private let session: URLSession

    // MARK: - Initialization

    init() {
        // Create ephemeral session - no cookies, no cache, no persistent storage
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        // Minimal user agent - just app name and version, no device info
        config.httpAdditionalHeaders = [
            "Accept": "application/vnd.github.v3+json"
        ]
        self.session = URLSession(configuration: config)
    }

    // For testing with mock session
    init(session: URLSession) {
        self.session = session
    }

    // MARK: - Public API

    /// Check GitHub releases for a newer version
    ///
    /// This makes a single GET request to the public GitHub API.
    /// No user data, device identifiers, or tracking information is sent.
    func checkForUpdates() async -> UpdateResult {
        guard let url = URL(string: Self.releasesURL) else {
            logger.error("Invalid releases URL")
            return .error("Invalid configuration")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10

        do {
            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                return .error("Invalid response")
            }

            guard httpResponse.statusCode == 200 else {
                logger.warning("GitHub API returned status \(httpResponse.statusCode)")
                return .error("Could not reach GitHub (status \(httpResponse.statusCode))")
            }

            return parseReleaseResponse(data)

        } catch {
            logger.error("Update check failed: \(error.localizedDescription)")
            return .error("Network error: \(error.localizedDescription)")
        }
    }

    // MARK: - Private Helpers

    private func parseReleaseResponse(_ data: Data) -> UpdateResult {
        do {
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tagName = json["tag_name"] as? String,
                  let htmlURL = json["html_url"] as? String,
                  let releaseURL = URL(string: htmlURL) else {
                return .error("Invalid response format")
            }

            // Remove 'v' prefix if present (e.g., "v1.0.4" -> "1.0.4")
            let latestVersion = tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName

            guard let currentVersion = Self.currentAppVersion else {
                logger.error("Could not determine current app version")
                return .error("Could not determine current version")
            }

            logger.info("Current: \(currentVersion), Latest: \(latestVersion)")

            if isNewerVersion(latestVersion, than: currentVersion) {
                return .updateAvailable(version: latestVersion, releaseURL: releaseURL)
            } else {
                return .upToDate
            }

        } catch {
            logger.error("Failed to parse release JSON: \(error.localizedDescription)")
            return .error("Failed to parse response")
        }
    }

    /// Compare semantic versions to determine if `latest` is newer than `current`
    private func isNewerVersion(_ latest: String, than current: String) -> Bool {
        let latestComponents = latest.split(separator: ".").compactMap { Int($0) }
        let currentComponents = current.split(separator: ".").compactMap { Int($0) }

        // Pad arrays to same length
        let maxLength = max(latestComponents.count, currentComponents.count)
        let paddedLatest = latestComponents + Array(repeating: 0, count: maxLength - latestComponents.count)
        let paddedCurrent = currentComponents + Array(repeating: 0, count: maxLength - currentComponents.count)

        for (latest, current) in zip(paddedLatest, paddedCurrent) {
            if latest > current { return true }
            if latest < current { return false }
        }

        return false // Equal versions
    }

    /// Get the current app version from the bundle
    private static var currentAppVersion: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}
