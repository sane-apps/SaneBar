import Foundation
@testable import SaneBar
import Testing

// MARK: - Mock Keychain

/// In-memory keychain for testing — no actual Keychain access.
private final class MockKeychainService: KeychainServiceProtocol, @unchecked Sendable {
    private var bools: [String: Bool] = [:]
    private var strings: [String: String] = [:]

    func bool(forKey key: String) throws -> Bool? {
        bools[key]
    }

    func set(_ value: Bool, forKey key: String) throws {
        bools[key] = value
    }

    func string(forKey key: String) throws -> String? {
        strings[key]
    }

    func set(_ value: String, forKey key: String) throws {
        strings[key] = value
    }

    func delete(_ key: String) throws {
        bools.removeValue(forKey: key)
        strings.removeValue(forKey: key)
    }
}

// MARK: - Tests

private func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "LicenseServiceTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

@MainActor
struct LicenseServiceTests {
    @Test("Free build (June 2026 MIT) unlocks Pro for everyone with no license or trial")
    func freeBuildUnlocksProForEveryone() {
        let keychain = MockKeychainService() // no stored license key
        let defaults = makeIsolatedDefaults()
        // Production default: freeBuildUnlock == true. SaneBar is free + open source.
        let service = LicenseService(keychain: keychain, userDefaults: defaults)
        service.checkCachedLicense()

        #expect(service.isPro) // the unlock fires for an unlicensed user
        #expect(service.hasPaidUnlock)
        #expect(!service.isProTrialActive) // Pro is granted by the free build, not a trial
        #expect(service.licenseEmail == nil)
    }

    @Test("Fresh install starts the 14-day Pro trial")
    func freshInstallStartsProTrial() throws {
        let keychain = MockKeychainService()
        let defaults = makeIsolatedDefaults()
        let service = LicenseService(keychain: keychain, userDefaults: defaults, freeBuildUnlock: false)
        service.checkCachedLicense()

        #expect(service.isPro)
        #expect(service.isProTrialActive)
        #expect(service.proAccessBadgeTitle == "Pro Trial")
        #expect(service.proTrialDaysRemaining == 14)
        #expect(try keychain.string(forKey: "sanebar.pro_trial.started_at") != nil)
        #expect(try keychain.string(forKey: "sanebar.pro_trial.last_seen_at") != nil)
        #expect(defaults.object(forKey: "sanebar.pro_trial.started_at") != nil)
        #expect(defaults.object(forKey: "sanebar.pro_trial.last_seen_at") != nil)
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

        let service = LicenseService(keychain: keychain, userDefaults: makeIsolatedDefaults(), freeBuildUnlock: false)
        service.checkCachedLicense()

        #expect(service.isPro)
        #expect(service.licenseEmail == "user@example.com")
    }

    @Test("Existing paid Pro users stay Pro without trial state")
    func existingPaidUsersStayProWithoutTrialState() throws {
        let keychain = MockKeychainService()
        try keychain.set("paid-license-key-123", forKey: "pro_license_key")
        try keychain.set("paid@example.com", forKey: "pro_license_email")
        try keychain.set(ISO8601DateFormatter().string(from: Date()), forKey: "pro_last_validation")

        let service = LicenseService(keychain: keychain, userDefaults: makeIsolatedDefaults(), freeBuildUnlock: false)
        service.checkCachedLicense()

        #expect(service.isPro)
        #expect(!service.isProTrialActive)
        #expect(service.proTrialStartedAt == nil)
        #expect(service.licenseEmail == "paid@example.com")
        #expect(try keychain.string(forKey: "pro_license_key") == "paid-license-key-123")
    }

