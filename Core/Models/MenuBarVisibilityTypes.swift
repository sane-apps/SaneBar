import AppKit

enum MenuBarRevealTrigger: String, Sendable {
    case hotkey
    case search
    case automation
    case hover
    case scroll
    case click
    case userDrag
    case settingsButton
    case findIcon
}

struct AutoRehideSettingsChangeContext: Equatable, Sendable {
    let wasAutoRehideEnabled: Bool
    let isAutoRehideEnabled: Bool
    let hidingState: HidingState
    let isRevealPinned: Bool
    let shouldSkipHideForExternalMonitor: Bool
    let isStatusMenuOpen: Bool
}
