import AppKit

extension AccessibilityService {
    typealias ScannedStatusItem = AccessibilityMenuBarScanningService.ScannedStatusItem
    typealias WindowBackedStatusItem = AccessibilityMenuBarScanningService.WindowBackedStatusItem

    private var scanningService: AccessibilityMenuBarScanningService {
        AccessibilityMenuBarScanningService(accessibilityService: self)
    }

    internal nonisolated static func resolvedBundleIdentifier(for app: NSRunningApplication) -> String? {
        AccessibilityMenuBarScanningService.resolvedBundleIdentifier(for: app)
    }

    internal nonisolated static func bundleIdentifierFallback(fromAXIdentifier axIdentifier: String?) -> String? {
        AccessibilityMenuBarScanningService.bundleIdentifierFallback(fromAXIdentifier: axIdentifier)
    }

    internal nonisolated static func resolvedScannedMenuExtraIdentifier(
        ownerBundleId: String,
        axIdentifier: String?,
        rawTitle: String?,
        rawDescription: String?,
        width: CGFloat
    ) -> String? {
        AccessibilityMenuBarScanningService.resolvedScannedMenuExtraIdentifier(
            ownerBundleId: ownerBundleId,
            axIdentifier: axIdentifier,
            rawTitle: rawTitle,
            rawDescription: rawDescription,
            width: width
        )
    }

    internal nonisolated static func scannedStatusItemIndex(
        itemCount: Int,
        itemIndex: Int,
        axIdentifier: String?
    ) -> Int? {
        AccessibilityMenuBarScanningService.scannedStatusItemIndex(
            itemCount: itemCount,
            itemIndex: itemIndex,
            axIdentifier: axIdentifier
        )
    }

    func listMenuBarItemOwners() async -> [RunningApp] {
        await scanningService.listMenuBarItemOwners()
    }

    func listMenuBarItemsWithPositions() async -> [MenuBarItemPosition] {
        await scanningService.listMenuBarItemsWithPositions()
    }

    func listKnownMenuBarItemsWithPositions(owners: [RunningApp]) async -> [MenuBarItemPosition] {
        await scanningService.listKnownMenuBarItemsWithPositions(owners: owners)
    }

    func scopedMenuBarItemsWithPositions(for owners: [RunningApp]) async -> [MenuBarItemPosition] {
        await scanningService.scopedMenuBarItemsWithPositions(for: owners)
    }

    internal nonisolated static func windowBackedMenuBarItems(candidatePIDs: Set<pid_t>) -> [WindowBackedStatusItem] {
        AccessibilityMenuBarWindowFallbackPolicy.windowBackedMenuBarItems(candidatePIDs: candidatePIDs)
    }

    internal nonisolated static func topBarHostPIDs(candidatePIDs: Set<pid_t>) -> Set<pid_t> {
        AccessibilityMenuBarWindowFallbackPolicy.topBarHostPIDs(candidatePIDs: candidatePIDs)
    }

    internal nonisolated static func mergeSystemWideMenuBarItem(
        _ item: MenuBarItemPosition,
        into appPositions: inout [String: MenuBarItemPosition]
    ) {
        AccessibilityMenuBarWindowFallbackPolicy.mergeSystemWideMenuBarItem(item, into: &appPositions)
    }

    internal nonisolated static func systemWideFallbackCandidatePIDs(
        axResolvedPIDs: Set<pid_t>,
        knownNoExtrasPIDs: Set<pid_t>,
        windowBackedPIDs: Set<pid_t>,
        topBarHostPIDs: Set<pid_t>
    ) -> Set<pid_t> {
        AccessibilityMenuBarWindowFallbackPolicy.systemWideFallbackCandidatePIDs(
            axResolvedPIDs: axResolvedPIDs,
            knownNoExtrasPIDs: knownNoExtrasPIDs,
            windowBackedPIDs: windowBackedPIDs,
            topBarHostPIDs: topBarHostPIDs
        )
    }

    internal nonisolated static func windowBackedMenuBarItems(
        fromWindowInfos infos: [[String: Any]],
        candidatePIDs: Set<pid_t>
    ) -> [WindowBackedStatusItem] {
        AccessibilityMenuBarWindowFallbackPolicy.windowBackedMenuBarItems(
            fromWindowInfos: infos,
            candidatePIDs: candidatePIDs
        )
    }

    internal nonisolated static func representativeWindowBackedFramesByPID(
        _ items: [WindowBackedStatusItem]
    ) -> [pid_t: CGRect] {
        AccessibilityMenuBarWindowFallbackPolicy.representativeWindowBackedFramesByPID(items)
    }

    internal nonisolated static func topBarHostPIDs(
        fromWindowInfos infos: [[String: Any]],
        candidatePIDs: Set<pid_t>,
        minimumWidth: CGFloat
    ) -> Set<pid_t> {
        AccessibilityMenuBarWindowFallbackPolicy.topBarHostPIDs(
            fromWindowInfos: infos,
            candidatePIDs: candidatePIDs,
            minimumWidth: minimumWidth
        )
    }

    internal nonisolated static func scanMenuBarOwnerPIDs(candidatePIDs: [pid_t]) async -> [pid_t] {
        await AccessibilityMenuBarWindowFallbackPolicy.scanMenuBarOwnerPIDs(candidatePIDs: candidatePIDs)
    }

    internal nonisolated static func shouldAllowThirdPartyTopBarFallback(bundleID: String) -> Bool {
        AccessibilityMenuBarWindowFallbackPolicy.shouldAllowThirdPartyTopBarFallback(bundleID: bundleID)
    }

    internal nonisolated static func shouldIncludeThirdPartyTopBarOwner(
        bundleID: String,
        fallbackItemsCount: Int
    ) -> Bool {
        AccessibilityMenuBarWindowFallbackPolicy.shouldIncludeThirdPartyTopBarOwner(
            bundleID: bundleID,
            fallbackItemsCount: fallbackItemsCount
        )
    }

    internal nonisolated static func scanMenuBarAppMinXPositions(candidatePIDs: [pid_t]) async -> [(pid: pid_t, x: CGFloat)] {
        await AccessibilityMenuBarWindowFallbackPolicy.scanMenuBarAppMinXPositions(candidatePIDs: candidatePIDs)
    }
}
