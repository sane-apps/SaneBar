import Foundation
import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "HidingService")

// MARK: - HidingServiceError

enum HidingServiceError: LocalizedError {
    case noPermission
    case itemNotFound
    case moveOperationFailed
    case delimiterNotFound

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Accessibility permission required"
        case .itemNotFound:
            return "Menu bar item not found"
        case .moveOperationFailed:
            return "Failed to move menu bar item"
        case .delimiterNotFound:
            return "Section delimiter not found"
        }
    }
}

// MARK: - HidingState

enum HidingState: String, Codable, Sendable {
    case hidden      // Hidden items are collapsed
    case expanded    // Hidden items are visible
}

// MARK: - HidingServiceProtocol

/// @mockable
@MainActor
protocol HidingServiceProtocol {
    var state: HidingState { get }
    var isAnimating: Bool { get }

    func toggle(items: [StatusItemModel]) async throws
    func show(items: [StatusItemModel]) async throws
    func hide(items: [StatusItemModel]) async throws
    func moveItem(_ item: StatusItemModel, to section: StatusItemModel.ItemSection) async throws
}

// MARK: - HidingService

/// Service that manages hiding/showing menu bar items
/// Uses synthetic mouse events to Cmd+drag items between sections
@MainActor
final class HidingService: ObservableObject, HidingServiceProtocol {

    // MARK: - Published State

    @Published private(set) var state: HidingState = .hidden
    @Published private(set) var isAnimating = false

    // MARK: - Dependencies

    private let eventService: EventServiceProtocol
    private let accessibilityService: AccessibilityServiceProtocol
    private let persistenceService: PersistenceServiceProtocol

    // MARK: - Configuration

    /// X position of the hidden section delimiter (SaneBar's main icon)
    private var delimiterX: CGFloat?

    /// X position of the always-hidden section delimiter (secondary icon)
    private var alwaysHiddenDelimiterX: CGFloat?

    /// Closure to get current items for auto-rehide
    var itemsProvider: (() -> [StatusItemModel])?

    // MARK: - Initialization

    init(
        eventService: EventServiceProtocol = EventService.shared,
        accessibilityService: AccessibilityServiceProtocol? = nil,
        persistenceService: PersistenceServiceProtocol = PersistenceService.shared
    ) {
        self.eventService = eventService
        // AccessibilityService is MainActor, so we need to handle this carefully
        self.accessibilityService = accessibilityService ?? AccessibilityService()
        self.persistenceService = persistenceService
    }

    // MARK: - Delimiter Management

    /// Set the X position of section delimiters
    func setDelimiterPositions(hidden: CGFloat, alwaysHidden: CGFloat? = nil) {
        delimiterX = hidden
        alwaysHiddenDelimiterX = alwaysHidden
    }

    // MARK: - Show/Hide Operations

    /// Toggle between hidden and expanded states
    func toggle(items: [StatusItemModel]) async throws {
        switch state {
        case .hidden:
            try await show(items: items)
        case .expanded:
            try await hide(items: items)
        }
    }

    /// Expand to show hidden items by moving them left of delimiter
    func show(items: [StatusItemModel]) async throws {
        guard !isAnimating else { return }
        guard state == .hidden else { return }

        isAnimating = true
        defer { isAnimating = false }

        logger.info("show() called with \(items.count) items to reveal")

        // Move each hidden item to visible area (left of delimiter)
        for item in items where item.section == .hidden {
            guard let itemX = item.screenX, let targetX = delimiterX else {
                logger.warning("Skipping item '\(item.displayName, privacy: .public)' - missing position")
                continue
            }

            // Move to left of delimiter (visible area)
            let destinationX = targetX - 50
            logger.info("Moving '\(item.displayName, privacy: .public)' from \(itemX) to \(destinationX)")

            do {
                try await eventService.moveMenuBarItem(from: itemX, to: destinationX)
                try await Task.sleep(nanoseconds: 150_000_000) // 150ms between moves
            } catch {
                logger.error("Failed to move item: \(error.localizedDescription, privacy: .public)")
            }
        }

        state = .expanded

        NotificationCenter.default.post(
            name: .hiddenSectionShown,
            object: nil
        )
    }

