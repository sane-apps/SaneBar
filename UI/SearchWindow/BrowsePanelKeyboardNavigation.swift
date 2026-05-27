import SwiftUI

struct BrowsePanelKeyboardNavigationContext {
    let isSearchFieldFocused: Bool
    let setSearchFieldFocused: (Bool) -> Void
    let selectedAppIndex: Int?
    let setSelectedAppIndex: (Int?) -> Void
    let filteredApps: [RunningApp]
    let activate: (RunningApp) -> Void
    let showSearchAndFocus: () -> Void
}

enum BrowsePanelKeyboardNavigation {
    @MainActor
    static func handleKeyPress(
        _ keyPress: KeyPress,
        context: BrowsePanelKeyboardNavigationContext
    ) -> KeyPress.Result {
        if context.isSearchFieldFocused {
            switch keyPress.key {
            case .downArrow:
                context.setSearchFieldFocused(false)
                context.setSelectedAppIndex(context.filteredApps.isEmpty ? nil : 0)
                return .handled
            case .upArrow:
                context.setSearchFieldFocused(false)
                context.setSelectedAppIndex(context.filteredApps.isEmpty ? nil : context.filteredApps.count - 1)
                return .handled
            case .return:
                if let first = context.filteredApps.first {
                    context.activate(first)
                    return .handled
                }
                return .ignored
            default:
                return .ignored
            }
        }

        switch keyPress.key {
        case .downArrow:
            context.setSelectedAppIndex(nextSelection(current: context.selectedAppIndex, count: context.filteredApps.count, delta: 1))
            return .handled
        case .upArrow:
            context.setSelectedAppIndex(nextSelection(current: context.selectedAppIndex, count: context.filteredApps.count, delta: -1))
            return .handled
        case .leftArrow:
            context.setSelectedAppIndex(nextSelection(current: context.selectedAppIndex, count: context.filteredApps.count, delta: -1))
            return .handled
        case .rightArrow:
            context.setSelectedAppIndex(nextSelection(current: context.selectedAppIndex, count: context.filteredApps.count, delta: 1))
            return .handled
        case .return:
            if let index = context.selectedAppIndex, index < context.filteredApps.count {
                context.activate(context.filteredApps[index])
                context.setSelectedAppIndex(nil)
                return .handled
            } else if let first = context.filteredApps.first {
                context.activate(first)
                return .handled
            }
            return .ignored
        default:
            if let char = keyPress.characters.first, char.isLetter || char.isNumber {
                context.showSearchAndFocus()
                return .ignored
            }
            return .ignored
        }
    }

    static func nextSelection(current: Int?, count: Int, delta: Int) -> Int? {
        guard count > 0 else { return nil }

        if let current {
            let newIndex = current + delta
            return (0 ..< count).contains(newIndex) ? newIndex : current
        }

        return delta > 0 ? 0 : count - 1
    }
}
