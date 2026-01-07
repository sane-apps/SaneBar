import AppKit
import Combine
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "HoverService")

// MARK: - HoverServiceProtocol

/// @mockable
@MainActor
protocol HoverServiceProtocol {
    var isHovering: Bool { get }
    func configure(
        mainItem: NSStatusItem,
        separatorItem: NSStatusItem,
        onHoverStart: @escaping () -> Void,
        onHoverEnd: @escaping () -> Void
    )
    func setEnabled(_ enabled: Bool)
    func setDelay(_ delay: TimeInterval)
}

// MARK: - HoverService

/// Service that detects mouse hover over menu bar items and triggers show/hide.
///
/// Uses a global event monitor to track mouse movement. When the mouse enters
/// the region near the SaneBar icon or separator, it triggers a callback after
/// a configurable delay.
@MainActor
final class HoverService: ObservableObject, HoverServiceProtocol {

    // MARK: - Published State

    @Published private(set) var isHovering = false

    // MARK: - Configuration

    private weak var mainItem: NSStatusItem?
    private weak var separatorItem: NSStatusItem?
    private var onHoverStart: (() -> Void)?
    private var onHoverEnd: (() -> Void)?

    private var isEnabled = false
    private var hoverDelay: TimeInterval = 0.3

    // MARK: - Event Monitoring

    private var eventMonitor: Any?
    private var hoverTimer: Timer?
    private var wasInHoverZone = false
    private var lastCheckTime: TimeInterval = 0

    // MARK: - Initialization

    init() {}

    deinit {
        // Clean up is handled in stopMonitoring which must be called before deinit
    }

    // MARK: - Configuration

    func configure(
        mainItem: NSStatusItem,
        separatorItem: NSStatusItem,
        onHoverStart: @escaping () -> Void,
        onHoverEnd: @escaping () -> Void
    ) {
        self.mainItem = mainItem
        self.separatorItem = separatorItem
        self.onHoverStart = onHoverStart
        self.onHoverEnd = onHoverEnd

        logger.info("HoverService configured")
    }

    func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled

        if enabled {
            startMonitoring()
        } else {
            stopMonitoring()
        }

        logger.info("HoverService enabled: \(enabled)")
    }

    func setDelay(_ delay: TimeInterval) {
        hoverDelay = max(0.1, min(delay, 2.0)) // Clamp between 0.1 and 2 seconds
    }

    // MARK: - Event Monitoring

    private func startMonitoring() {
        guard eventMonitor == nil else { return }

        // Monitor mouse moved events globally
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMoved(event)
            }
        }

        logger.info("Started hover monitoring")
    }

    private func stopMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        cancelHoverTimer()
        wasInHoverZone = false
        isHovering = false

        logger.info("Stopped hover monitoring")
    }

    private func handleMouseMoved(_ event: NSEvent) {
        // Throttle checks to ~10Hz (every 0.1s) to save CPU
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastCheckTime > 0.1 else { return }
        lastCheckTime = now

        let mouseLocation = NSEvent.mouseLocation

        // Check if mouse is in the hover zone
        let inZone = isMouseInHoverZone(mouseLocation)

        if inZone && !wasInHoverZone {
            // Entered hover zone - start timer
            startHoverTimer()
            wasInHoverZone = true
        } else if !inZone && wasInHoverZone {
            // Left hover zone - cancel timer and notify
            cancelHoverTimer()
            wasInHoverZone = false

            if isHovering {
                isHovering = false
                onHoverEnd?()
                logger.debug("Hover ended")
            }
        }
    }

    private func isMouseInHoverZone(_ mouseLocation: NSPoint) -> Bool {
        // Get frames of the status items
        guard let mainButton = mainItem?.button,
              let mainWindow = mainButton.window else {
            return false
        }

        // Expand the hover zone to include the separator area
        var hoverFrame = mainWindow.frame

        // Extend left to include separator
        if let separatorButton = separatorItem?.button,
           let separatorWindow = separatorButton.window {
            let separatorFrame = separatorWindow.frame
            // Union the frames
            hoverFrame = hoverFrame.union(separatorFrame)
        }

        // Add some padding (20px on each side)
        let padding: CGFloat = 20
        hoverFrame = hoverFrame.insetBy(dx: -padding, dy: -padding)

        return hoverFrame.contains(mouseLocation)
    }

    // MARK: - Hover Timer

    private func startHoverTimer() {
        cancelHoverTimer()

        hoverTimer = Timer.scheduledTimer(withTimeInterval: hoverDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.wasInHoverZone else { return }
                self.isHovering = true
                self.onHoverStart?()
                logger.debug("Hover triggered after \(self.hoverDelay)s delay")
            }
        }
    }

    private func cancelHoverTimer() {
        hoverTimer?.invalidate()
        hoverTimer = nil
    }
}
