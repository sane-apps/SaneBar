import Foundation
import os.log

struct SearchMenuBarZoneClassificationContext {
    let positions: (separatorX: CGFloat, alwaysHiddenSeparatorX: CGFloat?)?
    let allowEstimatedFallback: Bool
    let promotePinnedAlwaysHidden: Bool
    let screenFrame: CGRect?
    let hidingState: HidingState
    let hasAlwaysHiddenSeparator: Bool
    let pinnedIds: Set<String>
    let pinnedApps: [RunningApp]
    let logger: Logger
}

enum SearchMenuBarZoneClassifier {
    static func classifyItems(
        _ items: [AccessibilityService.MenuBarItemPosition],
        context: SearchMenuBarZoneClassificationContext
    ) -> SearchClassifiedApps {
        let zonedItems = zonedMenuBarItems(from: items)
        if zonedItems.count != items.count {
            context.logger.info(
                "classifyItems: filtered \(items.count - zonedItems.count, privacy: .public) coarse fallback item(s) from zoned views"
            )
        }

        if let positions = context.positions {
            return classifyWithSeparator(zonedItems, positions: positions, context: context)
        }

        guard context.allowEstimatedFallback else {
            context.logger.warning("classifyItems: separator geometry unavailable; strict classification failed closed")
            return SearchClassifiedApps(visible: [], hidden: [], alwaysHidden: [])
        }

        context.logger.warning("classifyItems: separator geometry unavailable; using read-only screen fallback")
        return classifyWithScreenFallback(zonedItems, context: context)
    }

    static func zonedMenuBarItems(
        from items: [AccessibilityService.MenuBarItemPosition]
    ) -> [AccessibilityService.MenuBarItemPosition] {
        let actionItems = items.filter { !SearchServiceSupport.isCompatibilityLimitedMenuBarActionItem($0.app) }
        let preciseBundleIds = Set(
            actionItems
                .filter { $0.app.hasPreciseMenuBarIdentity }
                .map(\.app.bundleId)
        )

        let filtered = actionItems.filter { item in
            item.app.hasPreciseMenuBarIdentity || !preciseBundleIds.contains(item.app.bundleId)
        }

        var kept: [AccessibilityService.MenuBarItemPosition] = []
        var aliasBuckets: [String: [AccessibilityService.MenuBarItemPosition]] = [:]

        for item in filtered {
            if let aliasKey = SearchServiceSupport.helperHostedAliasDisplayKey(for: item.app) {
                aliasBuckets[aliasKey, default: []].append(item)
            } else {
                kept.append(item)
            }
        }

        for bucket in aliasBuckets.values {
            guard let bestApp = SearchServiceSupport.bestHelperHostedAliasRepresentative(from: bucket.map(\.app)),
                  let bestItem = bucket.first(where: { $0.app.uniqueId == bestApp.uniqueId })
            else {
                continue
            }
            kept.append(bestItem)
        }

        return kept
    }

    private static func classifyWithSeparator(
        _ items: [AccessibilityService.MenuBarItemPosition],
        positions: (separatorX: CGFloat, alwaysHiddenSeparatorX: CGFloat?),
        context: SearchMenuBarZoneClassificationContext
    ) -> SearchClassifiedApps {
        var visible: [RunningApp] = []
        var hidden: [RunningApp] = []
        var alwaysHidden: [RunningApp] = []
        let alwaysHiddenSeparatorX = SearchService.alwaysHiddenSeparatorForClassification(
            hidingState: context.hidingState,
            alwaysHiddenSeparatorX: positions.alwaysHiddenSeparatorX
        )

        for item in items {
            let zone = classifyZone(
                itemX: item.x,
                itemWidth: item.app.width,
                separatorX: positions.separatorX,
                alwaysHiddenSeparatorX: alwaysHiddenSeparatorX
            )
            switch zone {
            case .visible: visible.append(item.app)
            case .hidden: hidden.append(item.app)
            case .alwaysHidden: alwaysHidden.append(item.app)
            }
        }

        if context.promotePinnedAlwaysHidden {
            let promoted = SearchService.promotePinnedHiddenAppsToAlwaysHidden(
                hidden: hidden,
                alwaysHidden: alwaysHidden,
                pinnedIds: context.pinnedIds,
                allApps: items.map(\.app)
            )
            let promotedCount = hidden.count - promoted.hidden.count
            hidden = promoted.hidden
            alwaysHidden = promoted.alwaysHidden
            logPromotion(promotedCount: promotedCount, positions: positions, context: context)
        }

        context.logger.debug("classifyItems: visible=\(visible.count, privacy: .public) hidden=\(hidden.count, privacy: .public) alwaysHidden=\(alwaysHidden.count, privacy: .public)")
        return SearchClassifiedApps(visible: visible, hidden: hidden, alwaysHidden: alwaysHidden)
    }

