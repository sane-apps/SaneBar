import Testing
@preconcurrency import ApplicationServices
@testable import SaneBar

// MARK: - AccessibilityServiceTests

@Suite("AccessibilityService Tests")
struct AccessibilityServiceTests {

    // MARK: - Permission State Tests

    @Test("Permission check matches AXIsProcessTrusted")
    @MainActor
    func testPermissionCheckMatchesSystemCall() async throws {
        let service = AccessibilityService()

        // Service's isTrusted should match direct AX API call
        let serviceResult = service.isTrusted
        let directResult = AXIsProcessTrusted()
        #expect(serviceResult == directResult)
    }

    // MARK: - StatusItemModel Tests

    @Test("StatusItemModel generates valid composite key")
    func testCompositeKeyGeneration() {
        let item = StatusItemModel(
            bundleIdentifier: "com.example.app",
            title: "Example",
            position: 0
        )

        let key = item.compositeKey
        #expect(key.contains("com.example.app"))
        #expect(key.contains("Example"))
    }

    @Test("StatusItemModel displayName uses title when available")
    func testDisplayNameWithTitle() {
        let item = StatusItemModel(
            bundleIdentifier: "com.example.app",
            title: "My App",
            position: 0
        )

        #expect(item.displayName == "My App")
    }

    @Test("StatusItemModel displayName extracts from bundleID when no title")
    func testDisplayNameFromBundleID() {
        let item = StatusItemModel(
            bundleIdentifier: "com.example.myapp",
            title: nil,
            position: 0
        )

        #expect(item.displayName == "Myapp")
    }

    @Test("StatusItemModel displayName shows Unknown when no info")
    func testDisplayNameUnknown() {
        let item = StatusItemModel(
            bundleIdentifier: nil,
            title: nil,
            position: 0
        )

        #expect(item.displayName == "Unknown Item")
    }

    // MARK: - Section Tests

    @Test("ItemSection has correct display names")
    func testSectionDisplayNames() {
        #expect(StatusItemModel.ItemSection.alwaysVisible.displayName == "Always Visible")
        #expect(StatusItemModel.ItemSection.hidden.displayName == "Hidden")
        #expect(StatusItemModel.ItemSection.collapsed.displayName == "Collapsed")
    }

    @Test("ItemSection has system images")
    func testSectionSystemImages() {
        #expect(!StatusItemModel.ItemSection.alwaysVisible.systemImage.isEmpty)
        #expect(!StatusItemModel.ItemSection.hidden.systemImage.isEmpty)
        #expect(!StatusItemModel.ItemSection.collapsed.systemImage.isEmpty)
    }

    // MARK: - PermissionState Tests

    @Test("PermissionState has correct display names")
    func testPermissionStateDisplayNames() {
        #expect(PermissionState.unknown.displayName == "Checking...")
        #expect(PermissionState.notGranted.displayName == "Not Granted")
        #expect(PermissionState.granted.displayName == "Granted")
    }

    @Test("PermissionState has system images")
    func testPermissionStateSystemImages() {
        #expect(!PermissionState.unknown.systemImage.isEmpty)
        #expect(!PermissionState.notGranted.systemImage.isEmpty)
        #expect(!PermissionState.granted.systemImage.isEmpty)
    }

    // MARK: - Error Tests

    @Test("AccessibilityError provides localized descriptions")
    func testErrorDescriptions() {
        let notTrusted = AccessibilityError.notTrusted
        #expect(notTrusted.errorDescription?.contains("permission") == true)

        let menuBarNotFound = AccessibilityError.menuBarNotFound
        #expect(menuBarNotFound.errorDescription?.contains("menu bar") == true)

        let attrNotFound = AccessibilityError.attributeNotFound("AXPosition")
        #expect(attrNotFound.errorDescription?.contains("AXPosition") == true)
    }
}
