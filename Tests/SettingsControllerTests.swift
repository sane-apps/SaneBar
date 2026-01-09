import Testing
import Foundation
import Combine
@testable import SaneBar

// MARK: - SettingsControllerTests

@Suite("SettingsController Tests")
struct SettingsControllerTests {

    // MARK: - Initialization Tests

    @Test("SettingsController initializes with default settings")
    @MainActor
    func testInitialization() {
        let mockPersistence = PersistenceServiceProtocolMock()
        // Setup mock to return default settings for load
        mockPersistence.loadSettingsHandler = { return SaneBarSettings() }
        
        let controller = SettingsController(persistence: mockPersistence)

        #expect(controller.settings.autoRehide == true, "Default autoRehide should be true")
        #expect(controller.settings.rehideDelay == 3.0, "Default rehideDelay should be 3.0")
    }

    // MARK: - Load Tests

    @Test("load() retrieves settings from persistence")
    @MainActor
    func testLoadRetrievesFromPersistence() throws {
        let mockPersistence = PersistenceServiceProtocolMock()
        var customSettingsBuilder = SaneBarSettings()
        customSettingsBuilder.autoRehide = false
        customSettingsBuilder.rehideDelay = 5.0
        customSettingsBuilder.spacerCount = 2
        let customSettings = customSettingsBuilder  // Capture as let for closure

        // Setup mock to return custom settings for load
        mockPersistence.loadSettingsHandler = { return customSettings }

        let controller = SettingsController(persistence: mockPersistence)
        try controller.load()

        #expect(controller.settings.autoRehide == false)
        #expect(controller.settings.rehideDelay == 5.0)
        #expect(controller.settings.spacerCount == 2)
    }

    @Test("loadOrDefault() falls back to defaults on error")
    @MainActor
    func testLoadOrDefaultFallsBack() {
        let mockPersistence = PersistenceServiceProtocolMock()
        // Setup mock to throw on load
        mockPersistence.loadSettingsHandler = { throw PersistenceError.profileNotFound } // Any error works

        let controller = SettingsController(persistence: mockPersistence)
        controller.loadOrDefault()

        // Should have default settings (no crash)
        #expect(controller.settings.autoRehide == true)
    }

    // MARK: - Save Tests

    @Test("save() writes settings to persistence")
    @MainActor
    func testSaveWritesToPersistence() throws {
        let mockPersistence = PersistenceServiceProtocolMock()
        // Capture saved settings using a reference type for safe concurrent access
        final class SettingsCapture: @unchecked Sendable {
            var settings: SaneBarSettings?
        }
        let capture = SettingsCapture()
        mockPersistence.saveSettingsHandler = { settings in
            capture.settings = settings
        }
        
        // Setup mock for load handler as it might be called during init or indirectly
        mockPersistence.loadSettingsHandler = { return SaneBarSettings() }

        let controller = SettingsController(persistence: mockPersistence)
        controller.settings.autoRehide = false
        controller.settings.spacerCount = 3
        
        try controller.save()

        #expect(capture.settings?.autoRehide == false)
        #expect(capture.settings?.spacerCount == 3)
    }

    @Test("saveQuietly() does not throw on error")
    @MainActor
    func testSaveQuietlyDoesNotThrow() {
        let mockPersistence = PersistenceServiceProtocolMock()
        mockPersistence.saveSettingsHandler = { _ in throw PersistenceError.profileNotFound }
        mockPersistence.loadSettingsHandler = { return SaneBarSettings() } // Required for init

        let controller = SettingsController(persistence: mockPersistence)
        controller.settings.autoRehide = false

        // Should not throw
        controller.saveQuietly()

        #expect(true, "saveQuietly should not throw even on error")
    }

    // MARK: - Update Tests

