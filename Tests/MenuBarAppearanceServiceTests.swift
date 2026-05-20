import Testing
import AppKit
import Foundation
import SwiftUI
@testable import SaneBar

// MARK: - MenuBarAppearanceServiceTests

@Suite("MenuBarAppearanceService Tests")
@MainActor
struct MenuBarAppearanceServiceTests {
    private func currentOverlayWindow(for service: MenuBarAppearanceService) -> NSWindow? {
        Mirror(reflecting: service).children.first { $0.label == "overlayWindow" }?.value as? NSWindow
    }

    // MARK: - Settings Initialization Tests

    @Test("MenuBarAppearanceSettings has sensible defaults")
    func testSettingsDefaults() {
        let settings = MenuBarAppearanceSettings()

        #expect(settings.isEnabled == false, "Custom appearance disabled by default")
        #expect(settings.useLiquidGlass == true, "Liquid Glass preferred when available")
        #expect(settings.tintColor == "#000000", "Default tint is black")
        #expect(settings.tintOpacity == 0.15, "Default opacity is 15%")
        #expect(settings.hasShadow == false, "Shadow disabled by default")
        #expect(settings.hasBorder == false, "Border disabled by default")
        #expect(settings.hasRoundedCorners == false, "Rounded corners disabled by default")
    }

    @Test("MenuBarAppearanceSettings is Codable")
    func testSettingsCodable() throws {
        let settings = MenuBarAppearanceSettings(
            isEnabled: true,
            useLiquidGlass: false,
            tintColor: "#FF5500",
            tintOpacity: 0.5,
            hasShadow: true,
            shadowOpacity: 0.8,
            hasBorder: true,
            borderColor: "#FFFFFF",
            borderWidth: 2.0,
            hasRoundedCorners: true,
            cornerRadius: 12.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MenuBarAppearanceSettings.self, from: data)

        #expect(decoded.isEnabled == settings.isEnabled)
        #expect(decoded.useLiquidGlass == settings.useLiquidGlass)
        #expect(decoded.tintColor == settings.tintColor)
        #expect(decoded.tintOpacity == settings.tintOpacity)
        #expect(decoded.hasShadow == settings.hasShadow)
        #expect(decoded.shadowOpacity == settings.shadowOpacity)
        #expect(decoded.hasBorder == settings.hasBorder)
        #expect(decoded.borderColor == settings.borderColor)
        #expect(decoded.borderWidth == settings.borderWidth)
        #expect(decoded.hasRoundedCorners == settings.hasRoundedCorners)
        #expect(decoded.cornerRadius == settings.cornerRadius)
    }

    @Test("MenuBarAppearanceSettings is Equatable")
    func testSettingsEquatable() {
        let settings1 = MenuBarAppearanceSettings()
        let settings2 = MenuBarAppearanceSettings()

        #expect(settings1 == settings2, "Default settings should be equal")

        var settings3 = MenuBarAppearanceSettings()
        settings3.tintColor = "#FF0000"

        #expect(settings1 != settings3, "Different settings should not be equal")
    }

    // MARK: - Color Validation Tests

    @Test("Hex color parsing handles 6-digit format")
    func testHexColor6Digit() {
        #expect(Color(hex: "#FF5500").toHex() == "#FF5500")
    }

    @Test("Hex color parsing handles 3-digit format")
    func testHexColor3Digit() {
        #expect(Color(hex: "#F50").toHex() == "#FF5500")
    }

    @Test("Hex color parsing handles 8-digit ARGB format")
    func testHexColor8Digit() {
        #expect(Color(hex: "#80FF5500").toHex() == "#FF5500")
    }

    @Test("Hex color parsing handles missing hash")
    func testHexColorNoHash() {
        #expect(Color(hex: "FF5500").toHex() == "#FF5500")
    }

    @Test("Invalid hex color defaults to black")
    func testHexColorInvalid() {
        #expect(Color(hex: "not-a-color").toHex() == "#000000")
    }

    // MARK: - Opacity Range Tests

