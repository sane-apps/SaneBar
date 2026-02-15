import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "SettingsController")

// MARK: - SettingsControllerProtocol

/// @mockable
@MainActor
protocol SettingsControllerProtocol: ObservableObject {
    var settings: SaneBarSettings { get set }
    var settingsPublisher: AnyPublisher<SaneBarSettings, Never> { get }
    func load() throws
    func save() throws
}

// MARK: - SettingsController

/// Controller responsible for loading, saving, and publishing settings changes.
///
/// Extracted from MenuBarManager to:
/// 1. Single responsibility for persistence
/// 2. Easier testing with mock persistence
/// 3. Cleaner dependency graph
@MainActor
final class SettingsController: ObservableObject, SettingsControllerProtocol {
    // MARK: - Published State

    @Published var settings: SaneBarSettings = .init()

    /// Publisher for observing settings changes
    var settingsPublisher: AnyPublisher<SaneBarSettings, Never> {
        $settings.eraseToAnyPublisher()
    }

    // MARK: - Dependencies

    private let persistence: PersistenceServiceProtocol

    // MARK: - Initialization

    init(persistence: PersistenceServiceProtocol = PersistenceService.shared) {
        self.persistence = persistence
    }

    // MARK: - Persistence

    /// Load settings from disk
    func load() throws {
        settings = try persistence.loadSettings()
        logger.info("Settings loaded successfully")
    }

    /// Load settings, falling back to defaults on error
    func loadOrDefault() {
        do {
            try load()
        } catch {
            logger.warning("Failed to load settings, using defaults: \(error.localizedDescription)")
            settings = SaneBarSettings()
        }
    }

    /// Save current settings to disk
    func save() throws {
        try persistence.saveSettings(settings)
        logger.info("Settings saved successfully")
    }

    /// Save settings, logging errors without throwing
    func saveQuietly() {
        do {
            try save()
        } catch {
            logger.error("Failed to save settings: \(error.localizedDescription)")
        }
    }

    // MARK: - Convenience Methods

    /// Update a setting and save immediately
    func update(_ transform: (inout SaneBarSettings) -> Void) {
        transform(&settings)
        saveQuietly()
    }

    /// Reset all settings to defaults (preserving onboarding status)
    func resetToDefaults() {
        let preserveOnboarding = settings.hasCompletedOnboarding
        let preserveFreemiumIntro = settings.hasSeenFreemiumIntro
        settings = SaneBarSettings()
        settings.hasCompletedOnboarding = preserveOnboarding
        settings.hasSeenFreemiumIntro = preserveFreemiumIntro
        saveQuietly()
        logger.info("Settings reset to defaults")
    }
}