    /// Collapse to hide items by moving them right of delimiter
    func hide(items: [StatusItemModel]) async throws {
        guard !isAnimating else { return }
        guard state == .expanded else { return }

        isAnimating = true
        defer { isAnimating = false }

        logger.info("hide() called with \(items.count) items to hide")

        // Move each hidden-section item back to hidden area (right of delimiter)
        for item in items where item.section == .hidden {
            guard let itemX = item.screenX, let targetX = delimiterX else {
                logger.warning("Skipping item '\(item.displayName, privacy: .public)' - missing position")
                continue
            }

            // Move to right of delimiter (hidden area)
            let destinationX = targetX + 30
            logger.info("Moving '\(item.displayName, privacy: .public)' from \(itemX) to \(destinationX)")

            do {
                try await eventService.moveMenuBarItem(from: itemX, to: destinationX)
                try await Task.sleep(nanoseconds: 150_000_000) // 150ms between moves
            } catch {
                logger.error("Failed to move item: \(error.localizedDescription, privacy: .public)")
            }
        }

        state = .hidden

        NotificationCenter.default.post(
            name: .hiddenSectionHidden,
            object: nil
        )
    }

    // MARK: - Item Movement

    /// Move an item to a different section
    /// This uses Cmd+drag simulation to physically move the item
    func moveItem(_ item: StatusItemModel, to section: StatusItemModel.ItemSection) async throws {
        logger.info("moveItem called for '\(item.displayName, privacy: .public)' to section: \(section.rawValue, privacy: .public)")
        logger.info("item.screenX = \(item.screenX?.description ?? "NIL", privacy: .public)")

        guard let itemX = item.screenX else {
            logger.error("ERROR: screenX is nil - cannot move item")
            throw HidingServiceError.itemNotFound
        }

        guard let targetX = positionForSection(section) else {
            logger.error("ERROR: delimiterX is nil - delimiter not set")
            throw HidingServiceError.delimiterNotFound
        }

        logger.info("Moving from X=\(itemX) to targetX=\(targetX)")

        isAnimating = true
        defer { isAnimating = false }

        // Calculate drag destination based on section
        // Items to the LEFT of delimiter are visible
        // Items to the RIGHT of delimiter are hidden
        let destinationX: CGFloat
        switch section {
        case .alwaysVisible:
            // Move to left of delimiter (visible area)
            destinationX = targetX - 50
        case .hidden:
            // Move to right of delimiter (hidden area)
            destinationX = targetX + 30
        case .collapsed:
            // Move to right of always-hidden delimiter
            destinationX = (alwaysHiddenDelimiterX ?? targetX) + 30
        }

        // Perform the drag
        try await eventService.moveMenuBarItem(from: itemX, to: destinationX)

        // Small delay for macOS to process the move
        try await Task.sleep(nanoseconds: 100_000_000)
    }

    /// Get the target X position for a section
    private func positionForSection(_ section: StatusItemModel.ItemSection) -> CGFloat? {
        switch section {
        case .alwaysVisible, .hidden:
            return delimiterX
        case .collapsed:
            return alwaysHiddenDelimiterX ?? delimiterX
        }
    }

    // MARK: - Auto-Rehide

    private var rehideTask: Task<Void, Never>?

    /// Schedule auto-rehide after delay
    func scheduleRehide(after delay: TimeInterval) {
        rehideTask?.cancel()

        rehideTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if !Task.isCancelled {
                    let items = itemsProvider?() ?? []
                    try await hide(items: items)
                }
            } catch {
                // Task cancelled or hide failed - ignore
            }
        }
    }

    /// Cancel pending auto-rehide
    func cancelRehide() {
        rehideTask?.cancel()
        rehideTask = nil
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let hiddenSectionShown = Notification.Name("SaneBar.hiddenSectionShown")
    static let hiddenSectionHidden = Notification.Name("SaneBar.hiddenSectionHidden")
}
