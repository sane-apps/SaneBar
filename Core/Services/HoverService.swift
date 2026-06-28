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
    /// Whether the mouse cursor is currently in the menu bar region.
    /// Used by rehide guards to prevent hiding while user interacts with any menu.
    var isMouseInMenuBar: Bool { get }
    func noteExplicitStatusItemInteraction()
    func start()
    func stop()
    /// Begin a passive hover dwell for the always-visible main status item. The
    /// global mouse monitor cannot see the cursor pass over our own status-item
    /// button, so the button's tracking area drives reveal through this — honoring
    /// the same Reveal-delay dwell as the strip-hover path (#160/#161).
    func beginMainStatusItemHoverDwell()
    /// Cancel an in-flight main status-item hover dwell (cursor left the icon).
    func cancelMainStatusItemHoverDwell()
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
    var isSuspended: Bool = false {
        didSet {
            guard isSuspended != oldValue else { return }
            if isSuspended {
                cancelHoverTimer()
            } else {
                refreshMouseInMenuBarState()
            }
        }
    }

    /// Called when hover/scroll should reveal icons
    var onTrigger: ((TriggerReason) -> Void)?

    /// Called when ⌘+drag ends (user stopped rearranging)
    var onUserDragEnd: (() -> Void)?

    /// Called when mouse leaves menu bar area (optional auto-hide)
    var onLeaveMenuBar: (() -> Void)?

    /// Track whether user is currently ⌘+dragging
    private var isUserDragging = false

    /// Shared dwell before a passive hover OR scroll reveal fires. Defaults to a
    /// deliberate 2s so incidental cursor passes and quick scrolls don't pop the
    /// hidden icons open constantly; user-adjustable 0.05…2.0s in settings.
    var hoverDelay: TimeInterval = 2.0

    /// Height of the hover detection zone (typically menu bar height)
    private let detectionZoneHeight: CGFloat = 24

    /// How far outside menu bar triggers leave event.
    /// 200px covers tall dropdown menus (100+ items). Previously 50px, which caused
    /// isMouseInMenuBar to go false while user was still interacting with tall menus (#97).
    private let leaveThreshold: CGFloat = 200

    private var globalMonitor: Any?
    private var hoverTimer: Timer?
    private(set) var isMouseInMenuBar = false
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

    /// Refreshes cached mouse-in-menu-bar state from the current cursor position.
    /// Useful when monitoring was suspended and no mouse-move event fired yet.
    func refreshMouseInMenuBarState() {
        let mouseLocation = NSEvent.mouseLocation
        isMouseInMenuBar = Self.isPointInMenuBarInteractionRegion(
            mouseLocation,
            screens: NSScreen.screens,
            detectionZoneHeight: detectionZoneHeight,
            leaveThreshold: leaveThreshold
        )
    }

    /// Refresh cached mouse state after Browse Icons panel dismissal.
    /// Uses strict menu-strip bounds (no dropdown zone) so panel-close events
    /// don't leave auto-rehide blocked while the cursor is still near the top.
    func refreshMouseInMenuBarStateForBrowseDismissal() {
        let mouseLocation = NSEvent.mouseLocation
        isMouseInMenuBar = Self.isPointInMenuBarStrip(
            mouseLocation,
            screens: NSScreen.screens,
            detectionZoneHeight: detectionZoneHeight
        )
    }

    /// Direct status-item clicks should win over any pending passive hover reveal.
    /// Otherwise a stale hover timer can fire after an explicit click and make
    /// the main icon feel inconsistent.
    func noteExplicitStatusItemInteraction() {
        cancelHoverTimer()
        isMouseInMenuBar = true
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

            // Determine scroll direction (positive = scroll up, negative = scroll down)
            let direction: ScrollDirection = deltaY > 0 ? .up : .down
            logger.debug("Scroll dwell started in menu bar: \(deltaY > 0 ? "up" : "down")")
            // Passive scroll reveal honors the same dwell delay as hover instead of
            // firing instantly. A quick incidental two-finger scroll across the menu
            // bar no longer pops the hidden icons open the moment it happens — the
            // cursor must stay in the menu bar region for the delay first.
            scheduleDelayedTrigger(.scroll(direction: direction))
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
        Self.isPointInMenuBarInteractionRegion(
            point,
            screens: NSScreen.screens,
            detectionZoneHeight: detectionZoneHeight,
            leaveThreshold: leaveThreshold
        )
    }

    nonisolated static func screenFrameContainingPoint(
        _ point: NSPoint,
        screenFrames: [CGRect]
    ) -> CGRect? {
        screenFrames.first(where: { NSMouseInRect(point, $0, false) })
    }

    nonisolated static func isPointInMenuBarInteractionRegion(
        _ point: NSPoint,
        screens: [NSScreen],
        detectionZoneHeight: CGFloat = 24,
        leaveThreshold: CGFloat = 200
    ) -> Bool {
        isPointInMenuBarInteractionRegion(
            point,
            screenFrames: screens.map(\.frame),
            detectionZoneHeight: detectionZoneHeight,
            leaveThreshold: leaveThreshold
        )
    }

    nonisolated static func isPointInMenuBarInteractionRegion(
        _ point: NSPoint,
        screenFrames: [CGRect],
        detectionZoneHeight: CGFloat = 24,
        leaveThreshold: CGFloat = 200
    ) -> Bool {
        guard let screenFrame = screenFrameContainingPoint(point, screenFrames: screenFrames) else {
            return false
        }

        let menuBarTop = screenFrame.maxY
        let menuBarBottom = menuBarTop - detectionZoneHeight

        // In the menu bar strip itself.
        if point.y >= menuBarBottom, point.y <= menuBarTop {
            return true
        }

        // In the interaction zone directly below menu bar (for open menus/popovers).
        let distanceBelowMenuBar = menuBarTop - point.y
        return distanceBelowMenuBar > 0 && distanceBelowMenuBar <= leaveThreshold
    }

    nonisolated static func isPointInMenuBarStrip(
        _ point: NSPoint,
        screens: [NSScreen],
        detectionZoneHeight: CGFloat = 24
    ) -> Bool {
        isPointInMenuBarStrip(
            point,
            screenFrames: screens.map(\.frame),
            detectionZoneHeight: detectionZoneHeight
        )
    }

    nonisolated static func isPointInMenuBarStrip(
        _ point: NSPoint,
        screenFrames: [CGRect],
        detectionZoneHeight: CGFloat = 24
    ) -> Bool {
        guard let screenFrame = screenFrameContainingPoint(point, screenFrames: screenFrames) else {
            return false
        }

        let menuBarTop = screenFrame.maxY
        let menuBarBottom = menuBarTop - detectionZoneHeight
        return point.y >= menuBarBottom && point.y <= menuBarTop
    }

    nonisolated static func distanceFromMenuBarTop(
        _ point: NSPoint,
        screenFrames: [CGRect]
    ) -> CGFloat? {
        guard let screenFrame = screenFrameContainingPoint(point, screenFrames: screenFrames) else {
            return nil
        }
        return screenFrame.maxY - point.y
    }

    private func distanceFromMenuBarTop(_ point: NSPoint) -> CGFloat {
        Self.distanceFromMenuBarTop(point, screenFrames: NSScreen.screens.map(\.frame))
            ?? .greatestFiniteMagnitude
    }

    /// Begin a passive hover dwell for the always-visible main status item.
    ///
    /// The global mouse monitor never sees the cursor pass over our OWN status-item
    /// button — those events are delivered to the button, not to other apps — so the
    /// button installs an `NSTrackingArea` whose `mouseEntered:` calls this. It routes
    /// through the same `hoverDelay` dwell + in-region re-check as the strip-hover
    /// path, so a cursor merely brushing the SaneBar icon no longer reveals the hidden
    /// items instantly (#160/#161 — "the menu keeps popping open every few minutes").
    /// The caller gates on `showOnHover`; here we additionally respect `isSuspended`
    /// (e.g. while the Find Icon window is open).
    func beginMainStatusItemHoverDwell() {
        guard !isSuspended else { return }
        scheduleDelayedTrigger(.hover)
    }

    /// Cancel an in-flight main status-item hover dwell — the cursor left the icon
    /// (`mouseExited:`) before the dwell elapsed, so no reveal should fire.
    func cancelMainStatusItemHoverDwell() {
        cancelHoverTimer()
    }

    private func scheduleHoverTrigger() {
        scheduleDelayedTrigger(.hover)
    }

    /// Schedule a passive reveal (hover or scroll) after `hoverDelay`, re-checking
    /// at fire time that the cursor is still in the menu bar region. Any deliberate
    /// action or leaving the menu bar cancels it via `cancelHoverTimer`, so a quick
    /// incidental hover/scroll never pops the hidden icons. Both passive triggers
    /// share one timer because they cannot be dwelling at the same time.
    private func scheduleDelayedTrigger(_ trigger: TriggerReason) {
        cancelHoverTimer()

        hoverTimer = Timer.scheduledTimer(withTimeInterval: hoverDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isMouseInMenuBar || self.isInMenuBarRegion(NSEvent.mouseLocation) else { return }
                self.onTrigger?(trigger)
            }
        }
    }

    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }
}
