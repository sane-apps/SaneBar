import Combine
import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "SettingsController")


@MainActor
protocol SettingsControllerProtocol: ObservableObject {
    var settings: SaneBarSettings { get set }
    var settingsPublisher: AnyPublisher<SaneBarSettings, Never> { get }
    func load() throws
    func save() throws
}


@MainActor
final class SettingsController: ObservableObject, SettingsControllerProtocol {

    @Published var settings: SaneBarSettings = .init()

    var settingsPublisher: AnyPublisher<SaneBarSettings, Never> {
        $settings.eraseToAnyPublisher()
    }


    private let persistence: PersistenceServiceProtocol


    init(persistence: PersistenceServiceProtocol = PersistenceService.shared) {
        self.persistence = persistence
    }


    func load() throws {
        settings = try persistence.loadSettings()
        logger.info("Settings loaded successfully")
    }

    func loadOrDefault() {
        do {
            try load()
        } catch {
            logger.warning("Failed to load settings, using defaults: \(error.localizedDescription)")
            settings = SaneBarSettings()
        }
    }

    func save() throws {
        try persistence.saveSettings(settings)
        logger.info("Settings saved successfully")
    }

    func saveQuietly() {
        do {
            try save()
        } catch {
            logger.error("Failed to save settings: \(error.localizedDescription)")
        }
    }


    func update(_ transform: (inout SaneBarSettings) -> Void) {
        transform(&settings)
        saveQuietly()
    }

    func resetToDefaults() {
        let preserveOnboarding = settings.hasCompletedOnboarding
        let preserveFreemiumIntro = settings.hasSeenFreemiumIntro
        let preserveHealthWizard = settings.hasCompletedHealthWizard
        let preserveLayoutRescueRestorePoint = settings.layoutRescueRestorePoint
        let preserveLayoutRescueRestorePointCreatedAt = settings.layoutRescueRestorePointCreatedAt
        settings = SaneBarSettings()
        settings.hasCompletedOnboarding = preserveOnboarding
        settings.hasSeenFreemiumIntro = preserveFreemiumIntro
        settings.hasCompletedHealthWizard = preserveHealthWizard
        settings.layoutRescueRestorePoint = preserveLayoutRescueRestorePoint
        settings.layoutRescueRestorePointCreatedAt = preserveLayoutRescueRestorePointCreatedAt
        saveQuietly()
        logger.info("Settings reset to defaults")
    }
}
