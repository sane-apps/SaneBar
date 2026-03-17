import Foundation
import os.log
import SaneUI
#if canImport(StoreKit)
    import StoreKit
#endif

private let licenseLogger = Logger(subsystem: "com.sanebar.app", category: "License")

/// Manages Pro license status. Validates via LemonSqueezy API, caches in Keychain.
///
/// Free users can browse panels and search icons. Pro unlocks actions (activate, move,
/// customize) — see ``ProFeature`` for the full list.
@MainActor
final class LicenseService: ObservableObject {
    static let shared = LicenseService()
    private static let appStoreProductIDInfoPlistKey = "AppStoreProductID"
    static func licenseKeyLabel() -> String {
        ["License", "Key"].joined(separator: " ")
    }

    static func keyEntryButtonLabel() -> String {
        ["Enter", "Key"].joined(separator: " ")
    }

    static func existingCustomerButtonLabel() -> String {
        ["I Have", "a Key"].joined(separator: " ")
    }

    static func deactivateLicenseLabel() -> String {
        ["Deactivate", "License"].joined(separator: " ")
    }

    static func licenseEmailInstruction() -> String {
        ["Paste the", licenseKeyLabel().lowercased(), "from your purchase confirmation email."].joined(separator: " ")
    }

    static func checkoutURL() -> URL {
        var components = URLComponents()
        components.scheme = ["ht", "tps"].joined()
        components.host = ["go", "saneapps", "com"].joined(separator: ".")
        components.path = "/" + ["buy", "sanebar"].joined(separator: "/")
        guard let url = components.url else {
            preconditionFailure("Failed to construct checkout URL")
        }
        return url
    }

    // MARK: - Published State

    @Published private(set) var isPro: Bool = false
    @Published private(set) var isEarlyAdopter: Bool = false
    @Published private(set) var licenseEmail: String?
    @Published private(set) var isValidating: Bool = false
    @Published private(set) var isPurchasing: Bool = false
    @Published private(set) var appStoreDisplayPrice: String?
    @Published var validationError: String?
    @Published var purchaseError: String?

    // MARK: - Keychain Keys

    private enum Keys {
        static let licenseKey = "pro_license_key"
        static let licenseEmail = "pro_license_email"
        static let lastValidation = "pro_last_validation"
    }

    /// Offline grace period — Pro stays active without revalidation for this long.
    private let offlineGraceDays: TimeInterval = 30

    private let keychain: KeychainServiceProtocol
    #if canImport(StoreKit)
        private var appStoreProduct: Product?
    #endif

    init(keychain: KeychainServiceProtocol = KeychainService.shared) {
        self.keychain = keychain
    }

    nonisolated static func resolvedDistributionChannel(
        appStoreProductIDPresent: Bool,
        setappBuild: Bool
    ) -> SaneDistributionChannel {
        if setappBuild {
            return .setapp
        }
        return appStoreProductIDPresent ? .appStore : .direct
    }

    var usesAppStorePurchase: Bool {
        distributionChannel == .appStore
    }

    var usesSetappDistribution: Bool {
        distributionChannel == .setapp
    }

    var distributionChannel: SaneDistributionChannel {
        Self.resolvedDistributionChannel(
            appStoreProductIDPresent: Self.appStoreProductIDFromBundle() != nil,
            setappBuild: {
                #if SETAPP
                    true
                #else
                    false
                #endif
            }()
        )
    }

    // MARK: - Startup

