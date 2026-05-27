#if !DEBUG
import AppIntents
import Foundation

struct ToggleHiddenItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Toggle Hidden Items"
    static let description = IntentDescription("Show or hide SaneBar's hidden menu bar icons.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        MenuBarManager.shared.visibilityWorkflow.toggleHiddenItems()
        return .result()
    }
}

struct ShowHiddenItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Show Hidden Icons"
    static let description = IntentDescription("Reveal SaneBar's hidden menu bar icons.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        MenuBarManager.shared.visibilityWorkflow.showHiddenItems()
        return .result()
    }
}

struct HideHiddenItemsIntent: AppIntent {
    static let title: LocalizedStringResource = "Hide Icons"
    static let description = IntentDescription("Hide SaneBar's hidden menu bar icons again.")
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult {
        MenuBarManager.shared.visibilityWorkflow.hideHiddenItems()
        return .result()
    }
}

struct ApplySaneBarProfileIntent: AppIntent {
    static let title: LocalizedStringResource = "Apply Profile"
    static let description = IntentDescription("Apply a saved SaneBar profile by name.")
    static let openAppWhenRun = false

    @Parameter(title: "Profile Name")
    var profileName: String

    init() {
        profileName = ""
    }

    init(profileName: String) {
        self.profileName = profileName
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmedName = profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return .result(dialog: "Choose a SaneBar profile name.")
        }

        let profiles = MenuBarManager.shared.profileWorkflow.savedProfiles()
        guard let profile = profiles.first(where: { $0.name.localizedCaseInsensitiveCompare(trimmedName) == .orderedSame }) else {
            return .result(dialog: "SaneBar could not find a profile named \(trimmedName).")
        }

        MenuBarManager.shared.profileWorkflow.applyProfile(profile, preserveAutomation: false, reason: "app-intent")
        return .result(dialog: "Applied \(profile.name).")
    }
}

struct QuickSearchSaneBarIntent: AppIntent {
    static let title: LocalizedStringResource = "Quick Search"
    static let description = IntentDescription("Open SaneBar Browse Icons with search text.")
    static let openAppWhenRun = true

    @Parameter(title: "Search Text")
    var query: String

    init() {
        query = ""
    }

    init(query: String) {
        self.query = query
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        _ = await MenuBarManager.shared.visibilityWorkflow.showHiddenItemsNow(trigger: .search)
        SearchWindowController.shared.show(mode: .findIcon, prefill: query.trimmingCharacters(in: .whitespacesAndNewlines))
        return .result()
    }
}

struct SaneBarAppShortcuts: AppShortcutsProvider {
    static let shortcutTileColor: ShortcutTileColor = .teal

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleHiddenItemsIntent(),
            phrases: [
                "Toggle \(.applicationName)",
                "Show or hide icons with \(.applicationName)"
            ],
            shortTitle: "Toggle Icons",
            systemImageName: "line.3.horizontal.decrease"
        )
        AppShortcut(
            intent: ShowHiddenItemsIntent(),
            phrases: [
                "Show icons with \(.applicationName)",
                "Reveal \(.applicationName)"
            ],
            shortTitle: "Show Icons",
            systemImageName: "eye"
        )
        AppShortcut(
            intent: HideHiddenItemsIntent(),
            phrases: [
                "Hide icons with \(.applicationName)",
                "Hide \(.applicationName)"
            ],
            shortTitle: "Hide Icons",
            systemImageName: "eye.slash"
        )
        AppShortcut(
            intent: ApplySaneBarProfileIntent(),
            phrases: [
                "Apply a profile in \(.applicationName)",
                "Switch \(.applicationName) profile"
            ],
            shortTitle: "Apply Profile",
            systemImageName: "rectangle.stack"
        )
        AppShortcut(
            intent: QuickSearchSaneBarIntent(),
            phrases: [
                "Search icons with \(.applicationName)",
                "Quick search in \(.applicationName)"
            ],
            shortTitle: "Quick Search",
            systemImageName: "magnifyingglass"
        )
    }
}

#endif
