import AppKit
import Foundation

extension StatusBarController {
    struct StatusItemVisibilityOverrideSnapshot: Equatable, Sendable {
        let scope: String
        let key: String
        let value: String
    }

    struct MissionControlSpacesDiagnostic: Equatable, Sendable {
        let spansDisplays: Bool?

        var displaysHaveSeparateSpaces: Bool? {
            spansDisplays.map { !$0 }
        }

        var summary: String {
            guard let spansDisplays else { return "unknown" }
            return spansDisplays
                ? "likely disabled (spans-displays=true)"
                : "likely enabled (spans-displays=false)"
        }
    }

    struct StatusItemSuppressionInput: Equatable, Sendable {
        let isVisibleFlag: Bool?
        let windowFrame: CGRect?
        let screenFrame: CGRect?
    }

    nonisolated static let statusItemVisibilityOverridePrefixes = [
        "NSStatusItem Visible SaneBar_",
        "NSStatusItem VisibleCC SaneBar_"
    ]

    nonisolated static func visibilityOverrideKeys(from keys: [String]) -> [String] {
        keys
            .filter { key in
                statusItemVisibilityOverridePrefixes.contains { key.hasPrefix($0) }
            }
            .sorted()
    }

    nonisolated static func likelySystemSuppressedStatusItem(
        isVisibleFlag: Bool?,
        windowFrame: CGRect?,
        screenFrame: CGRect?
    ) -> Bool {
        guard isVisibleFlag == true else { return false }
        return !isStatusItemWindowFrameValid(windowFrame: windowFrame, screenFrame: screenFrame)
    }

    nonisolated static func systemMenuBarSuppressionHint(
        main: StatusItemSuppressionInput,
        separator: StatusItemSuppressionInput
    ) -> String {
        let mainSuppressed = likelySystemSuppressedStatusItem(
            isVisibleFlag: main.isVisibleFlag,
            windowFrame: main.windowFrame,
            screenFrame: main.screenFrame
        )
        let separatorSuppressed = likelySystemSuppressedStatusItem(
            isVisibleFlag: separator.isVisibleFlag,
            windowFrame: separator.windowFrame,
            screenFrame: separator.screenFrame
        )

        if mainSuppressed || separatorSuppressed {
            return "possible macOS menu bar suppression: check System Settings > Menu Bar > Allow in Menu Bar for SaneBar"
        }
        return "none"
    }

    nonisolated static func missionControlSpacesSummary(spansDisplays: Bool?) -> String {
        MissionControlSpacesDiagnostic(spansDisplays: spansDisplays).summary
    }

    nonisolated static func missionControlSpacesDiagnostic() -> MissionControlSpacesDiagnostic {
        let value = copyBooleanPreference(
            key: "spans-displays",
            domain: "com.apple.spaces",
            host: kCFPreferencesCurrentHost
        ) ?? copyBooleanPreference(
            key: "spans-displays",
            domain: "com.apple.spaces",
            host: kCFPreferencesAnyHost
        )
        return MissionControlSpacesDiagnostic(spansDisplays: value)
    }

    nonisolated static func statusItemVisibilityOverrideSnapshots() -> [StatusItemVisibilityOverrideSnapshot] {
        let defaults = UserDefaults.standard
        let appSnapshots = visibilityOverrideKeys(from: Array(defaults.dictionaryRepresentation().keys))
            .compactMap { key -> StatusItemVisibilityOverrideSnapshot? in
                guard let value = defaults.object(forKey: key) else { return nil }
                return StatusItemVisibilityOverrideSnapshot(
                    scope: "app",
                    key: key,
                    value: formatVisibilityOverrideValue(value)
                )
            }

        let globalDomain = ".GlobalPreferences" as CFString
        let byHostKeys = CFPreferencesCopyKeyList(
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) as? [String] ?? []

        let byHostSnapshots = visibilityOverrideKeys(from: byHostKeys)
            .compactMap { key -> StatusItemVisibilityOverrideSnapshot? in
                guard let value = CFPreferencesCopyValue(
                    key as CFString,
                    globalDomain,
                    kCFPreferencesCurrentUser,
                    kCFPreferencesCurrentHost
                ) else { return nil }
                return StatusItemVisibilityOverrideSnapshot(
                    scope: "currentHost",
                    key: key,
                    value: formatVisibilityOverrideValue(value)
                )
            }

        return (appSnapshots + byHostSnapshots).sorted {
            if $0.scope == $1.scope {
                return $0.key < $1.key
            }
            return $0.scope < $1.scope
        }
    }

    private nonisolated static func copyBooleanPreference(
        key: String,
        domain: String,
        host: CFString
    ) -> Bool? {
        guard let value = CFPreferencesCopyValue(
            key as CFString,
            domain as CFString,
            kCFPreferencesCurrentUser,
            host
        ) else { return nil }
        return boolPreferenceValue(value)
    }

    private nonisolated static func boolPreferenceValue(_ value: Any) -> Bool? {
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        if let string = value as? String {
            switch string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "1", "true", "yes":
                return true
            case "0", "false", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }

    private nonisolated static func formatVisibilityOverrideValue(_ value: Any) -> String {
        if let bool = boolPreferenceValue(value) {
            return bool ? "true" : "false"
        }
        return String(describing: value)
    }
}
