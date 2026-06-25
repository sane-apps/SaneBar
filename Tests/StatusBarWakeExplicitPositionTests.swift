import AppKit
@testable import SaneBar
import Testing

/// FM-2 (#136 "Arrangement bug is back" / #168 "Always resets icon sort order").
///
/// A user's EXPLICIT persisted divider position must SURVIVE a wake / Space-change
/// validation pass. The regression was: when live geometry returned after wake, the
/// non-destructive recovery branch reanchored the persisted positions toward Control
/// Center (e.g. main 900 -> 144, the launch-safe limit), laundering an explicit
/// user value as if it were drift. The reset path was already gated (CHANGE B); this
/// covers the second write path — the reanchor in recoverStartupPositions /
/// recreateItemsFromPersistedPositions.
@Suite(.serialized)
struct StatusBarWakeExplicitPositionTests {
    // MARK: - Provenance gate

    @Test("Wake validation does NOT reanchor persisted positions toward Control Center")
    func wakeResumeDoesNotReanchor() {
        #expect(
            MenuBarManager.shouldReanchorPersistedPositionsForStatusItemRecovery(
                isStartupRecovery: false,
                validationContext: .wakeResume
            ) == false,
            "Wake validation must preserve the explicit persisted divider, not reanchor it (#136/#168)"
        )
    }

    @Test("Space-change and manual-restore validation also preserve explicit positions")
    func steadyStateContextsDoNotReanchor() {
        #expect(
            MenuBarManager.shouldReanchorPersistedPositionsForStatusItemRecovery(
                validationContext: .activeSpaceChanged
            ) == false
        )
        #expect(
            MenuBarManager.shouldReanchorPersistedPositionsForStatusItemRecovery(
                validationContext: .manualLayoutRestore
            ) == false
        )
    }

    @Test("Genuine startup / display-topology recovery still reanchors unsafe positions")
    func startupAndDisplayTopologyStillReanchor() {
        #expect(
            MenuBarManager.shouldReanchorPersistedPositionsForStatusItemRecovery(
                isStartupRecovery: true,
                validationContext: nil
            ) == true,
            "Startup recovery may reanchor positions from a different display"
        )
        #expect(
            MenuBarManager.shouldReanchorPersistedPositionsForStatusItemRecovery(
                validationContext: .screenParametersChanged
            ) == true
        )
        #expect(
            MenuBarManager.shouldReanchorPersistedPositionsForStatusItemRecovery(
                validationContext: .startupFollowUp
            ) == true
        )
    }

    // MARK: - Store-level preservation (the actual write path)

    @Test("recoverStartupPositions preserves an explicit far-left divider on the wake path")
    @MainActor
    func recoverStartupPreservesExplicitPosition() {
        guard let currentWidth = NSScreen.main?.frame.width else {
            Issue.record("Expected a main screen")
            return
        }

        let defaults = UserDefaults.standard
        let mainKey = StatusBarPositionDefaultsStore.preferredPositionKey(for: StatusBarPositionStore.mainAutosaveName)
        let sepKey = StatusBarPositionDefaultsStore.preferredPositionKey(for: StatusBarPositionStore.separatorAutosaveName)
        let widthKey = "SaneBar_CalibratedScreenWidth"
        let keys = [mainKey, sepKey, widthKey]
        let originals: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }
        let originalByHost = (
            StatusBarPositionDefaultsStore.preferredPositionValues(forAutosaveName: StatusBarPositionStore.mainAutosaveName).byHostValue,
            StatusBarPositionDefaultsStore.preferredPositionValues(forAutosaveName: StatusBarPositionStore.separatorAutosaveName).byHostValue
        )
        defer {
            for (key, value) in originals {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            if let main = StatusBarPositionDefaultsStore.numericPositionValue(originalByHost.0) {
                StatusBarPositionDefaultsStore.setByHostPreferredPosition(main, forAutosaveName: StatusBarPositionStore.mainAutosaveName)
            } else {
                StatusBarPositionDefaultsStore.removeByHostPreferredPosition(forAutosaveName: StatusBarPositionStore.mainAutosaveName)
            }
            if let sep = StatusBarPositionDefaultsStore.numericPositionValue(originalByHost.1) {
                StatusBarPositionDefaultsStore.setByHostPreferredPosition(sep, forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
            } else {
                StatusBarPositionDefaultsStore.removeByHostPreferredPosition(forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
            }
        }

        // The user explicitly dragged the divider far left of Control Center.
        // 900 is well past the launch-safe limit, so the reanchor would clamp it.
        StatusBarPositionDefaultsStore.setPreferredPosition(900, forAutosaveName: StatusBarPositionStore.mainAutosaveName)
        StatusBarPositionDefaultsStore.setPreferredPosition(940, forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
        defaults.set(currentWidth, forKey: widthKey) // same display: no legitimate display reset

        // Steady-state wake recovery: explicit positions must survive untouched.
        StatusBarPositionRecoveryStore.recoverStartupPositions(
            alwaysHiddenEnabled: false,
            referenceScreen: NSScreen.main,
            preserveExplicitPersistedPositions: true
        )

        let main = StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: StatusBarPositionStore.mainAutosaveName)
        let separator = StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
        #expect(main == 900, "Explicit persisted main divider must survive wake validation, got \(main ?? -1)")
        #expect(separator == 940, "Explicit persisted separator divider must survive wake validation, got \(separator ?? -1)")
    }

    // MARK: - AH-pin hard-recovery call site (#168 FM-2 follow-up)

    /// Mirror of the decision computed at the line that calls
    /// `repairSeparatorPositionIfNeeded(reason:preserveExplicitPersistedPositions:)`
    /// from the position-validation loop (MenuBarStatusItemRecoveryWorkflow). The
    /// product code computes exactly `!shouldReanchor(...)`; the test uses the same
    /// real gate (no source.contains) so a regression in either direction fails here.
    private func ahPinHardRecoveryPreservesExplicit(
        for context: MenuBarOperationCoordinator.PositionValidationContext
    ) -> Bool {
        !MenuBarManager.shouldReanchorPersistedPositionsForStatusItemRecovery(
            validationContext: context
        )
    }

    @Test("AH-pin hard-recovery call site preserves on wake/Space, reanchors on startup/topology")
    func ahPinHardRecoveryCallSiteDecision() {
        // Wake / Space / manual restore -> the explicit divider must survive,
        // so the call site passes preserveExplicitPersistedPositions = true.
        #expect(ahPinHardRecoveryPreservesExplicit(for: .wakeResume))
        #expect(ahPinHardRecoveryPreservesExplicit(for: .activeSpaceChanged))
        #expect(ahPinHardRecoveryPreservesExplicit(for: .manualLayoutRestore))
        // Genuine startup / display topology -> reanchor (preserve = false).
        #expect(!ahPinHardRecoveryPreservesExplicit(for: .startupFollowUp))
        #expect(!ahPinHardRecoveryPreservesExplicit(for: .screenParametersChanged))
    }

    /// End-to-end on the actual write path: feed the call site's decision for a
    /// wake/Space context into `recoverStartupPositions` (the function the AH-pin
    /// hard-recovery branch invokes) and confirm the explicit far-left main divider
    /// is NOT clamped toward Control Center. Before the fix this branch always ran
    /// with preserve = false and clamped 900 -> launch-safe limit.
    @Test(
        "AH-pin hard recovery on a wake/Space context preserves the explicit main divider",
        arguments: [
            MenuBarOperationCoordinator.PositionValidationContext.wakeResume,
            .activeSpaceChanged,
            .manualLayoutRestore
        ]
    )
    @MainActor
    func ahPinHardRecoveryPreservesExplicitMainOnWritePath(
        context: MenuBarOperationCoordinator.PositionValidationContext
    ) {
        guard let currentWidth = NSScreen.main?.frame.width else {
            Issue.record("Expected a main screen")
            return
        }

        let defaults = UserDefaults.standard
        let mainKey = StatusBarPositionDefaultsStore.preferredPositionKey(for: StatusBarPositionStore.mainAutosaveName)
        let sepKey = StatusBarPositionDefaultsStore.preferredPositionKey(for: StatusBarPositionStore.separatorAutosaveName)
        let widthKey = "SaneBar_CalibratedScreenWidth"
        let keys = [mainKey, sepKey, widthKey]
        let originals: [(String, Any?)] = keys.map { ($0, defaults.object(forKey: $0)) }
        let originalByHost = (
            StatusBarPositionDefaultsStore.preferredPositionValues(forAutosaveName: StatusBarPositionStore.mainAutosaveName).byHostValue,
            StatusBarPositionDefaultsStore.preferredPositionValues(forAutosaveName: StatusBarPositionStore.separatorAutosaveName).byHostValue
        )
        defer {
            for (key, value) in originals {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            if let main = StatusBarPositionDefaultsStore.numericPositionValue(originalByHost.0) {
                StatusBarPositionDefaultsStore.setByHostPreferredPosition(main, forAutosaveName: StatusBarPositionStore.mainAutosaveName)
            } else {
                StatusBarPositionDefaultsStore.removeByHostPreferredPosition(forAutosaveName: StatusBarPositionStore.mainAutosaveName)
            }
            if let sep = StatusBarPositionDefaultsStore.numericPositionValue(originalByHost.1) {
                StatusBarPositionDefaultsStore.setByHostPreferredPosition(sep, forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
            } else {
                StatusBarPositionDefaultsStore.removeByHostPreferredPosition(forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
            }
        }

        StatusBarPositionDefaultsStore.setPreferredPosition(900, forAutosaveName: StatusBarPositionStore.mainAutosaveName)
        StatusBarPositionDefaultsStore.setPreferredPosition(940, forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
        defaults.set(currentWidth, forKey: widthKey) // same display: no legitimate display reset

        // This is exactly what MenuBarStatusItemRecoveryWorkflow computes and forwards
        // through repairSeparatorPositionIfNeeded into recoverStartupPositions.
        let preserveExplicitPositions = ahPinHardRecoveryPreservesExplicit(for: context)
        #expect(preserveExplicitPositions, "\(context.rawValue) must preserve the explicit divider")

        StatusBarPositionRecoveryStore.recoverStartupPositions(
            alwaysHiddenEnabled: true,
            referenceScreen: NSScreen.main,
            preserveExplicitPersistedPositions: preserveExplicitPositions
        )

        let main = StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: StatusBarPositionStore.mainAutosaveName)
        #expect(
            main == 900,
            "AH-pin hard recovery on \(context.rawValue) must NOT clamp the explicit main divider (got \(main ?? -1)); pre-fix it would snap toward the launch-safe limit"
        )
    }

    // MARK: - Namespace-bump recovery (#136/#168 FM-2 third write path)

    // The `.bumpAutosaveVersion` recovery action re-seeds a fresh autosave namespace
    // via `StatusBarController.recreateItemsWithBumpedVersion`. Before this gate it
    // reanchored the explicit persisted divider toward Control Center on EVERY
    // context — e.g. main 900 -> 144 (the launch-safe limit) on a 1920-wide notchless
    // display — which a local runtime probe reproduced as the divider snapping back
    // at wake+1s with the autosave version bumped. The product code now passes
    // `reanchorUnsafePersistedPositions: shouldReanchor(validationContext:)`, so these
    // drive the EXACT store transform that real decision selects (no source.contains):
    // wake/Space/manual must preserve, startup/topology must still reanchor.

    @Test("Namespace bump preserves the explicit divider on the wake/Space/manual path")
    func bumpNamespacePreservesExplicitOnSteadyState() {
        let contexts: [MenuBarOperationCoordinator.PositionValidationContext] = [
            .wakeResume, .activeSpaceChanged, .manualLayoutRestore,
        ]
        for context in contexts {
            let reanchor = MenuBarManager.shouldReanchorPersistedPositionsForStatusItemRecovery(
                validationContext: context
            )
            #expect(!reanchor, "\(context.rawValue) must not reanchor (preserve the explicit divider)")
            let positions = StatusBarPositionRecoveryStore.bumpedNamespaceRecoveryPositions(
                originalMain: 900,
                originalSeparator: 940,
                screenWidth: 1920,
                screenHasTopSafeAreaInset: false,
                reanchorUnsafePersistedPositions: reanchor
            )
            #expect(
                positions?.main == 900,
                "\(context.rawValue): explicit main divider must survive the namespace bump (got \(positions?.main ?? -1)); pre-fix it snapped to the launch-safe limit"
            )
            #expect(
                positions?.separator == 940,
                "\(context.rawValue): explicit separator must survive the namespace bump (got \(positions?.separator ?? -1))"
            )
        }
    }

    @Test("Namespace bump still reanchors an unsafe divider on startup / display-topology")
    func bumpNamespaceReanchorsOnStartupTopology() {
        let limit = StatusBarPositionStore.launchSafePreferredMainPositionLimit(
            for: 1920,
            screenHasTopSafeAreaInset: false
        )
        let contexts: [MenuBarOperationCoordinator.PositionValidationContext] = [
            .startupFollowUp, .screenParametersChanged,
        ]
        for context in contexts {
            let reanchor = MenuBarManager.shouldReanchorPersistedPositionsForStatusItemRecovery(
                validationContext: context
            )
            #expect(reanchor, "\(context.rawValue) must reanchor positions from a different display")
            let positions = StatusBarPositionRecoveryStore.bumpedNamespaceRecoveryPositions(
                originalMain: 900,
                originalSeparator: 940,
                screenWidth: 1920,
                screenHasTopSafeAreaInset: false,
                reanchorUnsafePersistedPositions: reanchor
            )
            #expect(
                positions?.main == limit,
                "\(context.rawValue): unsafe divider must clamp to the launch-safe limit \(limit) (got \(positions?.main ?? -1))"
            )
            #expect((positions?.main ?? .infinity) < 900, "\(context.rawValue): reanchor must move the divider toward Control Center")
        }
    }

    // MARK: - Same-display launder chokepoint (#136/#168, screen-parameters-changed on wake)

    /// Display sleep/wake fires `.screenParametersChanged` even with no real display
    /// change, and a brief post-wake attachment glitch then drives a destructive
    /// reset/launch-safe pass that clamps the explicit divider to the launch-safe limit
    /// (the runtime probe reproduced this at wake+5s). The chokepoint restores it when
    /// the display width is unchanged, and leaves a genuine display change alone. This
    /// drives the real store-level restore (no source.contains).
    @Test("Chokepoint restores a same-display laundered divider but leaves a real display change reanchored")
    @MainActor
    func chokepointRestoresSameDisplayLaunderOnly() {
        guard let screen = NSScreen.main else {
            Issue.record("Expected a main screen")
            return
        }
        let width = Double(screen.frame.width)
        let safeLimit = StatusBarPositionStore.launchSafePreferredMainPositionLimit(
            for: width,
            screenHasTopSafeAreaInset: StatusBarPositionStore.screenHasTopSafeAreaInset(screen)
        )
        let explicitMain = max(safeLimit + 200.0, width * 0.45)
        let explicitSeparator = min(width - 24.0, explicitMain + 40.0)
        guard explicitSeparator > explicitMain, explicitSeparator < width else {
            Issue.record("Main screen too narrow for the chokepoint test (width=\(width))")
            return
        }

        let defaults = UserDefaults.standard
        let mainKey = StatusBarPositionDefaultsStore.preferredPositionKey(for: StatusBarPositionStore.mainAutosaveName)
        let sepKey = StatusBarPositionDefaultsStore.preferredPositionKey(for: StatusBarPositionStore.separatorAutosaveName)
        let originals: [(String, Any?)] = [mainKey, sepKey].map { ($0, defaults.object(forKey: $0)) }
        let originalByHost = (
            StatusBarPositionDefaultsStore.preferredPositionValues(forAutosaveName: StatusBarPositionStore.mainAutosaveName).byHostValue,
            StatusBarPositionDefaultsStore.preferredPositionValues(forAutosaveName: StatusBarPositionStore.separatorAutosaveName).byHostValue
        )
        defer {
            for (key, value) in originals {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
            if let main = StatusBarPositionDefaultsStore.numericPositionValue(originalByHost.0) {
                StatusBarPositionDefaultsStore.setByHostPreferredPosition(main, forAutosaveName: StatusBarPositionStore.mainAutosaveName)
            } else {
                StatusBarPositionDefaultsStore.removeByHostPreferredPosition(forAutosaveName: StatusBarPositionStore.mainAutosaveName)
            }
            if let sep = StatusBarPositionDefaultsStore.numericPositionValue(originalByHost.1) {
                StatusBarPositionDefaultsStore.setByHostPreferredPosition(sep, forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
            } else {
                StatusBarPositionDefaultsStore.removeByHostPreferredPosition(forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
            }
        }

        // Same display: recovery laundered the explicit divider down to the launch-safe limit.
        StatusBarPositionDefaultsStore.setPreferredPosition(safeLimit, forAutosaveName: StatusBarPositionStore.mainAutosaveName)
        StatusBarPositionDefaultsStore.setPreferredPosition(safeLimit + 40.0, forAutosaveName: StatusBarPositionStore.separatorAutosaveName)
        let restored = StatusBarPositionRecoveryStore.restoreExplicitDividerIfLaunderedOnSameDisplay(
            capturedMain: explicitMain,
            capturedSeparator: explicitSeparator,
            calibratedWidth: width,
            referenceScreen: screen
        )
        #expect(restored, "Same-display launder must be undone")
        #expect(
            StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: StatusBarPositionStore.mainAutosaveName) == explicitMain,
            "Explicit main divider must be restored, got \(StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: StatusBarPositionStore.mainAutosaveName) ?? -1)"
        )

        // Real display change (calibrated width far from current): the reanchor is legitimate.
        StatusBarPositionDefaultsStore.setPreferredPosition(safeLimit, forAutosaveName: StatusBarPositionStore.mainAutosaveName)
        let restoredOnDisplayChange = StatusBarPositionRecoveryStore.restoreExplicitDividerIfLaunderedOnSameDisplay(
            capturedMain: explicitMain,
            capturedSeparator: explicitSeparator,
            calibratedWidth: width * 0.5,
            referenceScreen: screen
        )
        #expect(!restoredOnDisplayChange, "A genuine display-topology change must keep the reanchored divider")
        #expect(
            StatusBarPositionDefaultsStore.resolvedPreferredPosition(forAutosaveName: StatusBarPositionStore.mainAutosaveName) == safeLimit,
            "On a real display change the divider stays reanchored"
        )
    }
}
