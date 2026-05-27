import AppKit
import SwiftUI

struct BrowsePanelLifecycleModifier: ViewModifier {
    let isSecondMenuBar: Bool
    @Binding var storedMode: String
    @Binding var searchText: String
    @Binding var searchTextDebounced: String
    @Binding var isSearchVisible: Bool
    let setSearchFieldFocused: (Bool) -> Void
    @Binding var selectedAppIndex: Int?
    @Binding var movingAppId: String?
    @Binding var hotkeyApp: RunningApp?
    @Binding var proUpsellFeature: ProFeature?
    @Binding var needsPostMoveRefresh: Bool
    let filteredAppsCount: Int
    let syncAccessibilityState: () -> Bool
    let loadCachedApps: () -> Void
    let refreshApps: (Bool) -> Void
    let startPermissionMonitoring: () -> Void
    let installModeStripDragEndMonitors: () -> Void
    let clearModeStripDragState: () -> Void
    let removeModeStripDragEndMonitors: () -> Void
    let cancelPanelTasks: () -> Void
    let schedulePostMoveFollowupRefresh: () -> Void
    let scheduleCrowdedVisibleHintEvaluation: (Notification) -> Void
    let handleKeyPress: (KeyPress) -> KeyPress.Result
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: handleAppear)
            .onReceive(NotificationCenter.default.publisher(for: MenuBarSearchView.resetSearchNotification)) { _ in
                searchText = ""
                isSearchVisible = true
                setSearchFieldFocused(true)
                refreshApps(false)
            }
            .onReceive(NotificationCenter.default.publisher(for: MenuBarSearchView.setSearchTextNotification)) { notification in
                let text = notification.object as? String ?? ""
                searchText = text
                searchTextDebounced = text
                isSearchVisible = true
                setSearchFieldFocused(true)
                refreshApps(false)
            }
            .onReceive(NotificationCenter.default.publisher(for: .menuBarIconsDidChange)) { _ in
                movingAppId = nil
                needsPostMoveRefresh = true
                refreshApps(true)
                schedulePostMoveFollowupRefresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: SearchWindowController.iconMoveDidFinishNotification)) { _ in
                movingAppId = nil
                needsPostMoveRefresh = true
                refreshApps(true)
            }
            .onReceive(NotificationCenter.default.publisher(for: MenuBarVisibleLaneCrowdingHint.notification)) { notification in
                scheduleCrowdedVisibleHintEvaluation(notification)
            }
            .onChange(of: storedMode) { _, _ in
                if needsPostMoveRefresh {
                    needsPostMoveRefresh = false
                    refreshApps(true)
                } else {
                    loadCachedApps()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: SearchWindowController.windowDidShowNotification)) { _ in
                _ = syncAccessibilityState()
                loadCachedApps()
                refreshApps(isSecondMenuBar)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                let nowTrusted = syncAccessibilityState()
                if nowTrusted {
                    loadCachedApps()
                    refreshApps(true)
                }
            }
            .onDisappear(perform: handleDisappear)
            .sheet(item: $hotkeyApp) { app in
                HotkeyAssignmentSheet(app: app, onDone: { hotkeyApp = nil })
            }
            .sheet(item: $proUpsellFeature) { feature in
                ProUpsellView(feature: feature)
            }
            .onKeyPress { keyPress in
                handleKeyPress(keyPress)
            }
            .onChange(of: filteredAppsCount) { _, _ in
                selectedAppIndex = nil
            }
            .onChange(of: searchText) { oldValue, newValue in
                debounceSearchText(oldValue, newValue)
            }
            .onChange(of: movingAppId) { oldValue, newValue in
                clearStaleMovingApp(oldValue, newValue)
            }
            .onExitCommand(perform: onDismiss)
    }

    private func handleAppear() {
        _ = syncAccessibilityState()
        loadCachedApps()
        refreshApps(isSecondMenuBar)
        startPermissionMonitoring()
        installModeStripDragEndMonitors()

        if !isSecondMenuBar {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                setSearchFieldFocused(true)
            }
        }
    }

    private func handleDisappear() {
        clearModeStripDragState()
        removeModeStripDragEndMonitors()
        cancelPanelTasks()
    }

    private func debounceSearchText(_ oldValue: String, _ newValue: String) {
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            if searchText == newValue {
                searchTextDebounced = newValue
            }
        }
    }

    private func clearStaleMovingApp(_ oldValue: String?, _ newValue: String?) {
        guard newValue != nil else { return }
        Task {
            try? await Task.sleep(for: .seconds(5))
            if movingAppId == newValue {
                movingAppId = nil
            }
        }
    }
}
