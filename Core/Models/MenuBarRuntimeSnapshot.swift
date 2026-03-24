import CoreGraphics
import Foundation

enum MenuBarIdentityPrecision: String, Sendable {
    case exact
    case coarse
    case unknown
}

enum MenuBarGeometryConfidence: String, Sendable {
    case live
    case cached
    case shielded
    case stale
    case missing
}

enum MenuBarVisibilityPhase: String, Sendable {
    case hidden
    case expanded
    case transitioning
}

enum MenuBarBrowsePhase: String, Sendable {
    case idle
    case open
    case activationInFlight
    case moveInProgress
}

struct MenuBarRuntimeSnapshot: Sendable {
    var identityPrecision: MenuBarIdentityPrecision
    var geometryConfidence: MenuBarGeometryConfidence
    var visibilityPhase: MenuBarVisibilityPhase
    var browsePhase: MenuBarBrowsePhase
    var startupItemsValid: Bool
    var hasAlwaysHiddenSeparator: Bool
    var hasActiveMoveTask: Bool
    var hasAnyScreens: Bool
    var separatorX: CGFloat?
    var alwaysHiddenSeparatorX: CGFloat?
    var mainX: CGFloat?
    var mainRightGap: CGFloat?
    var screenWidth: CGFloat?
    var notchRightSafeMinX: CGFloat?

    init(
        identityPrecision: MenuBarIdentityPrecision = .unknown,
        geometryConfidence: MenuBarGeometryConfidence = .missing,
        visibilityPhase: MenuBarVisibilityPhase = .expanded,
        browsePhase: MenuBarBrowsePhase = .idle,
        startupItemsValid: Bool = true,
        hasAlwaysHiddenSeparator: Bool = false,
        hasActiveMoveTask: Bool = false,
        hasAnyScreens: Bool = true,
        separatorX: CGFloat? = nil,
        alwaysHiddenSeparatorX: CGFloat? = nil,
        mainX: CGFloat? = nil,
        mainRightGap: CGFloat? = nil,
        screenWidth: CGFloat? = nil,
        notchRightSafeMinX: CGFloat? = nil
    ) {
        self.identityPrecision = identityPrecision
        self.geometryConfidence = geometryConfidence
        self.visibilityPhase = visibilityPhase
        self.browsePhase = browsePhase
        self.startupItemsValid = startupItemsValid
        self.hasAlwaysHiddenSeparator = hasAlwaysHiddenSeparator
        self.hasActiveMoveTask = hasActiveMoveTask
        self.hasAnyScreens = hasAnyScreens
        self.separatorX = separatorX
        self.alwaysHiddenSeparatorX = alwaysHiddenSeparatorX
        self.mainX = mainX
        self.mainRightGap = mainRightGap
        self.screenWidth = screenWidth
        self.notchRightSafeMinX = notchRightSafeMinX
    }
}
