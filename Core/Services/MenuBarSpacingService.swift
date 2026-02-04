import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarSpacing")

// MARK: - MenuBarSpacingServiceProtocol

/// @mockable
@MainActor
protocol MenuBarSpacingServiceProtocol {
    /// Current spacing value (nil if using system default)
    func currentSpacing() -> Int?

    /// Current selection padding (nil if using system default)
    func currentSelectionPadding() -> Int?

    /// Set spacing (1-10, or nil to reset)
    func setSpacing(_ value: Int?) throws

    /// Set selection padding (1-10, or nil to reset)
    func setSelectionPadding(_ value: Int?) throws

    /// Reset both to system defaults
    func resetToDefaults() throws

    /// Attempt graceful refresh (may not work - logout usually required)
    func attemptGracefulRefresh()
}

// MARK: - MenuBarSpacingError

enum MenuBarSpacingError: Error, LocalizedError {
    case valueOutOfRange(Int)
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case let .valueOutOfRange(value):
            "Spacing value \(value) is out of range (must be 1-10)"
        case let .commandFailed(message):
            "Failed to execute defaults command: \(message)"
        }
    }
}

// MARK: - MenuBarSpacingService

/// Service that manages system-wide menu bar icon spacing via macOS defaults.
///
/// Uses the private `NSStatusItemSpacing` and `NSStatusItemSelectionPadding` keys
/// in the `-currentHost -globalDomain` defaults domain. These settings affect ALL
/// menu bar icons system-wide, not just SaneBar.
///
/// **Important**: Changes typically require logout/login to take effect.
@MainActor
final class MenuBarSpacingService: MenuBarSpacingServiceProtocol {
    // MARK: - Constants

    private static let spacingKey = "NSStatusItemSpacing"
    private static let paddingKey = "NSStatusItemSelectionPadding"
    private static let validRange = 1 ... 10

    // MARK: - Singleton

    static let shared = MenuBarSpacingService()

    // MARK: - Reading Values

    func currentSpacing() -> Int? {
        readDefaultsInt(Self.spacingKey)
    }

    func currentSelectionPadding() -> Int? {
        readDefaultsInt(Self.paddingKey)
    }

    // MARK: - Writing Values

    func setSpacing(_ value: Int?) throws {
        if let value {
            guard Self.validRange.contains(value) else {
                throw MenuBarSpacingError.valueOutOfRange(value)
            }
            try writeDefaultsInt(Self.spacingKey, value: value)
            logger.info("Set menu bar spacing to \(value)")
        } else {
            try deleteDefaultsKey(Self.spacingKey)
            logger.info("Reset menu bar spacing to system default")
        }
    }

    func setSelectionPadding(_ value: Int?) throws {
        if let value {
            guard Self.validRange.contains(value) else {
                throw MenuBarSpacingError.valueOutOfRange(value)
            }
            try writeDefaultsInt(Self.paddingKey, value: value)
            logger.info("Set menu bar selection padding to \(value)")
        } else {
            try deleteDefaultsKey(Self.paddingKey)
            logger.info("Reset menu bar selection padding to system default")
        }
    }

    func resetToDefaults() throws {
        try? deleteDefaultsKey(Self.spacingKey)
        try? deleteDefaultsKey(Self.paddingKey)
        logger.info("Reset all menu bar spacing to system defaults")
    }

    // MARK: - Graceful Refresh

    /// Attempts to notify the system of spacing changes without requiring logout.
    /// This uses DistributedNotificationCenter to post known notification names
    /// that Control Center/SystemUIServer might listen to.
    ///
    /// **Note**: This rarely works - most users will need to logout/login.
    func attemptGracefulRefresh() {
        let notifications = [
            "com.apple.controlcenter.settingschanged",
            "com.apple.systemuiserver.spacingchanged",
            "com.apple.menubar.settingschanged",
            "NSStatusItemSpacingChanged"
        ]

        let center = DistributedNotificationCenter.default()
        for name in notifications {
            center.postNotificationName(
                NSNotification.Name(name),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }

        logger.debug("Posted graceful refresh notifications")
    }

    // MARK: - Private Helpers (CFPreferences)

    /// Reads an integer from the global domain for the current host.
    /// Equivalent to: `defaults -currentHost read -g <key>`
    private func readDefaultsInt(_ key: String) -> Int? {
        let value = CFPreferencesCopyValue(
            key as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        return value as? Int
    }

    /// Writes an integer to the global domain for the current host.
    /// Equivalent to: `defaults -currentHost write -g <key> -int <value>`
    private func writeDefaultsInt(_ key: String, value: Int) throws {
        CFPreferencesSetValue(
            key as CFString,
            value as CFNumber,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        // Best-effort sync to disk. The value is already in the in-memory
        // preferences cache and readable via CFPreferencesCopyValue.
        // Sync may fail in test environments without affecting functionality.
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }

    /// Deletes a key from the global domain for the current host.
    /// Equivalent to: `defaults -currentHost delete -g <key>`
    private func deleteDefaultsKey(_ key: String) throws {
        CFPreferencesSetValue(
            key as CFString,
            nil,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesSynchronize(
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
    }
}
