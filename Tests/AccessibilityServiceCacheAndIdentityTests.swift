import ApplicationServices
import Testing
import AppKit
@testable import SaneBar

@Suite("AccessibilityService — Cache and Identity")
struct AccessibilityServiceCacheAndIdentityTests {

    // MARK: - Permission Tests

    @Test("isTrusted matches the system Accessibility trust status")
    @MainActor
    func testIsTrustedMatchesSystemStatus() {
        let service = AccessibilityService.shared
        #expect(service.isTrusted == AXIsProcessTrusted())
    }

    // MARK: - clickMenuBarItem Tests

    @Test("clickMenuBarItem returns false for non-existent bundle ID")
    @MainActor
    func testClickMenuBarItemNonExistentApp() {
        let service = AccessibilityService.shared
        // This should return false because no app with this bundle ID exists
        let result = service.clickMenuBarItem(for: "com.nonexistent.app.that.does.not.exist")
        #expect(result == false)
    }

    @Test("clickMenuBarItem returns false for empty bundle ID")
    @MainActor
    func testClickMenuBarItemEmptyBundleID() {
        let service = AccessibilityService.shared
        let result = service.clickMenuBarItem(for: "")
        #expect(result == false)
    }

    @Test("System Settings accessibility URL is valid")
    func testAccessibilitySettingsURLIsValid() {
        // REGRESSION: "Open System Settings" button wasn't opening anything
        // because it called requestAccessibility() instead of opening the URL
        let urlString = AccessibilityService.accessibilitySettingsURLString
        let url = URL(string: urlString)

        #expect(url != nil, "Accessibility Settings URL must be valid")
        #expect(url?.scheme == "x-apple.systempreferences", "URL scheme must be x-apple.systempreferences")
    }

    @Test("Cache warmup delays prioritize launch immediacy and reveal settling")
    func testCacheWarmupDelays() {
        #expect(AccessibilityService.cacheWarmupDelay(for: .launch) == 0)
        #expect(AccessibilityService.cacheWarmupDelay(for: .reveal) > 0)
        #expect(AccessibilityService.cacheWarmupDelay(for: .structuralChange) >= AccessibilityService.cacheWarmupDelay(for: .reveal))
        #expect(AccessibilityService.cacheWarmupDelay(for: .conceal) <= AccessibilityService.cacheWarmupDelay(for: .structuralChange))
    }

    @Test("Geometry-only warmups prefer known-owner refreshes")
    func testGeometryWarmupsUseKnownOwnerRefresh() {
        #expect(!AccessibilityService.cacheWarmupUsesKnownOwnerRefresh(for: .launch))
        #expect(AccessibilityService.cacheWarmupUsesKnownOwnerRefresh(for: .reveal))
        #expect(AccessibilityService.cacheWarmupUsesKnownOwnerRefresh(for: .conceal))
        #expect(AccessibilityService.cacheWarmupUsesKnownOwnerRefresh(for: .structuralChange))
    }

