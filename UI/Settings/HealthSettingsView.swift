import AppKit
import SaneUI
import SwiftUI

struct HealthSettingsView: View {
    @ObservedObject private var menuBarManager = MenuBarManager.shared
    @ObservedObject private var accessibilityService = AccessibilityService.shared
    @State private var visibleCount = 0
    @State private var hiddenCount = 0
    @State private var alwaysHiddenCount = 0
    @State private var totalCount = 0
    @State private var lastScanDate: Date?
    @State private var lastRepairDate: Date?
    @State private var copiedDiagnostics = false
    @State private var layoutRescueMessage = ""
    @State private var repairInProgress = false

    private var runtimeSnapshot: MenuBarRuntimeSnapshot {
        menuBarManager.currentRuntimeSnapshot()
    }

    private var geometryLabel: String {
        switch runtimeSnapshot.geometryConfidence {
        case .live: "High"
        case .shielded: "Protected"
        case .cached: "Good"
        case .stale: "Needs Check"
        case .missing: "Needs Repair"
        }
    }

    private var geometryColor: Color {
        switch runtimeSnapshot.geometryConfidence {
        case .live, .cached: .green
        case .shielded: .cyan
        case .stale: .orange
        case .missing: .red
        }
    }

    private var structureLabel: String {
        if runtimeSnapshot.likelySystemSuppressedStatusItems {
            return "Hidden by macOS"
        }
        return switch runtimeSnapshot.structuralState {
        case .ready: "Ready"
        case .missingItems: "Missing"
        case .invisibleItems: "Hidden"
        case .unattachedWindows: "Detached"
        }
    }

    private var lastRepairLabel: String {
        lastRepairDate?.formatted(date: .omitted, time: .shortened) ?? "Not run"
    }

    private var restorePointLabel: String {
        menuBarManager.settings.layoutRescueRestorePointCreatedAt?.formatted(date: .abbreviated, time: .shortened) ?? "Not created"
    }

    private var canRestoreLayout: Bool {
        menuBarManager.settings.layoutRescueRestorePoint != nil
    }

    private var needsGeometryAction: Bool {
        switch runtimeSnapshot.geometryConfidence {
        case .live, .shielded, .cached:
            false
        case .stale, .missing:
            true
        }
    }

    private var needsStructureAction: Bool {
        runtimeSnapshot.structuralState != .ready
    }

    private var accessibilityHelp: String {
        accessibilityService.isGranted
            ? "SaneBar has Accessibility permission and can inspect, reveal, and arrange menu bar items."
            : "SaneBar needs Accessibility permission before Browse Icons, Arrange Now, and diagnostics can inspect menu bar items."
    }

    private var geometryHelp: String {
        switch runtimeSnapshot.geometryConfidence {
        case .live:
            "SaneBar has current menu bar anchor positions from the live system."
        case .shielded:
            "SaneBar is protecting the layout while macOS is temporarily hiding or moving menu bar items."
        case .cached:
            "SaneBar has usable saved menu bar anchor positions and will refresh them when needed."
        case .stale:
            "SaneBar can run Arrange Now to refresh older menu bar anchor positions."
        case .missing:
            "SaneBar does not have enough menu bar anchor data. Run Arrange Now to rebuild it."
        }
    }

    private var structureHelp: String {
        if runtimeSnapshot.likelySystemSuppressedStatusItems {
            return "macOS says SaneBar's menu bar items are visible, but their windows are detached. Check System Settings > Menu Bar > Allow in Menu Bar for SaneBar."
        }
        return switch runtimeSnapshot.structuralState {
        case .ready:
            "SaneBar can see the expected visible, hidden, and always-hidden item groups."
        case .missingItems:
            "Some expected menu bar items are not currently visible to SaneBar."
        case .invisibleItems:
            "macOS is reporting some menu bar items as hidden or unavailable right now."
        case .unattachedWindows:
            "Some menu bar windows are detached from their expected anchors. Arrange Now can repair this."
        }
    }

