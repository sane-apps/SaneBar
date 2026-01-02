import Foundation
import CoreGraphics
import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "EventService")

// MARK: - EventServiceError

enum EventServiceError: LocalizedError {
    case eventCreationFailed
    case postFailed
    case invalidPosition

    var errorDescription: String? {
        switch self {
        case .eventCreationFailed:
            return "Failed to create CGEvent"
        case .postFailed:
            return "Failed to post event"
        case .invalidPosition:
            return "Invalid position for event"
        }
    }
}

// MARK: - EventServiceProtocol

/// @mockable
protocol EventServiceProtocol: Sendable {
    func simulateMouseDown(at position: CGPoint, button: CGMouseButton) throws
    func simulateMouseUp(at position: CGPoint, button: CGMouseButton) throws
    func simulateMouseDrag(from start: CGPoint, to end: CGPoint, button: CGMouseButton, withCommand: Bool) async throws
    func simulateClick(at position: CGPoint, button: CGMouseButton) async throws
    func currentMouseLocation() -> CGPoint
    func moveMenuBarItem(from startX: CGFloat, to endX: CGFloat) async throws
}

// MARK: - EventService

/// Service for simulating mouse events via CoreGraphics CGEvent API
/// Used to move menu bar items by simulating Cmd+drag operations
final class EventService: EventServiceProtocol, Sendable {

    // MARK: - Singleton

    static let shared = EventService()

    // MARK: - Configuration

    /// Duration for drag operations in seconds
    private let dragDuration: TimeInterval = 0.3

    /// Number of intermediate points during drag
    private let dragSteps: Int = 20

    /// Delay between drag steps in nanoseconds
    private var stepDelay: UInt64 {
        UInt64((dragDuration / Double(dragSteps)) * 1_000_000_000)
    }

    // MARK: - Mouse Events

    /// Get current mouse cursor position
    func currentMouseLocation() -> CGPoint {
        NSEvent.mouseLocation
    }

    /// Simulate mouse button down at position
    func simulateMouseDown(at position: CGPoint, button: CGMouseButton = .left) throws {
        let eventType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: position,
            mouseButton: button
        ) else {
            throw EventServiceError.eventCreationFailed
        }

        event.post(tap: .cghidEventTap)
    }

    /// Simulate mouse button up at position
    func simulateMouseUp(at position: CGPoint, button: CGMouseButton = .left) throws {
        let eventType: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: position,
            mouseButton: button
        ) else {
            throw EventServiceError.eventCreationFailed
        }

        event.post(tap: .cghidEventTap)
    }

    /// Simulate mouse move/drag to position
    func simulateMouseMove(to position: CGPoint, dragging: Bool = false, button: CGMouseButton = .left) throws {
        let eventType: CGEventType = dragging
            ? (button == .left ? .leftMouseDragged : .rightMouseDragged)
            : .mouseMoved

        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: eventType,
            mouseCursorPosition: position,
            mouseButton: button
        ) else {
            throw EventServiceError.eventCreationFailed
        }

        event.post(tap: .cghidEventTap)
    }

    /// Simulate a complete drag operation from start to end
    /// - Parameters:
    ///   - start: Starting position
    ///   - end: Ending position
    ///   - button: Mouse button to use
    ///   - withCommand: Whether to hold Command key (for menu bar item rearrangement)
    func simulateMouseDrag(
        from start: CGPoint,
        to end: CGPoint,
        button: CGMouseButton = .left,
        withCommand: Bool = false
    ) async throws {
        // Mouse down at start position
        guard let downEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: button == .left ? .leftMouseDown : .rightMouseDown,
            mouseCursorPosition: start,
            mouseButton: button
        ) else {
            throw EventServiceError.eventCreationFailed
        }

        // Add Command modifier if needed (for menu bar item rearrangement)
        if withCommand {
            downEvent.flags = .maskCommand
        }

        downEvent.post(tap: .cghidEventTap)

        // Interpolate drag path
        for step in 1...dragSteps {
            let progress = CGFloat(step) / CGFloat(dragSteps)
            let currentX = start.x + (end.x - start.x) * progress
            let currentY = start.y + (end.y - start.y) * progress
            let currentPosition = CGPoint(x: currentX, y: currentY)

            guard let dragEvent = CGEvent(
                mouseEventSource: nil,
                mouseType: button == .left ? .leftMouseDragged : .rightMouseDragged,
                mouseCursorPosition: currentPosition,
                mouseButton: button
            ) else {
                throw EventServiceError.eventCreationFailed
            }

            if withCommand {
                dragEvent.flags = .maskCommand
            }

            dragEvent.post(tap: .cghidEventTap)

            try await Task.sleep(nanoseconds: stepDelay)
        }

        // Mouse up at end position
        guard let upEvent = CGEvent(
            mouseEventSource: nil,
            mouseType: button == .left ? .leftMouseUp : .rightMouseUp,
            mouseCursorPosition: end,
            mouseButton: button
        ) else {
            throw EventServiceError.eventCreationFailed
        }

        if withCommand {
            upEvent.flags = .maskCommand
        }

        upEvent.post(tap: .cghidEventTap)
    }

    /// Simulate a click at position
    func simulateClick(at position: CGPoint, button: CGMouseButton = .left) async throws {
        try simulateMouseDown(at: position, button: button)
        try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        try simulateMouseUp(at: position, button: button)
    }

    // MARK: - Menu Bar Specific

    /// Move a menu bar item by simulating Cmd+drag
    /// Menu bar items can be rearranged by Cmd+dragging them
    func moveMenuBarItem(from startX: CGFloat, to endX: CGFloat) async throws {
        // Menu bar is at y = 0 in screen coordinates (top of screen)
        // But CGEvent uses flipped coordinates, so we need the actual menu bar Y
        guard let screen = NSScreen.main else {
            logger.error("ERROR: No main screen found")
            throw EventServiceError.invalidPosition
        }

        // Menu bar height is typically 24-37 points depending on notch
        // CGEvent uses bottom-left origin, so Y is distance from bottom
        let menuBarY = screen.frame.height - 12 // Center of menu bar

        let start = CGPoint(x: startX, y: menuBarY)
        let end = CGPoint(x: endX, y: menuBarY)

        logger.info("moveMenuBarItem: screen.height=\(screen.frame.height)")
        logger.info("Cmd+drag from (\(start.x), \(start.y)) to (\(end.x), \(end.y))")

        try await simulateMouseDrag(from: start, to: end, button: .left, withCommand: true)
        logger.info("Cmd+drag completed")
    }
}
