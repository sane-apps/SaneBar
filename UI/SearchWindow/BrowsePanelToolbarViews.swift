import SaneUI
import SwiftUI

struct BrowseModeStripView: View {
    let availableModes: [BrowsePanelMode]
    let selectedMode: BrowsePanelMode
    @Binding var isSearchVisible: Bool
    @Binding var targetedModeDrop: BrowsePanelMode?
    let shouldShowMoveHint: Bool
    let moveHintModes: [BrowsePanelMode]
    let accentHighlight: Color
    let isLockedAlwaysHidden: (BrowsePanelMode) -> Bool
    let onSearchHidden: () -> Void
    let onModeSelected: (BrowsePanelMode) -> Void
    let onRefresh: () -> Void
    let handleZoneDrop: ([String], BrowsePanelMode) -> Bool
    let clearDragState: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(availableModes) { segmentMode in
                    modeSegment(segmentMode)
                }
            }

            Spacer(minLength: 0)

            Button {
                withAnimation(.easeInOut(duration: 0.12)) {
                    isSearchVisible.toggle()
                }
                if !isSearchVisible {
                    onSearchHidden()
                }
            } label: {
                Image(systemName: isSearchVisible ? "xmark.circle" : "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 26, height: 26)
                    .background(toolbarButtonBackground)
            }
            .buttonStyle(ChromePressablePlainStyle())
            .help(isSearchVisible ? "Hide filter" : "Filter")

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .frame(width: 26, height: 26)
                    .background(toolbarButtonBackground)
            }
            .buttonStyle(ChromePressablePlainStyle())
            .help("Refresh")
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, isSearchVisible ? 6 : 10)
    }

    private var toolbarButtonBackground: some View {
        ChromeGlassCircleBackground(
            tint: SaneBarChrome.controlNavyDeep,
            edgeTint: SaneBarChrome.accentTeal,
            tintStrength: 0.12,
            glowOpacity: 0.08
        )
    }

    @ViewBuilder
    private func modeSegment(_ segmentMode: BrowsePanelMode) -> some View {
        let selected = selectedMode == segmentMode
        let isLocked = isLockedAlwaysHidden(segmentMode)
        let isValidMoveTarget = shouldShowMoveHint && moveHintModes.contains(segmentMode)
        let isTargeted = targetedModeDrop == segmentMode
        let chip = Button {
            onModeSelected(segmentMode)
        } label: {
            HStack(spacing: 5) {
                Text(segmentMode.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                if isLocked {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(accentHighlight)
                }
            }
            .foregroundStyle(selected ? .white : .white.opacity(0.90))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                ChromeGlassRoundedBackground(
                    cornerRadius: 8,
                    tint: selected ? SaneBarChrome.accentTeal : SaneBarChrome.controlNavyDeep,
                    edgeTint: selected ? SaneBarChrome.accentHighlight : SaneBarChrome.accentTeal,
                    tintStrength: selected ? 0.66 : 0.10,
                    glowOpacity: selected ? 0.24 : 0.06,
                    interactive: true,
                    shadowOpacity: selected ? 0.18 : 0.12,
                    shadowRadius: selected ? 8 : 6,
                    shadowY: 3
                )
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(
                        isValidMoveTarget
                            ? accentHighlight.opacity(isTargeted ? 0.78 : 0.42)
                            : Color.clear,
                        lineWidth: isTargeted ? 1.6 : 1.2
                    )
                    .shadow(
                        color: isValidMoveTarget
                            ? accentHighlight.opacity(isTargeted ? 0.22 : 0.10)
                            : .clear,
                        radius: isTargeted ? 8 : 6
                    )
            }
            .shadow(
                color: isValidMoveTarget
                    ? accentHighlight.opacity(isTargeted ? 0.16 : 0.08)
                    : (selected ? SaneBarChrome.controlShadow.opacity(0.16) : .clear),
                radius: isValidMoveTarget ? 8 : 4,
                y: 1
            )
            .animation(.easeOut(duration: 0.12), value: isTargeted)
            .animation(.easeOut(duration: 0.12), value: isValidMoveTarget)
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(ChromePressablePlainStyle())
        .help(isValidMoveTarget ? (isTargeted ? "Drop to \(segmentMode.title)" : "Drop on \(segmentMode.title)") : segmentMode.title)

        if isValidMoveTarget {
            chip
                .dropDestination(for: String.self) { payloads, _ in
                    let didHandle = handleZoneDrop(payloads, segmentMode)
                    clearDragState()
                    return didHandle
                } isTargeted: { isNowTargeted in
                    if isNowTargeted {
                        targetedModeDrop = segmentMode
                    } else if targetedModeDrop == segmentMode {
                        targetedModeDrop = nil
                    }
                }
        } else {
            chip
        }
    }
}

struct BrowseGroupTabsView: View {
    let availableCategories: [AppCategory]
    let iconGroups: [SaneBarSettings.IconGroup]
    @Binding var selectedGroupId: UUID?
    @Binding var selectedSmartCategory: AppCategory?
    let addAppToGroup: (String, UUID) -> Void
    let deleteGroup: (UUID) -> Void
    let createCustomGroup: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    SmartGroupTab(
                        title: "All",
                        isSelected: selectedGroupId == nil && selectedSmartCategory == nil,
                        action: {
                            selectedGroupId = nil
                            selectedSmartCategory = nil
                        }
                    )

                    ForEach(availableCategories, id: \.self) { category in
                        SmartGroupTab(
                            title: category.rawValue,
                            isSelected: selectedGroupId == nil && selectedSmartCategory == category,
                            action: {
                                selectedGroupId = nil
                                selectedSmartCategory = category
                            }
                        )
                    }

                    if !iconGroups.isEmpty {
                        Divider()
                            .frame(height: 16)
                            .padding(.horizontal, 4)
                    }

                    ForEach(iconGroups) { group in
                        let groupId = group.id
                        GroupTabButton(
                            title: group.name,
                            isSelected: selectedGroupId == groupId,
                            action: {
                                selectedGroupId = groupId
                                selectedSmartCategory = nil
                            }
                        )
                        .dropDestination(for: String.self) { payloads, _ in
                            for payload in payloads {
                                addAppToGroup(BrowsePanelDropPayload.bundleID(from: payload), groupId)
                            }
                            return !payloads.isEmpty
                        }
                        .contextMenu {
                            Button("Delete Group", role: .destructive) {
                                deleteGroup(groupId)
                            }
                        }
                    }
                }
            }

            SmartGroupTab(
                title: "+ Custom",
                isSelected: false,
                action: createCustomGroup
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
    }
}
