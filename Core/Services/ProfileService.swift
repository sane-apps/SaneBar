import Foundation
import Combine

// MARK: - ProfileServiceProtocol

/// @mockable
@MainActor
protocol ProfileServiceProtocol: AnyObject {
    var profiles: [Profile] { get }
    var activeProfile: Profile? { get }

    func loadProfiles()
    func saveProfiles()
    func addProfile(_ profile: Profile)
    func updateProfile(_ profile: Profile)
    func deleteProfile(_ profile: Profile)
    func setActiveProfile(_ profile: Profile?)
    func checkTimeBasedProfiles() -> Profile?
    func startAutoSwitching()
    func stopAutoSwitching()
}

// MARK: - ProfileService

/// Service for managing menu bar configuration profiles with time-based auto-switching
@MainActor
final class ProfileService: ProfileServiceProtocol, ObservableObject {

    // MARK: - Singleton

    static let shared = ProfileService()

    // MARK: - Properties

    @Published private(set) var profiles: [Profile] = []
    @Published private(set) var activeProfile: Profile?

    private let persistenceService: PersistenceServiceProtocol
    private var autoSwitchTimer: Timer?
    private var isAutoSwitchingEnabled = false

    // MARK: - Initialization

    init(persistenceService: PersistenceServiceProtocol = PersistenceService.shared) {
        self.persistenceService = persistenceService
    }

    // MARK: - CRUD Operations

    func loadProfiles() {
        do {
            profiles = try persistenceService.loadProfiles()

            // Load active profile from settings
            let settings = try persistenceService.loadSettings()
            if let activeId = settings.activeProfileId {
                activeProfile = profiles.first { $0.id == activeId }
            } else {
                activeProfile = profiles.first
            }
        } catch {
            // Start with default profile
            let defaultProfile = Profile(name: "Default")
            profiles = [defaultProfile]
            activeProfile = defaultProfile
        }
    }

    func saveProfiles() {
        do {
            try persistenceService.saveProfiles(profiles)
        } catch {
            print("Failed to save profiles: \(error)")
        }
    }

    func addProfile(_ profile: Profile) {
        profiles.append(profile)
        saveProfiles()
    }

