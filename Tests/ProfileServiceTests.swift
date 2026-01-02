import Testing
import Foundation
@testable import SaneBar

// MARK: - ProfileService Tests

@Suite("ProfileService Tests")
struct ProfileServiceTests {

    // MARK: - Helper Methods

    private func createTestProfile(
        name: String = "Test",
        isTimeBased: Bool = false,
        startHour: Int = 9,
        endHour: Int = 17,
        activeDays: Set<Int> = [2, 3, 4, 5, 6] // Mon-Fri
    ) -> Profile {
        var profile = Profile(name: name)
        profile.isTimeBasedProfile = isTimeBased

        if isTimeBased {
            let calendar = Calendar.current
            profile.startTime = calendar.date(bySettingHour: startHour, minute: 0, second: 0, of: Date())
            profile.endTime = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: Date())
            profile.activeDays = activeDays
        }

        return profile
    }

    // MARK: - Basic Tests

    @Test("Service is singleton")
    @MainActor
    func isSingleton() {
        let instance1 = ProfileService.shared
        let instance2 = ProfileService.shared
        #expect(instance1 === instance2)
    }

    @Test("Service has empty profiles initially before loading")
    @MainActor
    func initiallyEmptyBeforeLoad() {
        // Create a fresh service with mock persistence
        let mockPersistence = PersistenceServiceProtocolMock()
        let service = ProfileService(persistenceService: mockPersistence)
        #expect(service.profiles.isEmpty)
    }

    // MARK: - Profile CRUD Tests

    @Test("Add profile appends to list")
    @MainActor
    func addProfile() {
        let mockPersistence = PersistenceServiceProtocolMock()
        let service = ProfileService(persistenceService: mockPersistence)

        let profile = createTestProfile(name: "Work")
        service.addProfile(profile)

        #expect(service.profiles.count == 1)
        #expect(service.profiles.first?.name == "Work")
    }

    @Test("Update profile modifies existing")
    @MainActor
    func updateProfile() {
        let mockPersistence = PersistenceServiceProtocolMock()
        let service = ProfileService(persistenceService: mockPersistence)

        var profile = createTestProfile(name: "Work")
        service.addProfile(profile)

        profile.name = "Office"
        service.updateProfile(profile)

        #expect(service.profiles.count == 1)
        #expect(service.profiles.first?.name == "Office")
    }

    @Test("Delete profile removes from list")
    @MainActor
    func deleteProfile() {
        let mockPersistence = PersistenceServiceProtocolMock()
        let service = ProfileService(persistenceService: mockPersistence)

        let profile = createTestProfile(name: "ToDelete")
        service.addProfile(profile)
        #expect(service.profiles.count == 1)

        service.deleteProfile(profile)

        // Should have default profile after deletion
        #expect(service.profiles.count == 1)
        #expect(service.profiles.first?.name == "Default")
    }

    @Test("Cannot delete last profile - creates default")
    @MainActor
    func cannotDeleteLastProfile() {
        let mockPersistence = PersistenceServiceProtocolMock()
        let service = ProfileService(persistenceService: mockPersistence)

        let profile = createTestProfile(name: "Only")
        service.addProfile(profile)
        service.deleteProfile(profile)

        #expect(!service.profiles.isEmpty)
        #expect(service.profiles.first?.name == "Default")
    }

    // MARK: - Active Profile Tests

    @Test("Set active profile updates selection")
    @MainActor
    func setActiveProfile() {
        let mockPersistence = PersistenceServiceProtocolMock()
        let service = ProfileService(persistenceService: mockPersistence)

        let profile1 = createTestProfile(name: "Work")
        let profile2 = createTestProfile(name: "Home")
        service.addProfile(profile1)
        service.addProfile(profile2)

        service.setActiveProfile(profile2)

        #expect(service.activeProfile?.name == "Home")
    }

    @Test("Set active profile posts notification")
    @MainActor
    func setActiveProfilePostsNotification() async {
        let mockPersistence = PersistenceServiceProtocolMock()
        let service = ProfileService(persistenceService: mockPersistence)

        var notificationReceived = false
        let observer = NotificationCenter.default.addObserver(
            forName: .profileDidChange,
            object: nil,
            queue: .main
        ) { _ in
            notificationReceived = true
        }

        let profile = createTestProfile(name: "Test")
        service.addProfile(profile)
        service.setActiveProfile(profile)

        // Small delay for notification
        try? await Task.sleep(for: .milliseconds(50))

        #expect(notificationReceived)
        NotificationCenter.default.removeObserver(observer)
    }

    // MARK: - Time-Based Profile Tests

    @Test("Check time-based profile returns matching profile")
    @MainActor
    func checkTimeBasedReturnsMatch() {
        let mockPersistence = PersistenceServiceProtocolMock()
        let service = ProfileService(persistenceService: mockPersistence)

        // Create a profile that's active now
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)

        // Create profile covering current time
        var profile = createTestProfile(
            name: "Current",
            isTimeBased: true,
            startHour: max(0, hour - 1),
            endHour: min(23, hour + 1),
            activeDays: Set([weekday])
        )
        service.addProfile(profile)

        let result = service.checkTimeBasedProfiles()

        #expect(result != nil)
        #expect(result?.name == "Current")
    }

    @Test("Check time-based profile returns nil when no match")
    @MainActor
    func checkTimeBasedReturnsNilWhenNoMatch() {
        let mockPersistence = PersistenceServiceProtocolMock()
        let service = ProfileService(persistenceService: mockPersistence)

        // Create a profile for a different day
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let otherDay = weekday == 7 ? 1 : weekday + 1

        var profile = createTestProfile(
            name: "OtherDay",
            isTimeBased: true,
            startHour: 9,
            endHour: 17,
            activeDays: Set([otherDay])
        )
        service.addProfile(profile)

        let result = service.checkTimeBasedProfiles()

        #expect(result == nil)
    }

    @Test("Manual profile is not returned by time check")
    @MainActor
    func manualProfileNotReturnedByTimeCheck() {
        let mockPersistence = PersistenceServiceProtocolMock()
        let service = ProfileService(persistenceService: mockPersistence)

        let profile = createTestProfile(name: "Manual", isTimeBased: false)
        service.addProfile(profile)

        let result = service.checkTimeBasedProfiles()

        #expect(result == nil)
    }

    // MARK: - Auto-Switching Tests

    @Test("Start auto-switching doesn't crash")
    @MainActor
    func startAutoSwitching() {
        let mockPersistence = PersistenceServiceProtocolMock()
        let service = ProfileService(persistenceService: mockPersistence)

        service.startAutoSwitching()
        service.stopAutoSwitching()

        // Just verify no crash
        #expect(true)
    }

    @Test("Stop auto-switching is idempotent")
    @MainActor
    func stopAutoSwitchingIdempotent() {
        let mockPersistence = PersistenceServiceProtocolMock()
        let service = ProfileService(persistenceService: mockPersistence)

        service.stopAutoSwitching()
        service.stopAutoSwitching()
        service.stopAutoSwitching()

        // Just verify no crash
        #expect(true)
    }
}

