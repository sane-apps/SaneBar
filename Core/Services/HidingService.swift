import Foundation
import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "HidingService")

// MARK: - HidingState

enum HidingState: String, Codable, Sendable {
    case hidden      // Hidden items are collapsed (pushed off screen)
    case expanded    // Hidden items are visible
}

// MARK: - HidingServiceProtocol

/// @mockable
@MainActor
protocol HidingServiceProtocol {
    var state: HidingState { get }
    var isAnimating: Bool { get }

    func configure(delimiterItem: NSStatusItem)
    func toggle() async
    func show() async
    func hide() async
}

// MARK: - StatusItem Length Constants

private enum StatusItemLength {
    /// Length when EXPANDED (hidden items are VISIBLE) - separator shows as small icon
    static let expanded: CGFloat = 20

    /// Length when COLLAPSED (hidden items are HIDDEN) - separator expands to push items off
    static let collapsed: CGFloat = 10_000
}

// MARK: - HidingService

/// Service that manages hiding/showing menu bar items using the length toggle technique.
///
/// HOW IT WORKS:
/// 1. User Cmd+drags their menu bar icons to position them left or right of our delimiter
/// 2. Icons to the LEFT of delimiter = always visible
/// 3. Icons to the RIGHT of delimiter = can be hidden
/// 4. To HIDE: Set delimiter's length to 10,000 → pushes everything to its right off screen
/// 5. To SHOW: Set delimiter's length back to 22 → reveals the hidden icons
///
/// This is how Bartender, Dozer, and Hidden Bar all work. No CGEvent needed.
@MainActor
final class HidingService: ObservableObject, HidingServiceProtocol {

    // MARK: - Published State

    /// Start expanded (visible) - length=22 matches this state
    @Published private(set) var state: HidingState = .expanded
    @Published private(set) var isAnimating = false

    // MARK: - Configuration

    /// The delimiter status item whose length we toggle
    private weak var delimiterItem: NSStatusItem?

    // MARK: - Initialization

    init() {
        // Simple init - configure with delimiterItem later
    }

    // MARK: - Configuration

    /// Set the delimiter status item that controls hiding
    func configure(delimiterItem: NSStatusItem) {
        self.delimiterItem = delimiterItem
        logger.info("HidingService configured with delimiter item")
    }

    // MARK: - Show/Hide Operations

    /// Toggle between hidden and expanded states
    func toggle() async {
        guard delimiterItem != nil else {
            logger.error("toggle() called but delimiterItem is nil - was configure() called?")
            return
        }
        print("[SaneBar] HidingService.toggle() called, current state: \(state)")
        switch state {
        case .hidden:
            await show()
        case .expanded:
            await hide()
        }
    }

    /// Show hidden items by shrinking separator to normal size (20px)
    func show() async {
        guard !isAnimating else { return }
        guard state == .hidden else { return }
        guard let delimiterItem = delimiterItem else {
            logger.error("show() called but delimiterItem is nil")
            return
        }

        isAnimating = true
        logger.info("Expanding menu bar (length → \(StatusItemLength.expanded))")

        delimiterItem.length = StatusItemLength.expanded

        state = .expanded
        isAnimating = false

        NotificationCenter.default.post(
            name: .hiddenSectionShown,
            object: nil
        )
    }

    /// Hide items by expanding delimiter to push them off screen
    func hide() async {
        guard !isAnimating else { return }
        guard state == .expanded else { return }
        guard let delimiterItem = delimiterItem else {
            logger.error("hide() called but delimiterItem is nil")
            return
        }

        isAnimating = true

        logger.info("Hiding items (length → \(StatusItemLength.collapsed))")

        // Set the length directly (animation handled by AppKit)
        delimiterItem.length = StatusItemLength.collapsed

        state = .hidden
        isAnimating = false

        NotificationCenter.default.post(
            name: .hiddenSectionHidden,
            object: nil
        )
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
                    await hide()
                }
            } catch {
                // Task cancelled - ignore
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