    private var layoutModeHelp: String {
        switch menuBarManager.settings.layoutMode {
        case .stability:
            "Hands-off: SaneBar only fixes its icon layout when it starts or when you click Fix. Good if your setup rarely changes."
        case .live:
            "SaneBar also re-checks the layout after sleep/wake and when displays are connected or disconnected. Good if icons sometimes scramble after wake."
        }
    }

    var body: some View {
        SaneSettingsPage {
                if runtimeSnapshot.likelySystemSuppressedStatusItems {
                    CompactSection("Icon Missing From the Menu Bar?", icon: "exclamationmark.triangle.fill", iconColor: .orange) {
                        CompactRow("Menu Bar settings") {
                            Button("Open Menu Bar Settings") {
                                openMenuBarSettings()
                            }
                            .buttonStyle(ChromeActionButtonStyle(prominent: true))
                            .saneHelp("Opens macOS System Settings so you can manage which icons are allowed in the menu bar.")
                            .accessibilityLabel("Open macOS Menu Bar settings")
                        }
                        SaneInlineHelp(
                            "macOS may be hiding SaneBar's icon behind the notch or because the menu bar is full. macOS doesn't let apps force their own icon back on screen, so this is fixed at the system level: open Menu Bar settings to manage what's shown, remove or reorder other menu-bar icons, or move SaneBar's icon to the immediate left of Control Center."
                        )
                    }
                }

                CompactSection("Status", icon: "stethoscope", iconColor: .green) {
                    CompactRow("Accessibility") {
                        HStack(spacing: 8) {
                            StatusBadge(
                                accessibilityService.isGranted ? "OK" : "Needs Action",
                                color: accessibilityService.isGranted ? .green : .orange,
                                icon: accessibilityService.isGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                            )
                            .saneHelp(accessibilityHelp)

                            if !accessibilityService.isGranted {
                                Button("Open") {
                                    openAccessibilitySettings()
                                }
                                .buttonStyle(ChromeActionButtonStyle(prominent: true))
                                .saneHelp("Opens Accessibility settings so you can grant SaneBar permission.")
                                .accessibilityLabel("Open Accessibility settings")
                            }
                        }
                    }
                    CompactDivider()
                    CompactRow("Menu Bar Geometry") {
                        HStack(spacing: 8) {
                            StatusBadge(geometryLabel, color: geometryColor, icon: "point.3.connected.trianglepath.dotted")
                                .saneHelp(geometryHelp)

                            if needsGeometryAction {
                                Button("Fix") {
                                    runRepair(reason: "health-geometry-fix", message: "Layout check ran.")
                                }
                                .buttonStyle(ChromeActionButtonStyle(prominent: true))
                                .disabled(repairInProgress)
                                .saneHelp("Runs a layout repair check now.")
                                .accessibilityLabel("Fix menu bar geometry")
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    CompactDivider()
                    CompactRow("SaneBar Items") {
                        HStack(spacing: 8) {
                            StatusBadge(structureLabel, color: runtimeSnapshot.structuralState == .ready ? .green : .orange, icon: "menubar.rectangle")
                                .saneHelp(structureHelp)

                            if needsStructureAction {
                                Button("Fix") {
                                    runRepair(reason: "health-items-fix", message: "Repair check ran.")
                                }
                                .buttonStyle(ChromeActionButtonStyle(prominent: true))
                                .disabled(repairInProgress)
                                .saneHelp("Repairs detached or missing SaneBar item groups.")
                                .accessibilityLabel("Fix SaneBar items")
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    CompactDivider()
                    CompactRow("Layout Mode") {
                        HStack(spacing: 6) {
                            ChromeSegmentedChoiceButton(
                                title: "Stability",
                                isSelected: menuBarManager.settings.layoutMode == .stability
                            ) {
                                setLayoutMode(.stability)
                            }
                            .saneHelp("Hands-off: SaneBar only fixes its icon layout at startup or when you click Fix.")

                            ChromeSegmentedChoiceButton(
                                title: "Live",
                                isSelected: menuBarManager.settings.layoutMode == .live
                            ) {
                                setLayoutMode(.live)
                            }
                            .saneHelp("SaneBar also re-checks the layout after sleep/wake, display changes, and session changes.")
                        }
                        .fixedSize(horizontal: true, vertical: false)
                    }
                    SaneInlineHelp(layoutModeHelp)
                }

                CompactSection("Layout Rescue", icon: "lifepreserver", iconColor: .orange) {
                    CompactRow("Restore Point") {
                        Text(restorePointLabel)
                            .font(SaneTypography.body)
                            .foregroundStyle(.white.opacity(0.94))
                            .saneHelp("The saved known-good layout SaneBar can return to if icons drift after restart, wake, or display changes.")
                    }
                    CompactDivider()
                    CompactRow("Save Current Layout") {
                        Button("Create") {
                            createRestorePoint()
                        }
                        .buttonStyle(ChromeActionButtonStyle())
                        .saneHelp("Saves the current SaneBar icon, divider, spacer, display-backup, and always-hidden divider positions as the restore point.")
                    }
                    CompactDivider()
                    CompactRow("Restore Last Good Layout") {
                        Button("Restore") {
                            restoreLayout()
                        }
                        .buttonStyle(ChromeActionButtonStyle())
                        .disabled(!canRestoreLayout)
                        .saneHelp(canRestoreLayout
                            ? "Restores the saved layout point, recreates SaneBar's menu bar items, then runs the same repair path as Arrange Now."
                            : "Create a restore point before using layout restore.")
                    }
                    if !layoutRescueMessage.isEmpty {
                        CompactDivider()
                        SaneInlineHelp(layoutRescueMessage)
                    }
                }

                CompactSection("Menu Bar Items", icon: "rectangle.grid.1x2", iconColor: .cyan) {
                    CompactRow("Detected") {
                        Text("\(totalCount)")
                            .font(SaneTypography.body)
                            .foregroundStyle(.white)
                    }
                    CompactDivider()
                    CompactRow("Visible / Hidden") {
                        Text("\(visibleCount) / \(hiddenCount)")
                            .font(SaneTypography.body)
                            .foregroundStyle(.white)
                    }
                    CompactDivider()
                    CompactRow("Always Hidden") {
                        Text("\(alwaysHiddenCount)")
                            .font(SaneTypography.body)
                            .foregroundStyle(.white)
                    }
                    CompactDivider()
                    CompactRow("Last Scan") {
                        Text(lastScanDate?.formatted(date: .omitted, time: .shortened) ?? "Not run")
                            .font(SaneTypography.body)
                            .foregroundStyle(.white.opacity(0.94))
                    }
                }

                CompactSection("Repair", icon: "wrench.and.screwdriver", iconColor: .orange) {
                    if menuBarManager.hasActionableDeferredWakeVisibleAllowListRepair() {
                        SaneInlineHelp("A layout restore after wake was postponed because icon positions could not be confirmed. Click Run to repair it now.")
                        CompactDivider()
                    }
                    CompactRow("Arrange Now") {
                        Button("Run") {
                            runRepair(reason: "health", message: "Repair check ran.")
                        }
                        .buttonStyle(ChromeActionButtonStyle())
                        .disabled(repairInProgress)
                        .saneHelp("Runs an immediate layout check, refreshes menu bar anchor positions, and repairs SaneBar's visible, hidden, and always-hidden groups if needed.")
                    }
                    CompactDivider()
                    CompactRow("Last Repair") {
                        Text(lastRepairLabel)
                            .font(SaneTypography.body)
                            .foregroundStyle(.white.opacity(0.94))
                    }
                    CompactDivider()
                    CompactRow("Accessibility Settings") {
                        Button("Open") {
                            openAccessibilitySettings()
                        }
                        .buttonStyle(ChromeActionButtonStyle())
                        .saneHelp("Opens macOS System Settings directly to Privacy & Security > Accessibility so you can grant or repair SaneBar's permission.")
                    }
                }

                CompactSection("Support Report", icon: "doc.text.magnifyingglass", iconColor: .blue) {
                    CompactRow("Diagnostics") {
                        Button(copiedDiagnostics ? "Copied" : "Copy Report") {
                            copyDiagnostics()
                        }
                        .buttonStyle(ChromeActionButtonStyle(prominent: copiedDiagnostics))
                        .saneHelp("Copies a support report with current permissions, layout state, item counts, and recent diagnostics to the clipboard.")
                    }
                }
        }
        .task {
            await refreshCounts()
        }
    }

    private func runRepair(reason: String, message: String? = nil) {
        guard !repairInProgress else { return }
        repairInProgress = true
        layoutRescueMessage = "Repairing layout..."
        Task { @MainActor in
            let hadDeferredWakeRepair = menuBarManager.hasActionableDeferredWakeVisibleAllowListRepair()
            let snapshot = await menuBarManager.profileWorkflow.repairMenuBarHealth(reason: reason)
            lastRepairDate = Date()
            if MenuBarProfileWorkflow.canCreateLayoutRescueRestorePoint(from: snapshot) {
                if hadDeferredWakeRepair,
                   menuBarManager.hasActionableDeferredWakeVisibleAllowListRepair() {
                    layoutRescueMessage = "Repair is running. SaneBar will clear the wake repair note after the layout restore finishes."
                } else {
                    layoutRescueMessage = message ?? "Repair check finished."
                }
            } else if snapshot.likelySystemSuppressedStatusItems {
                layoutRescueMessage = "macOS may be hiding SaneBar's icons. Check System Settings > Menu Bar > Allow in Menu Bar for SaneBar."
            } else {
                layoutRescueMessage = "Layout still needs attention."
            }
            await refreshCounts()
            repairInProgress = false
        }
    }

    private func createRestorePoint() {
        if menuBarManager.profileWorkflow.createLayoutRescueRestorePoint(reason: "health") {
            layoutRescueMessage = "Restore point saved."
        } else {
            layoutRescueMessage = MenuBarProfileWorkflow.layoutRescueRestorePointSaveFailureMessage(from: runtimeSnapshot)
        }
    }

    private func restoreLayout() {
        if menuBarManager.profileWorkflow.restoreLayoutRescueRestorePoint(reason: "health") {
            lastRepairDate = Date()
            layoutRescueMessage = "Last good layout restored."
            Task {
                _ = await menuBarManager.profileWorkflow.repairMenuBarHealth(reason: "health-restore-layout")
                await refreshCounts()
            }
        } else {
            layoutRescueMessage = "Create a restore point first."
        }
    }

    private func setLayoutMode(_ mode: SaneBarSettings.LayoutMode) {
        guard menuBarManager.settings.layoutMode != mode else { return }
        Task { @MainActor in
            layoutRescueMessage = mode == .live ? "Live checks enabled. Verifying layout..." : ""
            _ = await menuBarManager.profileWorkflow.setLayoutMode(mode, reason: "health")
            if mode == .live {
                lastRepairDate = Date()
                layoutRescueMessage = "Live checks enabled."
            }
            await refreshCounts()
        }
    }

    private func refreshCounts() async {
        let classified = await SearchService.shared.refreshKnownClassifiedApps()
        await MainActor.run {
            visibleCount = classified.visible.count
            hiddenCount = classified.hidden.count
            alwaysHiddenCount = classified.alwaysHidden.count
            totalCount = visibleCount + hiddenCount + alwaysHiddenCount
            lastScanDate = Date()
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(string: AccessibilityService.accessibilitySettingsURLString) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openMenuBarSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension")
            ?? URL(string: "x-apple.systempreferences:")
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    private func copyDiagnostics() {
        Task {
            let report = await SaneDiagnosticsService.shared.collectDiagnostics()
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(
                    report.toMarkdown(userDescription: "Menu bar health report"),
                    forType: .string
                )
                copiedDiagnostics = true
            }
            try? await Task.sleep(for: .seconds(1.2))
            await MainActor.run {
                copiedDiagnostics = false
            }
        }
    }
}