// MARK: - Profile Model Tests

@Suite("Profile Model Tests")
struct ProfileModelTests {

    @Test("Profile is Codable")
    func profileCodable() throws {
        let profile = Profile(
            name: "Test",
            itemSections: ["key1": .hidden, "key2": .alwaysVisible],
            isTimeBasedProfile: true,
            startTime: Date(),
            endTime: Date().addingTimeInterval(3600),
            activeDays: [2, 3, 4, 5, 6]
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(profile)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Profile.self, from: data)

        #expect(decoded.name == profile.name)
        #expect(decoded.itemSections == profile.itemSections)
        #expect(decoded.isTimeBasedProfile == profile.isTimeBasedProfile)
        #expect(decoded.activeDays == profile.activeDays)
    }

    @Test("Schedule description for manual profile")
    func scheduleDescriptionManual() {
        let profile = Profile(name: "Manual")
        #expect(profile.scheduleDescription == "Manual")
    }

    @Test("Schedule description for weekday profile")
    func scheduleDescriptionWeekdays() {
        var profile = Profile(name: "Work")
        profile.isTimeBasedProfile = true
        profile.activeDays = [2, 3, 4, 5, 6] // Mon-Fri

        let calendar = Calendar.current
        profile.startTime = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date())
        profile.endTime = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: Date())

        #expect(profile.scheduleDescription.contains("Weekdays"))
    }

    @Test("Schedule description for weekend profile")
    func scheduleDescriptionWeekends() {
        var profile = Profile(name: "Home")
        profile.isTimeBasedProfile = true
        profile.activeDays = [1, 7] // Sun, Sat

        let calendar = Calendar.current
        profile.startTime = calendar.date(bySettingHour: 10, minute: 0, second: 0, of: Date())
        profile.endTime = calendar.date(bySettingHour: 22, minute: 0, second: 0, of: Date())

        #expect(profile.scheduleDescription.contains("Weekends"))
    }

    @Test("Schedule description for every day")
    func scheduleDescriptionEveryDay() {
        var profile = Profile(name: "Always")
        profile.isTimeBasedProfile = true
        profile.activeDays = [1, 2, 3, 4, 5, 6, 7]

        let calendar = Calendar.current
        profile.startTime = calendar.date(bySettingHour: 0, minute: 0, second: 0, of: Date())
        profile.endTime = calendar.date(bySettingHour: 23, minute: 59, second: 0, of: Date())

        #expect(profile.scheduleDescription.contains("Every day"))
    }

    @Test("isActiveNow returns false for manual profile")
    func isActiveNowManual() {
        let profile = Profile(name: "Manual")
        #expect(!profile.isActiveNow())
    }

    @Test("isActiveNow returns true when schedule matches")
    func isActiveNowMatches() {
        let calendar = Calendar.current
        let now = Date()
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)

        var profile = Profile(name: "Current")
        profile.isTimeBasedProfile = true
        profile.activeDays = Set([weekday])
        profile.startTime = calendar.date(bySettingHour: max(0, hour - 1), minute: 0, second: 0, of: now)
        profile.endTime = calendar.date(bySettingHour: min(23, hour + 1), minute: 0, second: 0, of: now)

        #expect(profile.isActiveNow())
    }
}