    @Test("Paid license supersedes an in-progress Pro trial badge")
    func paidLicenseSupersedesActiveTrial() throws {
        let keychain = MockKeychainService()
        // The 14-day trial began when the customer updated, seeding trial dates...
        try keychain.set(String(Date().addingTimeInterval(-3 * 86400).timeIntervalSince1970), forKey: "sanebar.pro_trial.started_at")
        try keychain.set(String(Date().timeIntervalSince1970), forKey: "sanebar.pro_trial.last_seen_at")
        // ...then they activated a real paid license, which must win over the trial.
        try keychain.set("paid-license-key-123", forKey: "pro_license_key")
        try keychain.set("paid@example.com", forKey: "pro_license_email")
        try keychain.set(ISO8601DateFormatter().string(from: Date()), forKey: "pro_last_validation")

        let service = LicenseService(keychain: keychain, userDefaults: makeIsolatedDefaults(), freeBuildUnlock: false)
        service.checkCachedLicense()

        #expect(service.isPro)
        #expect(service.hasPaidUnlock)
        #expect(!service.isProTrialActive)
        #expect(!service.hasExpiredProTrial)
        #expect(service.proAccessBadgeTitle == "Pro")
        #expect(service.proAccessDetail == nil)
    }

    @Test("An expired trial never demotes a paying customer to Basic")
    func expiredTrialDoesNotDemotePaidUser() throws {
        let keychain = MockKeychainService()
        // Trial clock started 20 days ago (well past the 14-day window)...
        try keychain.set(String(Date().addingTimeInterval(-20 * 86400).timeIntervalSince1970), forKey: "sanebar.pro_trial.started_at")
        try keychain.set(String(Date().timeIntervalSince1970), forKey: "sanebar.pro_trial.last_seen_at")
        // ...but a paid license is present, so Pro must stay active.
        try keychain.set("paid-license-key-456", forKey: "pro_license_key")
        try keychain.set(ISO8601DateFormatter().string(from: Date()), forKey: "pro_last_validation")

        let service = LicenseService(keychain: keychain, userDefaults: makeIsolatedDefaults(), freeBuildUnlock: false)
        service.checkCachedLicense()

        #expect(service.isPro)
        #expect(service.hasPaidUnlock)
        #expect(!service.hasExpiredProTrial)
        #expect(service.proAccessBadgeTitle == "Pro")
    }

    @Test("Legacy early-adopter marker is retired into Pro trial")
    func legacyEarlyAdopterMarkerIsRetiredIntoProTrial() throws {
        let keychain = MockKeychainService()
        try keychain.set("early-adopter", forKey: "pro_license_key")
        try keychain.set(ISO8601DateFormatter().string(from: Date()), forKey: "pro_last_validation")

        let service = LicenseService(keychain: keychain, userDefaults: makeIsolatedDefaults(), freeBuildUnlock: false)
        service.checkCachedLicense()

        #expect(service.isPro)
        #expect(service.isProTrialActive)
        #expect(service.proTrialDaysRemaining == 14)
        #expect(try keychain.string(forKey: "pro_license_key") == nil)
        #expect(try keychain.string(forKey: "pro_last_validation") == nil)
        #expect(try keychain.string(forKey: "sanebar.pro_trial.started_at") != nil)
    }

    @Test("Trial uses last seen timestamp against clock rollback")
    func trialUsesLastSeenTimestampAgainstClockRollback() throws {
        let keychain = MockKeychainService()
        try keychain.set(String(Date().addingTimeInterval(-13 * 86400).timeIntervalSince1970), forKey: "sanebar.pro_trial.started_at")
        try keychain.set(String(Date().addingTimeInterval(2 * 86400).timeIntervalSince1970), forKey: "sanebar.pro_trial.last_seen_at")

        let service = LicenseService(keychain: keychain, userDefaults: makeIsolatedDefaults(), freeBuildUnlock: false)
        service.checkCachedLicense()

        #expect(!service.isPro)
        #expect(!service.isProTrialActive)
        #expect(service.hasExpiredProTrial)
        #expect(service.proAccessDetail == "Trial ended")
    }

