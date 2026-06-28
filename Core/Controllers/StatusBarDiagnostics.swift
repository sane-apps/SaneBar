import AppKit
import Foundation

struct StatusItemVisibilityOverrideSnapshot: Equatable {
    let scope: String
    let key: String
    let value: String
}

struct MissionControlSpacesDiagnostic: Equatable {
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

struct StatusItemSuppressionInput: Equatable {
    let isVisibleFlag: Bool?
    let windowFrame: CGRect?
    let screenFrame: CGRect?
}

struct HiddenCollapsedSeparatorHealthInput: Equatable {
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
              windowFrame.height > 0
        else {
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
        // In the hidden state the divider is parked off-screen (length 10000), so this
        // check governs STRUCTURAL validity only — that the items exist, are visible,
        // and are ordered correctly — NOT positional drift.
        //
        // Gating structural validity on positional drift (the old
        // !shouldRecoverStartupPositions + near-Control-Center/persisted-intent checks)
        // made startupItemsValid flap false whenever the divider drifted while hidden.
        // That triggered the recovery loop, which CANNOT correct the position while
        // hidden — so it churned (24+ attempts, autosave-version bumping; this is #160)
        // and never resolved, and it blocked the customer-UI receipt. Recovery wasn't
        // fixing the drift anyway, so gating on it only produced churn. Positional drift
        // is corrected when the geometry is reliable again (on un-hide / shown state),
        // where the restore mechanisms actually work.
        //
        // Genuine STRUCTURAL failures are still caught: a main item macOS never placed
        // (#157, default window y=-22) fails `mainWindowValid` (validateItemPosition
        // already guarantees a valid on-screen menu-bar frame); a missing or misordered
        // separator fails the visibility / `separatorX < mainX` invariants.
        guard input.hidingState == .hidden else { return false }
        guard input.mainWindowValid, input.separatorVisible == true else { return false }
        guard let separatorX = input.separatorX, let mainX = input.mainX, separatorX < mainX else { return false }
        return true
    }

    nonisolated static func persistedMainDistanceFromRight() -> CGFloat? {
        let persisted = StatusBarPositionDefaultsStore.resolvedPreferredPosition(
            forAutosaveName: StatusBarController.mainAutosaveName
        )
        guard StatusBarPositionStore.isPixelLikePosition(persisted), let persisted else { return nil }
        return CGFloat(persisted)
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
