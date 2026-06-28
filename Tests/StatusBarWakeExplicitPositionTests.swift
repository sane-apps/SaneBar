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

    // MARK: - Spurious screen-parameters prevention (#136/#153, upstream of the chokepoint)

    /// The chokepoint above is a POST-HOC restore — it undoes the launder only
    /// AFTER the destructive reanchor already fired (it cannot prevent the live
    /// transient the user sees as "moves right then back"). This is the UPSTREAM
    /// prevention: a `didChangeScreenParametersNotification` whose display
    /// fingerprint is unchanged (a plain sleep/wake) is routed by the observer to a
    /// non-destructive `.wakeResume` validation that never reanchors or resets, so
    /// the explicit divider is never laundered in the first place. A genuine
    /// fingerprint change keeps `.screenParametersChanged` and still reanchors an
    /// unsafe persisted position (#152/#157 intact). Drives the real observer
    /// context selection + the real reanchor/reset decision (no source.contains).
    @Test("Spurious screen-parameters (unchanged fingerprint) routes to a non-reanchoring context; a real change still reanchors")
    func spuriousScreenParametersDoesNotReanchor() {
        // Unchanged fingerprint → non-destructive wake → divider preserved.
        let spuriousContext = MenuBarObserverWorkflow.screenParametersValidationContext(
            displayActuallyChanged: false
        )
        #expect(spuriousContext == .wakeResume)
        #expect(
            !MenuBarManager.shouldReanchorPersistedPositionsForStatusItemRecovery(
                validationContext: spuriousContext
            ),
            "A spurious screen-parameters event on wake must not reanchor the explicit divider (#136/#153)"
        )
        #expect(
            !MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .invalidGeometry,
                validationContext: spuriousContext
            ),
            "A spurious screen-parameters event must not reset persistent state either"
        )

        // Real fingerprint change → topology context → reanchor still authorized.
        let realChangeContext = MenuBarObserverWorkflow.screenParametersValidationContext(
            displayActuallyChanged: true
        )
        #expect(realChangeContext == .screenParametersChanged)
        #expect(
            MenuBarManager.shouldReanchorPersistedPositionsForStatusItemRecovery(
                validationContext: realChangeContext
            ),
            "A genuine display-topology change must still reanchor an unsafe persisted position (#152/#157)"
        )
        #expect(
            MenuBarManager.shouldResetPersistentStateForStatusItemRecovery(
                reason: .invalidGeometry,
                validationContext: realChangeContext
            ),
            "A genuine display-topology change still authorizes a reset for invalid geometry"
        )
    }

    /// Pure fingerprint decision driving the observer: covers the three branches
    /// and the stored-fingerprint advancement. The no-screens branch (clamshell /
    /// all displays asleep) must stay non-destructive AND must not advance the
    /// stored fingerprint, so the same arrangement returning on wake is still seen
    /// as unchanged (otherwise the divider reanchors — the #136/#153 launder).
    @Test("screenParametersValidationDecision: no-screens & unchanged stay wake-resume; only a real fingerprint change is topology")
    func screenParametersDecisionCoversNoScreensUnchangedAndChanged() {
        let arrangementA = "1:0,0,1920x1080"
        let arrangementB = "1:0,0,1920x1080|2:1920,0,1080x1920"

        // Unchanged fingerprint → wake-resume, stored fingerprint stays.
        let unchanged = MenuBarObserverWorkflow.screenParametersValidationDecision(
            fingerprint: arrangementA, lastObservedFingerprint: arrangementA
        )
        #expect(unchanged.context == .wakeResume)
        #expect(unchanged.newLastObserved == arrangementA)

        // Real change → topology, stored fingerprint advances to the new one.
        let changed = MenuBarObserverWorkflow.screenParametersValidationDecision(
            fingerprint: arrangementB, lastObservedFingerprint: arrangementA
        )
        #expect(changed.context == .screenParametersChanged)
        #expect(changed.newLastObserved == arrangementB)

        // No screens → wake-resume AND the stored fingerprint is NOT advanced.
        let noScreens = MenuBarObserverWorkflow.screenParametersValidationDecision(
            fingerprint: MenuBarDisplayConfiguration.noScreensFingerprint,
            lastObservedFingerprint: arrangementA
        )
        #expect(noScreens.context == .wakeResume)
        #expect(
            noScreens.newLastObserved == arrangementA,
            "no-screens must preserve the last real fingerprint so the same arrangement on wake is still unchanged"
        )
        // ...and that non-destructive context must not reanchor.
        #expect(
            !MenuBarManager.shouldReanchorPersistedPositionsForStatusItemRecovery(
                validationContext: noScreens.context
            )
        )
    }

    /// #136/#168 channel 2: the CoreGraphics `CGDisplayRegisterReconfigurationCallback`
    /// path is a SECOND way a spurious wake can reach position validation. The original
    /// #136 fix only gated the `didChangeScreenParametersNotification` sink, leaving
    /// this channel emitting an unconditional `.screenParametersChanged` → reanchor.
    /// A plain sleep/wake on a notched built-in panel posts a reconfiguration callback
    /// carrying topology flags (mode/scale/main re-init) WITHOUT displayEnabledFlag, so
    /// it must route to the fingerprint gate — not a wake-resume short-circuit and never
    /// an unconditional reanchor. This test fails on the pre-fix unconditional path.
    @Test("CoreGraphics display-reconfiguration: a topology-only wake (no enable) is fingerprint-gated, not an unconditional reanchor (#136/#168 channel 2)")
    func displayReconfigurationTopologyOnlyWakeIsFingerprintGated() {
        let setMainFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 2)
        let setModeFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 3)
        let enabledFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 8)
        let desktopShapeFlag = CGDisplayChangeSummaryFlags(rawValue: 1 << 12)

        // Internal-panel mode/scale/main re-init on a plain wake (any topology flag, no
        // enable, no pending resume) → fingerprint-gated, so an unchanged arrangement is
        // NOT reanchored toward Control Center.
        let topologyOnlyCases: [CGDisplayChangeSummaryFlags] = [
            setModeFlag,
            desktopShapeFlag,
            setMainFlag,
            [setModeFlag, setMainFlag],
        ]
        for flags in topologyOnlyCases {
            #expect(
                MenuBarObserverWorkflow.displayReconfigurationWakeRouting(
                    flags: flags, resumePendingAfterDisable: false
                ) == .fingerprintGated,
                "A topology-only display-reconfiguration wake must be fingerprint-gated (#136/#168)"
            )
        }

        // An explicit enable is a genuine wake-resume (already non-destructive).
        #expect(
            MenuBarObserverWorkflow.displayReconfigurationWakeRouting(
                flags: enabledFlag, resumePendingAfterDisable: false
            ) == .wakeResume
        )
        // A topology change arriving after a prior display-disable is the matching resume.
        #expect(
            MenuBarObserverWorkflow.displayReconfigurationWakeRouting(
                flags: setModeFlag, resumePendingAfterDisable: true
            ) == .wakeResume
        )

        // End-to-end chain: a topology-only wake on an UNCHANGED fingerprint must yield a
        // non-reanchoring context (the divider survives) — the literal #136/#168 symptom.
        #expect(MenuBarObserverWorkflow.displayReconfigurationWakeRouting(
            flags: setModeFlag, resumePendingAfterDisable: false
        ) == .fingerprintGated)
        let unchanged = MenuBarObserverWorkflow.screenParametersValidationDecision(
            fingerprint: "1:0,0,1920x1080", lastObservedFingerprint: "1:0,0,1920x1080"
        )
        #expect(unchanged.context == .wakeResume)
        #expect(
            !MenuBarManager.shouldReanchorPersistedPositionsForStatusItemRecovery(
                validationContext: unchanged.context
            ),
            "Topology-only wake + unchanged fingerprint must not reanchor the explicit divider (#136/#168)"
        )
    }
}
