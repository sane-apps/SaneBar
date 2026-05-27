import Foundation

enum MenuBarMoveExpectedZone {
    case visible
    case hidden
    case alwaysHidden
}

enum MenuBarMoveVerifier {
    static func matchesTarget(
        app: RunningApp,
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?
    ) -> Bool {
        guard app.bundleId == bundleID else { return false }
        if let menuExtraId, app.menuExtraIdentifier != menuExtraId { return false }
        if let statusItemIndex, app.statusItemIndex != statusItemIndex { return false }
        return true
    }

    static func classifiedMatchesTarget(
        classified: SearchClassifiedApps,
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?,
        expectedZone: MenuBarMoveExpectedZone
    ) -> Bool {
        let matcher: (RunningApp) -> Bool = { app in
            matchesTarget(
                app: app,
                bundleID: bundleID,
                menuExtraId: menuExtraId,
                statusItemIndex: statusItemIndex
            )
        }

        return switch expectedZone {
        case .visible:
            classified.visible.contains(where: matcher)
        case .hidden:
            classified.hidden.contains(where: matcher)
        case .alwaysHidden:
            classified.alwaysHidden.contains(where: matcher)
        }
    }

    @MainActor
    static func owners(bundleID: String) async -> [RunningApp] {
        let accessibilityService = AccessibilityService.shared

        let cachedOwners = accessibilityService.cachedMenuBarItemOwners().filter { $0.bundleId == bundleID }
        if !cachedOwners.isEmpty {
            return cachedOwners
        }

        let cachedPositionedOwners = accessibilityService.cachedMenuBarItemsWithPositions()
            .map(\.app)
            .filter { $0.bundleId == bundleID }
        if !cachedPositionedOwners.isEmpty {
            return cachedPositionedOwners
        }

        let refreshedOwners = await accessibilityService.refreshMenuBarItemOwners()
        return refreshedOwners.filter { $0.bundleId == bundleID }
    }

    @MainActor
    static func verifyByClassifiedZone(
        bundleID: String,
        menuExtraId: String?,
        statusItemIndex: Int?,
        expectedZone: MenuBarMoveExpectedZone,
        attempts: Int = 4
    ) async -> Bool {
        for attempt in 1 ... attempts {
            let owners = await owners(bundleID: bundleID)
            if !owners.isEmpty {
                let scopedItems = await AccessibilityService.shared.scopedMenuBarItemsWithPositions(for: owners)
                if !scopedItems.isEmpty {
                    let classified = await MainActor.run {
                        SearchService.shared.classifyItemsForMoveVerification(scopedItems)
                    }
                    if classifiedMatchesTarget(
                        classified: classified,
                        bundleID: bundleID,
                        menuExtraId: menuExtraId,
                        statusItemIndex: statusItemIndex,
                        expectedZone: expectedZone
                    ) {
                        return true
                    }
                }
            }

            if attempt == attempts {
                let classified = await SearchService.shared.refreshClassifiedApps()
                let physicalClassified = await MainActor.run {
                    SearchService.shared.classifyAppsForMoveVerification(classified)
                }
                if classifiedMatchesTarget(
                    classified: physicalClassified,
                    bundleID: bundleID,
                    menuExtraId: menuExtraId,
                    statusItemIndex: statusItemIndex,
                    expectedZone: expectedZone
                ) {
                    return true
                }
            }

            if attempt < attempts {
                try? await Task.sleep(for: .milliseconds(150))
            }
        }

        return false
    }
}
