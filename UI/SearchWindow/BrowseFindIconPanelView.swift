import SaneUI
import SwiftUI

struct BrowseFindIconPanelView: View {
    let availableModes: [BrowsePanelMode]
    let mode: BrowsePanelMode
    let isAlwaysHiddenEnabled: Bool
    @Binding var isSearchVisible: Bool
    @Binding var targetedModeDrop: BrowsePanelMode?
    let shouldShowMoveHint: Bool
    let moveHintModes: [BrowsePanelMode]
    let accentHighlight: Color
    let onSearchHidden: () -> Void
    let onModeSelected: (BrowsePanelMode) -> Void
    let onRefresh: () -> Void
    let handleZoneDrop: ([String], BrowsePanelMode) -> Bool
    let clearDragState: () -> Void

    let availableCategories: [AppCategory]
    let iconGroups: [SaneBarSettings.IconGroup]
    @Binding var selectedGroupId: UUID?
    @Binding var selectedSmartCategory: AppCategory?
    let addAppToGroup: (String, UUID) -> Void
    let deleteGroup: (UUID) -> Void
    let createCustomGroup: () -> Void

    @Binding var searchText: String
    let isSearchFieldFocused: FocusState<Bool>.Binding
    @Binding var showingBrowseHelp: Bool
    let hasAccessibility: Bool
    let hasMenuBarApps: Bool
    let isRefreshing: Bool
    let filteredApps: [RunningApp]
    let duplicateMarkers: [String: BrowseDuplicateMarker]
    let selectedAppIndex: Int?
    let movingAppId: String?
    let appZone: (RunningApp) -> BrowseAppZone
    let activateApp: (RunningApp, Bool) -> Void
    let setHotkey: (RunningApp) -> Void
    let removeAppFromGroup: (String, UUID) -> Void
    let makeToggleHiddenAction: (RunningApp) -> (() -> Void)?
    let makeMoveToAlwaysHiddenAction: (RunningApp) -> (() -> Void)?
    let makeMoveToHiddenAction: (RunningApp) -> (() -> Void)?
    let showRestrictedFeature: (ProFeature) -> Void
    let noteDragStarted: (BrowseAppZone) -> Void
    let handleGridDrop: ([String], RunningApp) -> Bool
    let openAccessibilitySettings: () -> Void
    let retryAccessibility: () -> Void
    let showingCrowdedVisibleHint: Bool
    let dismissCrowdedVisibleHint: () -> Void
    let enableSecondMenuBarFromHint: () -> Void

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                controls

                groupTabs

                if isSearchVisible {
                    searchField
                }

                Divider()

                content

                footer
            }
            .frame(width: 420, height: 520)
            .background { SaneGradientBackground(style: .panel) }

            if showingCrowdedVisibleHint {
                BrowseCrowdedVisibleHintToast(
                    accentHighlight: accentHighlight,
                    dismiss: dismissCrowdedVisibleHint,
                    enableSecondMenuBar: enableSecondMenuBarFromHint
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .frame(width: 420, height: 520)
    }

    private var controls: some View {
        BrowseModeStripView(
            availableModes: availableModes,
            selectedMode: mode,
            isSearchVisible: $isSearchVisible,
            targetedModeDrop: $targetedModeDrop,
            shouldShowMoveHint: shouldShowMoveHint,
            moveHintModes: moveHintModes,
            accentHighlight: accentHighlight,
            isLockedAlwaysHidden: { $0 == .alwaysHidden && !isAlwaysHiddenEnabled },
            onSearchHidden: onSearchHidden,
            onModeSelected: onModeSelected,
            onRefresh: onRefresh,
            handleZoneDrop: handleZoneDrop,
            clearDragState: clearDragState
        )
    }

    private var groupTabs: some View {
        BrowseGroupTabsView(
            availableCategories: availableCategories,
            iconGroups: iconGroups,
            selectedGroupId: $selectedGroupId,
            selectedSmartCategory: $selectedSmartCategory,
            addAppToGroup: addAppToGroup,
            deleteGroup: deleteGroup,
            createCustomGroup: createCustomGroup
        )
    }

    private var searchField: some View {
        BrowseSearchField(text: $searchText, isFocused: isSearchFieldFocused)
    }

    private var content: some View {
        Group {
            if !hasAccessibility {
                accessibilityPrompt
            } else if !hasMenuBarApps {
                if isRefreshing {
                    BrowseScanningState()
                } else {
                    BrowseEmptyState(mode: mode, accentHighlight: accentHighlight)
                }
            } else if filteredApps.isEmpty {
                BrowseNoMatchState(searchText: searchText)
            } else {
                appGrid
            }
        }
    }

    private var footer: some View {
        BrowseFooter(
            isRefreshing: isRefreshing,
            filteredCount: filteredApps.count,
            mode: mode,
            showingHelp: $showingBrowseHelp
        )
    }

    private var accessibilityPrompt: some View {
        BrowseAccessibilityPrompt(
            accentHighlight: accentHighlight,
            openSettings: openAccessibilitySettings,
            retry: retryAccessibility
        )
    }

    private var appGrid: some View {
        BrowseAppGridView(
            apps: filteredApps,
            duplicateMarkers: duplicateMarkers,
            selectedGroupId: selectedGroupId,
            selectedAppIndex: selectedAppIndex,
            movingAppId: movingAppId,
            mode: mode,
            appZone: appZone,
            activateApp: activateApp,
            setHotkey: setHotkey,
            removeAppFromGroup: removeAppFromGroup,
            makeToggleHiddenAction: makeToggleHiddenAction,
            makeMoveToAlwaysHiddenAction: makeMoveToAlwaysHiddenAction,
            makeMoveToHiddenAction: makeMoveToHiddenAction,
            showRestrictedFeature: showRestrictedFeature,
            noteDragStarted: noteDragStarted,
            handleGridDrop: handleGridDrop,
            clearDragState: clearDragState
        )
    }
}
