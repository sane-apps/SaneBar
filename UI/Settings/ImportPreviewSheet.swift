import SaneUI
import SwiftUI

struct ImportPreviewSheet: View {
    let plan: SaneBarImportPreviewPlan
    let onCancel: () -> Void
    let onImport: () -> Void

    private var hasRuleDetails: Bool {
        plan.hideAllOtherItems ||
            !plan.showItemIds.isEmpty ||
            !plan.hideItemIds.isEmpty ||
            !plan.alwaysHideItemIds.isEmpty
    }

    private var enablesScriptTrigger: Bool {
        plan.behavioralSettings.contains { $0.localizedCaseInsensitiveContains("script trigger") }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Import Settings")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                Text("\(plan.sourceKind.rawValue): \(plan.fileName)")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(2)
            }

            VStack(alignment: .leading, spacing: 10) {
                if hasRuleDetails {
                    previewRow("Show", value: "\(plan.showItemIds.count) items")
                    previewRow("Hide", value: "\(plan.hideItemIds.count) items")
                    previewRow("Always Hide", value: "\(plan.alwaysHideItemIds.count) items")
                    previewRow("All Others", value: plan.hideAllOtherItems ? "On" : "Off")
                } else {
                    previewRow("Profile rules", value: "No visibility rules")
                }

                if plan.savedProfileCount > 0 {
                    previewRow("Saved profiles", value: "\(plan.savedProfileCount)")
                }
                if plan.includesLayoutSnapshot {
                    previewRow("Layout snapshot", value: "Included")
                }
                if plan.includesCustomIconSnapshot {
                    previewRow("Custom icon", value: "Included")
                }
                if !plan.behavioralSettings.isEmpty {
                    previewRow("Settings", value: "\(plan.behavioralSettings.count) changes")
                }
                if !plan.missingItemIds.isEmpty {
                    previewRow("Missing items", value: "\(plan.missingItemIds.count)")
                }
                if !plan.skippedItemIds.isEmpty {
                    previewRow("Skipped items", value: "\(plan.skippedItemIds.count)")
                }
            }
            .padding(12)
            .background(
                ChromeGlassRoundedBackground(
                    cornerRadius: 8,
                    tint: SaneBarChrome.panelTint,
                    tintStrength: 0.12,
                    shadowOpacity: 0.10,
                    shadowRadius: 8,
                    shadowY: 3
                )
            )

            if plan.hideAllOtherItems {
                Text("This import will keep the shown items visible and hide newly detected menu bar items by default.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.94))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if enablesScriptTrigger {
                Text("This import enables script-based control. Only import files you trust.")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(ChromeActionButtonStyle())
                Spacer()
                Button("Import", action: onImport)
                    .buttonStyle(ChromeActionButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background {
            SaneGradientBackground(style: .panel)
        }
    }

    private func previewRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.white.opacity(0.94))
            Spacer()
            Text(value)
                .foregroundStyle(.white)
                .fontWeight(.semibold)
        }
        .font(.system(size: 13))
    }
}
