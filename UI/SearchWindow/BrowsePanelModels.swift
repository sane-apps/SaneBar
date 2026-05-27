import Foundation
import CoreGraphics

enum BrowsePanelMode: String, CaseIterable, Identifiable {
    case hidden
    case visible
    case alwaysHidden
    case all

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .hidden: "Hidden"
        case .visible: "Visible"
        case .alwaysHidden: "Always Hidden"
        case .all: "All"
        }
    }
}

enum BrowseAppZone {
    case visible
    case hidden
    case alwaysHidden
}

enum BrowsePanelRestrictedAction {
    case rightClick
    case zoneMove
    case perIconHotkey

    static func upsellFeature(for action: BrowsePanelRestrictedAction, isPro: Bool) -> ProFeature? {
        guard !isPro else { return nil }

        switch action {
        case .rightClick:
            return .rightClickFromPanels
        case .zoneMove:
            return .zoneMoves
        case .perIconHotkey:
            return .perIconHotkeys
        }
    }
}

enum BrowsePanelDropPayload {
    static func bundleID(from payload: String) -> String {
        guard let split = payload.range(of: "::") else { return payload }
        return String(payload[..<split.lowerBound])
    }
}

enum BrowsePanelZoneClassifier {
    static func separatorBoundaryForAllTab(
        separatorRightEdgeX: CGFloat?,
        separatorOriginX: CGFloat?
    ) -> CGFloat? {
        if let separatorRightEdgeX, separatorRightEdgeX > 0 {
            return separatorRightEdgeX
        }
        if let separatorOriginX, separatorOriginX > 0 {
            return separatorOriginX
        }
        return nil
    }

    static func classifyAllTabZone(
        midX: CGFloat,
        separatorBoundaryX: CGFloat?,
        alwaysHiddenSeparatorX: CGFloat?,
        margin: CGFloat = 6
    ) -> BrowseAppZone {
        guard let separatorBoundaryX else { return .visible }

        if let alwaysHiddenSeparatorX,
           alwaysHiddenSeparatorX > 0,
           alwaysHiddenSeparatorX < separatorBoundaryX,
           midX < (alwaysHiddenSeparatorX - margin) {
            return .alwaysHidden
        }

        return midX < (separatorBoundaryX - margin) ? .hidden : .visible
    }

    static func alwaysHiddenBoundaryForAllTab(
        separatorBoundaryX: CGFloat?,
        alwaysHiddenBoundaryX: CGFloat?,
        alwaysHiddenOriginX: CGFloat?
    ) -> CGFloat? {
        guard let separatorBoundaryX else { return nil }

        let preferredBoundary = SearchService.normalizedAlwaysHiddenBoundary(
            alwaysHiddenBoundaryX,
            separatorX: separatorBoundaryX
        )
        if preferredBoundary != nil {
            return preferredBoundary
        }

        guard let alwaysHiddenOriginX, alwaysHiddenOriginX > 0 else { return nil }
        return SearchService.normalizedAlwaysHiddenBoundary(
            alwaysHiddenOriginX + 20,
            separatorX: separatorBoundaryX
        )
    }
}

enum BrowsePanelDropResolver {
    static func sourceForDropPayload(
        _ sourceID: String,
        classified: SearchClassifiedApps,
        filteredApps: [RunningApp] = [],
        mode: BrowsePanelMode? = nil,
        zoneForAllMode: ((RunningApp) -> BrowseAppZone)? = nil
    ) -> (app: RunningApp, zone: BrowseAppZone)? {
        if let app = classified.visible.first(where: { $0.uniqueId == sourceID }) {
            return (app, .visible)
        }
        if let app = classified.hidden.first(where: { $0.uniqueId == sourceID }) {
            return (app, .hidden)
        }
        if let app = classified.alwaysHidden.first(where: { $0.uniqueId == sourceID }) {
            return (app, .alwaysHidden)
        }
        guard let app = filteredApps.first(where: { $0.uniqueId == sourceID }),
              let mode else {
            return nil
        }

        switch mode {
        case .visible:
            return (app, .visible)
        case .hidden:
            return (app, .hidden)
        case .alwaysHidden:
            return (app, .alwaysHidden)
        case .all:
            if let zone = zoneForAllMode?(app) {
                return (app, zone)
            }
            return (app, .visible)
        }
    }
}

