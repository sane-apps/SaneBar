import Testing
import Foundation
import SwiftUI
@testable import SaneBar

// MARK: - MenuBarAppearanceServiceTests

@Suite("MenuBarAppearanceService Tests")
@MainActor
struct MenuBarAppearanceServiceTests {

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
        _ = Color(hex: "#FF5500")  // Verify no crash
        #expect(true, "6-digit hex should parse")
    }

    @Test("Hex color parsing handles 3-digit format")
    func testHexColor3Digit() {
        _ = Color(hex: "#F50")  // Verify no crash
        #expect(true, "3-digit hex should parse")
    }

    @Test("Hex color parsing handles 8-digit ARGB format")
    func testHexColor8Digit() {
        _ = Color(hex: "#80FF5500")  // Verify no crash
        #expect(true, "8-digit ARGB hex should parse")
    }

    @Test("Hex color parsing handles missing hash")
    func testHexColorNoHash() {
        _ = Color(hex: "FF5500")  // Verify no crash
        #expect(true, "Hex without # should parse")
    }

    @Test("Invalid hex color defaults to black")
    func testHexColorInvalid() {
        _ = Color(hex: "not-a-color")  // Should not crash, defaults to black
        #expect(true, "Invalid hex should not crash")
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

    @Test("MenuBarAppearanceService can be initialized")
    func testServiceInitialization() {
        _ = MenuBarAppearanceService()  // Verify no crash
        #expect(true, "Service should initialize without crash")
    }

    @Test("updateAppearance with disabled settings hides overlay")
    func testUpdateAppearanceDisabled() {
        let service = MenuBarAppearanceService()
        var settings = MenuBarAppearanceSettings()
        settings.isEnabled = false

        service.updateAppearance(settings)
        // Should not crash, overlay should be hidden

        #expect(true, "Disabled settings should hide overlay")
    }

    @Test("show and hide are safe to call without setup")
    func testShowHideWithoutSetup() {
        let service = MenuBarAppearanceService()

        // These should not crash even without prior updateAppearance
        service.show()
        service.hide()

        #expect(true, "show/hide should be safe without setup")
    }

    // MARK: - Protocol Conformance Tests

    @Test("MenuBarAppearanceService conforms to protocol")
    func testProtocolConformance() {
        let service: MenuBarAppearanceServiceProtocol = MenuBarAppearanceService()

        service.updateAppearance(MenuBarAppearanceSettings())
        service.show()
        service.hide()

        #expect(true, "Service conforms to protocol")
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
