import Testing
@testable import SaneBar

@MainActor
@Suite("MenuBarSpacingService")
struct MenuBarSpacingServiceTests {

    // MARK: - Setup/Teardown

    /// Reset spacing to system defaults after each test to avoid polluting user's system
    private func cleanup() throws {
        try MenuBarSpacingService.shared.resetToDefaults()
    }

    // MARK: - Reading Tests

    @Test("Reading spacing when not set returns nil")
    func readSpacingWhenNotSet() throws {
        try cleanup()
        let value = MenuBarSpacingService.shared.currentSpacing()
        // After reset, should be nil (system default)
        #expect(value == nil)
    }

    @Test("Reading selection padding when not set returns nil")
    func readPaddingWhenNotSet() throws {
        try cleanup()
        let value = MenuBarSpacingService.shared.currentSelectionPadding()
        #expect(value == nil)
    }

    // MARK: - Writing Tests

    @Test("Setting spacing within valid range succeeds")
    func setSpacingValidRange() throws {
        defer { try? cleanup() }

        try MenuBarSpacingService.shared.setSpacing(6)
        let value = MenuBarSpacingService.shared.currentSpacing()
        #expect(value == 6)
    }

    @Test("Setting selection padding within valid range succeeds")
    func setPaddingValidRange() throws {
        defer { try? cleanup() }

        try MenuBarSpacingService.shared.setSelectionPadding(8)
        let value = MenuBarSpacingService.shared.currentSelectionPadding()
        #expect(value == 8)
    }

    @Test("Setting spacing to minimum (1) succeeds")
    func setSpacingMinimum() throws {
        defer { try? cleanup() }

        try MenuBarSpacingService.shared.setSpacing(1)
        let value = MenuBarSpacingService.shared.currentSpacing()
        #expect(value == 1)
    }

    @Test("Setting spacing to maximum (10) succeeds")
    func setSpacingMaximum() throws {
        defer { try? cleanup() }

        try MenuBarSpacingService.shared.setSpacing(10)
        let value = MenuBarSpacingService.shared.currentSpacing()
        #expect(value == 10)
    }

    // MARK: - Validation Tests

    @Test("Setting spacing below range throws error")
    func setSpacingBelowRange() throws {
        defer { try? cleanup() }

        #expect(throws: MenuBarSpacingError.self) {
            try MenuBarSpacingService.shared.setSpacing(0)
        }
    }

    @Test("Setting spacing above range throws error")
    func setSpacingAboveRange() throws {
        defer { try? cleanup() }

        #expect(throws: MenuBarSpacingError.self) {
            try MenuBarSpacingService.shared.setSpacing(11)
        }
    }

    @Test("Setting padding below range throws error")
    func setPaddingBelowRange() throws {
        defer { try? cleanup() }

        #expect(throws: MenuBarSpacingError.self) {
            try MenuBarSpacingService.shared.setSelectionPadding(0)
        }
    }

    @Test("Setting padding above range throws error")
    func setPaddingAboveRange() throws {
        defer { try? cleanup() }

        #expect(throws: MenuBarSpacingError.self) {
            try MenuBarSpacingService.shared.setSelectionPadding(11)
        }
    }

    // MARK: - Reset Tests

    @Test("Setting spacing to nil resets to system default")
    func setSpacingNilResetsDefault() throws {
        defer { try? cleanup() }

        // First set a value
        try MenuBarSpacingService.shared.setSpacing(5)
        #expect(MenuBarSpacingService.shared.currentSpacing() == 5)

        // Then reset
        try MenuBarSpacingService.shared.setSpacing(nil)
        #expect(MenuBarSpacingService.shared.currentSpacing() == nil)
    }

    @Test("Setting padding to nil resets to system default")
    func setPaddingNilResetsDefault() throws {
        defer { try? cleanup() }

        try MenuBarSpacingService.shared.setSelectionPadding(5)
        #expect(MenuBarSpacingService.shared.currentSelectionPadding() == 5)

        try MenuBarSpacingService.shared.setSelectionPadding(nil)
        #expect(MenuBarSpacingService.shared.currentSelectionPadding() == nil)
    }

    @Test("Reset to defaults clears both values")
    func resetToDefaultsClearsBoth() throws {
        // Set both values
        try MenuBarSpacingService.shared.setSpacing(3)
        try MenuBarSpacingService.shared.setSelectionPadding(4)

        // Verify they're set
        #expect(MenuBarSpacingService.shared.currentSpacing() == 3)
        #expect(MenuBarSpacingService.shared.currentSelectionPadding() == 4)

        // Reset
        try MenuBarSpacingService.shared.resetToDefaults()

        // Verify both cleared
        #expect(MenuBarSpacingService.shared.currentSpacing() == nil)
        #expect(MenuBarSpacingService.shared.currentSelectionPadding() == nil)
    }

    // MARK: - Error Message Tests

    @Test("Value out of range error has descriptive message")
    func errorMessageDescriptive() {
        let error = MenuBarSpacingError.valueOutOfRange(15)
        #expect(error.localizedDescription.contains("15"))
        #expect(error.localizedDescription.contains("1-10"))
    }

    // MARK: - Graceful Refresh (Smoke Test)

    @Test("Graceful refresh does not throw")
    func gracefulRefreshNoThrow() {
        // This just verifies the method doesn't crash
        // We can't easily verify the notifications were received
        MenuBarSpacingService.shared.attemptGracefulRefresh()
    }
}
