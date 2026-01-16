import AppKit
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.Monitoring")

extension MenuBarManager {
    
    // MARK: - Position Validation

    /// Returns true if separator is correctly positioned (LEFT of main icon)
    /// Returns true if we can't determine position (assume valid on startup)
    func validateSeparatorPosition() -> Bool {
        // If main icon is hidden (divider-only mode), position checks are irrelevant
        // logic: The separator IS the leftmost item, so it can't be "misplaced" relative to a hidden anchor.
        if settings.hideMainIcon {
            return true
        }
        
        // If buttons aren't ready, assume valid (don't block on startup)
        guard let mainButton = mainStatusItem?.button,
              let separatorButton = separatorItem?.button else {
            logger.debug("validateSeparatorPosition: buttons not ready - assuming valid")
            return true
        }

        // If windows aren't ready, assume valid (don't block on startup)
        guard let mainWindow = mainButton.window,
              let separatorWindow = separatorButton.window else {
            logger.debug("validateSeparatorPosition: windows not ready - assuming valid")
            return true
        }

        let mainFrame = mainWindow.frame
        let separatorFrame = separatorWindow.frame

        guard let mainScreen = mainWindow.screen, let sepScreen = separatorWindow.screen else {
            logger.debug("validateSeparatorPosition: window screen not ready - assuming valid")
            return true
        }

        if mainScreen == sepScreen {
            let menuBarY = mainScreen.frame.maxY - NSStatusBar.system.thickness
            let mainDeltaY = abs(mainFrame.origin.y - menuBarY)
            let sepDeltaY = abs(separatorFrame.origin.y - menuBarY)
            if mainDeltaY > NSStatusBar.system.thickness || sepDeltaY > NSStatusBar.system.thickness {
                logger.debug("validateSeparatorPosition: windows not at menu bar yet (mainY=\(mainFrame.origin.y), sepY=\(separatorFrame.origin.y))")
                return true
            }
        }

        // If frames are zero/invalid, assume valid (UI not ready)
        if mainFrame.width == 0 || separatorFrame.width == 0 {
            logger.debug("validateSeparatorPosition: frames not ready - assuming valid")
            return true
        }

        // CRITICAL: Check if both windows are on the same screen
        // In multi-display setups, each display has its own menu bar, and coordinates
        // are in unified screen space. Comparing coordinates across different screens
        // will produce false positives.
        if mainScreen != sepScreen {
            logger.debug("validateSeparatorPosition: items on different screens - assuming valid (multi-display transition)")
            return true
        }

        // Check: separator must be LEFT of main icon (lower X in screen coordinates)
        // Menu bar: LEFT = lower X, RIGHT = higher X
        let separatorLeftEdge = separatorFrame.origin.x
        let mainLeftEdge = mainFrame.origin.x

        if separatorLeftEdge >= mainLeftEdge {
            if ProcessInfo.processInfo.environment["SANEBAR_FORCE_WINDOW_NUDGE"] == "1", !swapAttempted {
                logger.error("Position error detected; attempting forced swap before warning")
                print("[MenuBarManager] Position error detected; attempting forced swap before warning")
                swapAttempted = true

                statusBarController.forceSwapItems()
                mainStatusItem = statusBarController.mainItem
                separatorItem = statusBarController.separatorItem
                if let separator = separatorItem {
                    hidingService.configure(delimiterItem: separator)
                }
                clearStatusItemMenus()
                updateMainIconVisibility()
                return true
            }

            logger.warning("Position error: separator (left edge \(separatorLeftEdge)) is RIGHT of main (left edge \(mainLeftEdge))")
            return false
        }

        logger.debug("Position valid: separator left=\(separatorLeftEdge), main left=\(mainLeftEdge)")
        return true
    }

    /// Validates positions on startup with a delay to let UI settle
    /// If validation passes, hides the items. If it fails, shows a warning and stays expanded.
    func validatePositionsOnStartup() {
        // Delay to let status items get their final positions (2s for safety)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self = self else { return }
            if self.validateSeparatorPosition() {
                // Position is valid - safe to hide
                logger.info("Startup position validation passed - hiding items")
                Task {
                    await self.hidingService.hide()
                }
            } else {
                // Position is wrong - stay expanded and warn user
                logger.warning("Startup position validation failed! Staying expanded.")
                self.showPositionWarning()
            }

            // Start continuous position monitoring to prevent separator from eating main icon
            self.startPositionMonitoring()

            // Pre-warm Find Icon cache so first open is instant
            AccessibilityService.shared.prewarmCache()
        }
    }

    // MARK: - Continuous Position Monitoring

    /// Monitor separator position continuously to prevent it from "eating" the main icon
    /// If user drags separator to an invalid position while items are hidden, auto-expand
    func startPositionMonitoring() {
        positionMonitorTask?.cancel()

        positionMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                // Check every 500ms - balance between responsiveness and CPU usage
                try? await Task.sleep(nanoseconds: 500_000_000)

                guard !Task.isCancelled else { break }

                await MainActor.run {
                    self?.checkPositionAndAutoExpand()
                }
            }
        }
    }

    /// Check position and auto-expand if separator is eating the main icon
    private func checkPositionAndAutoExpand() {
        // Only check when hidden - that's when the 10,000px spacer can push the main icon off
        guard self.hidingState == .hidden else {
            self.invalidPositionCount = 0  // Reset when not hidden
            return
        }

        // If position is invalid, increment counter (debounce for drag operations)
        if !self.validateSeparatorPosition() {
            self.invalidPositionCount += 1

            // Only trigger after sustained invalid position (allows drag-through)
            if self.invalidPositionCount >= self.invalidPositionThreshold {
                logger.warning("⚠️ POSITION EMERGENCY: Separator in invalid position for \(self.invalidPositionCount) checks. Auto-expanding...")
                Task {
                    await self.hidingService.show()
                }
                self.showPositionWarning()
                self.invalidPositionCount = 0  // Reset after triggering
            } else {
                logger.debug("Position invalid, count: \(self.invalidPositionCount)/\(self.invalidPositionThreshold)")
            }
        } else {
            // Position is valid - reset counter
            if self.invalidPositionCount > 0 {
                logger.debug("Position valid again, resetting counter from \(self.invalidPositionCount)")
            }
            self.invalidPositionCount = 0
        }
    }

    /// Stop position monitoring (called on deinit or when appropriate)
    func stopPositionMonitoring() {
        positionMonitorTask?.cancel()
        positionMonitorTask = nil
    }

    func showPositionWarning() {
        // Double-check: If main icon is hidden, we logically CANNOT be misplaced relative to it.
        // Also suppress warning to avoid annoyance.
        if settings.hideMainIcon {
            logger.info("showPositionWarning suppressed because hideMainIcon is enabled")
            return
        }
        
        guard let button = mainStatusItem?.button else { return }

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 300, height: 120)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: PositionWarningView())
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Auto-close after 5 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            popover.close()
        }
    }
}
