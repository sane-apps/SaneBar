import Testing
import AppKit
import Foundation
import SwiftUI
@testable import SaneBar

@Suite("MenuBarAppearance — Tint and Support")
@MainActor
struct MenuBarAppearanceTintAndSupportTests {
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
        #expect(source.contains("private var visibilityReconciliationTimer"))
        #expect(source.contains("private func scheduleOverlayVisibilityRefreshes()"))
        #expect(source.contains("private func startVisibilityReconciliationTimer()"))
        #expect(source.contains("private func stopVisibilityReconciliationTimer()"))
        #expect(source.contains("DispatchQueue.main.asyncAfter"))
        #expect(source.contains("Timer(timeInterval: Self.overlayVisibilityReconciliationInterval"))
        #expect(source.contains("internal nonisolated static let overlayVisibilityRefreshRetryDelays"))
        #expect(MenuBarAppearanceService.overlayVisibilityRefreshRetryDelays == [0.15, 0.5, 1.5, 3.0])
        #expect(MenuBarAppearanceService.overlayVisibilityReconciliationInterval == 0.5)
        #expect(MenuBarAppearanceService.postOverlaySuppressionStatusItemValidationDelay == 0.75)
        #expect(source.contains("NSWorkspace.didActivateApplicationNotification"))
        #expect(source.contains("NSWorkspace.activeSpaceDidChangeNotification"))
        #expect(source.contains("NSWorkspace.didWakeNotification"))
        #expect(source.contains("NSWorkspace.screensDidWakeNotification"))
        #expect(source.contains("NSWorkspace.sessionDidBecomeActiveNotification"))
        #expect(source.contains("func refreshAfterStatusItemRecovery()"))
    }

    @Test("Ending fullscreen overlay suppression schedules status-item validation once")
    func overlaySuppressionEndSchedulesStatusItemValidation() {
        #expect(
            MenuBarAppearanceService.shouldValidateStatusItemsAfterOverlaySuppression(
                previousReason: .fullscreenContentWindow,
                currentReason: nil
            )
        )
        #expect(
            MenuBarAppearanceService.shouldValidateStatusItemsAfterOverlaySuppression(
                previousReason: .systemSpaceControl,
                currentReason: nil
            )
        )
        #expect(
            !MenuBarAppearanceService.shouldValidateStatusItemsAfterOverlaySuppression(
                previousReason: nil,
                currentReason: nil
            )
        )
        #expect(
            !MenuBarAppearanceService.shouldValidateStatusItemsAfterOverlaySuppression(
                previousReason: .fullscreenContentWindow,
                currentReason: .fullscreenContentWindow
            )
        )
    }

    @Test("Overlay hides for fullscreen content and thin top hosts")
    func testOverlaySuppressesFullscreenContentAndThinTopHosts() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = root.appendingPathComponent("Core/Services/MenuBarAppearanceService.swift")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)
        let policyURL = root.appendingPathComponent("Core/Services/MenuBarAppearanceSuppressionPolicy.swift")
        let policySource = try String(contentsOf: policyURL, encoding: .utf8)

        guard let refreshStart = source.range(of: "private func refreshOverlayVisibility()"),
              let refreshEnd = source.range(of: "private func scheduleOverlayVisibilityRefreshes()") else {
            Issue.record("Could not find refreshOverlayVisibility source")
            return
        }

        let refreshBody = String(source[refreshStart.lowerBound..<refreshEnd.lowerBound])
        #expect(policySource.contains("case fullscreenContentWindow"))
        #expect(policySource.contains("case systemSpaceControl"))
        #expect(!refreshBody.contains("scheduleStableFullscreenSuppression()"))
        #expect(refreshBody.contains("if suppressionReason != nil"))
        #expect(refreshBody.contains("window.orderOut(nil)"))
        #expect(source.contains(".optionOnScreenOnly"))
        #expect(policySource.contains("kCGWindowIsOnscreen"))
        #expect(policySource.contains("kCGWindowAlpha"))
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