    @Test("update() modifies settings and saves")
    @MainActor
    func testUpdateModifiesAndSaves() {
        let mockPersistence = PersistenceServiceProtocolMock()
        // Capture saved settings using a reference type for safe concurrent access
        final class SettingsCapture: @unchecked Sendable {
            var settings: SaneBarSettings?
        }
        let capture = SettingsCapture()
        mockPersistence.saveSettingsHandler = { settings in
            capture.settings = settings
        }
        mockPersistence.loadSettingsHandler = { return SaneBarSettings() } // Required for init

        let controller = SettingsController(persistence: mockPersistence)

        controller.update { settings in
            settings.autoRehide = false
            settings.showOnLowBattery = true
        }

        #expect(controller.settings.autoRehide == false)
        #expect(controller.settings.showOnLowBattery == true)
        #expect(capture.settings?.autoRehide == false, "Should have saved to persistence")
    }

    // MARK: - Publisher Tests

    @Test("settingsPublisher emits on changes")
    @MainActor
    func testSettingsPublisherEmitsChanges() async {
        let mockPersistence = PersistenceServiceProtocolMock()
        mockPersistence.loadSettingsHandler = { return SaneBarSettings() }
        mockPersistence.saveSettingsHandler = { _ in } // No-op save
        
        let controller = SettingsController(persistence: mockPersistence)

        var receivedSettings: [SaneBarSettings] = []
        var cancellables = Set<AnyCancellable>()

        controller.settingsPublisher
            .sink { settings in
                receivedSettings.append(settings)
            }
            .store(in: &cancellables)

        // Initial value
        #expect(receivedSettings.count == 1, "Should receive initial value")

        // Modify settings
        controller.settings.autoRehide = false

        // Give Combine time to propagate
        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms

        #expect(receivedSettings.count >= 2, "Should receive updated value")
        #expect(receivedSettings.last?.autoRehide == false)
    }

    // MARK: - Protocol Conformance Tests

    @Test("SettingsController conforms to SettingsControllerProtocol")
    @MainActor
    func testProtocolConformance() {
        let mockPersistence = PersistenceServiceProtocolMock()
        mockPersistence.loadSettingsHandler = { return SaneBarSettings() }
        
        let controller: any SettingsControllerProtocol = SettingsController(persistence: mockPersistence)

        // Protocol requires these
        _ = controller.settings
        _ = controller.settingsPublisher

        #expect(true, "Should conform to protocol")
    }

    // MARK: - Dock Icon Setting Tests

    @Test("showDockIcon defaults to false for backward compatibility")
    @MainActor
    func testShowDockIconDefaults() {
        let mockPersistence = PersistenceServiceProtocolMock()
        mockPersistence.loadSettingsHandler = { return SaneBarSettings() }
        
        let controller = SettingsController(persistence: mockPersistence)

        #expect(controller.settings.showDockIcon == false, "Default showDockIcon should be false")
    }

    @Test("showDockIcon setting persists when saved")
    @MainActor
    func testShowDockIconPersists() throws {
        let mockPersistence = PersistenceServiceProtocolMock()
        // Capture saved settings using a reference type for safe concurrent access
        final class SettingsCapture: @unchecked Sendable {
            var settings: SaneBarSettings?
        }
        let capture = SettingsCapture()
        mockPersistence.saveSettingsHandler = { settings in
            capture.settings = settings
        }
        mockPersistence.loadSettingsHandler = { return SaneBarSettings() } // Required for init

        let controller = SettingsController(persistence: mockPersistence)
        controller.settings.showDockIcon = true
        try controller.save()

        #expect(capture.settings?.showDockIcon == true, "showDockIcon should be saved")
    }

    @Test("showDockIcon setting loads correctly")
    @MainActor
    func testShowDockIconLoads() throws {
        let mockPersistence = PersistenceServiceProtocolMock()
        var customSettingsBuilder = SaneBarSettings()
        customSettingsBuilder.showDockIcon = true
        let customSettings = customSettingsBuilder  // Capture as let for closure

        mockPersistence.loadSettingsHandler = { return customSettings }

        let controller = SettingsController(persistence: mockPersistence)
        try controller.load()

        #expect(controller.settings.showDockIcon == true, "showDockIcon should be loaded")
    }
}