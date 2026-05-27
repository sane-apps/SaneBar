import AppKit
import Foundation

enum BrowsePanelGroupEditor {
    private static let maxGroupCount = 50

    @MainActor
    static func openCustomGroupCreation(
        isPro: Bool,
        manager: MenuBarManager,
        showUpsell: () -> Void,
        selectGroup: (UUID?) -> Void
    ) {
        if isPro {
            promptForCustomGroupName(manager: manager, selectGroup: selectGroup)
        } else {
            showUpsell()
        }
    }

    @MainActor
    static func deleteGroup(
        groupId: UUID,
        selectedGroupId: UUID?,
        manager: MenuBarManager
    ) -> UUID? {
        guard manager.settings.iconGroups.contains(where: { $0.id == groupId }) else {
            return selectedGroupId
        }

        manager.settings.iconGroups.removeAll { $0.id == groupId }
        manager.saveSettings()

        return selectedGroupId == groupId ? nil : selectedGroupId
    }

    @MainActor
    static func addAppToGroup(bundleId: String, groupId: UUID, manager: MenuBarManager) {
        guard let index = manager.settings.iconGroups.firstIndex(where: { $0.id == groupId }) else {
            return
        }
        guard index < manager.settings.iconGroups.count else { return }

        if !manager.settings.iconGroups[index].appBundleIds.contains(bundleId) {
            manager.settings.iconGroups[index].appBundleIds.append(bundleId)
            manager.saveSettings()
        }
    }

    @MainActor
    static func removeAppFromGroup(bundleId: String, groupId: UUID, manager: MenuBarManager) {
        guard let index = manager.settings.iconGroups.firstIndex(where: { $0.id == groupId }) else {
            return
        }
        guard index < manager.settings.iconGroups.count else { return }

        manager.settings.iconGroups[index].appBundleIds.removeAll { $0 == bundleId }
        manager.saveSettings()
    }

    @MainActor
    private static func promptForCustomGroupName(
        manager: MenuBarManager,
        selectGroup: (UUID?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "New Custom Group"
        alert.informativeText = "Name this group."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        input.placeholderString = "Group name"
        alert.accessoryView = input

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        createGroup(named: input.stringValue, manager: manager, selectGroup: selectGroup)
    }

    @MainActor
    private static func createGroup(
        named name: String,
        manager: MenuBarManager,
        selectGroup: (UUID?) -> Void
    ) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        guard manager.settings.iconGroups.count < maxGroupCount else { return }

        let newGroup = SaneBarSettings.IconGroup(name: trimmedName)
        manager.settings.iconGroups.append(newGroup)
        manager.saveSettings()
        selectGroup(newGroup.id)
    }
}