    func updateProfile(_ profile: Profile) {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
            saveProfiles()

            // Update active if it was modified
            if activeProfile?.id == profile.id {
                activeProfile = profile
            }
        }
    }

    func deleteProfile(_ profile: Profile) {
        profiles.removeAll { $0.id == profile.id }

        // Ensure at least one profile exists
        if profiles.isEmpty {
            let defaultProfile = Profile(name: "Default")
            profiles = [defaultProfile]
        }

        // Switch active if deleted
        if activeProfile?.id == profile.id {
            activeProfile = profiles.first
            saveActiveProfileId()
        }

        saveProfiles()
    }

    func setActiveProfile(_ profile: Profile?) {
        activeProfile = profile
        saveActiveProfileId()

        // Post notification for UI to update
        NotificationCenter.default.post(name: .profileDidChange, object: profile)
    }

    private func saveActiveProfileId() {
        do {
            var settings = try persistenceService.loadSettings()
            settings.activeProfileId = activeProfile?.id
            try persistenceService.saveSettings(settings)
        } catch {
            print("Failed to save active profile ID: \(error)")
        }
    }

    // MARK: - Time-Based Switching

    /// Check if any time-based profile should be active now
    func checkTimeBasedProfiles() -> Profile? {
        let now = Date()
        let calendar = Calendar.current

        // Get current day of week (1 = Sunday, 7 = Saturday)
        let weekday = calendar.component(.weekday, from: now)

        for profile in profiles where profile.isTimeBasedProfile {
            // Check if today is an active day
            guard profile.activeDays.contains(weekday) else { continue }

            // Check if current time is within the profile's time range
            guard let startTime = profile.startTime,
                  let endTime = profile.endTime else { continue }

            let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
            let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
            let nowComponents = calendar.dateComponents([.hour, .minute], from: now)

            guard let startHour = startComponents.hour,
                  let startMinute = startComponents.minute,
                  let endHour = endComponents.hour,
                  let endMinute = endComponents.minute,
                  let nowHour = nowComponents.hour,
                  let nowMinute = nowComponents.minute else { continue }

            let startMinutes = startHour * 60 + startMinute
            let endMinutes = endHour * 60 + endMinute
            let nowMinutes = nowHour * 60 + nowMinute

            // Handle overnight ranges (e.g., 22:00 - 06:00)
            let isInRange: Bool
            if startMinutes <= endMinutes {
                // Normal range (e.g., 09:00 - 17:00)
                isInRange = nowMinutes >= startMinutes && nowMinutes < endMinutes
            } else {
                // Overnight range (e.g., 22:00 - 06:00)
                isInRange = nowMinutes >= startMinutes || nowMinutes < endMinutes
            }

            if isInRange {
                return profile
            }
        }

        return nil
    }

    /// Start periodic checking for time-based profile switching
    func startAutoSwitching() {
        guard !isAutoSwitchingEnabled else { return }
        isAutoSwitchingEnabled = true

        // Check every minute
        autoSwitchTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performAutoSwitch()
            }
        }

        // Run once immediately
        performAutoSwitch()
    }

    func stopAutoSwitching() {
        isAutoSwitchingEnabled = false
        autoSwitchTimer?.invalidate()
        autoSwitchTimer = nil
    }

    private func performAutoSwitch() {
        guard let timeBasedProfile = checkTimeBasedProfiles() else {
            // No time-based profile matches - could revert to default
            // For now, we leave the current profile active
            return
        }

        // Only switch if different from current
        if activeProfile?.id != timeBasedProfile.id {
            setActiveProfile(timeBasedProfile)
        }
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let profileDidChange = Notification.Name("profileDidChange")
}

// MARK: - Profile Helpers

extension Profile {
    /// Human-readable schedule description
    var scheduleDescription: String {
        guard isTimeBasedProfile else { return "Manual" }

        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"

        var description = ""

        if let start = startTime, let end = endTime {
            description = "\(formatter.string(from: start)) - \(formatter.string(from: end))"
        }

        if !activeDays.isEmpty {
            let dayNames = activeDays.sorted().compactMap { dayNumber -> String? in
                switch dayNumber {
                case 1: return "Sun"
                case 2: return "Mon"
                case 3: return "Tue"
                case 4: return "Wed"
                case 5: return "Thu"
                case 6: return "Fri"
                case 7: return "Sat"
                default: return nil
                }
            }

            if dayNames.count == 7 {
                description += " (Every day)"
            } else if dayNames.count == 5 && !activeDays.contains(1) && !activeDays.contains(7) {
                description += " (Weekdays)"
            } else if dayNames.count == 2 && activeDays.contains(1) && activeDays.contains(7) {
                description += " (Weekends)"
            } else {
                description += " (\(dayNames.joined(separator: ", ")))"
            }
        }

        return description
    }

    /// Whether the profile is currently active based on time
    func isActiveNow() -> Bool {
        guard isTimeBasedProfile else { return false }

        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)

        guard activeDays.contains(weekday),
              let startTime = startTime,
              let endTime = endTime else { return false }

        let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
        let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
        let nowComponents = calendar.dateComponents([.hour, .minute], from: now)

        guard let startHour = startComponents.hour,
              let startMinute = startComponents.minute,
              let endHour = endComponents.hour,
              let endMinute = endComponents.minute,
              let nowHour = nowComponents.hour,
              let nowMinute = nowComponents.minute else { return false }

        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute
        let nowMinutes = nowHour * 60 + nowMinute

        if startMinutes <= endMinutes {
            return nowMinutes >= startMinutes && nowMinutes < endMinutes
        } else {
            return nowMinutes >= startMinutes || nowMinutes < endMinutes
        }
    }
}
