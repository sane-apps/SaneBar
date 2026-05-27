import SwiftUI

struct BrowsePanelCrowdingHintContext {
    let isSecondMenuBar: Bool
    let useSecondMenuBar: () -> Bool
    let isShowing: Bool
    let visibleApps: () -> [RunningApp]
    let show: @MainActor () -> Void
}

enum BrowsePanelCrowdingHintCoordinator {
    @MainActor
    static func evaluationTask(
        from notification: Notification,
        context: BrowsePanelCrowdingHintContext
    ) -> Task<Void, Never>? {
        guard !context.isSecondMenuBar else { return nil }
        guard !context.useSecondMenuBar() else { return nil }
        guard !context.isShowing else { return nil }
        guard let event = BrowseVisibleLaneCrowdingAdvisor.event(from: notification) else { return nil }
        guard BrowseVisibleLaneCrowdingAdvisor.shouldShowReminder() else { return nil }

        return Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            guard !context.useSecondMenuBar() else { return }

            let visible = context.visibleApps()
            guard let movedApp = visible.first(where: { BrowseVisibleLaneCrowdingAdvisor.matches($0, event: event) }) else {
                return
            }
            guard BrowseVisibleLaneCrowdingAdvisor.shouldSuggestSecondMenuBar(
                visibleApps: visible,
                movedApp: movedApp,
                separatorRightEdgeX: event.separatorRightEdgeX,
                mainLeftEdgeX: event.visibleBoundaryX
            ) else {
                return
            }

            context.show()
        }
    }

    @MainActor
    static func show(
        setShowing: (Bool) -> Void,
        setDismissTask: (Task<Void, Never>) -> Void,
        dismiss: @escaping @MainActor () -> Void
    ) {
        UserDefaults.standard.set(
            BrowseVisibleLaneCrowdingAdvisor.versionToken(),
            forKey: BrowseVisibleLaneCrowdingAdvisor.versionKey
        )

        withAnimation(.spring(response: 0.28, dampingFraction: 0.88)) {
            setShowing(true)
        }

        setDismissTask(Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            dismiss()
        })
    }

    @MainActor
    static func dismiss(cancelDismissTask: () -> Void, setShowing: (Bool) -> Void) {
        cancelDismissTask()
        withAnimation(.easeOut(duration: 0.18)) {
            setShowing(false)
        }
    }

    @MainActor
    static func enableSecondMenuBar(manager: MenuBarManager, dismiss: () -> Void) {
        dismiss()
        if !manager.settings.secondMenuBarShowVisible {
            manager.settings.secondMenuBarShowVisible = true
        }
        manager.settings.useSecondMenuBar = true
        SearchWindowController.shared.transition(to: .secondMenuBar)
    }
}
