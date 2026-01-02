import AppKit
import Combine

// MARK: - HoverServiceProtocol

/// @mockable
@MainActor
protocol HoverServiceProtocol {
    var isHovering: Bool { get }
    var isEnabled: Bool { get set }

    func startMonitoring()
    func stopMonitoring()
    func setHoverRegion(_ region: NSRect)
}

// MARK: - HoverService

/// Service that monitors mouse position and triggers show/hide on hover
/// Uses global event monitor to track mouse across all apps
@MainActor
final class HoverService: ObservableObject, HoverServiceProtocol {

    // MARK: - Published State

    @Published private(set) var isHovering = false
    @Published var isEnabled = true

    // MARK: - Configuration

    /// Region where hover triggers show (near delimiter)
    private var hoverRegion: NSRect = .zero

    /// Delay before showing hidden items on hover
    var hoverDelay: TimeInterval = 0.3

    /// Delay before hiding when mouse leaves
    var hideDelay: TimeInterval = 0.5

    // MARK: - Dependencies

    private weak var hidingService: HidingService?

    // MARK: - Private State

    private var eventMonitor: Any?
    private var hoverTimer: Timer?
    private var hideTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Initialization

    init(hidingService: HidingService? = nil) {
        self.hidingService = hidingService
    }

    /// Connect to HidingService
    func configure(with hidingService: HidingService) {
        self.hidingService = hidingService
    }

    // MARK: - Region Configuration

    /// Set the hover detection region
    /// Should be set to the area around the delimiter/separator icon
    func setHoverRegion(_ region: NSRect) {
        hoverRegion = region
    }

    /// Set hover region based on status item button
    func setHoverRegion(around button: NSStatusBarButton, padding: CGFloat = 20) {
        guard let window = button.window else { return }

        // Get button frame in screen coordinates
        let buttonFrame = button.convert(button.bounds, to: nil)
        let screenFrame = window.convertToScreen(buttonFrame)

        // Expand the region by padding
        hoverRegion = screenFrame.insetBy(dx: -padding, dy: -padding)
    }

    // MARK: - Monitoring

    /// Start monitoring mouse position
    func startMonitoring() {
        guard isEnabled else { return }
        guard eventMonitor == nil else { return }

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMoved(event)
            }
        }

        // Also monitor local events (when our window is focused)
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved) { [weak self] event in
            Task { @MainActor in
                self?.handleMouseMoved(event)
            }
            return event
        }

        // Store local monitor with global one
        if let localMonitor {
            // We need to track both monitors
            // Store them together - we'll remove them together
            objc_setAssociatedObject(
                eventMonitor as Any,
                "localMonitor",
                localMonitor,
                .OBJC_ASSOCIATION_RETAIN
            )
        }
    }

    /// Stop monitoring mouse position
    func stopMonitoring() {
        if let monitor = eventMonitor {
            // Remove local monitor if stored
            if let localMonitor = objc_getAssociatedObject(monitor, "localMonitor") {
                NSEvent.removeMonitor(localMonitor)
            }
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }

        hoverTimer?.invalidate()
        hoverTimer = nil
        hideTimer?.invalidate()
        hideTimer = nil
    }

    // MARK: - Event Handling

    private func handleMouseMoved(_ event: NSEvent) {
        guard isEnabled else { return }
        guard !hoverRegion.isEmpty else { return }

        let mouseLocation = NSEvent.mouseLocation

        // Check if mouse is in hover region
        let wasHovering = isHovering
        let nowHovering = hoverRegion.contains(mouseLocation)

        if nowHovering && !wasHovering {
            // Mouse entered region
            handleMouseEntered()
        } else if !nowHovering && wasHovering {
            // Mouse left region
            handleMouseExited()
        }

        isHovering = nowHovering
    }

    private func handleMouseEntered() {
        // Cancel any pending hide
        hideTimer?.invalidate()
        hideTimer = nil

        // Start hover timer
        hoverTimer?.invalidate()
        hoverTimer = Timer.scheduledTimer(withTimeInterval: hoverDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.triggerShow()
            }
        }
    }

    private func handleMouseExited() {
        // Cancel hover timer
        hoverTimer?.invalidate()
        hoverTimer = nil

        // Start hide timer
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: hideDelay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.triggerHide()
            }
        }
    }

    private func triggerShow() {
        guard let hidingService else { return }

        Task {
            do {
                try await hidingService.show()
            } catch {
                print("Hover show failed: \(error)")
            }
        }
    }

    private func triggerHide() {
        guard let hidingService else { return }

        Task {
            do {
                try await hidingService.hide()
            } catch {
                print("Hover hide failed: \(error)")
            }
        }
    }

    // MARK: - Cleanup

    deinit {
        // Note: Can't access self properties in deinit for @MainActor class
        // The monitors will be cleaned up when the object is deallocated
    }
}

// MARK: - Menu Bar Region Helpers

extension HoverService {
    /// Calculate hover region for menu bar area (top of screen)
    static func menuBarHoverRegion(screen: NSScreen = .main ?? NSScreen.screens[0]) -> NSRect {
        let screenFrame = screen.frame
        let menuBarHeight: CGFloat = 24 // Standard menu bar height

        return NSRect(
            x: screenFrame.minX,
            y: screenFrame.maxY - menuBarHeight,
            width: screenFrame.width,
            height: menuBarHeight
        )
    }

    /// Calculate hover region for a specific X range in menu bar
    static func menuBarHoverRegion(
        fromX: CGFloat,
        toX: CGFloat,
        screen: NSScreen = .main ?? NSScreen.screens[0]
    ) -> NSRect {
        let screenFrame = screen.frame
        let menuBarHeight: CGFloat = 24

        return NSRect(
            x: min(fromX, toX),
            y: screenFrame.maxY - menuBarHeight,
            width: abs(toX - fromX),
            height: menuBarHeight
        )
    }
}