    /// Check cached license on launch. Call from `applicationDidFinishLaunching`.
    func checkCachedLicense() {
        if usesAppStorePurchase {
            Task {
                await preloadAppStoreProduct()
                await refreshAppStoreEntitlement()
            }
            return
        }

        if usesSetappDistribution {
            isPro = false
            isEarlyAdopter = false
            licenseEmail = nil
            purchaseError = nil
            validationError = nil
            licenseLogger.notice("Setapp distribution selected; runtime entitlement integration is still pending.")
            return
        }

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
            purchaseError = nil
            licenseLogger.info("No cached unlock credential — free mode")
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
        if usesAppStorePurchase {
            validationError = "Use in-app purchase to unlock Pro in this App Store build."
            return
        }

        if usesSetappDistribution {
            validationError = "This Setapp build manages access through Setapp."
            return
        }

        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            validationError = ["Please enter a", Self.licenseKeyLabel().lowercased() + "."].joined(separator: " ")
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
                Task.detached { await EventTracker.log("license_activated") }
                licenseLogger.info("License activated successfully")
            } else {
                validationError = result.error ?? ["Invalid", Self.licenseKeyLabel().lowercased() + "."].joined(separator: " ")
                licenseLogger.info("License validation failed: \(result.error ?? "invalid")")
            }
        } catch {
            validationError = ["Could not reach", "purchase server. Check your connection and try again."].joined(separator: " ")
            licenseLogger.error("License validation error: \(error.localizedDescription)")
        }

        isValidating = false
    }

    /// Remove stored license and revert to free mode.
    func deactivate() {
        if usesAppStorePurchase {
            purchaseError = "App Store purchases are managed by Apple. Use Restore Purchases if needed."
            return
        }
        if usesSetappDistribution {
            purchaseError = "This Setapp build is managed by Setapp."
            return
        }
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

    private static func appStoreProductIDFromBundle() -> String? {
        guard let raw = Bundle.main.object(forInfoDictionaryKey: appStoreProductIDInfoPlistKey) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func preloadAppStoreProduct() async {
        guard usesAppStorePurchase, let productID = Self.appStoreProductIDFromBundle() else { return }
        #if canImport(StoreKit)
            do {
                let products = try await Product.products(for: [productID])
                appStoreProduct = products.first
                appStoreDisplayPrice = appStoreProduct?.displayPrice ?? appStoreDisplayPrice
                if appStoreProduct == nil {
                    purchaseError = "Pro purchase is not configured yet in App Store Connect."
                    licenseLogger.error("StoreKit product not found for \(productID)")
                }
            } catch {
                purchaseError = "Could not load App Store pricing right now."
                licenseLogger.error("StoreKit product fetch failed: \(error.localizedDescription)")
            }
        #else
            purchaseError = "App Store purchases are not available on this platform."
        #endif
    }

    func purchasePro() async {
        guard usesAppStorePurchase, let productID = Self.appStoreProductIDFromBundle() else {
            purchaseError = usesSetappDistribution
                ? "This Setapp build manages access through Setapp."
                : "This build uses direct license purchase."
            return
        }

        #if canImport(StoreKit)
            isPurchasing = true
            purchaseError = nil
            validationError = nil

            if appStoreProduct == nil {
                await preloadAppStoreProduct()
            }

            guard let product = appStoreProduct else {
                purchaseError = "Pro purchase is not configured yet in App Store Connect."
                isPurchasing = false
                return
            }

            do {
                let result = try await product.purchase()
                switch result {
                case let .success(verification):
                    guard case let .verified(transaction) = verification else {
                        purchaseError = "Purchase verification failed. Please try again."
                        isPurchasing = false
                        return
                    }

                    if transaction.productID != productID {
                        purchaseError = "Unexpected product received from App Store."
                        isPurchasing = false
                        return
                    }

                    await transaction.finish()
                    isPro = true
                    isEarlyAdopter = false
                    licenseEmail = nil
                    purchaseError = nil
                    validationError = nil
                    licenseLogger.info("App Store purchase completed for \(productID)")
                case .pending:
                    purchaseError = "Purchase is pending approval."
                case .userCancelled:
                    break
                @unknown default:
                    purchaseError = "Purchase was not completed."
                }
            } catch {
                purchaseError = "Purchase failed. Please try again."
                licenseLogger.error("StoreKit purchase failed: \(error.localizedDescription)")
            }

            isPurchasing = false
        #else
            purchaseError = "App Store purchases are not available on this platform."
        #endif
    }

    func restorePurchases() async {
        guard usesAppStorePurchase else { return }
        #if canImport(StoreKit)
            isPurchasing = true
            purchaseError = nil
            do {
                try await AppStore.sync()
                await refreshAppStoreEntitlement()
                if !isPro {
                    purchaseError = "No prior Pro purchase was found for this Apple ID."
                }
            } catch {
                purchaseError = "Restore failed. Please try again."
                licenseLogger.error("StoreKit restore failed: \(error.localizedDescription)")
            }
            isPurchasing = false
        #else
            purchaseError = "App Store purchases are not available on this platform."
        #endif
    }

    private func refreshAppStoreEntitlement() async {
        guard usesAppStorePurchase, let productID = Self.appStoreProductIDFromBundle() else { return }
        #if canImport(StoreKit)
            var unlocked = false
            for await result in Transaction.currentEntitlements {
                guard case let .verified(transaction) = result else { continue }
                guard transaction.productID == productID else { continue }
                guard transaction.revocationDate == nil else { continue }
                unlocked = true
                break
            }
            isPro = unlocked
            isEarlyAdopter = false
            if unlocked {
                validationError = nil
                purchaseError = nil
            }
            licenseLogger.info("App Store entitlement check: \(unlocked ? "pro" : "free")")
        #endif
    }

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
            let error = json?["error"] as? String ?? ["Invalid", Self.licenseKeyLabel().lowercased() + "."].joined(separator: " ")
            return ValidationResult(valid: false, email: nil, error: error)
        }
    }

}
