import AppKit
import Combine
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "HoverService")

// MARK: - HoverServiceProtocol

/// @mockable
@MainActor
protocol HoverServiceProtocol {
    var isEnabled: Bool { get set }
    var scrollEnabled: Bool { get set }
    var trackMouseLeave: Bool { get set }
    func start()
    func stop()
}

// MARK: - HoverService

/// Service that monitors mouse position and scroll gestures near the menu bar
/// to trigger showing/hiding of icons.
///
/// Key behaviors:
/// - Detects when mouse enters the menu bar region
/// - Optional scroll gesture trigger (two-finger scroll up in menu bar)
/// - Debounces rapid mouse movements to prevent flickering
/// - Only shows icons when cursor is actually in the menu bar area
@MainActor
final class HoverService: HoverServiceProtocol {

    // MARK: - Types

    enum TriggerReason {
        case hover
        case scroll
    }

    // MARK: - Properties

    var isEnabled: Bool = false {
        didSet {
            guard isEnabled != oldValue else { return }
            updateMonitoringState()
        }
    }

    var scrollEnabled: Bool = false {
        didSet {
            guard scrollEnabled != oldValue else { return }
            updateMonitoringState()
        }
    }

    /// Enable mouse leave tracking for auto-rehide (independent of hover trigger)
    var trackMouseLeave: Bool = false {
        didSet {
            guard trackMouseLeave != oldValue else { return }
            updateMonitoringState()
        }
    }

    /// Called when hover/scroll should reveal icons
    var onTrigger: ((TriggerReason) -> Void)?

    /// Called when mouse leaves menu bar area (optional auto-hide)
    var onLeaveMenuBar: (() -> Void)?

    /// Delay before triggering (prevents accidental triggers)
    var hoverDelay: TimeInterval = 0.15

    /// Height of the hover detection zone (typically menu bar height)
    private let detectionZoneHeight: CGFloat = 24

    /// How far outside menu bar triggers leave event
    private let leaveThreshold: CGFloat = 50

    private var globalMonitor: Any?
    private var hoverTimer: Timer?
    private var isMouseInMenuBar = false
    private var lastScrollTime: Date = .distantPast

    // MARK: - Initialization

    init() {}

    deinit {
        // Cleanup handled via stop()
    }

    // MARK: - Public API

    func start() {
        // Start monitoring if any feature needs it
        guard isEnabled || scrollEnabled || trackMouseLeave else { return }
        startMonitoring()
    }

    func stop() {
        stopMonitoring()
    }

    // MARK: - Private Methods

    /// Update monitoring state based on all relevant properties
    private func updateMonitoringState() {
        if isEnabled || scrollEnabled || trackMouseLeave {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        guard globalMonitor == nil else { return }

        logger.info("Starting hover/scroll monitoring")

        // Monitor mouse movement and scroll events globally
        let eventMask: NSEvent.EventTypeMask = [.mouseMoved, .scrollWheel]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            Task { @MainActor in
                self?.handleEvent(event)
            }
        }
        
        if globalMonitor == nil {
            logger.error("Failed to create global monitor - check Accessibility permissions")
        }
    }

    private func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
            logger.info("Stopped hover/scroll monitoring")
        }
        cancelHoverTimer()
        isMouseInMenuBar = false
    }

    private func handleEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved:
            handleMouseMoved(event)
        case .scrollWheel:
            handleScrollWheel(event)
        default:
            break
        }
    }

    private func handleMouseMoved(_ event: NSEvent) {
        // Need at least one feature enabled to process mouse movement
        guard isEnabled || trackMouseLeave else { return }

        let mouseLocation = NSEvent.mouseLocation
        let inMenuBar = isInMenuBarRegion(mouseLocation)

        if inMenuBar && !isMouseInMenuBar {
            // Entered menu bar region
            isMouseInMenuBar = true
            // Only trigger hover reveal if hover-to-show is enabled
            if isEnabled {
                scheduleHoverTrigger()
            }
        } else if !inMenuBar && isMouseInMenuBar {
            // Left menu bar region
            let distanceFromMenuBar = distanceFromMenuBarTop(mouseLocation)
            if distanceFromMenuBar > leaveThreshold {
                isMouseInMenuBar = false
                cancelHoverTimer()
                // Fire leave callback for auto-rehide (if trackMouseLeave enabled)
                if trackMouseLeave {
                    onLeaveMenuBar?()
                }
            }
        }
    }

    private func handleScrollWheel(_ event: NSEvent) {
        guard scrollEnabled else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard isInMenuBarRegion(mouseLocation) else { return }

        // Two-finger scroll up (deltaY > 0) to reveal
        // Require a meaningful scroll amount to avoid accidental triggers
        if event.scrollingDeltaY > 5 {
            let now = Date()
            // Debounce rapid scrolls
            guard now.timeIntervalSince(lastScrollTime) > 0.3 else { return }
            lastScrollTime = now

            logger.debug("Scroll trigger detected in menu bar")
            onTrigger?(.scroll)
        }
    }

    private func isInMenuBarRegion(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.main else { return false }

        let screenFrame = screen.frame
        let menuBarTop = screenFrame.maxY
        let menuBarBottom = menuBarTop - detectionZoneHeight

        // Check if point is in the menu bar vertical band
        return point.y >= menuBarBottom && point.y <= menuBarTop
    }

    private func distanceFromMenuBarTop(_ point: NSPoint) -> CGFloat {
        guard let screen = NSScreen.main else { return 0 }
        let menuBarTop = screen.frame.maxY
        return menuBarTop - point.y
    }

    private func scheduleHoverTrigger() {
        cancelHoverTimer()

        hoverTimer = Timer.scheduledTimer(withTimeInterval: hoverDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isMouseInMenuBar else { return }
                self.onTrigger?(.hover)
            }
        }
    }

    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }
}
