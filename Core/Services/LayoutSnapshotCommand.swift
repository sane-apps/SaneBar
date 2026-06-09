import AppKit
import Foundation
import os.log

// MARK: - Layout Snapshot Command

@objc(LayoutSnapshotCommand)
final class LayoutSnapshotCommand: SaneBarScriptCommand {
    override func performDefaultImplementation() -> Any? {
        let json: String
        if Thread.isMainThread {
            json = MainActor.assumeIsolated {
                Self.collectSnapshotJSONOnMain()
            }
        } else {
            json = DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    Self.collectSnapshotJSONOnMain()
                }
            }
        }
        return json
    }

    @MainActor
    private static func buildSnapshotPayload(from manager: MenuBarManager) -> [String: Any] {
        let licenseIsPro = LicenseService.shared.isPro
        let alwaysHiddenRequested = manager.settings.alwaysHiddenSectionEnabled
        let alwaysHiddenEffective = MenuBarActionWorkflow.effectiveAlwaysHiddenSectionEnabled(
            isPro: licenseIsPro,
            alwaysHiddenSectionEnabled: alwaysHiddenRequested
        )
        let mainX = manager.geometryResolver.mainStatusItemLeftEdgeX()
        let separatorX = manager.geometryResolver.separatorOriginX()
        let separatorRightEdgeX = manager.geometryResolver.separatorRightEdgeX()
        let rawAlwaysHiddenX = manager.geometryResolver.alwaysHiddenSeparatorOriginX()
        let rawAlwaysHiddenBoundaryX = manager.geometryResolver.alwaysHiddenSeparatorBoundaryX()
        let alwaysHiddenGeometry = normalizedSnapshotAlwaysHiddenGeometry(
            hidingState: manager.hidingService.state,
            separatorX: separatorX,
            alwaysHiddenOriginX: rawAlwaysHiddenX,
            alwaysHiddenBoundaryX: rawAlwaysHiddenBoundaryX
        )

        let mainWindow = manager.mainStatusItem?.button?.window
        let separatorWindow = manager.separatorItem?.button?.window
        let screenWidth = mainWindow?.screen?.frame.width ?? NSScreen.main?.frame.width
        let notchRightSafeMinX = mainWindow?.screen?.auxiliaryTopRightArea?.minX
            ?? NSScreen.main?.auxiliaryTopRightArea?.minX
        let mainScreenFrame = mainWindow?.screen?.frame ?? NSScreen.main?.frame
        let separatorScreenFrame = separatorWindow?.screen?.frame ?? mainScreenFrame
        let mainWindowValid = StatusBarController.isStatusItemWindowFrameValid(
            windowFrame: mainWindow?.frame,
            screenFrame: mainScreenFrame
        )
        let separatorWindowValid = StatusBarController.isStatusItemWindowFrameValid(
            windowFrame: separatorWindow?.frame,
            screenFrame: separatorScreenFrame
        )
        let missionControlSpaces = StatusBarDiagnostics.missionControlSpacesDiagnostic()
        let knownOwnerRefresh = AccessibilityService.shared.knownOwnerRefreshDiagnosticsSnapshot()
        let rightGap = resolvedSnapshotMainRightGap(
            referenceScreenRightEdge: mainWindow?.screen?.frame.maxX ?? NSScreen.main?.frame.maxX,
            liveFrameOriginX: mainWindow?.frame.origin.x,
            liveFrameWidth: mainWindow?.frame.width,
            cachedMainX: mainX
        )

        let separatorBeforeMain: Bool = {
            guard let separatorX, let mainX else { return false }
            return separatorX < mainX
        }()

        let alwaysHiddenBeforeSeparator: Bool = {
            guard alwaysHiddenGeometry.isReliable else { return false }
            guard let alwaysHiddenX = alwaysHiddenGeometry.originX, let separatorX else { return false }
            return alwaysHiddenX < separatorX
        }()

        let mainNearControlCenter = MenuBarVisibilityPolicy.isMainNearControlCenter(
            mainX: mainX,
            mainRightGap: rightGap,
            screenWidth: screenWidth,
            notchRightSafeMinX: notchRightSafeMinX
        )
        let hiddenCollapsedSeparatorHealthy = StatusBarDiagnostics.hiddenCollapsedSeparatorIsStructurallyHealthy(.init(
            hidingState: manager.hidingService.state,
            mainWindowValid: mainWindowValid,
            separatorVisible: manager.separatorItem?.isVisible,
            separatorX: separatorX,
            mainX: mainX,
            mainRightGap: rightGap,
            screenWidth: screenWidth,
            notchRightSafeMinX: notchRightSafeMinX
        ))
        let startupItemsValid = mainWindowValid && (separatorWindowValid || hiddenCollapsedSeparatorHealthy)
        let suppressionHint = startupItemsValid ? "none" : StatusBarDiagnostics.systemMenuBarSuppressionHint(
            main: .init(
                isVisibleFlag: manager.mainStatusItem?.isVisible,
                windowFrame: mainWindow?.frame,
                screenFrame: mainWindow?.screen?.frame
            ),
            separator: .init(
                isVisibleFlag: manager.separatorItem?.isVisible,
                windowFrame: separatorWindow?.frame,
                screenFrame: separatorWindow?.screen?.frame
            )
        )

        var payload: [String: Any] = [
            "hidingState": manager.hidingService.state.rawValue,
            "separatorBeforeMain": separatorBeforeMain,
            "alwaysHiddenBeforeSeparator": alwaysHiddenBeforeSeparator,
            "alwaysHiddenGeometryReliable": alwaysHiddenGeometry.isReliable,
            "alwaysHiddenSectionEnabledRequested": alwaysHiddenRequested,
            "alwaysHiddenSectionEnabledEffective": alwaysHiddenEffective,
            "alwaysHiddenSeparatorPresent": manager.alwaysHiddenSeparatorItem != nil,
            "licenseIsPro": licenseIsPro,
            "mainNearControlCenter": mainNearControlCenter,
            // Rehide/debug state to diagnose "stuck expanded" reports quickly.
            "autoRehideEnabled": manager.settings.autoRehide,
            "rehideOnAppChange": manager.settings.rehideOnAppChange,
            "rehideDelay": manager.settings.rehideDelay,
            "findIconRehideDelay": manager.settings.findIconRehideDelay,
            "isRevealPinned": manager.isRevealPinned,
            "isMenuOpen": manager.isMenuOpen,
            "isBrowseVisible": SearchWindowController.shared.isVisible,
            "isBrowseSessionActive": SearchWindowController.shared.isBrowseSessionActive,
            "isMoveInProgress": SearchWindowController.shared.isMoveInProgress,
            "hoverSuspended": manager.hoverService.isSuspended,
            "hoverMouseInMenuBar": manager.hoverService.isMouseInMenuBar,
            "autoRehideBlockReason": manager.visibilityWorkflow.autoRehideBlockReason(),
            "shouldSkipHideForExternalMonitor": manager.shouldSkipHideForExternalMonitor,
            "isOnExternalMonitor": manager.isOnExternalMonitor,
            "knownOwnerRefreshAttempts": knownOwnerRefresh.attemptCount,
            "knownOwnerRefreshAccepted": knownOwnerRefresh.acceptedCount,
            "knownOwnerRefreshFullFallbacks": knownOwnerRefresh.fullFallbackCount,
            "knownOwnerRefreshLastOutcome": knownOwnerRefresh.lastOutcome,
            "knownOwnerRefreshLastSeededItems": knownOwnerRefresh.lastSeededItemCount,
            "knownOwnerRefreshLastSeededOwners": knownOwnerRefresh.lastSeededOwnerCount,
            "knownOwnerRefreshLastFirstResult": knownOwnerRefresh.lastFirstResultCount,
            "knownOwnerRefreshLastFirstCoverage": knownOwnerRefresh.lastFirstCoverage,
            "knownOwnerRefreshLastRetryOwners": knownOwnerRefresh.lastRetryOwnerCount,
            "knownOwnerRefreshLastRetryResult": knownOwnerRefresh.lastRetryResultCount,
            "knownOwnerRefreshLastRetryCoverage": knownOwnerRefresh.lastRetryCoverage,
            "mainStatusItemVisibleFlag": manager.mainStatusItem?.isVisible ?? false,
            "separatorStatusItemVisibleFlag": manager.separatorItem?.isVisible ?? false,
            "mainStatusItemWindowValid": mainWindowValid,
            "separatorStatusItemWindowValid": separatorWindowValid,
            "startupItemsValid": startupItemsValid,
            "systemMenuBarSuppressionHint": suppressionHint,
            "possibleSystemMenuBarSuppression": suppressionHint != "none",
            "missionControlDisplaysHaveSeparateSpaces": missionControlSpaces.displaysHaveSeparateSpaces.map(String.init) ?? "unknown",
            "missionControlSpansDisplaysRaw": missionControlSpaces.spansDisplays.map(String.init) ?? "unknown"
        ]
        SearchWindowController.shared.browseWindowPositionSnapshot().forEach { key, value in
            payload[key] = value
        }

        func setOptional(_ key: String, _ value: CGFloat?) {
            payload[key] = value.map(Double.init) ?? NSNull()
        }

        setOptional("mainIconLeftEdgeX", mainX)
        setOptional("separatorOriginX", separatorX)
        setOptional("separatorRightEdgeX", separatorRightEdgeX)
        setOptional("alwaysHiddenSeparatorOriginX", alwaysHiddenGeometry.originX)
        setOptional("alwaysHiddenSeparatorBoundaryX", alwaysHiddenGeometry.boundaryX)
        setOptional("rawAlwaysHiddenSeparatorOriginX", rawAlwaysHiddenX)
        setOptional("rawAlwaysHiddenSeparatorBoundaryX", rawAlwaysHiddenBoundaryX)
        setOptional("screenWidth", screenWidth)
        setOptional("notchRightSafeMinX", notchRightSafeMinX)
        setOptional("mainRightGap", rightGap)
        payload["geometryAvailable"] = (mainX != nil) || (separatorX != nil) || (separatorRightEdgeX != nil)
        return payload
    }

    private static func geometryAvailable(in payload: [String: Any]) -> Bool {
        (payload["geometryAvailable"] as? Bool) == true
    }

    @MainActor
    private static func collectSnapshotJSONOnMain() -> String {
        let manager = MenuBarManager.shared
        let deadline = Date().addingTimeInterval(8.0)
        var payload = buildSnapshotPayload(from: manager)
        var attempts = 1

        while !geometryAvailable(in: payload), Date() < deadline {
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.25))
            payload = buildSnapshotPayload(from: manager)
            attempts += 1
        }

        payload["snapshotAttempts"] = attempts
        payload["snapshotTimeout"] = !geometryAvailable(in: payload)
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "{\"snapshotTimeout\":true}"
    }
}
