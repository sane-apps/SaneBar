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
        SaneSettingsPage {
                CompactSection("Automatic Triggers") {
                    if licenseService.isPro {
                        CompactToggle(label: "Show on Low Battery", isOn: $menuBarManager.settings.showOnLowBattery)
                            .help("Reveal battery and power icons when battery is low")

                        if menuBarManager.settings.showOnLowBattery {
                            CompactRow("Threshold") {
                                HStack(spacing: 8) {
                                    Slider(
                                        value: Binding(
                                            get: { Double(menuBarManager.settings.batteryThreshold) },
                                            set: { menuBarManager.settings.batteryThreshold = Int($0) }
                                        ),
                                        in: 5 ... 50,
                                        step: 5
                                    )
                                    .frame(width: 100)
                                    Text("\(menuBarManager.settings.batteryThreshold)%")
                                        .font(SaneTypography.body)
                                        .frame(width: 36, alignment: .trailing)
                                }
                            }

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
                        CompactToggle(label: "Show when specific apps open", isOn: $menuBarManager.settings.showOnAppLaunch)
                            .help("Reveal icons when certain apps are launched")

                        if menuBarManager.settings.showOnAppLaunch {
                            CompactDivider()
                            AppPickerView(
                                selectedBundleIDs: $menuBarManager.settings.triggerApps,
                                title: "Select Apps"
                            )

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
                        CompactToggle(label: "Show on Schedule", isOn: $menuBarManager.settings.showOnSchedule)
                            .help("Reveal icons when local time enters selected day/time window")

                        if menuBarManager.settings.showOnSchedule {
                            CompactRow("Days") {
                                HStack(spacing: 6) {
                                    ForEach(scheduleWeekdayOptions, id: \.day) { option in
                                        ChromeSegmentedChoiceButton(
                                            title: option.label,
                                            isSelected: menuBarManager.settings.scheduleWeekdays.contains(option.day)
                                        ) {
                                            toggleScheduleDay(option.day)
                                        }
                                    }
                                }
                                .fixedSize(horizontal: true, vertical: false)
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
                            SaneInlineHelp("Set the same start/end time for all-day schedule.")

                            triggerActionControls(
                                action: $menuBarManager.settings.scheduleTriggerAction,
                                profileId: $menuBarManager.settings.scheduleTriggerProfileId
                            )
                        }
                    } else {
                        proTriggerRow(
                            label: "Show on Schedule",
                            help: "Reveal hidden icons only during selected days and time windows"
                        )
                    }

                    CompactDivider()

                    if licenseService.isPro {
                        CompactToggle(label: "Show on Wi-Fi Change", isOn: $menuBarManager.settings.showOnNetworkChange)
                            .help("Reveal icons when connecting to specific Wi-Fi networks")

                        if menuBarManager.settings.showOnNetworkChange {
                            if let ssid = menuBarManager.networkTriggerService.currentSSID {
                                CompactRow("Current network") {
                                    Button("Add \(ssid)") {
                                        if !menuBarManager.settings.triggerNetworks.contains(ssid) {
                                            menuBarManager.settings.triggerNetworks.append(ssid)
                                        }
                                    }
                                    .buttonStyle(ChromeActionButtonStyle())
                                }
                            }

                            ForEach(menuBarManager.settings.triggerNetworks, id: \.self) { network in
                                CompactDivider()
                                CompactRow(network) {
                                    Button {
                                        menuBarManager.settings.triggerNetworks.removeAll { $0 == network }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white.opacity(0.9))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove this network")
                                }
                            }

                            triggerActionControls(
                                action: $menuBarManager.settings.networkTriggerAction,
                                profileId: $menuBarManager.settings.networkTriggerProfileId
                            )
                        }
                    } else {
                        proTriggerRow(
                            label: "Show on Wi-Fi Change",
                            help: "Reveal selected icons when your Mac joins specific Wi-Fi networks"
                        )
                    }

                    CompactDivider()

                    if licenseService.isPro {
                        CompactToggle(label: "Show on Focus Mode Change", isOn: $menuBarManager.settings.showOnFocusModeChange)
                            .help("Reveal icons when entering or exiting specific Focus Modes")

                        if menuBarManager.settings.showOnFocusModeChange {
                            if let currentMode = menuBarManager.focusModeService.currentFocusMode {
                                CompactRow("Current Focus") {
                                    Button("Add \(currentMode)") {
                                        if !menuBarManager.settings.triggerFocusModes.contains(currentMode) {
                                            menuBarManager.settings.triggerFocusModes.append(currentMode)
                                        }
                                    }
                                    .buttonStyle(ChromeActionButtonStyle())
                                }
                            }

                            if !menuBarManager.settings.triggerFocusModes.contains("(Focus Off)") {
                                CompactRow("When Focus is off") {
                                    Button("Add") {
                                        menuBarManager.settings.triggerFocusModes.append("(Focus Off)")
                                    }
                                    .buttonStyle(ChromeActionButtonStyle())
                                }
                            }

                            ForEach(menuBarManager.settings.triggerFocusModes, id: \.self) { mode in
                                CompactDivider()
                                CompactRow(mode) {
                                    Button {
                                        menuBarManager.settings.triggerFocusModes.removeAll { $0 == mode }
                                    } label: {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundStyle(.white.opacity(0.9))
                                    }
                                    .buttonStyle(.plain)
                                    .help("Remove this Focus Mode")
                                }
                            }

                            if menuBarManager.settings.triggerFocusModes.isEmpty {
                                SaneInlineHelp("No Focus Modes configured. Enable a Focus Mode in System Settings to add it here.")
                            }

                            triggerActionControls(
                                action: $menuBarManager.settings.focusTriggerAction,
                                profileId: $menuBarManager.settings.focusTriggerProfileId
                            )
                        }
                    } else {
                        proTriggerRow(
                            label: "Show on Focus Mode Change",
                            help: "Reveal selected icons when Focus turns on, changes, or turns off"
                        )
                    }

                    CompactDivider()

                    if licenseService.isPro {
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
        .sheet(item: $proUpsellFeature) { feature in
            ProUpsellView(feature: feature)
        }
        .onAppear {
            savedProfiles = menuBarManager.profileWorkflow.savedProfiles()
        }
    }


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
        CompactRow(label) {
            Button {
                proUpsellFeature = .advancedTriggers
            } label: {
                ChromeBadge(title: "Pro", systemImage: "lock.fill")
            }
            .buttonStyle(.plain)
        }
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
                .fixedSize(horizontal: true, vertical: false)
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
                }
            }
        }
    }

    private func selectedProfileName(_ id: UUID?) -> String {
        guard let id,
              let profile = savedProfiles.first(where: { $0.id == id }) else {
            return savedProfiles.isEmpty ? "No Profiles" : "Choose Profile"
        }
        return profile.name
    }
}


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
        CompactRow("Script") {
            HStack(spacing: 8) {
                TextField("Script path", text: $menuBarManager.settings.scriptTriggerPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 0, maxWidth: 180)

                scriptPathStatusIcon

                Button("Browse…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.unixExecutable, .shellScript, .script, .plainText]
                    panel.canChooseDirectories = false
                    panel.allowsMultipleSelection = false
                    panel.message = "Select a script (must be executable)"

                    if panel.runModal() == .OK, let url = panel.url {
                        menuBarManager.settings.scriptTriggerPath = url.path
                    }
                }
                .buttonStyle(ChromeActionButtonStyle())
            }
        }

        CompactRow("Check every") {
            HStack(spacing: 8) {
                Text(intervalLabel)
                    .frame(width: 40, alignment: .trailing)
                Stepper("", value: $menuBarManager.settings.scriptTriggerInterval, in: 1 ... 60, step: 1)
                    .labelsHidden()
            }
        }

        CompactRow("Test") {
            HStack(spacing: 8) {
                Button("Run Now") {
                    runTestScript()
                }
                .buttonStyle(ChromeActionButtonStyle())
                .disabled(scriptPathStatus != .ready)

                if let testResult {
                    Text(testResult)
                        .font(SaneTypography.body)
                        .foregroundStyle(testResult.hasPrefix("Exit 0") ? .green : .orange)
                        .lineLimit(1)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        SaneInlineHelp("Exit code 0 = show hidden icons, non-zero = hide.")
    }

    @ViewBuilder
    private var scriptPathStatusIcon: some View {
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