struct BrowseVisibleLaneCrowdingEvent {
    let bundleID: String
    let menuExtraID: String?
    let statusItemIndex: Int?
    let separatorRightEdgeX: CGFloat
    let visibleBoundaryX: CGFloat
}

enum BrowseVisibleLaneCrowdingAdvisor {
    static let versionKey = "MenuBarSearchView.crowdedVisibleHintVersion"
    static let slackThreshold: CGFloat = 18
    static let occupancyThreshold: CGFloat = 0.88

    static func shouldSuggestSecondMenuBar(
        visibleApps: [RunningApp],
        movedApp: RunningApp,
        separatorRightEdgeX: CGFloat?,
        mainLeftEdgeX: CGFloat?,
        slackThreshold: CGFloat = Self.slackThreshold,
        occupancyThreshold: CGFloat = Self.occupancyThreshold
    ) -> Bool {
        guard let separatorRightEdgeX,
              let mainLeftEdgeX,
              separatorRightEdgeX > 0,
              mainLeftEdgeX > separatorRightEdgeX
        else {
            return false
        }

        let laneWidth = mainLeftEdgeX - separatorRightEdgeX
        guard laneWidth > 0 else { return false }

        var visibleByID: [String: RunningApp] = [:]
        for app in visibleApps where !app.isUnmovableSystemItem {
            visibleByID[app.uniqueId] = app
        }
        visibleByID[movedApp.uniqueId] = movedApp

        let projectedWidth = visibleByID.values.reduce(CGFloat.zero) { partial, app in
            partial + approximateVisibleLaneWidth(for: app)
        }

        if projectedWidth >= laneWidth - slackThreshold {
            return true
        }

        return (projectedWidth / laneWidth) >= occupancyThreshold
    }

    static func approximateVisibleLaneWidth(for app: RunningApp) -> CGFloat {
        max(app.width ?? 22, 18) + 4
    }

    static func event(from notification: Notification) -> BrowseVisibleLaneCrowdingEvent? {
        guard let userInfo = notification.userInfo,
              let bundleID = userInfo[MenuBarVisibleLaneCrowdingHint.bundleIDKey] as? String,
              let separatorRightEdgeRaw = userInfo[MenuBarVisibleLaneCrowdingHint.separatorRightEdgeKey] as? Double,
              let visibleBoundaryRaw = userInfo[MenuBarVisibleLaneCrowdingHint.visibleBoundaryKey] as? Double
        else {
            return nil
        }

        return BrowseVisibleLaneCrowdingEvent(
            bundleID: bundleID,
            menuExtraID: userInfo[MenuBarVisibleLaneCrowdingHint.menuExtraIDKey] as? String,
            statusItemIndex: userInfo[MenuBarVisibleLaneCrowdingHint.statusItemIndexKey] as? Int,
            separatorRightEdgeX: CGFloat(separatorRightEdgeRaw),
            visibleBoundaryX: CGFloat(visibleBoundaryRaw)
        )
    }

    static func matches(_ app: RunningApp, event: BrowseVisibleLaneCrowdingEvent) -> Bool {
        guard app.bundleId == event.bundleID else { return false }
        if let menuExtraID = event.menuExtraID {
            return app.menuExtraIdentifier == menuExtraID
        }
        if let statusItemIndex = event.statusItemIndex {
            return app.statusItemIndex == statusItemIndex
        }
        return app.menuExtraIdentifier == nil && app.statusItemIndex == nil
    }

    static func versionToken(bundle: Bundle = .main) -> String {
        let shortVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"
        let build = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(shortVersion)-\(build)"
    }

    static func shouldShowReminder(
        defaults: UserDefaults = .standard,
        bundle: Bundle = .main
    ) -> Bool {
        let currentVersion = versionToken(bundle: bundle)
        let lastShownVersion = defaults.string(forKey: versionKey)
        return lastShownVersion != currentVersion
    }
}
