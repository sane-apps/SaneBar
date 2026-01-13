import AppKit
import os.log
import SwiftUI

private let logger = Logger(subsystem: "com.sanebar.app", category: "MenuBarManager.Monitoring")

extension MenuBarManager {
    
    // MARK: - Position Validation

    /// Returns true if separator is correctly positioned (LEFT of main icon)
    /// Returns true if we can't determine position (assume valid on startup)
    func validateSeparatorPosition() -> Bool {
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

        // If frames are zero/invalid, assume valid (UI not ready)
        if mainFrame.width == 0 || separatorFrame.width == 0 {
            logger.debug("validateSeparatorPosition: frames not ready - assuming valid")
            return true
        }

        // CRITICAL: Check if both windows are on the same screen
        // In multi-display setups, each display has its own menu bar, and coordinates
        // are in unified screen space. Comparing coordinates across different screens
        // will produce false positives.
        if mainWindow.screen != separatorWindow.screen {
            logger.debug("validateSeparatorPosition: items on different screens - assuming valid (multi-display transition)")
            return true
        }

        // Check: separator must be LEFT of main icon (lower X in screen coordinates)
        // Menu bar: LEFT = lower X, RIGHT = higher X
        let separatorRightEdge = separatorFrame.origin.x + separatorFrame.width
        let mainLeftEdge = mainFrame.origin.x

        if separatorRightEdge > mainLeftEdge {
            logger.warning("Position error: separator (right edge \(separatorRightEdge)) is RIGHT of main (left edge \(mainLeftEdge))")
            return false
        }

        logger.debug("Position valid: separator right=\(separatorRightEdge), main left=\(mainLeftEdge)")
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