    private static func classifyWithScreenFallback(
        _ items: [AccessibilityService.MenuBarItemPosition],
        context: SearchMenuBarZoneClassificationContext
    ) -> SearchClassifiedApps {
        context.logger.debug("classifyItems: no separator, using screen-based fallback for \(items.count, privacy: .public) items")
        let allApps = items.map(\.app)
        let alwaysHidden = context.promotePinnedAlwaysHidden ? context.pinnedApps : []
        let alwaysHiddenIds = Set(alwaysHidden.map(\.id))

        let hidden: [RunningApp] = if let frame = context.screenFrame {
            items
                .filter { isOffscreen(x: $0.x, in: frame) && !alwaysHiddenIds.contains($0.app.id) }
                .map(\.app)
        } else {
            items
                .filter { $0.x < 0 && !alwaysHiddenIds.contains($0.app.id) }
                .map(\.app)
        }

        let hiddenIds = Set(hidden.map(\.id))
        let visible = allApps.filter { !alwaysHiddenIds.contains($0.id) && !hiddenIds.contains($0.id) }

        context.logger.debug("classifyItems(fallback): visible=\(visible.count, privacy: .public) hidden=\(hidden.count, privacy: .public) alwaysHidden=\(alwaysHidden.count, privacy: .public)")
        return SearchClassifiedApps(visible: visible, hidden: hidden, alwaysHidden: alwaysHidden)
    }

    static func classifyZone(
        itemX: CGFloat,
        itemWidth: CGFloat?,
        separatorX: CGFloat,
        alwaysHiddenSeparatorX: CGFloat?
    ) -> SearchService.VisibilityZone {
        let margin: CGFloat = 6

        if let alwaysHiddenSeparatorX {
            if isAlwaysHiddenZone(
                itemX: itemX,
                itemWidth: itemWidth,
                alwaysHiddenSeparatorX: alwaysHiddenSeparatorX
            ) {
                return .alwaysHidden
            }
            let midX = itemMidX(itemX: itemX, itemWidth: itemWidth)
            if midX < (separatorX - margin) {
                return .hidden
            }
            return .visible
        }

        let midX = itemMidX(itemX: itemX, itemWidth: itemWidth)
        return midX < (separatorX - margin) ? .hidden : .visible
    }

    static func isAlwaysHiddenZone(
        itemX: CGFloat,
        itemWidth: CGFloat?,
        alwaysHiddenSeparatorX: CGFloat?
    ) -> Bool {
        guard let alwaysHiddenSeparatorX,
              alwaysHiddenSeparatorX.isFinite else {
            return false
        }
        let margin: CGFloat = 6
        return itemMidX(itemX: itemX, itemWidth: itemWidth) < (alwaysHiddenSeparatorX - margin)
    }

    private static func itemMidX(itemX: CGFloat, itemWidth: CGFloat?) -> CGFloat {
        let width = max(1, itemWidth ?? 22)
        return itemX + (width / 2)
    }

    static func isOffscreen(x: CGFloat, in screenFrame: CGRect) -> Bool {
        let margin: CGFloat = 6
        return x < (screenFrame.minX - margin) || x > (screenFrame.maxX + margin)
    }

    private static func logPromotion(
        promotedCount: Int,
        positions: (separatorX: CGFloat, alwaysHiddenSeparatorX: CGFloat?),
        context: SearchMenuBarZoneClassificationContext
    ) {
        guard promotedCount > 0 else { return }
        if positions.alwaysHiddenSeparatorX == nil, context.hasAlwaysHiddenSeparator {
            context.logger.debug("classifyItems: post-pass moved \(promotedCount, privacy: .public) pinned apps to alwaysHidden (fallback)")
        } else {
            context.logger.debug("classifyItems: post-pass kept \(promotedCount, privacy: .public) pinned hidden apps in alwaysHidden")
        }
    }
}
