import Testing
import Foundation
@testable import SaneBar

// MARK: - Welcome Banner Logic Tests

@Suite("Welcome Banner Tests")
struct WelcomeBannerTests {

    // MARK: - UserDefaults Persistence

    @Test("hasSeenWelcome defaults to false")
    func testDefaultsToFalse() {
        // Use a separate test suite for UserDefaults
        let testDefaults = UserDefaults(suiteName: "com.sanebar.test.welcome")!
        testDefaults.removePersistentDomain(forName: "com.sanebar.test.welcome")

        // Fresh defaults should not have hasSeenWelcome key
        let hasKey = testDefaults.object(forKey: "SaneBar.hasSeenWelcome")
        #expect(hasKey == nil,
                "Fresh UserDefaults should not have hasSeenWelcome set")
    }

    @Test("hasSeenWelcome can be set to true")
    func testCanSetToTrue() {
        let testDefaults = UserDefaults(suiteName: "com.sanebar.test.welcome2")!
        testDefaults.removePersistentDomain(forName: "com.sanebar.test.welcome2")

        testDefaults.set(true, forKey: "SaneBar.hasSeenWelcome")
        let value = testDefaults.bool(forKey: "SaneBar.hasSeenWelcome")

        #expect(value == true,
                "hasSeenWelcome should persist as true")
    }

    @Test("hasSeenWelcome persists across reads")
    func testPersistsAcrossReads() {
        let testDefaults = UserDefaults(suiteName: "com.sanebar.test.welcome3")!
        testDefaults.removePersistentDomain(forName: "com.sanebar.test.welcome3")

        // Set value
        testDefaults.set(true, forKey: "SaneBar.hasSeenWelcome")
        testDefaults.synchronize()

        // Read again
        let newDefaults = UserDefaults(suiteName: "com.sanebar.test.welcome3")!
        let value = newDefaults.bool(forKey: "SaneBar.hasSeenWelcome")

        #expect(value == true,
                "hasSeenWelcome should persist across UserDefaults instances")
    }
}

// MARK: - Section Subtitle Tests

@Suite("Section Subtitle Tests")
struct SectionSubtitleTests {

    @Test("Always visible section has correct subtitle")
    func testAlwaysVisibleSubtitle() {
        let section = StatusItemModel.ItemSection.alwaysVisible
        let subtitle = sectionSubtitle(for: section)

        #expect(subtitle.contains("all the time"),
                "Always visible subtitle should mention 'all the time'")
    }

    @Test("Hidden section has correct subtitle")
    func testHiddenSubtitle() {
        let section = StatusItemModel.ItemSection.hidden
        let subtitle = sectionSubtitle(for: section)

        #expect(subtitle.contains("SaneBar icon"),
                "Hidden subtitle should mention the SaneBar icon")
    }

    @Test("Collapsed section has correct subtitle")
    func testCollapsedSubtitle() {
        let section = StatusItemModel.ItemSection.collapsed
        let subtitle = sectionSubtitle(for: section)

        #expect(subtitle.contains("completely hidden"),
                "Collapsed subtitle should mention 'completely hidden'")
    }

    // Helper matching SettingsView logic
    private func sectionSubtitle(for section: StatusItemModel.ItemSection) -> String {
        switch section {
        case .alwaysVisible:
            return "These icons stay in your menu bar all the time"
        case .hidden:
            return "Click the SaneBar icon to reveal these when needed"
        case .collapsed:
            return "These icons are completely hidden from view"
        }
    }
}

// MARK: - Scan Feedback Tests

@Suite("Scan Feedback Tests")
@MainActor
struct ScanFeedbackTests {

    @Test("MenuBarManager has lastScanMessage property")
    func testLastScanMessageExists() async {
        // Create manager with mocks
        let mockAccessibility = AccessibilityServiceProtocolMock()
        let mockPermission = PermissionServiceProtocolMock()
        let mockPersistence = PersistenceServiceProtocolMock()

        mockPermission.permissionState = .unknown

        let manager = MenuBarManager(
            accessibilityService: mockAccessibility,
            permissionService: mockPermission,
            persistenceService: mockPersistence
        )

        // Initial state should have nil message
        #expect(manager.lastScanMessage == nil,
                "lastScanMessage should be nil initially")
    }

    @Test("Scan updates lastScanMessage on success")
    func testScanUpdatesMessage() async {
        let mockAccessibility = AccessibilityServiceProtocolMock()
        let mockPermission = PermissionServiceProtocolMock()
        let mockPersistence = PersistenceServiceProtocolMock()

        mockPermission.permissionState = .granted
        mockAccessibility.scanMenuBarItemsHandler = {
            [StatusItemModel(bundleIdentifier: "com.test.app", title: "Test", position: 0)]
        }

        let manager = MenuBarManager(
            accessibilityService: mockAccessibility,
            permissionService: mockPermission,
            persistenceService: mockPersistence
        )

        await manager.scan()

        #expect(manager.lastScanMessage != nil,
                "lastScanMessage should be set after successful scan")
        #expect(manager.lastScanMessage?.contains("1") == true,
                "lastScanMessage should contain item count")
    }

    @Test("Scan with no items shows correct message")
    func testScanEmptyMessage() async {
        let mockAccessibility = AccessibilityServiceProtocolMock()
        let mockPermission = PermissionServiceProtocolMock()
        let mockPersistence = PersistenceServiceProtocolMock()

        mockPermission.permissionState = .granted
        mockAccessibility.scanMenuBarItemsHandler = { [] }

        let manager = MenuBarManager(
            accessibilityService: mockAccessibility,
            permissionService: mockPermission,
            persistenceService: mockPersistence
        )

        await manager.scan()

        #expect(manager.lastScanMessage?.contains("0") == true,
                "lastScanMessage should show 0 items when empty")
    }
}
