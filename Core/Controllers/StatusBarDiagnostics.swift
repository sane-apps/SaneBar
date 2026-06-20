import AppKit
import Foundation

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

struct HiddenCollapsedSeparatorHealthInput: Equatable, Sendable {
    let hidingState: HidingState
    let mainWindowValid: Bool
    let separatorVisible: Bool?
    let separatorX: CGFloat?
    let mainX: CGFloat?
    let mainRightGap: CGFloat?
    let screenWidth: CGFloat?
    let notchRightSafeMinX: CGFloat?
    let persistedMainDistanceFromRight: CGFloat?

    init(
        hidingState: HidingState,
        mainWindowValid: Bool,
        separatorVisible: Bool?,
        separatorX: CGFloat?,
        mainX: CGFloat?,
        mainRightGap: CGFloat?,
        screenWidth: CGFloat?,
        notchRightSafeMinX: CGFloat?,
        persistedMainDistanceFromRight: CGFloat? = nil
    ) {
        self.hidingState = hidingState
        self.mainWindowValid = mainWindowValid
        self.separatorVisible = separatorVisible
        self.separatorX = separatorX
        self.mainX = mainX
        self.mainRightGap = mainRightGap
        self.screenWidth = screenWidth
        self.notchRightSafeMinX = notchRightSafeMinX
        self.persistedMainDistanceFromRight = persistedMainDistanceFromRight
    }
}

enum StatusBarDiagnostics {
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
        guard let windowFrame else { return false }
        guard let screenFrame else {
            return detachedVisibleStatusItemWindowLooksParked(windowFrame)
        }
        return !StatusBarController.isStatusItemWindowFrameValid(windowFrame: windowFrame, screenFrame: screenFrame)
    }

    nonisolated static func detachedVisibleStatusItemWindowLooksParked(_ windowFrame: CGRect) -> Bool {
        guard windowFrame.origin.x.isFinite,
              windowFrame.origin.y.isFinite,
              windowFrame.width.isFinite,
              windowFrame.height.isFinite,
              windowFrame.width > 0,
              windowFrame.height > 0 else {
            return false
        }

        return abs(windowFrame.origin.x) <= 1 &&
            windowFrame.origin.y < 0 &&
            windowFrame.maxY <= 1
    }

    nonisolated static func likelySystemSuppressedStatusItems(
        startupItemsValid: Bool,
        main: StatusItemSuppressionInput,
        separator: StatusItemSuppressionInput
    ) -> Bool {
        guard !startupItemsValid else { return false }
        return likelySystemSuppressedStatusItem(
            isVisibleFlag: main.isVisibleFlag,
            windowFrame: main.windowFrame,
            screenFrame: main.screenFrame
        ) || likelySystemSuppressedStatusItem(
            isVisibleFlag: separator.isVisibleFlag,
            windowFrame: separator.windowFrame,
            screenFrame: separator.screenFrame
        )
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

    nonisolated static func hiddenCollapsedSeparatorIsStructurallyHealthy(
        _ input: HiddenCollapsedSeparatorHealthInput
    ) -> Bool {
        guard input.hidingState == .hidden else { return false }
        guard input.mainWindowValid, input.separatorVisible == true else { return false }
        guard let separatorX = input.separatorX, let mainX = input.mainX, separatorX < mainX else { return false }
        guard !MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
            separatorX: input.separatorX,
            mainX: input.mainX,
            mainRightGap: input.mainRightGap,
            screenWidth: input.screenWidth,
            notchRightSafeMinX: input.notchRightSafeMinX,
            persistedMainDistanceFromRight: input.persistedMainDistanceFromRight
        ) else {
            return false
        }
        if hasUsablePersistedMainIntent(
            persistedMainDistanceFromRight: input.persistedMainDistanceFromRight,
            mainRightGap: input.mainRightGap
        ) {
            return true
        }
        return MenuBarVisibilityPolicy.isMainNearControlCenter(
            mainX: mainX,
            mainRightGap: input.mainRightGap,
            screenWidth: input.screenWidth,
            notchRightSafeMinX: input.notchRightSafeMinX
        )
    }

    nonisolated static func persistedMainDistanceFromRight() -> CGFloat? {
        let persisted = StatusBarPositionDefaultsStore.resolvedPreferredPosition(
            forAutosaveName: StatusBarController.mainAutosaveName
        )
        guard StatusBarController.isPixelLikePosition(persisted), let persisted else { return nil }
        return CGFloat(persisted)
    }

    private nonisolated static func hasUsablePersistedMainIntent(
        persistedMainDistanceFromRight: CGFloat?,
        mainRightGap: CGFloat?
    ) -> Bool {
        guard let persistedMainDistanceFromRight,
              persistedMainDistanceFromRight.isFinite,
              persistedMainDistanceFromRight >= 0,
              persistedMainDistanceFromRight < 5000,
              let mainRightGap,
              mainRightGap.isFinite else {
            return false
        }
        return true
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
