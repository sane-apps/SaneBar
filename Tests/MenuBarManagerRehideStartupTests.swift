import Foundation
@testable import SaneBar
import Testing

@Suite("MenuBarManager — Rehide and Startup")
struct MenuBarManagerRehideStartupTests {
    @Test("App-change auto-hide ignores browse sessions and SaneBar self-activation")
    func appChangeRehideDecisionMatrix() {
        let ownBundleID = "com.sanebar.app"

        #expect(
            MenuBarVisibilityPolicy.shouldScheduleRehideOnAppChange(
                rehideOnAppChange: true,
                autoRehideEnabled: true,
                hidingState: .expanded,
                isRevealPinned: false,
                shouldSkipHideForExternalMonitor: false,
                isBrowseSessionActive: false,
                activatedBundleID: "com.apple.finder",
                ownBundleID: ownBundleID
            )
        )

        #expect(
            !MenuBarVisibilityPolicy.shouldScheduleRehideOnAppChange(
                rehideOnAppChange: true,
                autoRehideEnabled: true,
                hidingState: .expanded,
                isRevealPinned: false,
                shouldSkipHideForExternalMonitor: false,
                isBrowseSessionActive: true,
                activatedBundleID: "com.apple.finder",
                ownBundleID: ownBundleID
            )
        )

        #expect(
            !MenuBarVisibilityPolicy.shouldScheduleRehideOnAppChange(
                rehideOnAppChange: true,
                autoRehideEnabled: true,
                hidingState: .expanded,
                isRevealPinned: false,
                shouldSkipHideForExternalMonitor: false,
                isBrowseSessionActive: false,
                activatedBundleID: ownBundleID,
                ownBundleID: ownBundleID
            )
        )

        #expect(
            !MenuBarVisibilityPolicy.shouldScheduleRehideOnAppChange(
                rehideOnAppChange: false,
                autoRehideEnabled: true,
                hidingState: .expanded,
                isRevealPinned: false,
                shouldSkipHideForExternalMonitor: false,
                isBrowseSessionActive: false,
                activatedBundleID: "com.apple.finder",
                ownBundleID: ownBundleID
            )
        )

        #expect(
            !MenuBarVisibilityPolicy.shouldScheduleRehideOnAppChange(
                rehideOnAppChange: true,
                autoRehideEnabled: false,
                hidingState: .expanded,
                isRevealPinned: false,
                shouldSkipHideForExternalMonitor: false,
                isBrowseSessionActive: false,
                activatedBundleID: "com.apple.finder",
                ownBundleID: ownBundleID
            )
        )
    }

    @Test("Mouse-location helper only treats below-strip hover as an interaction")
    func mouseLocationRehideInteractionPolicy() {
        let screen = CGRect(x: 0, y: 0, width: 1920, height: 1080)

        #expect(
            !MenuBarVisibilityPolicy.shouldBlockRehideForMouseLocation(
                NSPoint(x: 1500, y: 1075),
                screenFrames: [screen]
            ),
            "The top menu bar strip alone should not hold auto-rehide open"
        )

        #expect(
            MenuBarVisibilityPolicy.shouldBlockRehideForMouseLocation(
                NSPoint(x: 1500, y: 980),
                screenFrames: [screen]
            ),
            "The legacy helper should still identify below-strip menu interaction zones for callers that need that signal"
        )

        #expect(
            !MenuBarVisibilityPolicy.shouldBlockRehideForMouseLocation(
                NSPoint(x: 1500, y: 700),
                screenFrames: [screen]
            ),
            "Pointer positions outside the menu interaction zone should allow rehide"
        )
    }

    @Test("Settings auto-rehide change only arms when it becomes enabled for an expanded unpinned bar")
    func settingsChangeAutoRehideDecisionMatrix() {
        func context(
            wasAutoRehideEnabled: Bool,
            isAutoRehideEnabled: Bool = true,
            hidingState: HidingState = .expanded,
            isRevealPinned: Bool = false,
            shouldSkipHideForExternalMonitor: Bool = false,
            isStatusMenuOpen: Bool = false
        ) -> AutoRehideSettingsChangeContext {
            AutoRehideSettingsChangeContext(
                wasAutoRehideEnabled: wasAutoRehideEnabled,
                isAutoRehideEnabled: isAutoRehideEnabled,
                hidingState: hidingState,
                isRevealPinned: isRevealPinned,
                shouldSkipHideForExternalMonitor: shouldSkipHideForExternalMonitor,
                isStatusMenuOpen: isStatusMenuOpen
            )
        }

        #expect(
            MenuBarVisibilityPolicy.shouldArmAutoRehideAfterSettingsChange(context(wasAutoRehideEnabled: false))
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldArmAutoRehideAfterSettingsChange(context(wasAutoRehideEnabled: true))
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldArmAutoRehideAfterSettingsChange(
                context(wasAutoRehideEnabled: false, hidingState: .hidden)
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldArmAutoRehideAfterSettingsChange(
                context(wasAutoRehideEnabled: false, isRevealPinned: true)
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldArmAutoRehideAfterSettingsChange(
                context(wasAutoRehideEnabled: false, isStatusMenuOpen: true)
            )
        )
    }

    @Test("Own app windows can bypass pointer rehide blocking without bypassing menus or browse panels")
    func ownAppWindowRehideBypassPolicy() {
        #expect(
            MenuBarVisibilityPolicy.shouldIgnorePointerRehideBlockForOwnAppWindow(
                ownAppWindowActive: true,
                isStatusMenuOpen: false,
                isBrowseSessionActive: false,
                isBrowseVisible: false
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldIgnorePointerRehideBlockForOwnAppWindow(
                ownAppWindowActive: false,
                isStatusMenuOpen: false,
                isBrowseSessionActive: false,
                isBrowseVisible: false
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldIgnorePointerRehideBlockForOwnAppWindow(
                ownAppWindowActive: true,
                isStatusMenuOpen: true,
                isBrowseSessionActive: false,
                isBrowseVisible: false
            )
        )
        #expect(
            !MenuBarVisibilityPolicy.shouldIgnorePointerRehideBlockForOwnAppWindow(
                ownAppWindowActive: true,
                isStatusMenuOpen: false,
                isBrowseSessionActive: true,
                isBrowseVisible: false
            )
        )
    }

    @Test("Startup recovery triggers when main icon drifts left of notch-safe boundary")
    @MainActor
    func startupRecoveryTriggersForNotchBoundaryDrift() {
        #expect(
            MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: 930,
                mainX: 1070,
                mainRightGap: 220,
                screenWidth: 1512,
                notchRightSafeMinX: 1080
            )
        )
    }

    @Test("Startup recovery tolerates notch boundary within 8pt slack")
    @MainActor
    func startupRecoveryAllowsNotchBoundarySlack() {
        #expect(
            !MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: 930,
                mainX: 1073,
                mainRightGap: 220,
                screenWidth: 1512,
                notchRightSafeMinX: 1080
            )
        )
    }

    @Test("Startup recovery right-gap boundary is strict-greater-than on non-notched displays")
    @MainActor
    func startupRecoveryRightGapStrictBoundary() {
        // maxAllowedRightGap = min(480, max(300, 1440*0.18)) = 300
        #expect(
            !MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: 910,
                mainX: 1080,
                mainRightGap: 300,
                screenWidth: 1440,
                notchRightSafeMinX: nil
            )
        )
        #expect(
            MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: 910,
                mainX: 1080,
                mainRightGap: 301,
                screenWidth: 1440,
                notchRightSafeMinX: nil
            )
        )
    }

    @Test("Startup recovery trusts the notch-safe right zone even when the legacy gap cap would fail")
    @MainActor
    func startupRecoveryAllowsCrowdedNotchedRightZone() {
        #expect(
            !MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: 1050,
                mainX: 1219,
                mainRightGap: 290,
                screenWidth: 1470,
                notchRightSafeMinX: 825
            )
        )
    }

    @Test("Startup recovery tolerates healthy wide-screen right-edge gap")
    @MainActor
    func startupRecoveryAllowsHealthyWideScreenGap() {
        #expect(
            !MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: 1500,
                mainX: 1698,
                mainRightGap: 222,
                screenWidth: 1920,
                notchRightSafeMinX: nil
            )
        )
    }

    @Test("Startup recovery triggers for Mini external-monitor far-left drift")
    @MainActor
    func startupRecoveryTriggersForMiniFarLeftDrift() {
        #expect(
            MenuBarVisibilityPolicy.shouldRecoverStartupPositions(
                separatorX: 956,
                mainX: 976,
                mainRightGap: 944,
                screenWidth: 1920,
                notchRightSafeMinX: nil
            )
        )
    }
}
