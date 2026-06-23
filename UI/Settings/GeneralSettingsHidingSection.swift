import SaneUI
import SwiftUI

struct GeneralSettingsHidingSection: View {
    @ObservedObject var menuBarManager: MenuBarManager
    @ObservedObject var licenseService: LicenseService
    let showProUpsell: (ProFeature) -> Void
    @State private var hideAllOtherStatusMessage: String?

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

    private var hideAllOtherMenuBarItemsBinding: Binding<Bool> {
        Binding(
            get: { menuBarManager.settings.hideAllOtherMenuBarItems },
            set: { isEnabled in
                if isEnabled {
                    hideAllOtherStatusMessage = "Checking current menu bar..."
                    menuBarManager.hideAllOtherWorkflow.enableFromCurrentLayout { enabled in
                        hideAllOtherStatusMessage = enabled
                            ? nil
                            : "SaneBar couldn't turn this on safely. Open Health and repair menu bar detection, then try again."
                    }
                } else {
                    hideAllOtherStatusMessage = nil
                    menuBarManager.settings.hideAllOtherMenuBarItems = false
                    menuBarManager.saveSettings()
                }
            }
        )
    }

    private var gestureModeSummary: String {
        menuBarManager.settings.gestureMode == .showOnly
            ? "Gestures reveal hidden icons."
            : "Scroll up shows icons, scroll down hides icons."
    }

    var body: some View {
        CompactSection("Hiding Behavior") {
            CompactToggle(label: "Hide icons automatically", isOn: $menuBarManager.settings.autoRehide)
                .help("Hide revealed icons again after the delay below.")

            if menuBarManager.settings.autoRehide {
                autoRehideRows
            }

            CompactDivider()
            CompactToggle(label: "Reveal hidden icons on hover", isOn: $menuBarManager.settings.showOnHover)
                .help("Hover near the menu bar to reveal hidden icons inline. Click the SaneBar icon to open or toggle manually.")
            if menuBarManager.settings.showOnHover {
                hoverDelayRow
            }

            CompactDivider()
            CompactToggle(label: "Show when scrolling on menu bar", isOn: $menuBarManager.settings.showOnScroll)
            if menuBarManager.settings.showOnScroll {
                scrollGestureRows
            }

            CompactDivider()
            CompactToggle(label: "Show when rearranging icons", isOn: $menuBarManager.settings.showOnUserDrag)

            CompactDivider()
            if licenseService.isPro {
                CompactToggle(label: "Always show on external monitors", isOn: $menuBarManager.settings.disableOnExternalMonitor)
                    .help("Keep icons visible on external displays where menu bar space is less constrained.")
            } else {
                proGatedRow(feature: .autoRehideCustomization, label: "Always show on external monitors")
            }

            CompactDivider()
            CompactToggle(label: "Hide app menus during inline reveal", isOn: $menuBarManager.settings.hideApplicationMenusOnInlineReveal)
                .help("Temporarily hides File/Edit/View if needed to make room in the menu bar. Only affects inline reveal.")

            CompactDivider()
            if licenseService.isPro {
                hideNewUnlistedToggleRow
                    .help("Keep only the explicitly visible items shown; move other detected menu bar items to Hidden.")
                if let hideAllOtherStatusMessage {
                    CompactDivider()
                    Text(hideAllOtherStatusMessage)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.9))
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("sanebar-hide-new-unlisted-status")
                }
            } else {
                proGatedRow(feature: .zoneMoves, label: "Hide new/unlisted items by default")
            }
        }
    }

    private var hideNewUnlistedToggleRow: some View {
        Button {
            hideAllOtherMenuBarItemsBinding.wrappedValue.toggle()
        } label: {
            HStack {
                Text("Hide new/unlisted items by default")
                    .foregroundStyle(.white)
                Spacer()
                Capsule()
                    .fill(menuBarManager.settings.hideAllOtherMenuBarItems ? Color.accentColor : Color.white.opacity(0.22))
                    .overlay(alignment: menuBarManager.settings.hideAllOtherMenuBarItems ? .trailing : .leading) {
                        Circle()
                            .fill(.white)
                            .frame(width: 18, height: 18)
                            .padding(3)
                    }
                    .frame(width: 44, height: 24)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Hide new/unlisted items by default")
        .accessibilityValue(menuBarManager.settings.hideAllOtherMenuBarItems ? "On" : "Off")
        .accessibilityIdentifier("sanebar-hide-new-unlisted-toggle")
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var autoRehideRows: some View {
        Group {
            if licenseService.isPro {
                CompactDivider()
                CompactRow("Wait before hiding") {
                    HStack {
                        Text(rehideDelayLabel)
                            .frame(width: 95, alignment: .trailing)
                        Stepper("", value: $menuBarManager.settings.rehideDelay, in: 1 ... 60, step: 1)
                            .labelsHidden()
                    }
                }
                CompactDivider()
                CompactRow("Wait after Browse Icons") {
                    HStack {
                        Text(findIconDelayLabel)
                            .frame(width: 95, alignment: .trailing)
                        Stepper("", value: $menuBarManager.settings.findIconRehideDelay, in: 5 ... 60, step: 5)
                            .labelsHidden()
                    }
                }
                CompactDivider()
                CompactToggle(label: "Hide when app changes", isOn: $menuBarManager.settings.rehideOnAppChange)
            } else {
                CompactDivider()
                proGatedRow(feature: .autoRehideCustomization, label: "Customize auto-hide timing")
            }
        }
    }

    private var hoverDelayRow: some View {
        Group {
            CompactDivider()
            CompactRow("Hover delay") {
                HStack {
                    Slider(value: $menuBarManager.settings.hoverDelay, in: 0.05 ... 1.0, step: 0.05)
                        .frame(width: 80)
                    Text(hoverDelayLabel)
                        .frame(width: 55, alignment: .trailing)
                }
            }
        }
    }

    private var scrollGestureRows: some View {
        Group {
            CompactDivider()
            if licenseService.isPro {
                CompactRow("Gesture behavior") {
                    HStack(spacing: 6) {
                        ForEach(SaneBarSettings.GestureMode.allCases, id: \.self) { mode in
                            ChromeSegmentedChoiceButton(
                                title: mode.rawValue,
                                isSelected: menuBarManager.settings.gestureMode == mode
                            ) {
                                menuBarManager.settings.gestureMode = mode
                            }
                            .help(gestureModeHelp(mode))
                        }
                    }
                    .frame(width: 220)
                }
                Text(gestureModeSummary)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 4)
            } else {
                proGatedRow(feature: .gestureCustomization, label: "Customize gesture behavior")
            }
        }
    }

    private func gestureModeHelp(_ mode: SaneBarSettings.GestureMode) -> String {
        switch mode {
        case .showOnly:
            return "Gestures only reveal hidden icons."
        case .showAndHide:
            return "Gestures toggle visibility. Scroll up shows icons, scroll down hides them."
        }
    }

    private func proGatedRow(feature: ProFeature, label: String) -> some View {
        CompactRow(label) {
            Button {
                showProUpsell(feature)
            } label: {
                ChromeBadge(title: "Pro", systemImage: "lock.fill")
            }
            .buttonStyle(.plain)
        }
    }
}
