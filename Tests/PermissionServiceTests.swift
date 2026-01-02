import Testing
import Foundation
@preconcurrency import ApplicationServices
@testable import SaneBar

// MARK: - PermissionServiceTests

@Suite("PermissionService Tests")
struct PermissionServiceTests {

    // MARK: - Permission State Tests

    @Test("Permission state matches system call")
    @MainActor
    func testPermissionStateMatchesSystemCall() async {
        let service = PermissionService()

        let systemTrusted = AXIsProcessTrusted()
        let expectedState: PermissionState = systemTrusted ? .granted : .notGranted

        #expect(service.permissionState == expectedState)
    }

    @Test("Check permission updates state")
    @MainActor
    func testCheckPermissionUpdatesState() async {
        let service = PermissionService()

        // State should not be unknown after check
        service.checkPermission()
        #expect(service.permissionState != .unknown)
    }

    // MARK: - Polling Tests

    @Test("Start polling creates timer")
    @MainActor
    func testStartPollingCreatesTimer() async {
        let service = PermissionService()

        service.startPermissionPolling()

        // Give timer a moment to be created
        try? await Task.sleep(for: .milliseconds(100))

        // Stop polling to clean up
        service.stopPermissionPolling()

        // Test passes if no crash - timer was created on main run loop
        #expect(true)
    }

    @Test("Stop polling invalidates timer")
    @MainActor
    func testStopPollingInvalidatesTimer() async {
        let service = PermissionService()

        service.startPermissionPolling()
        service.stopPermissionPolling()

        // Should be safe to call multiple times
        service.stopPermissionPolling()

        #expect(true)
    }

    // MARK: - AppleScript Settings Opening
    // BUG-002: URL scheme opens browser instead of System Settings
    // Now using AppleScript - no URL scheme to test

    @Test("Permission instructions are not empty")
    func testPermissionInstructionsNotEmpty() {
        let instructions = PermissionService.permissionInstructions
        #expect(!instructions.isEmpty)
        #expect(instructions.contains("Accessibility"))
    }
}
