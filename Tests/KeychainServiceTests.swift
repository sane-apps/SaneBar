import Foundation
import Testing

@testable import SaneBar

struct KeychainServiceTests {
    @Test("Legacy no-keychain values migrate into the primary defaults domain")
    func legacyFallbackMigratesForward() {
        let service = "KeychainServiceTests.\(UUID().uuidString)"
        let key = "sane.no-keychain.\(service).pro_license_key"

        let primaryDefaults = UserDefaults.standard
        let legacySuiteName = "\(service)\(KeychainService.legacyFallbackSuiteNameSuffix)"
        let legacyDefaults = UserDefaults(suiteName: legacySuiteName)!

        primaryDefaults.removeObject(forKey: key)
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        defer {
            primaryDefaults.removeObject(forKey: key)
            legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        }

        legacyDefaults.set("sample-license-key", forKey: key)

        let keychain = KeychainService(service: service)
        let migratedValue = try? keychain.string(forKey: "pro_license_key")

        #expect(migratedValue == "sample-license-key")
        #expect(primaryDefaults.string(forKey: key) == "sample-license-key")
        #expect(legacyDefaults.object(forKey: key) == nil)
    }
}