    @Test("Trial restores from UserDefaults when keychain state is missing")
    func trialRestoresFromUserDefaultsWhenKeychainStateIsMissing() throws {
        let keychain = MockKeychainService()
        let defaults = makeIsolatedDefaults()
        let startedAt = Date().addingTimeInterval(-3 * 86400).timeIntervalSince1970
        let lastSeenAt = Date().addingTimeInterval(-2 * 86400).timeIntervalSince1970
        defaults.set(startedAt, forKey: "sanebar.pro_trial.started_at")
        defaults.set(lastSeenAt, forKey: "sanebar.pro_trial.last_seen_at")

        let service = LicenseService(keychain: keychain, userDefaults: defaults, freeBuildUnlock: false)
        service.checkCachedLicense()

        #expect(service.isPro)
        #expect(service.isProTrialActive)
        #expect(try keychain.string(forKey: "sanebar.pro_trial.started_at") != nil)
        #expect(try keychain.string(forKey: "sanebar.pro_trial.last_seen_at") != nil)
    }

    @Test("Deactivation clears all license data")
    func deactivationClearsData() throws {
        let keychain = MockKeychainService()
        try keychain.set("test-key", forKey: "pro_license_key")
        try keychain.set("user@test.com", forKey: "pro_license_email")
        try keychain.set(ISO8601DateFormatter().string(from: Date()), forKey: "pro_last_validation")

        let service = LicenseService(keychain: keychain, userDefaults: makeIsolatedDefaults(), freeBuildUnlock: false)
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
        let service = LicenseService(keychain: keychain, userDefaults: makeIsolatedDefaults(), freeBuildUnlock: false)

        await service.activate(key: "   ")

        #expect(!service.isPro)
        #expect(service.validationError == "Please enter a license key.")
    }

    @Test("License metadata must match SaneBar")
    func licenseMetadataMustMatchSaneBar() {
        #expect(LicenseService.licenseProductMatchesApp(productName: "SaneBar", variantName: "Pro"))
        #expect(LicenseService.licenseProductMatchesApp(productName: "SaneApps Bundle", variantName: "SaneBar Pro"))
        #expect(!LicenseService.licenseProductMatchesApp(productName: "SaneVideo", variantName: "Pro"))
        #expect(!LicenseService.licenseProductMatchesApp(productName: nil, variantName: nil))
    }

    @Test("License input extracts forwarded receipt keys")
    func licenseInputExtractsForwardedReceiptKeys() {
        let key = "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"
        #expect(LicenseService.normalizedLicenseKeyInput("License key:\n\(key)\u{200B}") == key)
        #expect(LicenseService.normalizedLicenseKeyInput("aaaaaaaa–bbbb–4ccc–8ddd–eeeeeeeeeeee") == key)
        #expect(LicenseService.normalizedLicenseKeyInput("  \(key.prefix(8)) \n-\tBBBB-4CCC-8DDD-EEEEEEEEEEEE  ") == key)
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

    @Test("Distribution channel resolves direct, App Store, and Setapp lanes")
    func distributionChannelResolution() {
        #expect(LicenseService.resolvedDistributionChannel(appStoreProductIDPresent: false, setappBuild: false) == .direct)
        #expect(LicenseService.resolvedDistributionChannel(appStoreProductIDPresent: true, setappBuild: false) == .appStore)
        #expect(LicenseService.resolvedDistributionChannel(appStoreProductIDPresent: true, setappBuild: true) == .setapp)
        #expect(LicenseService.resolvedDistributionChannel(appStoreProductIDPresent: false, setappBuild: true) == .setapp)
    }

    #if SETAPP
        @Test("Setapp build starts in Pro mode")
        func setappBuildStartsInProMode() {
            let keychain = MockKeychainService()
            let service = LicenseService(keychain: keychain, userDefaults: makeIsolatedDefaults(), freeBuildUnlock: false)

            service.checkCachedLicense()

            #expect(service.isPro)
            #expect(service.validationError == nil)
            #expect(service.purchaseError == nil)
        }
    #endif
}
