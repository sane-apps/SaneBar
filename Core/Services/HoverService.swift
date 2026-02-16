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
    var clickEnabled: Bool { get set }
    var trackMouseLeave: Bool { get set }
    func start()
    func stop()
}

// MARK: - HoverService

/// Service that monitors mouse position, scroll gestures, and clicks near the menu bar
/// to trigger showing/hiding of icons.
///
/// Key behaviors:
/// - Detects when mouse enters the menu bar region
/// - Optional scroll gesture trigger (two-finger scroll in menu bar)
/// - Optional click trigger (left-click in menu bar)
/// - Debounces rapid mouse movements to prevent flickering
/// - Only shows icons when cursor is actually in the menu bar area
@MainActor
final class HoverService: HoverServiceProtocol {
    // MARK: - Types

    enum TriggerReason: Equatable {
        case hover
        case scroll(direction: ScrollDirection)
        case click
        case userDrag // ⌘+drag started in menu bar
    }

    enum ScrollDirection: Equatable {
        case up // Positive deltaY (show in Ice-style)
        case down // Negative deltaY (hide in Ice-style)
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

    var clickEnabled: Bool = false {
        didSet {
            guard clickEnabled != oldValue else { return }
            updateMonitoringState()
        }
    }

    /// Enable revealing all icons when user is ⌘+dragging to rearrange (Ice-style)
    var userDragEnabled: Bool = false {
        didSet {
            guard userDragEnabled != oldValue else { return }
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

    /// Temporarily suspend all triggers (e.g. when Find Icon window is open)
    var isSuspended: Bool = false

    /// Called when hover/scroll should reveal icons
    var onTrigger: ((TriggerReason) -> Void)?

    /// Called when ⌘+drag ends (user stopped rearranging)
    var onUserDragEnd: (() -> Void)?

    /// Called when mouse leaves menu bar area (optional auto-hide)
    var onLeaveMenuBar: (() -> Void)?

    /// Track whether user is currently ⌘+dragging
    private var isUserDragging = false

    /// Delay before triggering (prevents accidental triggers)
    var hoverDelay: TimeInterval = 0.25

    /// Height of the hover detection zone (typically menu bar height)
    private let detectionZoneHeight: CGFloat = 24

    /// How far outside menu bar triggers leave event
    private let leaveThreshold: CGFloat = 50

    private var globalMonitor: Any?
    private var hoverTimer: Timer?
    private var isMouseInMenuBar = false
    private var lastScrollTime: Date = .distantPast
    /// Throttle mouse moved events to reduce energy impact (~20fps is plenty for hover detection)
    private var lastMouseMovedTime: CFAbsoluteTime = 0
    private let mouseMovedThrottleInterval: CFAbsoluteTime = 0.05 // 50ms = 20fps

    // MARK: - Initialization

    init() {}

    deinit {
        // Cleanup handled via stop()
    }

    // MARK: - Public API

    func start() {
        // Start monitoring if any feature needs it
        guard isEnabled || scrollEnabled || clickEnabled || trackMouseLeave else { return }
        startMonitoring()
    }

    func stop() {
        stopMonitoring()
    }

    // MARK: - Private Methods

    /// Update monitoring state based on all relevant properties
    private func updateMonitoringState() {
        if isEnabled || scrollEnabled || clickEnabled || userDragEnabled || trackMouseLeave {
            startMonitoring()
        } else {
            stopMonitoring()
        }
    }

    private func startMonitoring() {
        guard globalMonitor == nil else { return }

        logger.info("Starting hover/scroll/click/drag monitoring")

        // Monitor mouse movement, scroll, click, drag, and modifier key events globally
        let eventMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .scrollWheel,
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .flagsChanged
        ]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
            // Throttle mouse moved events to reduce energy impact — 50ms interval is plenty for hover detection.
            // Click, scroll, drag, and flags events are processed immediately (they're infrequent).
            if event.type == .mouseMoved {
                let now = CFAbsoluteTimeGetCurrent()
                guard let self, now - lastMouseMovedTime >= mouseMovedThrottleInterval else { return }
                lastMouseMovedTime = now
            }
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
            logger.info("Stopped hover/scroll/click monitoring")
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
        case .leftMouseDown:
            handleLeftMouseDown(event)
        case .leftMouseDragged:
            handleLeftMouseDragged(event)
        case .leftMouseUp:
            handleLeftMouseUp(event)
        case .flagsChanged:
            handleFlagsChanged(event)
        default:
            break
        }
    }

    private func handleMouseMoved(_: NSEvent) {
        // Need at least one feature enabled to process mouse movement
        guard isEnabled || trackMouseLeave, !isSuspended else { return }

        let mouseLocation = NSEvent.mouseLocation
        let inMenuBar = isInMenuBarRegion(mouseLocation)

        if inMenuBar, !isMouseInMenuBar {
            // Entered menu bar region
            isMouseInMenuBar = true
            // Only trigger hover reveal if hover-to-show is enabled
            if isEnabled {
                scheduleHoverTrigger()
            }
        } else if !inMenuBar, isMouseInMenuBar {
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
        guard scrollEnabled, !isSuspended else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard isInMenuBarRegion(mouseLocation) else { return }

        // Two-finger scroll - require meaningful scroll amount to avoid accidental triggers
        let deltaY = event.scrollingDeltaY
        if abs(deltaY) > 5 {
            let now = Date()
            // Debounce rapid scrolls
            guard now.timeIntervalSince(lastScrollTime) > 0.3 else { return }
            lastScrollTime = now

            cancelHoverTimer() // Deliberate action cancels passive hover timer

            // Determine scroll direction (positive = scroll up, negative = scroll down)
            let direction: ScrollDirection = deltaY > 0 ? .up : .down
            logger.debug("Scroll trigger detected in menu bar: \(deltaY > 0 ? "up" : "down")")
            onTrigger?(.scroll(direction: direction))
        }
    }

    private func handleLeftMouseDown(_: NSEvent) {
        guard clickEnabled, !isSuspended else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard isInMenuBarRegion(mouseLocation) else { return }

        cancelHoverTimer() // Deliberate action cancels passive hover timer
        logger.debug("Click trigger detected in menu bar")
        onTrigger?(.click)
    }

    private func handleLeftMouseDragged(_ event: NSEvent) {
        guard userDragEnabled, !isSuspended else { return }

        // Check if ⌘ is held down (user is rearranging menu bar icons)
        guard event.modifierFlags.contains(.command) else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard isInMenuBarRegion(mouseLocation) else { return }

        // Start user drag if not already dragging
        if !isUserDragging {
            isUserDragging = true
            logger.debug("⌘+drag started in menu bar - revealing all icons")
            onTrigger?(.userDrag)
        }
    }

    private func handleLeftMouseUp(_: NSEvent) {
        // End user drag when mouse is released
        if isUserDragging {
            isUserDragging = false
            logger.debug("⌘+drag ended - allowing auto-hide")
            onUserDragEnd?()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        // If ⌘ is released while dragging, end the drag
        if isUserDragging, !event.modifierFlags.contains(.command) {
            isUserDragging = false
            logger.debug("⌘ released during drag - allowing auto-hide")
            onUserDragEnd?()
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
                guard let self, self.isMouseInMenuBar else { return }
                self.onTrigger?(.hover)
            }
        }
    }

    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }
}
