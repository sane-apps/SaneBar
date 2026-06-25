import Foundation
@testable import SaneBar
import Testing

/// Plan B — CHANGE 1 regression lock.
///
/// `shouldResetPersistentStateForStatusItemRecovery` previously returned `true`
/// for EVERY non-nil reason, discarding its `isStartupRecovery` /
/// `validationContext` params. That destructively reset + reanchored an EXPLICIT
/// user divider toward Control Center during ordinary steady-state validation
/// (Space change / wake / app activation) on macOS 26/27 — the #136/#168 root
/// cause, violating invariant #5. The gate now honors its context: a destructive
/// reset only happens for startup / display-topology contexts, while ordinary
/// validation repairs non-destructively from the persisted user layout.
/// Structurally invalid items always reset (a broken item is never a user
/// layout — #147/#152 protections intact).
@Suite("StatusItemResetGate")
struct StatusItemResetGateTests {
    @Test("Transient missing coordinates during a Space change does not reset the persisted layout")
    func missingCoordinatesDuringSpaceChangeDoesNotReset() {
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .missingCoordinates,
                isStartupRecovery: false,
                validationContext: .activeSpaceChanged
            ) == false
        )
    }

    @Test("Transient invalid geometry on wake does not reset the persisted layout")
    func invalidGeometryOnWakeDoesNotReset() {
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .invalidGeometry,
                isStartupRecovery: false,
                validationContext: .wakeResume
            ) == false
        )
    }

    @Test("Display-topology change still resets to safe anchors")
    func screenParametersChangedStillResets() {
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .missingCoordinates,
                isStartupRecovery: false,
                validationContext: .screenParametersChanged
            ) == true
        )
    }

    @Test("Startup follow-up still resets to safe anchors")
    func startupFollowUpStillResets() {
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .invalidGeometry,
                isStartupRecovery: false,
                validationContext: .startupFollowUp
            ) == true
        )
    }

    @Test("Startup recovery flag still resets regardless of validation context")
    func startupRecoveryFlagStillResets() {
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .missingCoordinates,
                isStartupRecovery: true,
                validationContext: .activeSpaceChanged
            ) == true
        )
    }

    @Test("Structurally invalid items always reset regardless of context")
    func invalidStatusItemsAlwaysReset() {
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .invalidStatusItems,
                isStartupRecovery: false,
                validationContext: .activeSpaceChanged
            ) == true
        )
    }

    @Test("Manual layout restore repairs from persisted layout, not a reset")
    func manualLayoutRestoreDoesNotReset() {
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .invalidGeometry,
                isStartupRecovery: false,
                validationContext: .manualLayoutRestore
            ) == false
        )
    }

    @Test("A nil reason never resets")
    func nilReasonNeverResets() {
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: nil,
                isStartupRecovery: true,
                validationContext: .screenParametersChanged
            ) == false
        )
    }
}

/// Plan B — #168 derived-zone stability lock.
///
/// Zone membership (hidden / visible / alwaysHidden) is DERIVED at read time from
/// the live separator X; there is no persisted sort-order array. #168 ("sort
/// order resets") is a pure derived symptom of B: when the divider reanchors,
/// items flip hidden↔visible. This guards that the classifier is a pure function
/// of geometry, so stopping the reanchor (CHANGE 1) keeps zones stable.
@Suite("DerivedZoneStability")
struct DerivedZoneStabilityTests {
    @Test("Zone membership is derived only from separator X — identical inputs give identical zones")
    func zoneMembershipIsDerivedFromSeparatorX() {
        let separatorX: CGFloat = 800
        let alwaysHiddenSeparatorX: CGFloat = 400
        let itemXs: [CGFloat] = [300, 600, 1000]

        func classifyAll() -> [SearchService.VisibilityZone] {
            itemXs.map {
                SearchMenuBarZoneClassifier.classifyZone(
                    itemX: $0,
                    itemWidth: 22,
                    separatorX: separatorX,
                    alwaysHiddenSeparatorX: alwaysHiddenSeparatorX
                )
            }
        }

        // No-op validation pass changes nothing about geometry → zones must match.
        #expect(classifyAll() == classifyAll())
    }

    @Test("An item right of the separator is visible; left of it is hidden")
    func itemsClassifyByPositionRelativeToSeparator() {
        let visibleZone = SearchMenuBarZoneClassifier.classifyZone(
            itemX: 1000, itemWidth: 22, separatorX: 800, alwaysHiddenSeparatorX: 400
        )
        let hiddenZone = SearchMenuBarZoneClassifier.classifyZone(
            itemX: 600, itemWidth: 22, separatorX: 800, alwaysHiddenSeparatorX: 400
        )

        #expect(visibleZone == .visible)
        #expect(hiddenZone == .hidden)
    }
}