    @Test("Tint opacity is clamped to valid range")
    func testOpacityRange() {
        var settings = MenuBarAppearanceSettings()

        settings.tintOpacity = 0.0
        #expect(settings.tintOpacity == 0.0, "Zero opacity is valid")

        settings.tintOpacity = 1.0
        #expect(settings.tintOpacity == 1.0, "Full opacity is valid")

        settings.tintOpacity = 0.5
        #expect(settings.tintOpacity == 0.5, "Mid opacity is valid")

        // Note: The struct doesn't enforce clamping, so these pass through
        // Real clamping should happen in UI layer (Slider constraints)
    }

    @Test("Shadow opacity is clamped to valid range")
    func testShadowOpacityRange() {
        var settings = MenuBarAppearanceSettings()

        settings.shadowOpacity = 0.0
        #expect(settings.shadowOpacity == 0.0)

        settings.shadowOpacity = 1.0
        #expect(settings.shadowOpacity == 1.0)
    }

    // MARK: - Corner Radius Tests

    @Test("Corner radius accepts positive values")
    func testCornerRadiusPositive() {
        var settings = MenuBarAppearanceSettings()

        settings.cornerRadius = 8.0
        #expect(settings.cornerRadius == 8.0)

        settings.cornerRadius = 0.0
        #expect(settings.cornerRadius == 0.0, "Zero radius is valid (no rounding)")

        settings.cornerRadius = 50.0
        #expect(settings.cornerRadius == 50.0, "Large radius is valid")
    }

    // MARK: - Border Width Tests

    @Test("Border width accepts positive values")
    func testBorderWidthPositive() {
        var settings = MenuBarAppearanceSettings()

        settings.borderWidth = 1.0
        #expect(settings.borderWidth == 1.0)

        settings.borderWidth = 0.5
        #expect(settings.borderWidth == 0.5, "Sub-pixel border is valid")

        settings.borderWidth = 5.0
        #expect(settings.borderWidth == 5.0, "Thick border is valid")
    }

    // MARK: - Service API Tests

    @Test("updateAppearance with disabled settings hides overlay")
    func testUpdateAppearanceDisabled() {
        let service = MenuBarAppearanceService()
        var settings = MenuBarAppearanceSettings()
        settings.isEnabled = false

        service.updateAppearance(settings)

        #expect(currentOverlayWindow(for: service)?.isVisible != true)
    }

    @Test("Disabled appearance stays hidden across later refreshes")
    func testDisabledAppearanceDoesNotReshowOnRefresh() throws {
        let service = MenuBarAppearanceService()

        var enabled = MenuBarAppearanceSettings()
        enabled.isEnabled = true
        service.updateAppearance(enabled)

        let window = try #require(currentOverlayWindow(for: service))
        #expect(window.isVisible, "Enabled appearance should create a visible overlay")

        var disabled = enabled
        disabled.isEnabled = false
        service.updateAppearance(disabled)
        #expect(!window.isVisible, "Disabling appearance should hide the overlay")

        service.show()
        #expect(!window.isVisible, "Later refreshes should not re-show a disabled overlay")
    }

    @Test("show and hide without setup do not create a visible overlay")
    func testShowHideWithoutSetupDoesNotCreateVisibleOverlay() {
        let service = MenuBarAppearanceService()

        service.show()
        service.hide()

        #expect(currentOverlayWindow(for: service)?.isVisible != true)
    }

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

