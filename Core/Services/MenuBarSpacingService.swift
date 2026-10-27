import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarSpacing")


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


@MainActor
final class MenuBarSpacingService {

    private static let spacingKey = "NSStatusItemSpacing"
    private static let paddingKey = "NSStatusItemSelectionPadding"
    private static let validRange = 1 ... 10


    static let shared = MenuBarSpacingService()


    func currentSpacing() -> Int? {
        readDefaultsInt(Self.spacingKey)
    }

    func currentSelectionPadding() -> Int? {
        readDefaultsInt(Self.paddingKey)
    }


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


    private func readDefaultsInt(_ key: String) -> Int? {
        let value = CFPreferencesCopyValue(
            key as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        )
        return value as? Int
    }

    private func writeDefaultsInt(_ key: String, value: Int) throws {
        CFPreferencesSetValue(
            key as CFString,
            value as CFNumber,
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
