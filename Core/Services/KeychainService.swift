import Foundation
import LocalAuthentication
import Security

protocol KeychainServiceProtocol: Sendable {
    func bool(forKey key: String) throws -> Bool?
    func set(_ value: Bool, forKey key: String) throws
    func string(forKey key: String) throws -> String?
    func set(_ value: String, forKey key: String) throws
    func delete(_ key: String) throws
}

struct KeychainError: LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error (\(status))"
    }
}

final class KeychainService: KeychainServiceProtocol, @unchecked Sendable {
    static let shared = KeychainService()
    static let legacyFallbackSuiteNameSuffix = ".no-keychain"

    private let service: String

    private let isTestEnvironment: Bool
    private let isKeychainBypassed: Bool
    private let usesFallbackStorage: Bool
    private let fallbackDefaults: UserDefaults
    private let legacyFallbackDefaults: UserDefaults?

    init(service: String = Bundle.main.bundleIdentifier ?? "com.sanebar.app") {
        self.service = service
        self.fallbackDefaults = .standard
        self.legacyFallbackDefaults = UserDefaults(suiteName: "\(service)\(Self.legacyFallbackSuiteNameSuffix)")
        let debugBypass: Bool = {
#if DEBUG
            return ProcessInfo.processInfo.environment["SANEAPPS_ENABLE_KEYCHAIN_IN_DEBUG"] != "1"
#else
            return false
#endif
        }()
        isTestEnvironment = NSClassFromString("XCTestCase") != nil
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let explicitDebugBypass: Bool = {
#if DEBUG
            return ProcessInfo.processInfo.environment["SANEAPPS_DISABLE_KEYCHAIN"] == "1"
                || ProcessInfo.processInfo.arguments.contains("--sane-no-keychain")
#else
            return false
#endif
        }()
        isKeychainBypassed = debugBypass || explicitDebugBypass
        usesFallbackStorage = isTestEnvironment || isKeychainBypassed
    }

    func bool(forKey key: String) throws -> Bool? {
        if usesFallbackStorage {
            return fallbackString(forKey: fallbackKey(key)).flatMap { fallbackBool(for: $0) }
        }
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ]
        Self.applyNonInteractiveReadPolicy(to: &query)

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return fallbackBool(forKey: fallbackKey(key)) }
        if Self.isSilentKeychainFailure(status) { return fallbackBool(forKey: fallbackKey(key)) }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data else { return nil }
        return data.first == 1
    }

    func set(_ value: Bool, forKey key: String) throws {
        if usesFallbackStorage {
            fallbackDefaults.set(value ? "1" : "0", forKey: fallbackKey(key))
            legacyFallbackDefaults?.removeObject(forKey: fallbackKey(key))
            return
        }
        let data = Data([value ? 1 : 0])
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
            return
        }

        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func string(forKey key: String) throws -> String? {
        if usesFallbackStorage {
            return fallbackString(forKey: fallbackKey(key))
        }
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecReturnData: true
        ]
        Self.applyNonInteractiveReadPolicy(to: &query)

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return fallbackString(forKey: fallbackKey(key)) }
        if Self.isSilentKeychainFailure(status) { return fallbackString(forKey: fallbackKey(key)) }
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func set(_ value: String, forKey key: String) throws {
        if usesFallbackStorage {
            fallbackDefaults.set(value, forKey: fallbackKey(key))
            legacyFallbackDefaults?.removeObject(forKey: fallbackKey(key))
            return
        }
        guard let data = value.data(using: .utf8) else { return }
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]

        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData] = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
            return
        }

        guard status == errSecSuccess else { throw KeychainError(status: status) }
    }

    func delete(_ key: String) throws {
        if usesFallbackStorage {
            fallbackDefaults.removeObject(forKey: fallbackKey(key))
            legacyFallbackDefaults?.removeObject(forKey: fallbackKey(key))
            return
        }
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key
        ]
        Self.applyNonInteractiveReadPolicy(to: &query)
        let status = SecItemDelete(query as CFDictionary)
        fallbackDefaults.removeObject(forKey: fallbackKey(key))
        legacyFallbackDefaults?.removeObject(forKey: fallbackKey(key))
        guard status == errSecSuccess || status == errSecItemNotFound || Self.isSilentKeychainFailure(status) else {
            throw KeychainError(status: status)
        }
    }

    static func applyNonInteractiveReadPolicy(to query: inout [CFString: Any]) {
        query[kSecUseAuthenticationUI] = kSecUseAuthenticationUIFail
        query[kSecUseAuthenticationContext] = {
            let context = LAContext()
            context.interactionNotAllowed = true
            return context
        }()
    }

    private static func isSilentKeychainFailure(_ status: OSStatus) -> Bool {
        status == errSecInteractionNotAllowed
            || status == errSecAuthFailed
            || status == errSecUserCanceled
            || status == errSecWrPerm
    }

    private func fallbackKey(_ key: String) -> String {
        "sane.no-keychain.\(service).\(key)"
    }

    private func fallbackBool(forKey key: String) -> Bool? {
        fallbackString(forKey: key).flatMap { fallbackBool(for: $0) }
    }

    private func fallbackString(forKey key: String) -> String? {
        if let value = fallbackDefaults.string(forKey: key) {
            return value
        }
        guard let legacyValue = legacyFallbackDefaults?.string(forKey: key) else { return nil }

        fallbackDefaults.set(legacyValue, forKey: key)
        legacyFallbackDefaults?.removeObject(forKey: key)
        return legacyValue
    }

    private func fallbackBool(for value: String) -> Bool? {
        switch value.lowercased() {
        case "1", "true", "yes":
            return true
        case "0", "false", "no":
            return false
        default:
            return nil
        }
    }
}
