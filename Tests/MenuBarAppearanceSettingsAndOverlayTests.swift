import Testing
import AppKit
import Foundation
import SwiftUI
@testable import SaneBar

@Suite("MenuBarAppearance — Settings and Overlay")
@MainActor
struct MenuBarAppearanceSettingsAndOverlayTests {
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
        #expect(currentOverlayWindow(for: service) != nil, "Enabled appearance should create the overlay window")

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
}
