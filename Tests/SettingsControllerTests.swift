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
        let controller = SettingsController(persistence: mockPersistence)

        #expect(controller.settings.autoRehide == true, "Default autoRehide should be true")
        #expect(controller.settings.rehideDelay == 3.0, "Default rehideDelay should be 3.0")
    }

    // MARK: - Load Tests

    @Test("load() retrieves settings from persistence")
    @MainActor
    func testLoadRetrievesFromPersistence() throws {
        let mockPersistence = PersistenceServiceProtocolMock()
        var customSettings = SaneBarSettings()
        customSettings.autoRehide = false
        customSettings.rehideDelay = 5.0
        customSettings.spacerCount = 2
        mockPersistence.settings = customSettings

        let controller = SettingsController(persistence: mockPersistence)
        try controller.load()

        #expect(controller.settings.autoRehide == false)
        #expect(controller.settings.rehideDelay == 5.0)
        #expect(controller.settings.spacerCount == 2)
    }

    @Test("loadOrDefault() falls back to defaults on error")
    @MainActor
    func testLoadOrDefaultFallsBack() {
        let mockPersistence = ThrowingPersistenceServiceMock()
        mockPersistence.shouldThrowOnLoad = true

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
        let controller = SettingsController(persistence: mockPersistence)

        controller.settings.autoRehide = false
        controller.settings.spacerCount = 3
        try controller.save()

        #expect(mockPersistence.settings.autoRehide == false)
        #expect(mockPersistence.settings.spacerCount == 3)
    }

    @Test("saveQuietly() does not throw on error")
    @MainActor
    func testSaveQuietlyDoesNotThrow() {
        let mockPersistence = ThrowingPersistenceServiceMock()
        mockPersistence.shouldThrowOnSave = true

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
        let controller = SettingsController(persistence: mockPersistence)

        controller.update { settings in
            settings.autoRehide = false
            settings.showOnHover = true
        }

        #expect(controller.settings.autoRehide == false)
        #expect(controller.settings.showOnHover == true)
        #expect(mockPersistence.settings.autoRehide == false, "Should have saved to persistence")
    }

    // MARK: - Publisher Tests

    @Test("settingsPublisher emits on changes")
    @MainActor
    func testSettingsPublisherEmitsChanges() async {
        let mockPersistence = PersistenceServiceProtocolMock()
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
        let controller: any SettingsControllerProtocol = SettingsController(persistence: mockPersistence)

        // Protocol requires these
        _ = controller.settings
        _ = controller.settingsPublisher

        #expect(true, "Should conform to protocol")
    }
}

// MARK: - Test Helpers

/// Mock that can throw on load/save for error handling tests
class ThrowingPersistenceServiceMock: PersistenceServiceProtocol, @unchecked Sendable {
    var settings: SaneBarSettings = SaneBarSettings()
    var shouldThrowOnLoad = false
    var shouldThrowOnSave = false

    enum MockError: Error {
        case loadFailed
        case saveFailed
    }

    func saveSettings(_ settings: SaneBarSettings) throws {
        if shouldThrowOnSave {
            throw MockError.saveFailed
        }
        self.settings = settings
    }

    func loadSettings() throws -> SaneBarSettings {
        if shouldThrowOnLoad {
            throw MockError.loadFailed
        }
        return settings
    }

    func clearAll() throws {
        settings = SaneBarSettings()
    }
}