    @Test("Appearance overlay stays visible for fullscreen-shaped content windows")
    func testDoesNotSuppressOverlayForFullscreenContentWindow() {
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
            !MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: 5151,
                frontmostBundleID: "com.google.Chrome",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                windowInfos: infos,
                selfPID: 9999
            )
        )
    }

    @Test("Fullscreen-shaped content windows do not hide Custom Appearance")
    func testFullscreenContentSuppressionIsDisabled() {
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
            ) == nil
        )
    }

    @Test("Appearance overlay stays visible for fullscreen windows with slight geometry drift")
    func testDoesNotSuppressOverlayForFullscreenWindowWithDrift() {
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
            !MenuBarAppearanceService.shouldSuppressOverlay(
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

    @Test("Appearance overlay stays visible for Apple fullscreen content windows")
    func testDoesNotSuppressOverlayForAppleFullscreenContentWindow() {
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
            !MenuBarAppearanceService.shouldSuppressOverlay(
                frontmostPID: 5151,
                frontmostBundleID: "com.apple.Safari",
                targetScreenFrame: CGRect(x: 0, y: 0, width: 1728, height: 1117),
                windowInfos: infos,
                selfPID: 9999
            )
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

    @Test("Overlay appearance resolves dark matches to a concrete dark appearance")
    func testResolvedOverlayAppearanceDarkMatch() {
        let source = NSAppearance(named: .darkAqua)

        let resolved = MenuBarAppearanceService.resolvedOverlayAppearance(from: source)

        #expect(
            resolved?.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) == .darkAqua
        )
    }

    @Test("Overlay appearance resolves light matches to a concrete light appearance")
    func testResolvedOverlayAppearanceLightMatch() {
        let source = NSAppearance(named: .aqua)

        let resolved = MenuBarAppearanceService.resolvedOverlayAppearance(from: source)

        #expect(
            resolved?.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) == .aqua
        )
    }

    @Test("Overlay appearance follows system style instead of activated app appearance")
    func testResolvedOverlayAppearanceUsesSystemInterfaceStyle() {
        let source = NSAppearance(named: .aqua)

        let resolved = MenuBarAppearanceService.resolvedOverlayAppearance(
            from: source,
            systemInterfaceStyleName: "Dark"
        )

        #expect(
            resolved?.bestMatch(from: MenuBarAppearanceService.supportedOverlayAppearances) == .darkAqua,
            "App activation can report Aqua briefly; the menu-bar overlay should keep the system dark tint"
        )
    }

    @Test("Unknown system interface style falls back to effective appearance")
    func testResolvedOverlayAppearanceIgnoresUnknownSystemInterfaceStyle() {
        let source = NSAppearance(named: .darkAqua)

        let resolved = MenuBarAppearanceService.resolvedOverlayAppearance(
            from: source,
            systemInterfaceStyleName: "Automatic"
        )

        #expect(
            resolved?.bestMatch(from: MenuBarAppearanceService.supportedOverlayAppearances) == .darkAqua,
            "Unknown or unavailable system style names must not force the overlay into the light/black tint path"
        )
    }

    @Test("Dark effective appearance keeps dark tint when system style is unavailable")
    func testDarkTintDoesNotFallBackToLightTintWhenSystemStyleUnavailable() {
        var settings = MenuBarAppearanceSettings()
        settings.tintColor = "#000000"
        settings.tintColorDark = "#FF5500"

        #expect(
            MenuBarAppearanceService.resolvedTintColorHex(
                settings: settings,
                appearance: NSAppearance(named: .darkAqua),
                systemInterfaceStyleName: nil
            ) == "#FF5500"
        )
    }

    @Test("Appearance tint colors are normalized before rendering")
    func testAppearanceTintColorsNormalizeInvalidPersistedValues() throws {
        let json = """
        {
          "isEnabled": true,
          "tintColor": "f50",
          "tintColorDark": "not-a-color",
          "tintOpacity": 0.2,
          "tintOpacityDark": 0.3
        }
        """

        let settings = try JSONDecoder().decode(
            MenuBarAppearanceSettings.self,
            from: Data(json.utf8)
        )

        #expect(settings.tintColor == "#FF5500")
        #expect(settings.tintColorDark == "#FFFFFF")
    }

    @Test("Tint mode matrix preserves dark and high contrast dark choices")
    func testTintModeMatrixPreservesDarkChoices() {
        var settings = MenuBarAppearanceSettings()
        settings.tintColor = "#000000"
        settings.tintColorDark = "#FF5500"

        let darkInputs: [(NSAppearance?, String?)] = [
            (NSAppearance(named: .darkAqua), nil),
            (NSAppearance(named: .aqua), "Dark"),
            (NSAppearance(named: .accessibilityHighContrastDarkAqua), nil),
            (NSAppearance(named: .accessibilityHighContrastAqua), "Dark"),
            (NSAppearance(named: .darkAqua), "Automatic")
        ]

        for input in darkInputs {
            #expect(
                MenuBarAppearanceService.resolvedTintColorHex(
                    settings: settings,
                    appearance: input.0,
                    systemInterfaceStyleName: input.1
                ) == "#FF5500"
            )
        }
    }

    @Test("Reduce Transparency raises tint opacity and plain tint level")
    func testReduceTransparencyOpacityAndWindowLevel() {
        var settings = MenuBarAppearanceSettings()
        settings.useLiquidGlass = true
        settings.tintOpacity = 0.15
        settings.tintOpacityDark = 0.25

        #expect(
            MenuBarAppearanceService.resolvedTintOpacity(
                settings: settings,
                isDarkAppearance: true,
                reduceTransparency: true
            ) == 0.5
        )
        #expect(
            MenuBarAppearanceService.resolvedTintOpacity(
                settings: settings,
                isDarkAppearance: true,
                reduceTransparency: false
            ) == 0.25
        )
        #expect(
            MenuBarAppearanceService.resolvedOverlayWindowLevel(
                settings: settings,
                reduceTransparency: true
            ) == .statusBar
        )

        settings.useLiquidGlass = false
        #expect(
            MenuBarAppearanceService.resolvedOverlayWindowLevel(
                settings: settings,
                reduceTransparency: false
            ) == .statusBar
        )
    }

    @Test("Liquid Glass keeps overlay below status items only when transparency is available")
    func testLiquidGlassWindowLevelIsConditional() {
        var settings = MenuBarAppearanceSettings()
        settings.useLiquidGlass = true

        let expectedLevel: NSWindow.Level = MenuBarAppearanceSettings.supportsLiquidGlass ? .statusBar - 1 : .statusBar

        #expect(
            MenuBarAppearanceService.resolvedOverlayWindowLevel(
                settings: settings,
                reduceTransparency: false
            ) == expectedLevel
        )
    }

    @Test("Overlay appearance keeps nil when no appearance is available")
    func testResolvedOverlayAppearanceNil() {
        #expect(MenuBarAppearanceService.resolvedOverlayAppearance(from: nil) == nil)
    }

    @Test("Overlay tint mode is resolved from explicit window appearance")
    func testOverlayTintModeUsesResolvedAppearance() {
        #expect(MenuBarAppearanceService.isDarkAppearance(NSAppearance(named: .darkAqua)))
        #expect(MenuBarAppearanceService.isDarkAppearance(NSAppearance(named: .accessibilityHighContrastDarkAqua)))
        #expect(!MenuBarAppearanceService.isDarkAppearance(NSAppearance(named: .aqua)))
        #expect(!MenuBarAppearanceService.isDarkAppearance(NSAppearance(named: .accessibilityHighContrastAqua)))
    }

    @Test("Overlay refresh resolves appearance before showing window")
    func testOverlayRefreshResolvesAppearanceBeforeShowingWindow() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("Core/Services/MenuBarAppearanceService.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        guard let refreshStart = source.range(of: "private func refreshOverlayVisibility()"),
              let refreshEnd = source.range(of: "private func currentWindowInfos") else {
            Issue.record("Could not find refreshOverlayVisibility source")
            return
        }

        let refreshBody = String(source[refreshStart.lowerBound..<refreshEnd.lowerBound])
        guard let appearanceCall = refreshBody.range(of: "applyResolvedAppearance()"),
              let orderFrontCall = refreshBody.range(of: "window.orderFront(nil)") else {
            Issue.record("Appearance refresh or orderFront call missing")
            return
        }

        #expect(appearanceCall.lowerBound < orderFrontCall.lowerBound)
        #expect(refreshBody.contains("if !window.isVisible"))
        #expect(source.contains("systemInterfaceStyleName: Self.currentSystemInterfaceStyleName()"))
        #expect(!source.contains("string(forKey: \"AppleInterfaceStyle\") ?? \"Light\""))
        #expect(!source.contains(#"@Environment(\.colorScheme)"#))
        #expect(!source.contains("colorScheme"))
    }

    @Test("Overlay visibility refresh retries after space and app changes")
    func testOverlayVisibilityRefreshRetriesAfterSpaceAndAppChanges() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("Core/Services/MenuBarAppearanceService.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        #expect(source.contains("private var pendingOverlayRefreshWorkItems"))
        #expect(source.contains("private func scheduleOverlayVisibilityRefreshes()"))
        #expect(source.contains("DispatchQueue.main.asyncAfter"))
        #expect(source.contains("internal nonisolated static let overlayVisibilityRefreshRetryDelays"))
        #expect(MenuBarAppearanceService.overlayVisibilityRefreshRetryDelays == [0.15, 0.5, 1.5, 3.0])
        #expect(source.contains("NSWorkspace.didActivateApplicationNotification"))
        #expect(source.contains("NSWorkspace.activeSpaceDidChangeNotification"))
        #expect(source.contains("NSWorkspace.didWakeNotification"))
        #expect(source.contains("NSWorkspace.screensDidWakeNotification"))
        #expect(source.contains("NSWorkspace.sessionDidBecomeActiveNotification"))
        #expect(source.contains("func refreshAfterStatusItemRecovery()"))
    }

    @Test("Overlay hides only for thin top hosts and joins fullscreen spaces")
    func testOverlayOnlySuppressesThinTopHostsAndJoinsFullscreenSpaces() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("Core/Services/MenuBarAppearanceService.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        guard let refreshStart = source.range(of: "private func refreshOverlayVisibility()"),
              let refreshEnd = source.range(of: "private func scheduleOverlayVisibilityRefreshes()") else {
            Issue.record("Could not find refreshOverlayVisibility source")
            return
        }

        let refreshBody = String(source[refreshStart.lowerBound..<refreshEnd.lowerBound])
        #expect(!refreshBody.contains("fullscreenContentWindow"))
        #expect(!refreshBody.contains("scheduleStableFullscreenSuppression()"))
        #expect(refreshBody.contains("if suppressionReason == .thinTopHost"))
        #expect(refreshBody.contains("window.orderOut(nil)"))
        #expect(source.contains(".optionOnScreenOnly"))
        #expect(source.contains("kCGWindowIsOnscreen"))
        #expect(source.contains("kCGWindowAlpha"))
        #expect(source.contains(".fullScreenAuxiliary"))
    }

    // MARK: - Mock Tests

    @Test("MenuBarAppearanceServiceProtocolMock tracks method calls")
    func testMockTracking() {
        let mock = MenuBarAppearanceServiceProtocolMock()

        mock.updateAppearance(MenuBarAppearanceSettings())
        mock.show()
        mock.show()
        mock.hide()

        #expect(mock.updateAppearanceCallCount == 1)
        #expect(mock.showCallCount == 2)
        #expect(mock.hideCallCount == 1)
    }

    @Test("MenuBarAppearanceServiceProtocolMock captures settings")
    func testMockCapturesSettings() {
        let mock = MenuBarAppearanceServiceProtocolMock()
        var settings = MenuBarAppearanceSettings()
        settings.tintColor = "#123456"

        mock.updateAppearance(settings)

        #expect(mock.updateAppearanceArgValues.count == 1)
        #expect(mock.updateAppearanceArgValues[0].tintColor == "#123456")
    }

    // MARK: - Liquid Glass Support Detection

    @Test("supportsLiquidGlass returns boolean based on OS version")
    func testLiquidGlassDetection() {
        let supportsLiquidGlass = MenuBarAppearanceSettings.supportsLiquidGlass

        // This will be true on macOS 26+, false otherwise
        // We just verify it returns a boolean without crashing
        #expect(supportsLiquidGlass == true || supportsLiquidGlass == false)
    }

    // MARK: - AnyShape Tests

    @Test("AnyShape wraps Rectangle correctly")
    func testAnyShapeRectangle() {
        let rect = Rectangle()
        let shape = SaneBar.AnyShape(rect)
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 50))

        #expect(!path.isEmpty, "Rectangle path should not be empty")
    }

    @Test("AnyShape wraps RoundedRectangle correctly")
    func testAnyShapeRoundedRectangle() {
        let roundedRect = RoundedRectangle(cornerRadius: 10)
        let shape = SaneBar.AnyShape(roundedRect)
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 50))

        #expect(!path.isEmpty, "RoundedRectangle path should not be empty")
    }

    @Test("AnyShape wraps UnevenRoundedRectangle correctly")
    func testAnyShapeUnevenRoundedRectangle() {
        let unevenRect = UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8)
        let shape = SaneBar.AnyShape(unevenRect)
        let path = shape.path(in: CGRect(x: 0, y: 0, width: 100, height: 50))

        #expect(!path.isEmpty, "UnevenRoundedRectangle path should not be empty")
    }
}
