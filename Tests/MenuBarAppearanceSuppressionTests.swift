import Testing
import AppKit
import Foundation
import SwiftUI
@testable import SaneBar

@Suite("MenuBarAppearance — Suppression")
@MainActor
struct MenuBarAppearanceSuppressionTests {
    @Test("Appearance overlay suppresses for active third-party full-width top host")
    func testSuppressOverlayForThirdPartyTopHost() {
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: 5151),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 0),
                "Y": NSNumber(value: 0),
                "Width": NSNumber(value: 1920),
                "Height": NSNumber(value: 24)
            ]
        ]]

        #expect(
            MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: 5151,
                frontmostBundleID: "com.blizzard.worldofwarcraft",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                windowInfos: infos,
                selfPID: 9999
            )
        )
    }

    @Test("Appearance overlay hides for fullscreen-shaped content windows")
    func testSuppressesOverlayForFullscreenContentWindow() {
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: 5151),
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowIsOnscreen as String: NSNumber(value: true),
            kCGWindowAlpha as String: NSNumber(value: 1),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 0),
                "Y": NSNumber(value: 0),
                "Width": NSNumber(value: 1920),
                "Height": NSNumber(value: 1080)
            ]
        ]]

        #expect(
            MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: 5151,
                frontmostBundleID: "com.google.Chrome",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                windowInfos: infos,
                selfPID: 9999
            )
        )
    }

    @Test("Fullscreen-shaped content windows hide Custom Appearance")
    func testFullscreenContentSuppressionIsEnabled() {
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: 5151),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 0),
                "Y": NSNumber(value: 0),
                "Width": NSNumber(value: 1920),
                "Height": NSNumber(value: 1080)
            ]
        ]]

        #expect(
            MenuBarAppearanceService.overlaySuppressionReason(
                frontmostPID: 5151,
                frontmostBundleID: "com.google.Chrome",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                windowInfos: infos,
                selfPID: 9999
            ) == .fullscreenContentWindow
        )
    }

    @Test("Appearance overlay hides for fullscreen windows with slight geometry drift")
    func testSuppressesOverlayForFullscreenWindowWithDrift() {
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: 5151),
            kCGWindowBounds as String: [
                "X": NSNumber(value: -4),
                "Y": NSNumber(value: -3),
                "Width": NSNumber(value: 1736),
                "Height": NSNumber(value: 1124)
            ]
        ]]

        #expect(
            MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: 5151,
                frontmostBundleID: "com.brave.Browser",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                windowInfos: infos,
                selfPID: 9999
            )
        )
    }

    @Test("Appearance overlay stays visible for maximized desktop windows below the menu bar")
    func testDoesNotSuppressOverlayForDesktopMaximizedWindowBelowMenuBar() {
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: 5151),
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowIsOnscreen as String: NSNumber(value: true),
            kCGWindowAlpha as String: NSNumber(value: 1),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 0),
                "Y": NSNumber(value: 25),
                "Width": NSNumber(value: 1728),
                "Height": NSNumber(value: 1068)
            ]
        ]]

        #expect(
            !MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: 5151,
                frontmostBundleID: "com.anthropic.claudefordesktop",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                windowInfos: infos,
                selfPID: 9999
            ),
            "A large desktop app window below the menu bar should not hide Custom Appearance tint"
        )
    }

    @Test("Appearance overlay ignores fullscreen-shaped transition snapshots")
    func testIgnoresFullscreenShapedTransitionSnapshotWindows() {
        let infos: [[String: Any]] = [
            [
                kCGWindowOwnerPID as String: NSNumber(value: 5151),
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowAlpha as String: NSNumber(value: 1),
                kCGWindowBounds as String: [
                    "X": NSNumber(value: 0),
                    "Y": NSNumber(value: 25),
                    "Width": NSNumber(value: 1728),
                    "Height": NSNumber(value: 1068)
                ]
            ],
            [
                kCGWindowOwnerPID as String: NSNumber(value: 5151),
                kCGWindowLayer as String: NSNumber(value: 24),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowAlpha as String: NSNumber(value: 1),
                kCGWindowBounds as String: [
                    "X": NSNumber(value: 0),
                    "Y": NSNumber(value: 0),
                    "Width": NSNumber(value: 1728),
                    "Height": NSNumber(value: 1117)
                ]
            ]
        ]

        #expect(
            MenuBarAppearanceService.overlaySuppressionReason(
                frontmostPID: 5151,
                frontmostBundleID: "com.anthropic.claudefordesktop",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                windowInfos: infos,
                selfPID: 9999
            ) == nil,
            "A fullscreen-shaped transition/snapshot window must not hide the custom tint"
        )
    }

    @Test("Appearance overlay ignores thin transition strip when same app has a content window")
    func testDoesNotSuppressThinTopHostWithCompanionContentWindow() {
        let infos: [[String: Any]] = [
            [
                kCGWindowOwnerPID as String: NSNumber(value: 5151),
                kCGWindowLayer as String: NSNumber(value: 24),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowAlpha as String: NSNumber(value: 1),
                kCGWindowBounds as String: [
                    "X": NSNumber(value: 0),
                    "Y": NSNumber(value: 0),
                    "Width": NSNumber(value: 1728),
                    "Height": NSNumber(value: 24)
                ]
            ],
            [
                kCGWindowOwnerPID as String: NSNumber(value: 5151),
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowAlpha as String: NSNumber(value: 1),
                kCGWindowBounds as String: [
                    "X": NSNumber(value: 0),
                    "Y": NSNumber(value: 25),
                    "Width": NSNumber(value: 1728),
                    "Height": NSNumber(value: 1068)
                ]
            ]
        ]

        #expect(
            MenuBarAppearanceService.overlaySuppressionReason(
                frontmostPID: 5151,
                frontmostBundleID: "com.anthropic.claudefordesktop",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                windowInfos: infos,
                selfPID: 9999
            ) == nil,
            "A titlebar/top transition strip should not hide Custom Appearance while the same app has a normal content window"
        )
    }

    @Test("Appearance overlay ignores offscreen or transparent fullscreen-shaped windows")
    func testIgnoresInvisibleFullscreenShapedWindows() {
        let infos: [[String: Any]] = [
            [
                kCGWindowOwnerPID as String: NSNumber(value: 5151),
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowIsOnscreen as String: NSNumber(value: false),
                kCGWindowAlpha as String: NSNumber(value: 1),
                kCGWindowBounds as String: [
                    "X": NSNumber(value: 0),
                    "Y": NSNumber(value: 0),
                    "Width": NSNumber(value: 1920),
                    "Height": NSNumber(value: 1080)
                ]
            ],
            [
                kCGWindowOwnerPID as String: NSNumber(value: 5151),
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowAlpha as String: NSNumber(value: 0),
                kCGWindowBounds as String: [
                    "X": NSNumber(value: 0),
                    "Y": NSNumber(value: 0),
                    "Width": NSNumber(value: 1920),
                    "Height": NSNumber(value: 1080)
                ]
            ]
        ]

        #expect(
            MenuBarAppearanceService.overlaySuppressionReason(
                frontmostPID: 5151,
                frontmostBundleID: "com.google.Chrome",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                windowInfos: infos,
                selfPID: 9999
            ) == nil
        )
    }

    @Test("Appearance overlay stays visible for accessory launcher fullscreen windows")
    func testDoesNotSuppressOverlayForAccessoryLauncherFullscreenWindow() {
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: 5151),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 0),
                "Y": NSNumber(value: 0),
                "Width": NSNumber(value: 1920),
                "Height": NSNumber(value: 1080)
            ]
        ]]

        #expect(
            !MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: 5151,
                frontmostBundleID: "app.remixdesign.LaunchOS",
                frontmostIsAccessoryApp: true,
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                windowInfos: infos,
                selfPID: 9999
            )
        )
    }

    @Test("Appearance overlay still suppresses accessory thin top hosts")
    func testSuppressOverlayForAccessoryThinTopHost() {
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: 5151),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 0),
                "Y": NSNumber(value: 0),
                "Width": NSNumber(value: 1920),
                "Height": NSNumber(value: 24)
            ]
        ]]

        #expect(
            MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: 5151,
                frontmostBundleID: "com.example.MenuBarHost",
                frontmostIsAccessoryApp: true,
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                windowInfos: infos,
                selfPID: 9999
            )
        )

        #expect(
            MenuBarAppearanceService.overlaySuppressionReason(
                frontmostPID: 5151,
                frontmostBundleID: "com.example.MenuBarHost",
                frontmostIsAccessoryApp: true,
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                windowInfos: infos,
                selfPID: 9999
            ) == .thinTopHost
        )
    }

    @Test("Appearance overlay hides for Apple fullscreen content windows")
    func testSuppressesOverlayForAppleFullscreenContentWindow() {
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: 5151),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 0),
                "Y": NSNumber(value: 0),
                "Width": NSNumber(value: 1728),
                "Height": NSNumber(value: 1117)
            ]
        ]]

        #expect(
            MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: 5151,
                frontmostBundleID: "com.apple.Safari",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                windowInfos: infos,
                selfPID: 9999
            )
        )
    }

    @Test("Appearance overlay hides when Accessibility reports frontmost fullscreen without CG windows")
    func testSuppressesOverlayForAccessibilityFullscreenFallback() {
        #expect(
            MenuBarAppearanceService.overlaySuppressionReason(
                frontmostPID: 5151,
                frontmostBundleID: "com.apple.Safari",
                frontmostHasFullscreenAXWindow: true,
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                windowInfos: [],
                selfPID: 9999
            ) == .fullscreenContentWindow
        )
    }

    @Test("Appearance overlay ignores Accessibility fullscreen state for accessory apps")
    func testDoesNotSuppressOverlayForAccessoryAccessibilityFullscreenFallback() {
        #expect(
            MenuBarAppearanceService.overlaySuppressionReason(
                frontmostPID: 5151,
                frontmostBundleID: "app.remixdesign.LaunchOS",
                frontmostIsAccessoryApp: true,
                frontmostHasFullscreenAXWindow: true,
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                windowInfos: [],
                selfPID: 9999
            ) == nil
        )
    }

    @Test("Appearance overlay hides for Safari fullscreen windows offset below transparent top host")
    func testSuppressesOverlayForSafariFullscreenWindowWithTransparentTopHost() {
        let infos: [[String: Any]] = [
            [
                kCGWindowOwnerPID as String: NSNumber(value: 5151),
                kCGWindowLayer as String: NSNumber(value: 26),
                kCGWindowAlpha as String: NSNumber(value: 0),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowBounds as String: [
                    "X": NSNumber(value: 0),
                    "Y": NSNumber(value: 0),
                    "Width": NSNumber(value: 1470),
                    "Height": NSNumber(value: 85)
                ]
            ],
            [
                kCGWindowOwnerPID as String: NSNumber(value: 5151),
                kCGWindowLayer as String: NSNumber(value: 0),
                kCGWindowAlpha as String: NSNumber(value: 1),
                kCGWindowIsOnscreen as String: NSNumber(value: true),
                kCGWindowBounds as String: [
                    "X": NSNumber(value: 0),
                    "Y": NSNumber(value: 33),
                    "Width": NSNumber(value: 1470),
                    "Height": NSNumber(value: 923)
                ]
            ]
        ]

        #expect(
            MenuBarAppearanceService.overlaySuppressionReason(
                frontmostPID: 5151,
                frontmostBundleID: "com.apple.Safari",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1470, height: 956),
                windowInfos: infos,
                selfPID: 9999
            ) == .fullscreenContentWindow
        )
    }

    @Test("Appearance overlay does not suppress for wide titlebar windows")
    func testDoesNotSuppressOverlayForWideTopAlignedWindow() {
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: 5151),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 148),
                "Y": NSNumber(value: 0),
                "Width": NSNumber(value: 1280),
                "Height": NSNumber(value: 30)
            ]
        ]]

        #expect(
            !MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: 5151,
                frontmostBundleID: "org.mozilla.firefox",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1600, height: 900),
                windowInfos: infos,
                selfPID: 9999
            )
        )
    }

    @Test("Appearance overlay does not suppress for top host on another screen")
    func testDoesNotSuppressOverlayForTopHostOnDifferentScreen() {
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: 5151),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 0),
                "Y": NSNumber(value: 0),
                "Width": NSNumber(value: 1600),
                "Height": NSNumber(value: 24)
            ]
        ]]

        #expect(
            !MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: 5151,
                frontmostBundleID: "com.blizzard.worldofwarcraft",
                targetScreenFrame: CGRect(x: 1600, y: 0, width: 1600, height: 900),
                windowInfos: infos,
                selfPID: 9999
            )
        )
    }

    @Test("Appearance overlay does not suppress for ordinary frontmost windows")
    func testDoesNotSuppressOverlayForOrdinaryWindow() {
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: 5151),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 345),
                "Y": NSNumber(value: 109),
                "Width": NSNumber(value: 1230),
                "Height": NSNumber(value: 646)
            ]
        ]]

        #expect(
            !MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: 5151,
                frontmostBundleID: "com.blizzard.worldofwarcraft",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                windowInfos: infos,
                selfPID: 9999
            )
        )
    }

    @Test("Appearance overlay does not suppress for SaneBar itself")
    func testDoesNotSuppressOverlayForSelf() {
        let selfPID: pid_t = 4242
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: selfPID),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 0),
                "Y": NSNumber(value: 0),
                "Width": NSNumber(value: 1920),
                "Height": NSNumber(value: 30)
            ]
        ]]

        #expect(
            !MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: selfPID,
                frontmostBundleID: "com.sanebar.app",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                windowInfos: infos,
                selfPID: selfPID
            )
        )
    }

    @Test("Appearance overlay does not suppress for Apple-owned top bars")
    func testDoesNotSuppressOverlayForAppleBundle() {
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: 5151),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 0),
                "Y": NSNumber(value: 0),
                "Width": NSNumber(value: 1920),
                "Height": NSNumber(value: 30)
            ]
        ]]

        #expect(
            !MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: 5151,
                frontmostBundleID: "com.apple.controlcenter",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                windowInfos: infos,
                selfPID: 9999
            )
        )
    }

    @Test("Appearance overlay does not suppress lone transition layer top strips")
    func testDoesNotSuppressLoneTransitionLayerThinTopStrip() {
        let infos: [[String: Any]] = [[
            kCGWindowOwnerPID as String: NSNumber(value: 5151),
            kCGWindowLayer as String: NSNumber(value: 24),
            kCGWindowBounds as String: [
                "X": NSNumber(value: 0),
                "Y": NSNumber(value: 0),
                "Width": NSNumber(value: 1920),
                "Height": NSNumber(value: 24)
            ]
        ]]

        #expect(
            !MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: 5151,
                frontmostBundleID: "com.anthropic.claudefordesktop",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                windowInfos: infos,
                selfPID: 9999
            ),
            "A fullscreen/app-switch transition strip above layer 0 should not hide the customer tint overlay"
        )
    }
}
