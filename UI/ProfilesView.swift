import SwiftUI

// MARK: - ProfilesView

/// View for managing menu bar configuration profiles
struct ProfilesView: View {
    @ObservedObject var menuBarManager: MenuBarManager
    @StateObject private var profileService = ProfileService.shared
    @State private var isAddingProfile = false
    @State private var editingProfile: Profile?
    @State private var showDeleteConfirmation = false
    @State private var profileToDelete: Profile?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                profilesList
            }
            .padding()
        }
        .sheet(isPresented: $isAddingProfile) {
            ProfileEditorView(
                profile: Profile(name: "New Profile"),
                menuBarManager: menuBarManager,
                isNew: true
            ) { newProfile in
                profileService.addProfile(newProfile)
            }
        }
        .sheet(item: $editingProfile) { profile in
            ProfileEditorView(
                profile: profile,
                menuBarManager: menuBarManager,
                isNew: false
            ) { updatedProfile in
                profileService.updateProfile(updatedProfile)
            }
        }
        .alert("Delete Profile", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let profile = profileToDelete {
                    profileService.deleteProfile(profile)
                }
            }
        } message: {
            if let profile = profileToDelete {
                Text("Are you sure you want to delete '\(profile.name)'?")
            }
        }
        .onAppear {
            profileService.loadProfiles()
        }
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Profiles")
                    .font(.headline)

                Text("Create different configurations for work, home, or focus time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                isAddingProfile = true
            } label: {
                Label("Add Profile", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Profiles List

    private var profilesList: some View {
        VStack(spacing: 12) {
            ForEach(profileService.profiles) { profile in
                ProfileRow(
                    profile: profile,
                    isActive: profileService.activeProfile?.id == profile.id,
                    onActivate: {
                        profileService.setActiveProfile(profile)
                        applyProfile(profile)
                    },
                    onEdit: {
                        editingProfile = profile
                    },
                    onDelete: {
                        profileToDelete = profile
                        showDeleteConfirmation = true
                    }
                )
            }
        }
    }

    // MARK: - Actions

    private func applyProfile(_ profile: Profile) {
        // Apply the profile's item sections to the menu bar manager
        for (key, section) in profile.itemSections {
            if let item = menuBarManager.statusItems.first(where: { $0.compositeKey == key }) {
                menuBarManager.updateItem(item, section: section)
            }
        }
    }
}

// MARK: - ProfileRow

private struct ProfileRow: View {
    let profile: Profile
    let isActive: Bool
    let onActivate: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Active indicator
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(isActive ? .green : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(profile.name)
                        .font(.body)
                        .fontWeight(isActive ? .semibold : .regular)

                    if profile.isTimeBasedProfile {
                        Image(systemName: "clock")
                            .font(.caption)
                            .foregroundStyle(.blue)
                    }
                }

                if profile.isTimeBasedProfile {
                    Text(profile.scheduleDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(profile.itemSections.count) custom settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 8) {
                if !isActive {
                    Button("Activate") {
                        onActivate()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Button {
                    onEdit()
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.red)
                .disabled(ProfileService.shared.profiles.count <= 1)
            }
        }
        .padding()
        .background(isActive ? Color.accentColor.opacity(0.1) : Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - ProfileEditorView

struct ProfileEditorView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var profile: Profile
    let menuBarManager: MenuBarManager
    let isNew: Bool
    let onSave: (Profile) -> Void

    init(
        profile: Profile,
        menuBarManager: MenuBarManager,
        isNew: Bool,
        onSave: @escaping (Profile) -> Void
    ) {
        _profile = State(initialValue: profile)
        self.menuBarManager = menuBarManager
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Text(isNew ? "New Profile" : "Edit Profile")
                    .font(.headline)

                Spacer()

                Button("Save") {
                    saveProfile()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(profile.name.isEmpty)
            }
            .padding()

            Divider()

            // Content
            Form {
                Section("Profile Info") {
                    TextField("Name", text: $profile.name)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Schedule") {
                    Toggle("Time-based switching", isOn: $profile.isTimeBasedProfile)

                    if profile.isTimeBasedProfile {
                        timeScheduleSection
                        dayPickerSection
                    }
                }

                if !isNew {
                    Section("Current Items") {
                        Text("This profile will use the current item configuration when saved.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button("Capture Current Layout") {
                            captureCurrentLayout()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
            .formStyle(.grouped)
            .padding()
        }
        .frame(width: 400, height: profile.isTimeBasedProfile ? 500 : 300)
    }

    // MARK: - Time Schedule Section

    private var timeScheduleSection: some View {
        HStack(spacing: 20) {
            VStack(alignment: .leading) {
                Text("Start Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DatePicker(
                    "",
                    selection: Binding(
                        get: { profile.startTime ?? defaultStartTime },
                        set: { profile.startTime = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
            }

            VStack(alignment: .leading) {
                Text("End Time")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                DatePicker(
                    "",
                    selection: Binding(
                        get: { profile.endTime ?? defaultEndTime },
                        set: { profile.endTime = $0 }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .labelsHidden()
            }
        }
    }

    private var defaultStartTime: Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private var defaultEndTime: Date {
        Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date()
    }

    // MARK: - Day Picker Section

    private var dayPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Active Days")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(1...7, id: \.self) { day in
                    DayButton(
                        day: day,
                        isSelected: profile.activeDays.contains(day)
                    ) {
                        toggleDay(day)
                    }
                }
            }

            // Quick presets
            HStack(spacing: 12) {
                Button("Weekdays") {
                    profile.activeDays = [2, 3, 4, 5, 6] // Mon-Fri
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Weekends") {
                    profile.activeDays = [1, 7] // Sun, Sat
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Every Day") {
                    profile.activeDays = [1, 2, 3, 4, 5, 6, 7]
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func toggleDay(_ day: Int) {
        if profile.activeDays.contains(day) {
            profile.activeDays.remove(day)
        } else {
            profile.activeDays.insert(day)
        }
    }

    // MARK: - Actions

    private func captureCurrentLayout() {
        var sections: [String: StatusItemModel.ItemSection] = [:]
        for item in menuBarManager.statusItems {
            sections[item.compositeKey] = item.section
        }
        profile.itemSections = sections
    }

    private func saveProfile() {
        // If new, capture current layout
        if isNew {
            captureCurrentLayout()
        }

        onSave(profile)
        dismiss()
    }
}

// MARK: - DayButton

private struct DayButton: View {
    let day: Int
    let isSelected: Bool
    let action: () -> Void

    private var dayAbbreviation: String {
        switch day {
        case 1: return "S"
        case 2: return "M"
        case 3: return "T"
        case 4: return "W"
        case 5: return "T"
        case 6: return "F"
        case 7: return "S"
        default: return "?"
        }
    }

    var body: some View {
        Button {
            action()
        } label: {
            Text(dayAbbreviation)
                .font(.caption)
                .fontWeight(.medium)
                .frame(width: 28, height: 28)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.2))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    ProfilesView(menuBarManager: MenuBarManager.shared)
        .frame(width: 500, height: 400)
}
