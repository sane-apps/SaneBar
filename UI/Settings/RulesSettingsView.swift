import AppKit
import SwiftUI

struct RulesSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared

    // MARK: - User-Friendly Labels (instead of "s" and "ms" jargon)

    private var rehideDelayLabel: String {
        let value = Int(menuBarManager.settings.rehideDelay)
        switch value {
        case 1 ... 5: return "Quick (\(value)s)"
        case 6 ... 15: return "Normal (\(value)s)"
        case 16 ... 30: return "Leisurely (\(value)s)"
        default: return "Extended (\(value)s)"
        }
    }

    private var findIconDelayLabel: String {
        let value = Int(menuBarManager.settings.findIconRehideDelay)
        switch value {
        case 1 ... 5: return "Quick (\(value)s)"
        case 6 ... 15: return "Normal (\(value)s)"
        case 16 ... 30: return "Leisurely (\(value)s)"
        default: return "Extended (\(value)s)"
        }
    }

    private var hoverDelayLabel: String {
        let ms = Int(menuBarManager.settings.hoverDelay * 1000)
        switch ms {
        case 0 ... 150: return "Instant"
        case 151 ... 350: return "Quick"
        case 351 ... 600: return "Normal"
        default: return "Patient"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // 1. Behavior (Hiding)
                CompactSection("Hiding Behavior") {
                    CompactToggle(label: "Hide icons automatically", isOn: $menuBarManager.settings.autoRehide)
                        .help("Automatically hide icons after a delay when revealed")

                    if menuBarManager.settings.autoRehide {
                        CompactDivider()
                        CompactRow("Wait before hiding") {
                            HStack {
                                Text(rehideDelayLabel)
                                    .frame(width: 95, alignment: .trailing)
                                Stepper("", value: $menuBarManager.settings.rehideDelay, in: 1 ... 60, step: 1)
                                    .labelsHidden()
                                    .help("How long to wait before hiding icons again")
                            }
                        }
                        CompactDivider()
                        CompactRow("Wait after Find Icon") {
                            HStack {
                                Text(findIconDelayLabel)
                                    .frame(width: 95, alignment: .trailing)
                                Stepper("", value: $menuBarManager.settings.findIconRehideDelay, in: 5 ... 60, step: 5)
                                    .labelsHidden()
                                    .help("Extra time to browse after using Find Icon")
                            }
                        }
                        CompactDivider()
                        CompactToggle(
                            label: "Hide when app changes",
                            isOn: $menuBarManager.settings.rehideOnAppChange
                        )
                        .help("Auto-hide when you switch to a different app")
                    }

                    CompactDivider()
                    CompactToggle(
                        label: "Always show on external monitors",
                        isOn: $menuBarManager.settings.disableOnExternalMonitor
                    )
                    .help("External monitors have plenty of space—keep icons visible")
                }

                // 2. Gestures (Revealing)
                CompactSection("Revealing") {
                    CompactToggle(label: "Show when mouse hovers top edge", isOn: $menuBarManager.settings.showOnHover)
                        .help("Reveal hidden icons when your mouse moves to the top of the screen")

                    if menuBarManager.settings.showOnHover {
                        CompactDivider()
                        CompactRow("Hover Delay") {
                            HStack {
                                Slider(value: $menuBarManager.settings.hoverDelay, in: 0.05 ... 1.0, step: 0.05)
                                    .frame(width: 80)
                                    .help("How long to hover before icons appear")
                                Text(hoverDelayLabel)
                                    .frame(width: 55, alignment: .trailing)
                            }
                        }
                    }

                    CompactDivider()
                    CompactToggle(label: "Show when scrolling on menu bar", isOn: $menuBarManager.settings.showOnScroll)
                        .help("Scroll on the menu bar to reveal or hide icons")

                    // Gesture behavior picker - only show if scroll is enabled
                    if menuBarManager.settings.showOnScroll {
                        CompactDivider()
                        CompactRow("Gesture behavior") {
                            Picker("", selection: $menuBarManager.settings.gestureMode) {
                                ForEach(SaneBarSettings.GestureMode.allCases, id: \.self) { mode in
                                    Text(mode.rawValue).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 180)
                            .help("Show only: gestures only reveal. Show and hide: gestures toggle visibility")
                        }
                        Text(menuBarManager.settings.gestureMode == .showOnly
                            ? "Gestures reveal hidden icons"
                            : "Click toggles, scroll up shows, scroll down hides")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 4)
                    }

                    CompactDivider()

                    // Show on user drag (Ice-style) - reveal all when ⌘+dragging to rearrange
                    CompactToggle(
                        label: "Show when rearranging icons",
                        isOn: $menuBarManager.settings.showOnUserDrag
                    )
                    .help("Reveal all icons while ⌘+dragging to rearrange")
                }

                // 3. Triggers (Automation)
                CompactSection("Automatic Triggers") {
                    // Battery
                    CompactToggle(label: "Show on Low Battery", isOn: $menuBarManager.settings.showOnLowBattery)
                        .help("Reveal battery and power icons when battery is low")

                    CompactDivider()

                    // App Launch
                    CompactToggle(label: "Show when specific apps open", isOn: $menuBarManager.settings.showOnAppLaunch)
                        .help("Reveal icons when certain apps are launched")

                    if menuBarManager.settings.showOnAppLaunch {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("If these apps open:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .padding(.leading, 4)

                            AppPickerView(
                                selectedBundleIDs: $menuBarManager.settings.triggerApps,
                                title: "Select Apps"
                            )
                            .padding(.horizontal, 4)
                        }
                        .padding(.vertical, 8)
                    }

                    CompactDivider()

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
                                .buttonStyle(.bordered)
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
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }

                    CompactDivider()

                    // Focus Mode
                    CompactToggle(label: "Show on Focus Mode Change", isOn: $menuBarManager.settings.showOnFocusModeChange)
                        .help("Reveal icons when entering or exiting specific Focus Modes")

                    if menuBarManager.settings.showOnFocusModeChange {
                        VStack(alignment: .leading, spacing: 8) {
                            // Add current Focus Mode button
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
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            // Add "(Focus Off)" option
                            if !menuBarManager.settings.triggerFocusModes.contains("(Focus Off)") {
                                Button {
                                    menuBarManager.settings.triggerFocusModes.append("(Focus Off)")
                                } label: {
                                    HStack {
                                        Image(systemName: "moon")
                                        Text("Add: (Focus Off)")
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            // List of configured trigger modes
                            ForEach(menuBarManager.settings.triggerFocusModes, id: \.self) { mode in
                                HStack {
                                    Image(systemName: mode == "(Focus Off)" ? "moon" : "moon.fill")
                                        .foregroundStyle(.secondary)
                                    Text(mode)
                                    Spacer()
                                    Button {
                                        menuBarManager.settings.triggerFocusModes.removeAll { $0 == mode }
                                    } label: {
                                        Image(systemName: "xmark")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(8)
                                .background(Color.secondary.opacity(0.1))
                                .cornerRadius(6)
                            }

                            if menuBarManager.settings.triggerFocusModes.isEmpty {
                                Text("No Focus Modes configured. Enable a Focus Mode in System Settings to add it here.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                        .padding(.horizontal, 4)
                    }

                    CompactDivider()

                    // Script Trigger
                    CompactToggle(label: "Let a script control visibility", isOn: $menuBarManager.settings.scriptTriggerEnabled)
                        .help("Run a script on a timer — exit 0 shows icons, non-zero hides")

                    if menuBarManager.settings.scriptTriggerEnabled {
                        ScriptTriggerSettingsView()
                    }
                }
            }
            .padding(20)
        }
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
        let path = menuBarManager.settings.scriptTriggerPath.trimmingCharacters(in: .whitespacesAndNewlines)
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
                        .font(.caption)
                        .foregroundStyle(testResult.hasPrefix("Exit 0") ? .green : .orange)
                }
            }

            Text("Exit code 0 = show hidden icons, non-zero = hide.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }

    private func runTestScript() {
        let path = menuBarManager.settings.scriptTriggerPath.trimmingCharacters(in: .whitespacesAndNewlines)
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
