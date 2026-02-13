import Foundation
@testable import SaneBar
import Testing

// MARK: - Mock Keychain

/// In-memory keychain for testing — no actual Keychain access.
private final class MockKeychainService: KeychainServiceProtocol, @unchecked Sendable {
    private var bools: [String: Bool] = [:]
    private var strings: [String: String] = [:]

    func bool(forKey key: String) throws -> Bool? { bools[key] }
    func set(_ value: Bool, forKey key: String) throws { bools[key] = value }
    func string(forKey key: String) throws -> String? { strings[key] }
    func set(_ value: String, forKey key: String) throws { strings[key] = value }
    func delete(_ key: String) throws {
        bools.removeValue(forKey: key)
        strings.removeValue(forKey: key)
    }
}

// MARK: - Tests

@MainActor
struct LicenseServiceTests {
    @Test("Fresh install starts in free mode")
    func freshInstallIsFree() {
        let keychain = MockKeychainService()
        let service = LicenseService(keychain: keychain)
        service.checkCachedLicense()

        #expect(!service.isPro)
        #expect(service.licenseEmail == nil)
    }

    @Test("Cached license within grace period activates Pro")
    func cachedLicenseWithinGrace() throws {
        let keychain = MockKeychainService()
        try keychain.set("test-license-key-123", forKey: "pro_license_key")
        try keychain.set("user@example.com", forKey: "pro_license_email")
        // Validated 5 days ago — well within 30-day grace
        let fiveDaysAgo = Date().addingTimeInterval(-5 * 86400)
        try keychain.set(ISO8601DateFormatter().string(from: fiveDaysAgo), forKey: "pro_last_validation")

        let service = LicenseService(keychain: keychain)
        service.checkCachedLicense()

        #expect(service.isPro)
        #expect(service.licenseEmail == "user@example.com")
    }

    @Test("Deactivation clears all license data")
    func deactivationClearsData() throws {
        let keychain = MockKeychainService()
        try keychain.set("test-key", forKey: "pro_license_key")
        try keychain.set("user@test.com", forKey: "pro_license_email")
        try keychain.set(ISO8601DateFormatter().string(from: Date()), forKey: "pro_last_validation")

        let service = LicenseService(keychain: keychain)
        service.checkCachedLicense()
        #expect(service.isPro)

        service.deactivate()

        #expect(!service.isPro)
        #expect(service.licenseEmail == nil)
        #expect(try keychain.string(forKey: "pro_license_key") == nil)
        #expect(try keychain.string(forKey: "pro_license_email") == nil)
    }

    @Test("Empty key is rejected without network call")
    func emptyKeyRejected() async {
        let keychain = MockKeychainService()
        let service = LicenseService(keychain: keychain)

        await service.activate(key: "   ")

        #expect(!service.isPro)
        #expect(service.validationError == "Please enter a license key.")
    }

    @Test("ProFeature enum has all required cases")
    func proFeatureEnumComplete() {
        // Verify key features exist and have non-empty descriptions
        let features: [ProFeature] = [
            .iconActivation, .rightClickFromPanels, .zoneMoves,
            .alwaysHidden, .perIconHotkeys, .iconGroups,
            .advancedTriggers, .menuBarAppearance, .touchIDProtection,
        ]

        for feature in features {
            #expect(!feature.rawValue.isEmpty)
            #expect(!feature.description.isEmpty)
            #expect(!feature.icon.isEmpty)
        }
    }

    @Test("ProFeature conforms to Identifiable")
    func proFeatureIdentifiable() {
        let feature = ProFeature.iconActivation
        #expect(feature.id == feature.rawValue)
    }
}
