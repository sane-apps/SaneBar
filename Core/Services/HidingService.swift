import Foundation
import AppKit

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

    func toggle() async throws
    func show() async throws
    func hide() async throws
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
    func toggle() async throws {
        switch state {
        case .hidden:
            try await show()
        case .expanded:
            try await hide()
        }
    }

    /// Expand to show hidden items
    func show() async throws {
        guard !isAnimating else { return }
        guard state == .hidden else { return }

        isAnimating = true
        defer { isAnimating = false }

        // For now, we just update state
        // The actual visual "expansion" is handled by MenuBarManager
        // which will adjust the delimiter status item positions
        state = .expanded

        // Record show time for analytics
        NotificationCenter.default.post(
            name: .hiddenSectionShown,
            object: nil
        )
    }

    /// Collapse to hide items
    func hide() async throws {
        guard !isAnimating else { return }
        guard state == .expanded else { return }

        isAnimating = true
        defer { isAnimating = false }

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
        guard let itemX = item.screenX else {
            throw HidingServiceError.itemNotFound
        }

        guard let targetX = positionForSection(section) else {
            throw HidingServiceError.delimiterNotFound
        }

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
                    try await hide()
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
