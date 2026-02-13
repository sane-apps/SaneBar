import Foundation

/// Features gated behind Pro. Each case maps to a user-visible action
/// that free users can see but not perform.
enum ProFeature: String, Identifiable, CaseIterable {
    case iconActivation = "Activate Icons from Panels"
    case rightClickFromPanels = "Right-Click from Panels"
    case zoneMoves = "Move Icons Between Zones"
    case alwaysHidden = "Always Hidden Zone"
    case perIconHotkeys = "Per-Icon Hotkeys"
    case iconGroups = "Custom Icon Groups"
    case advancedTriggers = "Advanced Triggers"
    case gestureCustomization = "Gesture Customization"
    case autoRehideCustomization = "Auto-Rehide Customization"
    case menuBarAppearance = "Menu Bar Appearance"
    case iconSpacing = "Icon Spacing Control"
    case touchIDProtection = "Password / Touch ID Protection"
    case settingsProfiles = "Settings Profiles"
    case exportImport = "Export / Import Settings"
    case competitorImport = "Competitor Import"
    case customIcon = "Custom Menu Bar Icon"
    case spacersConfig = "Spacers Configuration"
    case additionalShortcuts = "Additional Global Shortcuts"
    case appleScript = "AppleScript Automation"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .iconActivation: "Click icons directly from the panel to open their menus"
        case .rightClickFromPanels: "Right-click icons from the panel for quick actions"
        case .zoneMoves: "Drag icons between Visible, Hidden, and Always Hidden zones"
        case .alwaysHidden: "A third zone for icons you never want to see"
        case .perIconHotkeys: "Assign a unique keyboard shortcut to any icon"
        case .iconGroups: "Organize icons into custom named groups"
        case .advancedTriggers: "Auto-show icons on Wi-Fi, Focus, battery, app launch, or script"
        case .gestureCustomization: "Toggle mode, directional scroll, and more gesture options"
        case .autoRehideCustomization: "Custom timing, hide-on-app-change, external monitor rules"
        case .menuBarAppearance: "Tint colors, glass effects, borders, corners, and shadows"
        case .iconSpacing: "Reduce or increase the space between menu bar icons"
        case .touchIDProtection: "Protect hidden icons with Touch ID or your password"
        case .settingsProfiles: "Save and load different configurations"
        case .exportImport: "Export settings to share or back up, import from file"
        case .competitorImport: "Import settings from Bartender or Ice"
        case .customIcon: "Use your own image as the SaneBar menu bar icon"
        case .spacersConfig: "Add extra visual dividers to organize your menu bar"
        case .additionalShortcuts: "Show-only, hide-only, open settings, and more shortcuts"
        case .appleScript: "Control SaneBar from scripts and automation tools"
        }
    }

    var icon: String {
        switch self {
        case .iconActivation: "cursorarrow.click"
        case .rightClickFromPanels: "cursorarrow.click.2"
        case .zoneMoves: "arrow.left.arrow.right"
        case .alwaysHidden: "lock.fill"
        case .perIconHotkeys: "keyboard"
        case .iconGroups: "folder"
        case .advancedTriggers: "bolt.fill"
        case .gestureCustomization: "hand.draw"
        case .autoRehideCustomization: "timer"
        case .menuBarAppearance: "paintpalette.fill"
        case .iconSpacing: "arrow.left.and.right"
        case .touchIDProtection: "touchid"
        case .settingsProfiles: "doc.on.doc"
        case .exportImport: "square.and.arrow.up.on.square"
        case .competitorImport: "arrow.down.doc"
        case .customIcon: "photo"
        case .spacersConfig: "line.3.horizontal"
        case .additionalShortcuts: "command"
        case .appleScript: "applescript"
        }
    }
}
