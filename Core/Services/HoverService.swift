import AppKit
import Combine
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "HoverService")


@MainActor
protocol HoverServiceProtocol {
    var isEnabled: Bool { get set }
    var scrollEnabled: Bool { get set }
    var clickEnabled: Bool { get set }
    var trackMouseLeave: Bool { get set }
    var isMouseInMenuBar: Bool { get }
    func noteExplicitStatusItemInteraction()
    func start()
    func stop()
    func beginMainStatusItemHoverDwell()
    func cancelMainStatusItemHoverDwell()
}


@MainActor
final class HoverService: HoverServiceProtocol {

    enum TriggerReason: Equatable {
        case hover
        case scroll(direction: ScrollDirection)
        case click
        case userDrag
    }

    enum ScrollDirection: Equatable {
        case up
        case down
    }


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

    var userDragEnabled: Bool = false {
        didSet {
            guard userDragEnabled != oldValue else { return }
            updateMonitoringState()
        }
    }

    var trackMouseLeave: Bool = false {
        didSet {
            guard trackMouseLeave != oldValue else { return }
            updateMonitoringState()
        }
    }

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

    var onTrigger: ((TriggerReason) -> Void)?

    var onUserDragEnd: (() -> Void)?

    var onLeaveMenuBar: (() -> Void)?

    private var isUserDragging = false

    var hoverDelay: TimeInterval = 2.0

    private let detectionZoneHeight: CGFloat = 24

    private let leaveThreshold: CGFloat = 200

    private var globalMonitor: Any?
    private var hoverTimer: Timer?
    private(set) var isMouseInMenuBar = false
    private var lastScrollTime: Date = .distantPast
    private var lastMouseMovedTime: CFAbsoluteTime = 0
    private let mouseMovedThrottleInterval: CFAbsoluteTime = 0.05


    init() {}

    deinit {
    }


    func start() {
        guard isEnabled || scrollEnabled || clickEnabled || trackMouseLeave else { return }
        startMonitoring()
    }

    func stop() {
        stopMonitoring()
    }

    func refreshMouseInMenuBarState() {
        let mouseLocation = NSEvent.mouseLocation
        isMouseInMenuBar = Self.isPointInMenuBarInteractionRegion(
            mouseLocation,
            screens: NSScreen.screens,
            detectionZoneHeight: detectionZoneHeight,
            leaveThreshold: leaveThreshold
        )
    }

    func refreshMouseInMenuBarStateForBrowseDismissal() {
        let mouseLocation = NSEvent.mouseLocation
        isMouseInMenuBar = Self.isPointInMenuBarStrip(
            mouseLocation,
            screens: NSScreen.screens,
            detectionZoneHeight: detectionZoneHeight
        )
    }

    func noteExplicitStatusItemInteraction() {
        cancelHoverTimer()
        isMouseInMenuBar = true
    }


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

        let eventMask: NSEvent.EventTypeMask = [
            .mouseMoved,
            .scrollWheel,
            .leftMouseDown,
            .leftMouseDragged,
            .leftMouseUp,
            .flagsChanged
        ]

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: eventMask) { [weak self] event in
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
        guard isEnabled || trackMouseLeave, !isSuspended else { return }

        let mouseLocation = NSEvent.mouseLocation
        let inMenuBar = isInMenuBarRegion(mouseLocation)

        if inMenuBar, !isMouseInMenuBar {
            isMouseInMenuBar = true
            if isEnabled {
                scheduleHoverTrigger()
            }
        } else if !inMenuBar, isMouseInMenuBar {
            let distanceFromMenuBar = distanceFromMenuBarTop(mouseLocation)
            if distanceFromMenuBar > leaveThreshold {
                isMouseInMenuBar = false
                cancelHoverTimer()
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

        let deltaY = event.scrollingDeltaY
        if abs(deltaY) > 5 {
            let now = Date()
            guard now.timeIntervalSince(lastScrollTime) > 0.3 else { return }
            lastScrollTime = now

            let direction: ScrollDirection = deltaY > 0 ? .up : .down
            logger.debug("Scroll dwell started in menu bar: \(deltaY > 0 ? "up" : "down")")
            scheduleDelayedTrigger(.scroll(direction: direction))
        }
    }

    private func handleLeftMouseDown(_: NSEvent) {
        guard clickEnabled, !isSuspended else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard isInMenuBarRegion(mouseLocation) else { return }

        cancelHoverTimer()
        logger.debug("Click trigger detected in menu bar")
        onTrigger?(.click)
    }

    private func handleLeftMouseDragged(_ event: NSEvent) {
        guard userDragEnabled, !isSuspended else { return }

        guard event.modifierFlags.contains(.command) else { return }

        let mouseLocation = NSEvent.mouseLocation
        guard isInMenuBarRegion(mouseLocation) else { return }

        if !isUserDragging {
            isUserDragging = true
            logger.debug("⌘+drag started in menu bar - revealing all icons")
            onTrigger?(.userDrag)
        }
    }

    private func handleLeftMouseUp(_: NSEvent) {
        if isUserDragging {
            isUserDragging = false
            logger.debug("⌘+drag ended - allowing auto-hide")
            onUserDragEnd?()
        }
    }

    private func handleFlagsChanged(_ event: NSEvent) {
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

        if point.y >= menuBarBottom, point.y <= menuBarTop {
            return true
        }

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

    func beginMainStatusItemHoverDwell() {
        guard !isSuspended else { return }
        scheduleDelayedTrigger(.hover)
    }

    func cancelMainStatusItemHoverDwell() {
        cancelHoverTimer()
    }

    private func scheduleHoverTrigger() {
        scheduleDelayedTrigger(.hover)
    }

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
