import AppKit
import SaneUI
import SwiftUI

struct RulesSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @ObservedObject private var licenseService = LicenseService.shared
    @State private var proUpsellFeature: ProFeature?
    @State private var savedProfiles: [SaneBarProfile] = []

    private var scheduleStartLabel: String {
        formatScheduleTime(hour: menuBarManager.settings.scheduleStartHour, minute: menuBarManager.settings.scheduleStartMinute)
    }

    private var scheduleEndLabel: String {
        formatScheduleTime(hour: menuBarManager.settings.scheduleEndHour, minute: menuBarManager.settings.scheduleEndMinute)
    }

    private let scheduleWeekdayOptions: [(day: Int, label: String)] = [
        (1, "Su"), (2, "Mo"), (3, "Tu"), (4, "We"), (5, "Th"), (6, "Fr"), (7, "Sa")
    ]

    private func formatScheduleTime(hour: Int, minute: Int) -> String {
        let clampedHour = min(max(hour, 0), 23)
        let clampedMinute = min(max(minute, 0), 59)
        return String(format: "%02d:%02d", clampedHour, clampedMinute)
    }

    private func toggleScheduleDay(_ day: Int) {
        if menuBarManager.settings.scheduleWeekdays.contains(day) {
            menuBarManager.settings.scheduleWeekdays.removeAll { $0 == day }
        } else {
            menuBarManager.settings.scheduleWeekdays.append(day)
            menuBarManager.settings.scheduleWeekdays.sort()
        }
    }

    private func segmentedChoiceButton(
        _ title: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        ChromeSegmentedChoiceButton(title: title, isSelected: isSelected, action: action)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Triggers (Automation) — Pro
                CompactSection("Automatic Triggers") {
                    if licenseService.isPro {
                        // Battery
                        CompactToggle(label: "Show on Low Battery", isOn: $menuBarManager.settings.showOnLowBattery)
                            .help("Reveal battery and power icons when battery is low")

                        if menuBarManager.settings.showOnLowBattery {
                            HStack(spacing: 8) {
                                Text("Threshold:")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.92))
                                Slider(
                                    value: Binding(
                                        get: { Double(menuBarManager.settings.batteryThreshold) },
                                        set: { menuBarManager.settings.batteryThreshold = Int($0) }
                                    ),
                                    in: 5 ... 50,
                                    step: 5
                                )
                                Text("\(menuBarManager.settings.batteryThreshold)%")
                                    .font(.system(size: 13, design: .monospaced))
                                    .frame(width: 36, alignment: .trailing)
                            }
                            .padding(.leading, 4)

                            triggerActionControls(
                                action: $menuBarManager.settings.batteryTriggerAction,
                                profileId: $menuBarManager.settings.batteryTriggerProfileId
                            )
                        }
                    } else {
                        proTriggerRow(
                            label: "Show on Low Battery",
                            help: "Reveal battery and power icons automatically when battery is low"
                        )
                    }

                    CompactDivider()

                    if licenseService.isPro {
                        // App Launch
                        CompactToggle(label: "Show when specific apps open", isOn: $menuBarManager.settings.showOnAppLaunch)
                            .help("Reveal icons when certain apps are launched")

                        if menuBarManager.settings.showOnAppLaunch {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("If these apps open:")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.white.opacity(0.92))
                                    .padding(.leading, 4)

                                AppPickerView(
                                    selectedBundleIDs: $menuBarManager.settings.triggerApps,
                                    title: "Select Apps"
                                )
                                .padding(.horizontal, 4)
                            }
                            .padding(.vertical, 8)

                            triggerActionControls(
                                action: $menuBarManager.settings.appLaunchTriggerAction,
                                profileId: $menuBarManager.settings.appLaunchTriggerProfileId
                            )
                        }
                    } else {
                        proTriggerRow(
                            label: "Show when specific apps open",
                            help: "Reveal chosen menu bar icons automatically when selected apps launch"
                        )
                    }

                    CompactDivider()

                    if licenseService.isPro {
                        // Schedule
                        CompactToggle(label: "Show on Schedule", isOn: $menuBarManager.settings.showOnSchedule)
                            .help("Reveal icons when local time enters selected day/time window")

                        if menuBarManager.settings.showOnSchedule {
                            VStack(alignment: .leading, spacing: 10) {
                                CompactRow("Days") {
                                    HStack(spacing: 6) {
                                        ForEach(scheduleWeekdayOptions, id: \.day) { option in
                                            let isSelected = menuBarManager.settings.scheduleWeekdays.contains(option.day)
                                            Button(option.label) {
                                                toggleScheduleDay(option.day)
                                            }
                                            .buttonStyle(.plain)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(isSelected ? .white : .white.opacity(0.92))
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                Capsule()
                                                    .fill(isSelected ? Color.saneAccent : Color.primary.opacity(0.12))
                                            )
                                        }
                                    }
                                }

                                CompactRow("From") {
                                    HStack(spacing: 8) {
                                        Text(scheduleStartLabel)
                                            .frame(width: 52, alignment: .trailing)
                                        Stepper("", value: $menuBarManager.settings.scheduleStartHour, in: 0 ... 23, step: 1)
                                            .labelsHidden()
                                    }
                                }

                                CompactRow("To") {
                                    HStack(spacing: 8) {
                                        Text(scheduleEndLabel)
                                            .frame(width: 52, alignment: .trailing)
                                        Stepper("", value: $menuBarManager.settings.scheduleEndHour, in: 0 ... 23, step: 1)
                                            .labelsHidden()
                                    }
                                }

                                Text("Set the same start/end time for all-day schedule.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.white.opacity(0.9))
                                    .padding(.leading, 4)

                                triggerActionControls(
                                    action: $menuBarManager.settings.scheduleTriggerAction,
                                    profileId: $menuBarManager.settings.scheduleTriggerProfileId
                                )
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        }
                    } else {
                        proTriggerRow(
                            label: "Show on Schedule",
                            help: "Reveal hidden icons only during selected days and time windows"
                        )
                    }

                    CompactDivider()

                    if licenseService.isPro {
                        // Network
                        CompactToggle(label: "Show on Wi-Fi Change", isOn: $menuBarManager.settings.showOnNetworkChange)
                            .help("Reveal icons when connecting to specific Wi-Fi networks")

                        if menuBarManager.settings.showOnNetworkChange {
                            VStack(alignment: .leading, spacing: 8) {
                                if let ssid = menuBarManager.networkTriggerService.currentSSID {
                                    Button {
                                        if !menuBarManager.settings.triggerNetworks.contains(ssid) {
                                            menuBarManager.settings.triggerNetworks.append(ssid)
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: "wifi")
                                            Text("Add current: \(ssid)")
                                        }
                                    }
                                    .buttonStyle(ChromeActionButtonStyle())
                                    .controlSize(.small)
                                }

                                ForEach(menuBarManager.settings.triggerNetworks, id: \.self) { network in
                                    HStack {
                                        Text(network)
                                        Spacer()
                                        Button {
                                            menuBarManager.settings.triggerNetworks.removeAll { $0 == network }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .foregroundStyle(.white.opacity(0.9))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(8)
                                    .background(Color.primary.opacity(0.1))
                                    .cornerRadius(6)
                                }

                                triggerActionControls(
                                    action: $menuBarManager.settings.networkTriggerAction,
                                    profileId: $menuBarManager.settings.networkTriggerProfileId
                                )
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        }
                    } else {
                        proTriggerRow(
                            label: "Show on Wi-Fi Change",
                            help: "Reveal selected icons when your Mac joins specific Wi-Fi networks"
                        )
                    }

                    CompactDivider()

                    if licenseService.isPro {
                        // Focus Mode
                        CompactToggle(label: "Show on Focus Mode Change", isOn: $menuBarManager.settings.showOnFocusModeChange)
                            .help("Reveal icons when entering or exiting specific Focus Modes")

                        if menuBarManager.settings.showOnFocusModeChange {
                            VStack(alignment: .leading, spacing: 8) {
                                if let currentMode = menuBarManager.focusModeService.currentFocusMode {
                                    Button {
                                        if !menuBarManager.settings.triggerFocusModes.contains(currentMode) {
                                            menuBarManager.settings.triggerFocusModes.append(currentMode)
                                        }
                                    } label: {
                                        HStack {
                                            Image(systemName: "moon.fill")
                                            Text("Add current: \(currentMode)")
                                        }
                                    }
                                    .buttonStyle(ChromeActionButtonStyle())
                                    .controlSize(.small)
                                }

                                if !menuBarManager.settings.triggerFocusModes.contains("(Focus Off)") {
                                    Button {
                                        menuBarManager.settings.triggerFocusModes.append("(Focus Off)")
                                    } label: {
                                        HStack {
                                            Image(systemName: "moon")
                                            Text("Add: (Focus Off)")
                                        }
                                    }
                                    .buttonStyle(ChromeActionButtonStyle())
                                    .controlSize(.small)
                                }

                                ForEach(menuBarManager.settings.triggerFocusModes, id: \.self) { mode in
                                    HStack {
                                        Image(systemName: mode == "(Focus Off)" ? "moon" : "moon.fill")
                                            .foregroundStyle(.white.opacity(0.9))
                                        Text(mode)
                                        Spacer()
                                        Button {
                                            menuBarManager.settings.triggerFocusModes.removeAll { $0 == mode }
                                        } label: {
                                            Image(systemName: "xmark")
                                                .foregroundStyle(.white.opacity(0.9))
                                        }
                                        .buttonStyle(.plain)
                                    }
                                    .padding(8)
                                    .background(Color.primary.opacity(0.1))
                                    .cornerRadius(6)
                                }

                                if menuBarManager.settings.triggerFocusModes.isEmpty {
                                    Text("No Focus Modes configured. Enable a Focus Mode in System Settings to add it here.")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white.opacity(0.92))
                                }

                                triggerActionControls(
                                    action: $menuBarManager.settings.focusTriggerAction,
                                    profileId: $menuBarManager.settings.focusTriggerProfileId
                                )
                            }
                            .padding(.vertical, 8)
                            .padding(.horizontal, 4)
                        }
                    } else {
                        proTriggerRow(
                            label: "Show on Focus Mode Change",
                            help: "Reveal selected icons when Focus turns on, changes, or turns off"
                        )
                    }

                    CompactDivider()

                    if licenseService.isPro {
                        // Script Trigger
                        CompactToggle(label: "Let a script control visibility", isOn: $menuBarManager.settings.scriptTriggerEnabled)
                            .help("Run a script every few seconds. Exit 0 shows icons; any other exit code hides them.")

                        if menuBarManager.settings.scriptTriggerEnabled {
                            ScriptTriggerSettingsView()
                        }
                    } else {
                        proTriggerRow(
                            label: "Let a script control visibility",
                            help: "Run your own script to decide when hidden icons should show or hide"
                        )
                    }
                }
            }
            .padding(20)
        }
        .sheet(item: $proUpsellFeature) { feature in
            ProUpsellView(feature: feature)
        }
        .onAppear {
            savedProfiles = menuBarManager.profileWorkflow.savedProfiles()
        }
    }

    // MARK: - Pro Gating Helper

    private func proGatedRow(feature: ProFeature, label: String) -> some View {
        CompactRow(label) {
            Button {
                proUpsellFeature = feature
            } label: {
                ChromeBadge(title: "Pro", systemImage: "lock.fill")
            }
            .buttonStyle(.plain)
        }
    }

    private func proTriggerRow(label: String, help: String) -> some View {
        Button {
            proUpsellFeature = .advancedTriggers
        } label: {
            CompactRow(label) {
                ChromeBadge(title: "Pro", systemImage: "lock.fill")
            }
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func triggerActionControls(
        action: Binding<SaneBarSettings.TriggerAction>,
        profileId: Binding<UUID?>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            CompactRow("Action") {
                HStack(spacing: 6) {
                    ForEach(SaneBarSettings.TriggerAction.allCases, id: \.self) { option in
                        segmentedChoiceButton(
                            option.rawValue,
                            isSelected: action.wrappedValue == option
                        ) {
                            action.wrappedValue = option
                            if option == .applyProfile, profileId.wrappedValue == nil {
                                profileId.wrappedValue = savedProfiles.first?.id
                            }
                        }
                    }
                }
                .frame(width: 220)
            }

            if action.wrappedValue == .applyProfile {
                CompactRow("Profile") {
                    Menu(selectedProfileName(profileId.wrappedValue)) {
                        if savedProfiles.isEmpty {
                            Button("No saved profiles") {}
                                .disabled(true)
                        } else {
                            ForEach(savedProfiles) { profile in
                                Button(profile.name) {
                                    profileId.wrappedValue = profile.id
                                }
                            }
                        }
                    }
                    .buttonStyle(ChromeActionButtonStyle())
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func selectedProfileName(_ id: UUID?) -> String {
        guard let id,
              let profile = savedProfiles.first(where: { $0.id == id }) else {
            return savedProfiles.isEmpty ? "No Profiles" : "Choose Profile"
        }
        return profile.name
    }
}

// MARK: - Script Trigger Settings

private struct ScriptTriggerSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @State private var testResult: String?

    private var intervalLabel: String {
        let value = Int(menuBarManager.settings.scriptTriggerInterval)
        return "\(value)s"
    }

    private var scriptPathStatus: ScriptPathStatus {
        let path = menuBarManager.settings.scriptTriggerPath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !path.isEmpty else { return .empty }
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return .notFound }
        guard fm.isExecutableFile(atPath: path) else { return .notExecutable }
        return .ready
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Script path with status indicator
            HStack {
                TextField("Script path", text: $menuBarManager.settings.scriptTriggerPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                switch scriptPathStatus {
                case .empty:
                    EmptyView()
                case .ready:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .help("Script found and executable")
                case .notFound:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .help("File not found")
                case .notExecutable:
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .help("File exists but is not executable (run: chmod +x)")
                }

                Button("Browse...") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.unixExecutable, .shellScript, .script, .plainText]
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.message = "Select a script (must be executable)"

                    if panel.runModal() == .OK, let url = panel.url {
                        menuBarManager.settings.scriptTriggerPath = url.path
                    }
                }
                .controlSize(.small)
            }

            // Interval stepper
            CompactRow("Check every") {
                HStack {
                    Text(intervalLabel)
                        .frame(width: 40, alignment: .trailing)
                    Stepper("", value: $menuBarManager.settings.scriptTriggerInterval, in: 1 ... 60, step: 1)
                        .labelsHidden()
                }
            }

            // Test button
            HStack {
                Button("Run Now") {
                    runTestScript()
                }
                .controlSize(.small)
                .disabled(scriptPathStatus != .ready)

                if let testResult {
                    Text(testResult)
                        .font(.system(size: 13))
                        .foregroundStyle(testResult.hasPrefix("Exit 0") ? .green : .orange)
                }
            }

            Text("Exit code 0 = show hidden icons, non-zero = hide.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.92))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private func runTestScript() {
        let path = menuBarManager.settings.scriptTriggerPath.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        guard !path.isEmpty else { return }
        testResult = "Running..."

        Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = []

            do {
                try process.run()
                process.waitUntilExit()
                let code = process.terminationStatus
                await MainActor.run {
                    if code == 0 {
                        testResult = "Exit 0 — would show icons"
                    } else {
                        testResult = "Exit \(code) — would hide icons"
                    }
                }
            } catch {
                await MainActor.run {
                    testResult = "Error: \(error.localizedDescription)"
                }
            }
        }
    }
}

private enum ScriptPathStatus {
    case empty, notFound, notExecutable, ready
}
