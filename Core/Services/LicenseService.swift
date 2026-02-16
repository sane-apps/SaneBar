import Foundation
import os.log

private let licenseLogger = Logger(subsystem: "com.sanebar.app", category: "License")

/// Manages Pro license status. Validates via LemonSqueezy API, caches in Keychain.
///
/// Free users can browse panels and search icons. Pro unlocks actions (activate, move,
/// customize) — see ``ProFeature`` for the full list.
@MainActor
final class LicenseService: ObservableObject {
    static let shared = LicenseService()

    // MARK: - Published State

    @Published private(set) var isPro: Bool = false
    @Published private(set) var isEarlyAdopter: Bool = false
    @Published private(set) var licenseEmail: String?
    @Published private(set) var isValidating: Bool = false
    @Published var validationError: String?

    // MARK: - Keychain Keys

    private enum Keys {
        static let licenseKey = "pro_license_key"
        static let licenseEmail = "pro_license_email"
        static let lastValidation = "pro_last_validation"
    }

    /// Offline grace period — Pro stays active without revalidation for this long.
    private let offlineGraceDays: TimeInterval = 30

    private let keychain: KeychainServiceProtocol

    init(keychain: KeychainServiceProtocol = KeychainService.shared) {
        self.keychain = keychain
    }

    // MARK: - Startup

    /// Check cached license on launch. Call from `applicationDidFinishLaunching`.
    func checkCachedLicense() {
        #if DEBUG
            // Debug builds: auto-grant Pro so developers can test all features
            // without fighting keychain over SSH. Does NOT ship in release.
            // Skip when running under test host to preserve test expectations.
            if NSClassFromString("XCTestCase") == nil,
               ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
                isPro = true
                isEarlyAdopter = true
                licenseEmail = nil
                licenseLogger.info("DEBUG build — auto-granted Pro access")
                return
            }
        #endif

        guard let storedKey = try? keychain.string(forKey: Keys.licenseKey),
              !storedKey.isEmpty
        else {
            isPro = false
            isEarlyAdopter = false
            licenseEmail = nil
            licenseLogger.info("No cached license key — free mode")
            return
        }

        // Early adopters get permanent Pro — no revalidation needed
        if storedKey == "early-adopter" {
            isPro = true
            isEarlyAdopter = true
            licenseEmail = nil
            licenseLogger.info("Early adopter — lifetime Pro access")
            return
        }

        licenseEmail = try? keychain.string(forKey: Keys.licenseEmail)

        // Check offline grace
        if let lastDateString = try? keychain.string(forKey: Keys.lastValidation),
           let lastDate = ISO8601DateFormatter().date(from: lastDateString) {
            let daysSince = Date().timeIntervalSince(lastDate) / 86400
            if daysSince <= offlineGraceDays {
                isPro = true
                licenseLogger.info("License valid (offline grace, \(Int(daysSince))d since check)")
                return
            }
        }

        // Grace expired or no date — attempt background revalidation
        isPro = true // Optimistic while validating
        Task {
            await revalidate(key: storedKey)
        }
    }

    /// Grant Pro to early adopters who used SaneBar before the freemium model.
    func grantEarlyAdopterPro() {
        try? keychain.set("early-adopter", forKey: Keys.licenseKey)
        try? keychain.set(ISO8601DateFormatter().string(from: Date()), forKey: Keys.lastValidation)
        isPro = true
        isEarlyAdopter = true
        licenseEmail = nil
        licenseLogger.info("Early adopter Pro granted — lifetime access")
    }

    // MARK: - Activation

    /// Validate a license key with LemonSqueezy and activate Pro.
    func activate(key: String) async {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationError = "Please enter a license key."
            return
        }

        isValidating = true
        validationError = nil

        do {
            let result = try await validateWithLemonSqueezy(key: trimmed)
            if result.valid {
                try keychain.set(trimmed, forKey: Keys.licenseKey)
                if let email = result.email {
                    try keychain.set(email, forKey: Keys.licenseEmail)
                    licenseEmail = email
                }
                try keychain.set(ISO8601DateFormatter().string(from: Date()), forKey: Keys.lastValidation)
                isPro = true
                validationError = nil
                licenseLogger.info("License activated successfully")
            } else {
                validationError = result.error ?? "Invalid license key."
                licenseLogger.info("License validation failed: \(result.error ?? "invalid")")
            }
        } catch {
            validationError = "Could not reach license server. Check your connection and try again."
            licenseLogger.error("License validation error: \(error.localizedDescription)")
        }

        isValidating = false
    }

    /// Remove stored license and revert to free mode.
    func deactivate() {
        try? keychain.delete(Keys.licenseKey)
        try? keychain.delete(Keys.licenseEmail)
        try? keychain.delete(Keys.lastValidation)
        isPro = false
        isEarlyAdopter = false
        licenseEmail = nil
        validationError = nil
        licenseLogger.info("License deactivated")
    }

    // MARK: - Private

    private func revalidate(key: String) async {
        do {
            let result = try await validateWithLemonSqueezy(key: key)
            if result.valid {
                try? keychain.set(ISO8601DateFormatter().string(from: Date()), forKey: Keys.lastValidation)
                isPro = true
                licenseLogger.info("Background revalidation succeeded")
            } else {
                // Key was revoked — revert to free
                isPro = false
                licenseLogger.info("Background revalidation failed — reverting to free")
            }
        } catch {
            // Network error during revalidation — keep Pro active (grace period)
            licenseLogger.info("Background revalidation network error — maintaining Pro")
        }
    }

    // MARK: - LemonSqueezy API

    private struct ValidationResult {
        let valid: Bool
        let email: String?
        let error: String?
    }

    private func validateWithLemonSqueezy(key: String) async throws -> ValidationResult {
        let url = URL(string: "https://api.lemonsqueezy.com/v1/licenses/validate")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let body: [String: String] = ["license_key": key]
        request.httpBody = try JSONEncoder().encode(body)
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            return ValidationResult(valid: false, email: nil, error: "Unexpected response")
        }

        // LemonSqueezy returns 200 for valid, 400/404 for invalid
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

        if http.statusCode == 200 {
            let valid = json?["valid"] as? Bool ?? false
            let meta = json?["meta"] as? [String: Any]
            let email = meta?["customer_email"] as? String
            return ValidationResult(valid: valid, email: email, error: nil)
        } else {
            let error = json?["error"] as? String ?? "Invalid license key."
            return ValidationResult(valid: false, email: nil, error: error)
        }
    }

    /// LemonSqueezy checkout URL for new purchases (via go.saneapps.com redirect).
    static let checkoutURL = URL(string: "https://go.saneapps.com/buy/sanebar")!
}
