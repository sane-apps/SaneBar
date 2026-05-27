import Foundation
@testable import SaneBar
import Testing

@Suite("Icon Moving — Identity Proof")
struct IconMovingIdentityProofTests {
    private struct SmokeItem {
        let bundle: String
        let uniqueID: String
        let name: String
        let zone: String
        let movable: Bool
    }

    private func sameBundleMovableCandidates(
        zones: [SmokeItem],
        candidate: SmokeItem
    ) -> [SmokeItem] {
        zones.filter { $0.bundle == candidate.bundle && $0.movable }
    }

    private func exactMoveIdentityLost(
        candidate: SmokeItem,
        requestedUniqueID: String,
        zones: [SmokeItem]
    ) -> Bool {
        guard sameBundleMovableCandidates(zones: zones, candidate: candidate).count > 1 else {
            return false
        }

        return !zones.contains { $0.uniqueID == requestedUniqueID }
    }

    private func matchedMoveCandidate(
        zones: [SmokeItem],
        requestedUniqueID: String,
        candidate: SmokeItem
    ) -> SmokeItem? {
        if let exact = zones.first(where: { $0.uniqueID == requestedUniqueID }) {
            return exact
        }

        let sameBundle = sameBundleMovableCandidates(zones: zones, candidate: candidate)
        guard sameBundle.count <= 1 else { return nil }

        return zones.first(where: { $0.bundle == candidate.bundle && $0.name == candidate.name }) ??
            sameBundle.first
    }

    @Test("Shared-bundle move proof rejects sibling fallback when requested identity disappears")
    func sharedBundleMoveProofRejectsSiblingFallback() {
        let requested = SmokeItem(
            bundle: "com.apple.controlcenter",
            uniqueID: "com.apple.controlcenter::axid:wifi",
            name: "Wi-Fi",
            zone: "hidden",
            movable: true
        )
        let liveZones = [
            SmokeItem(
                bundle: "com.apple.controlcenter",
                uniqueID: "com.apple.controlcenter::axid:battery",
                name: "Battery",
                zone: "visible",
                movable: true
            ),
            SmokeItem(
                bundle: "com.apple.controlcenter",
                uniqueID: "com.apple.controlcenter::axid:bluetooth",
                name: "Bluetooth",
                zone: "hidden",
                movable: true
            ),
        ]

        #expect(exactMoveIdentityLost(candidate: requested, requestedUniqueID: requested.uniqueID, zones: liveZones))
        #expect(matchedMoveCandidate(zones: liveZones, requestedUniqueID: requested.uniqueID, candidate: requested) == nil)
    }

    @Test("Single-bundle move proof still allows non-shared fallback")
    func singleBundleMoveProofAllowsSingleCandidateFallback() {
        let requested = SmokeItem(
            bundle: "com.example.single",
            uniqueID: "com.example.single::statusItem:1",
            name: "Single App",
            zone: "hidden",
            movable: true
        )
        let liveZones = [
            SmokeItem(
                bundle: "com.example.single",
                uniqueID: "com.example.single::statusItem:2",
                name: "Single App",
                zone: "visible",
                movable: true
            )
        ]

        let matched = matchedMoveCandidate(
            zones: liveZones,
            requestedUniqueID: requested.uniqueID,
            candidate: requested
        )

        #expect(!exactMoveIdentityLost(candidate: requested, requestedUniqueID: requested.uniqueID, zones: liveZones))
        #expect(matched?.uniqueID == "com.example.single::statusItem:2")
    }
}

@Suite("AppleScript Move Resolution")
struct AppleScriptMoveResolutionTests {
    @Test("Precise identifiers trust a fresh zone snapshot for moves")
    func preciseIdentifiersTrustFreshSnapshot() {
        let focus = RunningApp.menuExtraItem(
            ownerBundleId: "com.apple.controlcenter",
            name: "Focus",
            identifier: "com.apple.menuextra.focusmode",
            xPosition: 1400,
            width: 24
        )

        #expect(
            !shouldPreferFreshZonesForScriptMove(
                identifier: "com.apple.menuextra.focusmode",
                matchedApp: focus,
                sameBundleCount: 2,
                cacheIsFresh: true
            )
        )
        #expect(
            !shouldPreferFreshZonesForScriptMove(
                identifier: focus.uniqueId,
                matchedApp: focus,
                sameBundleCount: 1,
                cacheIsFresh: true
            )
        )
    }

    @Test("Precise identifiers still refresh when the zone cache is stale")
    func preciseIdentifiersRefreshWhenCacheIsStale() {
        let focus = RunningApp.menuExtraItem(
            ownerBundleId: "com.apple.controlcenter",
            name: "Focus",
            identifier: "com.apple.menuextra.focusmode",
            xPosition: 1400,
            width: 24
        )

        #expect(
            shouldPreferFreshZonesForScriptMove(
                identifier: focus.uniqueId,
                matchedApp: focus,
                sameBundleCount: 1,
                cacheIsFresh: false
            )
        )
    }

    @Test("Coarse bundle identifiers only force refresh when siblings exist")
    func coarseBundleIdentifiersOnlyRefreshWhenNeeded() {
        let coarse = RunningApp(
            id: "com.example.single",
            name: "Single",
            icon: nil,
            menuExtraIdentifier: nil,
            statusItemIndex: nil,
            xPosition: 1200,
            width: 24
        )

        #expect(
            !shouldPreferFreshZonesForScriptMove(
                identifier: "com.example.single",
                matchedApp: coarse,
                sameBundleCount: 1,
                cacheIsFresh: true
            )
        )
        #expect(
            shouldPreferFreshZonesForScriptMove(
                identifier: "com.example.single",
                matchedApp: coarse,
                sameBundleCount: 2,
                cacheIsFresh: true
            )
        )
    }
}

// MARK: - Grab Point Tests
