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
    let defaults = UserDefaults.standard

    let mainButton = manager.mainStatusItem?.button
    let separatorButton = manager.separatorItem?.button
    let alwaysHiddenButton = manager.alwaysHiddenSeparatorItem?.button

    let mainPreferred = defaults.object(forKey: "NSStatusItem Preferred Position \(StatusBarController.mainAutosaveName)")
    let separatorPreferred = defaults.object(forKey: "NSStatusItem Preferred Position \(StatusBarController.separatorAutosaveName)")
    let alwaysHiddenPreferred = defaults.object(forKey: "NSStatusItem Preferred Position \(StatusBarController.alwaysHiddenSeparatorAutosaveName)")
    let legacyAlwaysHiddenPreferred = defaults.object(forKey: "NSStatusItem Preferred Position SaneBar_AlwaysHiddenSeparator")
    let statusItemScreen = mainButton?.window?.screen ?? separatorButton?.window?.screen
    let pointerScreen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
    let currentScreenWidth = statusItemScreen?.frame.width ?? NSScreen.main?.frame.width
    let currentScreenCount = NSScreen.screens.count
    let calibratedScreenWidth = (defaults.object(forKey: "SaneBar_CalibratedScreenWidth") as? NSNumber)?.doubleValue
    let currentWidthBucket = currentScreenWidth.map { StatusBarController.displayWidthBucket(Double($0)) }
    let storedWidthBucket = calibratedScreenWidth.map { StatusBarController.displayWidthBucket($0) }

    func backupValue(for width: Double?, slot: String) -> Any? {
        guard let width, width > 0 else { return nil }
        return defaults.object(forKey: StatusBarController.displayPositionBackupKey(for: width, slot: slot))
    }

    let currentMainBackup = backupValue(for: currentScreenWidth.map(Double.init), slot: "main")
    let currentSeparatorBackup = backupValue(for: currentScreenWidth.map(Double.init), slot: "separator")
    let storedMainBackup = backupValue(for: calibratedScreenWidth, slot: "main")
    let storedSeparatorBackup = backupValue(for: calibratedScreenWidth, slot: "separator")

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

    func formatDouble(_ value: Double?) -> String {
        guard let value else { return "nil" }
        return String(format: "%.2f", value)
    }

    func formatAny(_ value: Any?) -> String {
        guard let value else { return "nil" }
        return String(describing: value)
    }

    func indent(_ block: String, spaces: Int = 2) -> String {
        let prefix = String(repeating: " ", count: spaces)
        return block
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { prefix + $0 }
            .joined(separator: "\n")
    }

    let accessibilityDiagnostics = AccessibilityService.shared.diagnosticsSnapshot()
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

    prefsForensics:
      bundleIdentifier: \(Bundle.main.bundleIdentifier ?? "nil")
      autosaveVersion: \(StatusBarController.autosaveVersion)
      currentScreenWidth: \(formatCGFloat(currentScreenWidth))
      currentScreenCount: \(currentScreenCount)
      statusItemScreen: \(statusItemScreen?.localizedName ?? "nil")
      statusItemScreenWidth: \(formatCGFloat(statusItemScreen?.frame.width))
      pointerScreen: \(pointerScreen?.localizedName ?? "nil")
      pointerScreenWidth: \(formatCGFloat(pointerScreen?.frame.width))
      calibratedScreenWidth: \(formatDouble(calibratedScreenWidth))
      currentWidthBucket: \(currentWidthBucket.map(String.init) ?? "nil")
      storedWidthBucket: \(storedWidthBucket.map(String.init) ?? "nil")
      legacyAlwaysHiddenSeparator: \(formatAny(legacyAlwaysHiddenPreferred))
      displayBackupCurrentMain: \(formatAny(currentMainBackup))
      displayBackupCurrentSeparator: \(formatAny(currentSeparatorBackup))
      displayBackupStoredMain: \(formatAny(storedMainBackup))
      displayBackupStoredSeparator: \(formatAny(storedSeparatorBackup))

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
      hideApplicationMenusOnInlineReveal: \(settings.hideApplicationMenusOnInlineReveal)
      showOnUserDrag: \(settings.showOnUserDrag)
      showOnLowBattery: \(settings.showOnLowBattery)
      showOnAppLaunch: \(settings.showOnAppLaunch)
      showOnNetworkChange: \(settings.showOnNetworkChange)
      rehideOnAppChange: \(settings.rehideOnAppChange)
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
    \(indent(accessibilityDiagnostics, spaces: 4))
    \(indent(searchDiagnostics, spaces: 4))
    \(indent(secondMenuBarDiagnostics, spaces: 4))
    """
}
