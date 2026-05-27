import AppKit
import SaneUI
@testable import SaneBar
import Testing

// MARK: - Menu Item Lookup Helper

extension NSMenu {
    /// Find a menu item by its title (safer than hardcoded indices)
    func item(titled title: String) -> NSMenuItem? {
        items.first { $0.title == title }
    }
}

// MARK: - StatusBarControllerTests


func launchSafeRecoveryPair() -> (main: Double, separator: Double)? {
    guard let currentWidth = NSScreen.main?.frame.width else { return nil }
    return StatusBarController.launchSafeCurrentDisplayRecoveryPair(
        screenWidth: currentWidth,
        screenHasTopSafeAreaInset: StatusBarController.screenHasTopSafeAreaInset(NSScreen.main)
    )
}

// MARK: - Icon Name Tests