    @Test("Deferred cache warmup keeps the strongest pending reason")
    func testMergedDeferredCacheWarmupReason() {
        #expect(
            AccessibilityService.mergedDeferredCacheWarmupReason(
                current: .reveal,
                new: .structuralChange
            ) == .structuralChange
        )
        #expect(
            AccessibilityService.mergedDeferredCacheWarmupReason(
                current: .structuralChange,
                new: .conceal
            ) == .structuralChange
        )
        #expect(
            AccessibilityService.mergedDeferredCacheWarmupReason(
                current: nil,
                new: .launch
            ) == .launch
        )
    }

    @Test("Position-only cache invalidation keeps owner cache warm")
    @MainActor
    func testInvalidateMenuBarItemPositionsCacheKeepsOwnersWarm() {
        let service = AccessibilityService.shared
        let ownersTime = Date()
        let itemsTime = ownersTime.addingTimeInterval(-1)

        service.menuBarOwnersCacheTime = ownersTime
        service.menuBarItemCacheTime = itemsTime

        service.invalidateMenuBarItemPositionsCache()

        #expect(service.menuBarOwnersCacheTime == ownersTime)
        #expect(service.menuBarItemCacheTime == .distantPast)
    }

    @Test("Warmup suppression can drop deferred warmup when caller already refreshed")
    @MainActor
    func testEndMenuBarCacheWarmupSuppressionCanSkipDeferredWarmup() {
        let service = AccessibilityService.shared
        service.menuBarCacheWarmupTask?.cancel()
        service.menuBarCacheWarmupTask = nil
        service.menuBarCacheWarmupSuppressionDepth = 0
        service.deferredMenuBarCacheWarmupReason = nil

        service.beginMenuBarCacheWarmupSuppression()
        service.deferredMenuBarCacheWarmupReason = .structuralChange

        service.endMenuBarCacheWarmupSuppression(scheduleDeferredWarmup: false)

        #expect(service.menuBarCacheWarmupSuppressionDepth == 0)
        #expect(service.deferredMenuBarCacheWarmupReason == nil)
        #expect(service.menuBarCacheWarmupTask == nil)
    }

    @Test("Manual move cache preservation keeps refreshed positions fresh")
    @MainActor
    func testManualMoveCachePreservationKeepsPositionsFresh() {
        let service = AccessibilityService.shared
        service.menuBarItemCache = [
            AccessibilityService.MenuBarItemPosition(
                app: RunningApp.menuExtraItem(
                    ownerBundleId: "com.apple.systemuiserver",
                    name: "Siri",
                    identifier: "com.apple.menuextra.siri",
                    xPosition: 1480,
                    width: 34
                ),
                x: 1480,
                width: 34
            )
        ]
        service.menuBarItemCacheTime = .distantPast
        service.deferredMenuBarCacheWarmupReason = .conceal

        service.preserveFreshMenuBarItemPositionsAfterManualMove()

        #expect(service.menuBarItemCache.count == 1)
        #expect(Date().timeIntervalSince(service.menuBarItemCacheTime) < service.menuBarItemCacheValiditySeconds)
        #expect(service.deferredMenuBarCacheWarmupReason == nil)
        #expect(service.menuBarCacheWarmupTask == nil)
    }

    @Test("Known-owner position refresh accepts strong coverage")
    func testKnownOwnerPositionRefreshAcceptsStrongCoverage() {
        #expect(
            AccessibilityService.shouldAcceptKnownOwnerPositionRefresh(
                seededItemCount: 10,
                refreshedItemCount: 8
            )
        )
    }

    @Test("Known-owner position refresh rejects empty or weak coverage")
    func testKnownOwnerPositionRefreshRejectsWeakCoverage() {
        #expect(
            !AccessibilityService.shouldAcceptKnownOwnerPositionRefresh(
                seededItemCount: 10,
                refreshedItemCount: 0
            )
        )
        #expect(
            !AccessibilityService.shouldAcceptKnownOwnerPositionRefresh(
                seededItemCount: 10,
                refreshedItemCount: 6
            )
        )
    }

    @Test("Known-owner position refresh coverage handles empty seeded sets")
    func testKnownOwnerPositionRefreshCoverageHandlesEmptySeededSets() {
        #expect(
            AccessibilityService.knownOwnerPositionRefreshCoverage(
                seededItemCount: 0,
                refreshedItemCount: 3
            ) == 1
        )
        #expect(
            AccessibilityService.knownOwnerPositionRefreshCoverage(
                seededItemCount: 10,
                refreshedItemCount: 0
            ) == 0
        )
    }

    @Test("Cmd-drag step count keeps a minimum for short drags")
    func testCmdDragStepCountHasMinimum() {
        #expect(AccessibilityService.cmdDragStepCount(distance: 40) == 10)
    }

    @Test("Cmd-drag step count scales for medium drags")
    func testCmdDragStepCountScales() {
        #expect(AccessibilityService.cmdDragStepCount(distance: 264) == 12)
    }

    @Test("Cmd-drag step count caps for long drags")
    func testCmdDragStepCountHasMaximum() {
        #expect(AccessibilityService.cmdDragStepCount(distance: 600) == 14)
    }

    @Test("Preferred status item index chooses nearest X when explicit identity is missing")
    func testPreferredStatusItemIndexUsesNearestCenterX() {
        let index = AccessibilityMenuExtraFrameResolver.preferredStatusItemIndex(
            midXs: [120, 260, 410],
            preferredCenterX: 275
        )

        #expect(index == 1)
    }

    @Test("Preferred status item index falls back to first item without preferred X")
    func testPreferredStatusItemIndexFallsBackToFirst() {
        let index = AccessibilityMenuExtraFrameResolver.preferredStatusItemIndex(
            midXs: [120, 260, 410],
            preferredCenterX: nil
        )

        #expect(index == 0)
    }

    @Test("Preferred center rejects stale far-offscreen values")
    func testPreferredCenterRejectsFarOffscreenValues() {
        let center = AccessibilityMenuExtraFrameResolver.screenValidPreferredCenterX(
            -4_288,
            screenFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)]
        )

        #expect(center == nil)
    }

    @Test("Preferred center accepts left-arranged display coordinates")
    func testPreferredCenterAcceptsLeftArrangedDisplayCoordinates() {
        let center = AccessibilityMenuExtraFrameResolver.screenValidPreferredCenterX(
            -420,
            screenFrames: [
                CGRect(x: -1280, y: 0, width: 1280, height: 720),
                CGRect(x: 0, y: 0, width: 1512, height: 982)
            ]
        )

        #expect(center == -420)
    }

    @Test("Resolved status item index keeps the hinted item when it still matches the requested center")
    func testResolvedStatusItemIndexKeepsMatchingHint() {
        let index = AccessibilityMenuExtraFrameResolver.resolvedStatusItemIndex(
            midXs: [120, 260, 410],
            statusItemIndex: 1,
            preferredCenterX: 272
        )

        #expect(index == 1)
    }

    @Test("Resolved status item index falls back to nearest center when the hinted item drifts")
    func testResolvedStatusItemIndexFallsBackWhenHintDrifts() {
        let index = AccessibilityMenuExtraFrameResolver.resolvedStatusItemIndex(
            midXs: [120, 260, 410],
            statusItemIndex: 2,
            preferredCenterX: 272
        )

        #expect(index == 1)
    }

    @Test("Resolved status item index uses the hint when no preferred center is available")
    func testResolvedStatusItemIndexUsesHintWithoutPreferredCenter() {
        let index = AccessibilityMenuExtraFrameResolver.resolvedStatusItemIndex(
            midXs: [120, 260, 410],
            statusItemIndex: 2,
            preferredCenterX: nil
        )

        #expect(index == 2)
    }

    @Test("Resolved status item index ignores offscreen preferred center and keeps valid ordinal")
    func testResolvedStatusItemIndexIgnoresOffscreenPreferredCenter() {
        let index = AccessibilityMenuExtraFrameResolver.resolvedStatusItemIndex(
            midXs: [120, 260, 410],
            statusItemIndex: 2,
            preferredCenterX: -4_288,
            screenFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)]
        )

        #expect(index == 2)
    }

    @Test("Identifier miss fallback rejects offscreen preferred center")
    func testIdentifierMissFallbackRejectsOffscreenPreferredCenter() {
        let canFallback = AccessibilityMenuExtraService.shouldContinueStatusItemResolutionAfterIdentifierMiss(
            statusItemIndex: nil,
            preferredCenterX: -4_288,
            screenFrames: [CGRect(x: 0, y: 0, width: 1512, height: 982)]
        )

        #expect(canFallback == false)
    }

    @Test("Single status item without AX identifier still gets an ordinal identity")
    func testSingleUnidentifiedStatusItemGetsIndexIdentity() {
        let index = AccessibilityService.scannedStatusItemIndex(
            itemCount: 1,
            itemIndex: 0,
            axIdentifier: nil
        )

        #expect(index == 0)
    }

    @Test("Single status item with AX identifier keeps identifier-only identity")
    func testSingleIdentifiedStatusItemDoesNotNeedIndexIdentity() {
        let index = AccessibilityService.scannedStatusItemIndex(
            itemCount: 1,
            itemIndex: 0,
            axIdentifier: "com.example.menu"
        )

        #expect(index == nil)
    }

    @Test("Multiple status items with AX identifiers use identifier identity")
    func testMultipleIdentifiedStatusItemsDoNotNeedIndexIdentity() {
        let index = AccessibilityService.scannedStatusItemIndex(
            itemCount: 2,
            itemIndex: 1,
            axIdentifier: "com.example.menu"
        )

        #expect(index == nil)
    }

    @Test("Status item resolution continues after identifier miss when a live spatial hint exists")
    func testStatusItemResolutionContinuesAfterIdentifierMissWithPreferredCenterX() {
        #expect(
            AccessibilityMenuExtraService.shouldContinueStatusItemResolutionAfterIdentifierMiss(
                statusItemIndex: nil,
                preferredCenterX: 1408
            )
        )
    }

    @Test("Status item resolution stops after identifier miss when only stale ordinal remains")
    func testStatusItemResolutionStopsAfterIdentifierMissWithOnlyStatusItemIndex() {
        #expect(
            !AccessibilityMenuExtraService.shouldContinueStatusItemResolutionAfterIdentifierMiss(
                statusItemIndex: 1,
                preferredCenterX: nil
            )
        )
    }

    @Test("Status item resolution stops after identifier miss when no hints exist")
    func testStatusItemResolutionStopsAfterIdentifierMissWithoutHints() {
        #expect(
            AccessibilityMenuExtraService.shouldContinueStatusItemResolutionAfterIdentifierMiss(
                statusItemIndex: nil,
                preferredCenterX: nil
            ) == false
        )
    }

    @Test("Canonical Apple menu extra identifier falls back from visible Siri label")
    func testCanonicalMenuExtraIdentifierUsesVisibleSiriLabelFallback() {
        let identifier = AccessibilityMenuExtraService.canonicalMenuExtraIdentifier(
            ownerBundleId: "com.apple.systemuiserver",
            rawIdentifier: nil,
            rawLabel: "Siri",
            width: 24
        )

        #expect(identifier == "com.apple.menuextra.siri")
    }

    @Test("Canonical Apple menu extra identifier refuses hidden Siri label fallback")
    func testCanonicalMenuExtraIdentifierRejectsHiddenSiriLabelFallback() {
        let identifier = AccessibilityMenuExtraService.canonicalMenuExtraIdentifier(
            ownerBundleId: "com.apple.systemuiserver",
            rawIdentifier: nil,
            rawLabel: "Siri",
            width: 0
        )

        #expect(identifier == nil)
    }

    @Test("Single status item falls back to sole item after identifier miss")
    @MainActor
    func testResolvedTargetStatusItemFallsBackToSingleItemAfterIdentifierMiss() {
        let item = AXUIElementCreateApplication(getpid())

        let resolved = AccessibilityMenuExtraService.resolvedTargetStatusItem(
            from: [item],
            bundleID: "com.example.tool",
            menuExtraId: "com.example.tool.missing",
            statusItemIndex: nil,
            preferredCenterX: nil
        )

        #expect(resolved != nil)
    }

    @Test("Status item index exact IDs use live preferred centers before ordinal fallback")
    func testStatusItemIndexExactIdsUsePreferredCentersBeforeOrdinalFallback() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: projectRoot.appendingPathComponent("Core/Services/AccessibilityMenuExtraService.swift"),
            encoding: .utf8
        )

        #expect(!source.contains("if menuExtraId == nil,\n           let statusItemIndex,\n           items.indices.contains(statusItemIndex)"))
        #expect(source.contains("screenValidPreferredCenterX"))
        #expect(source.contains("screenFrames: NSScreen.screens.map(\\.frame)"))
        #expect(source.contains("AccessibilityMenuExtraFrameResolver.resolvedStatusItemIndex"))
        #expect(source.contains("return (true, false)"))
    }
}
