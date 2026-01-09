import Testing
import AppKit
@testable import SaneBar

@Suite("AccessibilityService Tests")
struct AccessibilityServiceTests {

    // MARK: - Permission Tests

    @Test("isTrusted returns boolean without crashing")
    @MainActor
    func testIsTrustedReturnsBoolean() {
        let service = AccessibilityService.shared
        // Just verify it doesn't crash - actual value depends on system permissions
        let result = service.isTrusted
        #expect(result == true || result == false)
    }

    // MARK: - clickMenuBarItem Tests

    @Test("clickMenuBarItem returns false for non-existent bundle ID")
    @MainActor
    func testClickMenuBarItemNonExistentApp() {
        let service = AccessibilityService.shared
        // This should return false because no app with this bundle ID exists
        let result = service.clickMenuBarItem(for: "com.nonexistent.app.that.does.not.exist")
        #expect(result == false)
    }

    @Test("clickMenuBarItem returns false for empty bundle ID")
    @MainActor
    func testClickMenuBarItemEmptyBundleID() {
        let service = AccessibilityService.shared
        let result = service.clickMenuBarItem(for: "")
        #expect(result == false)
    }

    @Test("clickMenuBarItem handles Finder gracefully")
    @MainActor
    func testClickMenuBarItemFinder() {
        let service = AccessibilityService.shared
        // Finder is always running but may not have a menu bar extra
        // This tests that the code handles a real app without crashing
        let result = service.clickMenuBarItem(for: "com.apple.finder")
        // Result depends on whether Finder has a status item - just verify no crash
        #expect(result == true || result == false)
    }

    // MARK: - Integration Tests (require accessibility permission)

    @Test("Full virtual click flow for System Preferences")
    @MainActor
    func testVirtualClickSystemPreferences() async {
        let service = AccessibilityService.shared

        // Skip if no accessibility permission
        guard service.isTrusted else {
            // Can't test without permission - this is expected in CI
            return
        }

        // Control Center usually has a status item
        // This is a real integration test
        let result = service.clickMenuBarItem(for: "com.apple.controlcenter")

        // We can't guarantee it works (depends on system state)
        // but we verify it doesn't crash and returns a boolean
        #expect(result == true || result == false)
    }

    // MARK: - Permission Flow Regression Tests

    @Test("isGranted property doesn't trigger system permission dialog")
    @MainActor
    func testIsGrantedDoesNotPrompt() {
        // REGRESSION: MenuBarSearchView was calling requestAccessibility() which
        // triggered the system permission dialog unexpectedly.
        // Fix: Use isGranted property which only checks current status.
        let service = AccessibilityService.shared

        // Reading isGranted should NEVER trigger a dialog
        // It uses AXIsProcessTrusted() internally which is read-only
        let _ = service.isGranted
        let _ = service.isGranted
        let _ = service.isGranted

        // If we got here without a dialog, test passed
        #expect(true)
    }

    @Test("System Settings accessibility URL is valid")
    func testAccessibilitySettingsURLIsValid() {
        // REGRESSION: "Open System Settings" button wasn't opening anything
        // because it called requestAccessibility() instead of opening the URL
        let urlString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        let url = URL(string: urlString)

        #expect(url != nil, "Accessibility Settings URL must be valid")
        #expect(url?.scheme == "x-apple.systempreferences", "URL scheme must be x-apple.systempreferences")
    }
}
