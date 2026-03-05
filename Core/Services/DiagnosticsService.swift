import AppKit
import Foundation
import SaneUI

// MARK: - SaneBar Diagnostics

/// SaneBar's diagnostics service — delegates generic collection (logs, system info,
/// markdown, sanitization) to SaneDiagnosticsService and provides SaneBar-specific
/// settings and menu bar classification data via the settingsCollector closure.
extension SaneDiagnosticsService {
    static let shared = SaneDiagnosticsService(
        appName: "SaneBar",
        subsystem: "com.sanebar.app",
        githubRepo: "SaneBar",
        settingsCollector: { await collectSaneBarSettings() }
    )
}

// MARK: - SaneBar-Specific Settings Collection

@MainActor
private func collectSaneBarSettings() -> String {
    let manager = MenuBarManager.shared
    let settings = manager.settings

    let mainButton = manager.mainStatusItem?.button
    let separatorButton = manager.separatorItem?.button
    let alwaysHiddenButton = manager.alwaysHiddenSeparatorItem?.button

    let mainPreferred = UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)")
    let separatorPreferred = UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)")
    let alwaysHiddenPreferred = UserDefaults.standard.object(forKey: "NSStatusItem Preferred Position \(StatusBarController.alwaysHiddenSeparatorAutosaveName)")

    func formatSelector(_ action: Selector?) -> String {
        guard let action else { return "nil" }
        return NSStringFromSelector(action)
    }

    func formatRect(_ rect: CGRect?) -> String {
        guard let rect else { return "nil" }
        return String(format: "x=%.1f y=%.1f w=%.1f h=%.1f", rect.origin.x, rect.origin.y, rect.size.width, rect.size.height)
    }

    func formatCGFloat(_ value: CGFloat?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.2f", value)
    }

    func indent(_ block: String, spaces: Int = 2) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    let searchDiagnostics = SearchService.shared.diagnosticsSnapshot()
    let secondMenuBarDiagnostics = SearchWindowController.shared.diagnosticsSnapshot()

    return """
    hidingState: \(manager.hidingService.state.rawValue)
    isAnimating: \(manager.hidingService.isAnimating)
    delimiterConfigured: \(manager.hidingService.isConfigured)
    delimiterLength: \(formatCGFloat(manager.hidingService.delimiterLength))
    isMenuOpen: \(manager.isMenuOpen)
    isRevealPinned: \(manager.isRevealPinned)
    shouldSkipHideForExternalMonitor: \(manager.shouldSkipHideForExternalMonitor)
    hasNotch: \(manager.hasNotch)
    isOnExternalMonitor: \(manager.isOnExternalMonitor)
    accessibilityGranted: \(AccessibilityService.shared.isGranted)

    separatorOriginX: \(formatCGFloat(manager.getSeparatorOriginX()))
    alwaysHiddenSeparatorOriginX: \(formatCGFloat(manager.getAlwaysHiddenSeparatorOriginX()))
    mainIconLeftEdgeX: \(formatCGFloat(manager.getMainStatusItemLeftEdgeX()))

    mainStatusItemVisible: \(manager.mainStatusItem?.isVisible ?? false)
    statusMenuItemCount: \(manager.statusMenu?.items.count ?? 0)

    mainButton:
      identifier: \(mainButton?.identifier?.rawValue ?? "nil")
      action: \(formatSelector(mainButton?.action))
      hasTarget: \(mainButton?.target != nil)
      windowFrame: \(formatRect(mainButton?.window?.frame))
      screen: \(mainButton?.window?.screen?.localizedName ?? "nil")

    separatorButton:
      identifier: \(separatorButton?.identifier?.rawValue ?? "nil")
      action: \(formatSelector(separatorButton?.action))
      hasTarget: \(separatorButton?.target != nil)
      windowFrame: \(formatRect(separatorButton?.window?.frame))

    alwaysHiddenSeparatorButton:
      identifier: \(alwaysHiddenButton?.identifier?.rawValue ?? "nil")
      action: \(formatSelector(alwaysHiddenButton?.action))
      hasTarget: \(alwaysHiddenButton?.target != nil)
      windowFrame: \(formatRect(alwaysHiddenButton?.window?.frame))

    nsStatusItemPreferredPositions:
      main: \(mainPreferred.map { String(describing: $0) } ?? "nil")
      separator: \(separatorPreferred.map { String(describing: $0) } ?? "nil")
      alwaysHiddenSeparator: \(alwaysHiddenPreferred.map { String(describing: $0) } ?? "nil")

    settings:
      autoRehide: \(settings.autoRehide)
      rehideDelay: \(settings.rehideDelay)s
      findIconRehideDelay: \(settings.findIconRehideDelay)s
      showOnHover: \(settings.showOnHover)
      showOnScroll: \(settings.showOnScroll)
      showOnClick: \(settings.showOnClick)
      showOnUserDrag: \(settings.showOnUserDrag)
      showOnLowBattery: \(settings.showOnLowBattery)
      showOnAppLaunch: \(settings.showOnAppLaunch)
      showOnNetworkChange: \(settings.showOnNetworkChange)
      requireAuthToShowHiddenIcons: \(settings.requireAuthToShowHiddenIcons)
      showDockIcon: \(settings.showDockIcon)
      hideMainIcon: \(settings.hideMainIcon)
      dividerStyle: \(settings.dividerStyle.rawValue)
      menuBarSpacing: \(settings.menuBarSpacing.map { String($0) } ?? "default")
      iconGroups: \(settings.iconGroups.count)
      iconHotkeys: \(settings.iconHotkeys.count)
      disableOnExternalMonitor: \(settings.disableOnExternalMonitor)
      useSecondMenuBar: \(settings.useSecondMenuBar)
      alwaysHiddenSectionEnabled: \(settings.alwaysHiddenSectionEnabled)
      alwaysHiddenPinnedItemCount: \(settings.alwaysHiddenPinnedItemIds.count)

    diagnostics:
    \(indent(searchDiagnostics, spaces: 4))
    \(indent(secondMenuBarDiagnostics, spaces: 4))
    """
}
