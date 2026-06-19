import CoreGraphics
import Foundation

enum MenuBarIdentityPrecision: String {
    case exact
    case coarse
    case unknown
}

enum MenuBarGeometryConfidence: String {
    case live
    case cached
    case shielded
    case stale
    case missing
}

enum MenuBarStructuralState: String {
    case ready
    case missingItems
    case invisibleItems
    case unattachedWindows
}

enum MenuBarAnchorSource: String {
    case live
    case cached
    case estimated
    case missing
}

extension MenuBarAnchorSource {
    var isTrustworthySeparatorAnchor: Bool {
        switch self {
        case .live:
            true
        case .cached, .estimated, .missing:
            false
        }
    }

    var isTrustworthyMainAnchor: Bool {
        switch self {
        case .live:
            true
        case .cached, .estimated, .missing:
            false
        }
    }
}

enum MenuBarBootstrapPhase: String {
    case steady
    case awaitingAnchor
}

enum MenuBarVisibilityPhase: String {
    case hidden
    case expanded
    case transitioning
}

enum MenuBarBrowsePhase: String {
    case idle
    case open
    case activationInFlight
    case moveInProgress
}

enum MenuBarVisibilityIntentMode {
    case auditOnly
    case repairWithPhysicalMoves
}

enum MenuBarPhysicalMoveOrigin {
    case explicitUserAction
    case appleScriptUserAction
    case systemWakeRecovery
}

struct MenuBarRuntimeSnapshot {
    var identityPrecision: MenuBarIdentityPrecision
    var geometryConfidence: MenuBarGeometryConfidence
    var structuralState: MenuBarStructuralState
    var separatorAnchorSource: MenuBarAnchorSource
    var mainAnchorSource: MenuBarAnchorSource
    var bootstrapPhase: MenuBarBootstrapPhase
    var visibilityPhase: MenuBarVisibilityPhase
    var browsePhase: MenuBarBrowsePhase
    var startupItemsValid: Bool
    var hasAlwaysHiddenSeparator: Bool
    var hasActiveMoveTask: Bool
    var hasAnyScreens: Bool
    var mainItemVisible: Bool?
    var separatorItemVisible: Bool?
    var alwaysHiddenSeparatorVisible: Bool?
    var likelySystemSuppressedStatusItems: Bool
    var separatorX: CGFloat?
    /// Always Hidden separator boundary/right edge. This is not the origin.
    var alwaysHiddenSeparatorX: CGFloat?
    var mainX: CGFloat?
    var mainRightGap: CGFloat?
    var screenWidth: CGFloat?
    var notchRightSafeMinX: CGFloat?
    /// SaneBar's own persisted preferred main position, as distance from the
    /// screen's right edge. Used to judge soft drift against user intent.
    var persistedMainDistanceFromRight: CGFloat?

    init(
        identityPrecision: MenuBarIdentityPrecision = .unknown,
        geometryConfidence: MenuBarGeometryConfidence = .missing,
        structuralState: MenuBarStructuralState? = nil,
        separatorAnchorSource: MenuBarAnchorSource = .missing,
        mainAnchorSource: MenuBarAnchorSource = .missing,
        bootstrapPhase: MenuBarBootstrapPhase = .steady,
        visibilityPhase: MenuBarVisibilityPhase = .expanded,
        browsePhase: MenuBarBrowsePhase = .idle,
        startupItemsValid: Bool = true,
        hasAlwaysHiddenSeparator: Bool = false,
        hasActiveMoveTask: Bool = false,
        hasAnyScreens: Bool = true,
        mainItemVisible: Bool? = nil,
        separatorItemVisible: Bool? = nil,
        alwaysHiddenSeparatorVisible: Bool? = nil,
        likelySystemSuppressedStatusItems: Bool = false,
        separatorX: CGFloat? = nil,
        alwaysHiddenSeparatorX: CGFloat? = nil,
        mainX: CGFloat? = nil,
        mainRightGap: CGFloat? = nil,
        screenWidth: CGFloat? = nil,
        notchRightSafeMinX: CGFloat? = nil,
        persistedMainDistanceFromRight: CGFloat? = nil
    ) {
        self.identityPrecision = identityPrecision
        let inferredStructuralState = structuralState ?? {
            if mainItemVisible == false || separatorItemVisible == false {
                return .invisibleItems
            }
            if !startupItemsValid {
                return .unattachedWindows
            }
            return .ready
        }()

        self.geometryConfidence = geometryConfidence
        self.structuralState = inferredStructuralState
        self.separatorAnchorSource = separatorAnchorSource
        self.mainAnchorSource = mainAnchorSource
        self.bootstrapPhase = bootstrapPhase
        self.visibilityPhase = visibilityPhase
        self.browsePhase = browsePhase
        self.startupItemsValid = startupItemsValid
        self.hasAlwaysHiddenSeparator = hasAlwaysHiddenSeparator
        self.hasActiveMoveTask = hasActiveMoveTask
        self.hasAnyScreens = hasAnyScreens
        self.mainItemVisible = mainItemVisible
        self.separatorItemVisible = separatorItemVisible
        self.alwaysHiddenSeparatorVisible = alwaysHiddenSeparatorVisible
        self.likelySystemSuppressedStatusItems = likelySystemSuppressedStatusItems
        self.separatorX = separatorX
        self.alwaysHiddenSeparatorX = alwaysHiddenSeparatorX
        self.mainX = mainX
        self.mainRightGap = mainRightGap
        self.screenWidth = screenWidth
        self.notchRightSafeMinX = notchRightSafeMinX
        self.persistedMainDistanceFromRight = persistedMainDistanceFromRight
    }

    var hasTrustworthyBootstrapAnchors: Bool {
        guard structuralState == .ready else { return false }
        guard separatorAnchorSource.isTrustworthySeparatorAnchor else { return false }
        return mainAnchorSource.isTrustworthyMainAnchor
    }

    var hasLiveCoreAnchors: Bool {
        hasTrustworthyBootstrapAnchors
    }
}
