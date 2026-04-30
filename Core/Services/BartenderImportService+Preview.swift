import Foundation

extension BartenderImportService {
    private struct PreviewResolution {
        var resolved: [String]
        var missing: [String]
        var skipped: [String]
    }

    static func previewImport(from url: URL) async throws -> SaneBarImportPreviewPlan {
        let data = try Data(contentsOf: url)
        let (profile, root) = try parseProfile(from: data)
        let context = await buildResolutionContext()
        return previewPlan(
            profile: profile,
            root: root,
            fileName: url.lastPathComponent,
            context: context
        )
    }

    static func previewPlan(
        profile: Profile,
        root: [String: Any],
        fileName: String,
        context: ResolutionContext
    ) -> SaneBarImportPreviewPlan {
        let hide = profile.hide.compactMap(parseItem)
        let show = profile.show.compactMap(parseItem)
        let alwaysHide = profile.alwaysHide.compactMap(parseItem)
        let uniqueShow = uniqueParsedItems(show)
        let uniqueHide = uniqueParsedItems(hide)
        let uniqueAlwaysHide = uniqueParsedItems(alwaysHide)
        let specialAllOtherHide = uniqueHide.contains(where: isAllOtherItemsToken)
        let explicitHide = uniqueHide.filter { !isAllOtherItemsToken($0) }
        let allOtherHideItems = specialAllOtherHide
            ? resolvedAllOtherItems(context: context, preservedRawItems: uniqueShow)
            : []

        let showPreview = previewResolvedItems(uniqueShow, context: context)
        let hidePreview = previewResolvedItems(explicitHide, context: context)
        let alwaysHidePreview = previewResolvedItems(uniqueAlwaysHide, context: context)
        let behavioralSettings = behavioralSettingDescriptions(from: root)

        return SaneBarImportPreviewPlan(
            sourceKind: .bartender,
            fileName: fileName,
            showItemIds: showPreview.resolved,
            hideItemIds: sortedUnique(allOtherHideItems.map(storedRuleItemId) + hidePreview.resolved),
            alwaysHideItemIds: alwaysHidePreview.resolved,
            hideAllOtherItems: specialAllOtherHide,
            missingItemIds: sortedUnique(showPreview.missing + hidePreview.missing + alwaysHidePreview.missing),
            skippedItemIds: sortedUnique(showPreview.skipped + hidePreview.skipped + alwaysHidePreview.skipped),
            behavioralSettings: behavioralSettings
        )
    }

    private static func behavioralSettingDescriptions(from root: [String: Any]) -> [String] {
        var descriptions: [String] = []

        if let delay = root["MouseExitDelay"] as? Double, delay >= 0.05, delay <= 1.0 {
            descriptions.append("Hover delay: \(String(format: "%.1f", delay))s")
        }
        if let showOnDrag = root["ShowAllItemsWhenDragging"] as? Bool {
            descriptions.append("Show on drag: \(showOnDrag ? "on" : "off")")
        }
        if let hideWhenShowing = root["HideItemsWhenShowingOthers"] as? Bool {
            descriptions.append("Rehide on app change: \(hideWhenShowing ? "on" : "off")")
        }
        if let launchAtLogin = root["launchAtLogin.isEnabled"] as? Bool, launchAtLogin {
            descriptions.append("Launch at login: on")
        }

        return descriptions
    }

    private static func previewResolvedItems(
        _ items: [ParsedItem],
        context: ResolutionContext
    ) -> PreviewResolution {
        var resolved: [String] = []
        var missing: [String] = []
        var skipped: [String] = []

        for item in items {
            if isAllOtherItemsToken(item) {
                continue
            }
            if isUnsupportedAllOtherBundle(item.raw) {
                skipped.append(item.raw)
                continue
            }

            var summary = ImportSummary()
            if let match = resolveItem(item, context: context, summary: &summary) {
                resolved.append(storedRuleItemId(match))
            } else if summary.skippedNotRunning > 0 {
                missing.append(item.raw)
            } else {
                skipped.append(item.raw)
            }
        }

        return PreviewResolution(
            resolved: sortedUnique(resolved),
            missing: sortedUnique(missing),
            skipped: sortedUnique(skipped)
        )
    }

    private static func uniqueParsedItems(_ items: [ParsedItem]) -> [ParsedItem] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.raw).inserted }
    }
}
