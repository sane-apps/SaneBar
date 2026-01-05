import Foundation
import AppKit
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "HidingService")

// MARK: - HidingState

enum HidingState: String, Codable, Sendable {
    case hidden              // All hidden items are collapsed (pushed off screen)
    case expanded            // Regular hidden items visible, always-hidden still hidden
    case alwaysHiddenShown   // Everything visible including always-hidden section (Option+click)
}

// MARK: - HidingServiceProtocol

/// @mockable
@MainActor
protocol HidingServiceProtocol {
    var state: HidingState { get }
    var isAnimating: Bool { get }

    func configure(delimiterItem: NSStatusItem, alwaysHiddenDelimiter: NSStatusItem?)
    func toggle(withModifier: Bool) async
    func show() async
    func hide() async
    func showAlwaysHidden() async
    func hideAlwaysHidden() async
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
/// This is how Dozer, Hidden Bar, and similar tools work. No CGEvent needed.
@MainActor
final class HidingService: ObservableObject, HidingServiceProtocol {

    // MARK: - Published State

    /// Start expanded (visible) - length=22 matches this state
    @Published private(set) var state: HidingState = .expanded
    @Published private(set) var isAnimating = false

    // MARK: - Configuration

    /// The delimiter status item whose length we toggle (regular hidden section)
    private weak var delimiterItem: NSStatusItem?

    /// The always-hidden delimiter (Option+click to reveal)
    private weak var alwaysHiddenDelimiter: NSStatusItem?

    // MARK: - Initialization

    init() {
        // Simple init - configure with delimiterItems later
    }

    // MARK: - Configuration

    /// Set the delimiter status items that control hiding
    func configure(delimiterItem: NSStatusItem, alwaysHiddenDelimiter: NSStatusItem? = nil) {
        self.delimiterItem = delimiterItem
        self.alwaysHiddenDelimiter = alwaysHiddenDelimiter
        logger.info("HidingService configured with delimiter item(s)")
    }

    // MARK: - Show/Hide Operations

    /// Toggle visibility with optional modifier key support
    /// - Parameter withModifier: If true (Option key held), also shows always-hidden section
    func toggle(withModifier: Bool = false) async {
        guard delimiterItem != nil else {
            logger.error("toggle() called but delimiterItem is nil - was configure() called?")
            return
        }
        logger.info("toggle(withModifier: \(withModifier)) called, current state: \(self.state.rawValue)")

        switch state {
        case .hidden:
            if withModifier {
                await showAlwaysHidden()
            } else {
                await show()
            }
        case .expanded:
            if withModifier {
                await showAlwaysHidden()
            } else {
                await hide()
            }
        case .alwaysHiddenShown:
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

        // Show both delimiters so users can always see the zone markers
        delimiterItem.length = StatusItemLength.expanded
        alwaysHiddenDelimiter?.length = StatusItemLength.expanded

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
        guard state != .hidden else { return }
        guard let delimiterItem = delimiterItem else {
            logger.error("hide() called but delimiterItem is nil")
            return
        }

        isAnimating = true

        logger.info("Hiding items (length → \(StatusItemLength.collapsed))")

        // Hide both delimiters
        delimiterItem.length = StatusItemLength.collapsed
        alwaysHiddenDelimiter?.length = StatusItemLength.collapsed

        state = .hidden
        isAnimating = false

        NotificationCenter.default.post(
            name: .hiddenSectionHidden,
            object: nil
        )
    }

    /// Show always-hidden section (Option+click behavior)
    func showAlwaysHidden() async {
        guard !isAnimating else { return }
        guard let delimiterItem = delimiterItem else {
            logger.error("showAlwaysHidden() called but delimiterItem is nil")
            return
        }

        isAnimating = true

        logger.info("Showing ALL items including always-hidden")

        // Shrink both delimiters to reveal everything
        delimiterItem.length = StatusItemLength.expanded
        alwaysHiddenDelimiter?.length = StatusItemLength.expanded

        state = .alwaysHiddenShown
        isAnimating = false

        NotificationCenter.default.post(
            name: .alwaysHiddenSectionShown,
            object: nil
        )
    }

    /// Hide just the always-hidden section (keep regular hidden visible)
    func hideAlwaysHidden() async {
        guard !isAnimating else { return }
        guard state == .alwaysHiddenShown else { return }

        isAnimating = true

        logger.info("Hiding always-hidden section only")

        // Expand only the always-hidden delimiter
        alwaysHiddenDelimiter?.length = StatusItemLength.collapsed

        state = .expanded
        isAnimating = false

        NotificationCenter.default.post(
            name: .hiddenSectionShown,
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
    static let alwaysHiddenSectionShown = Notification.Name("SaneBar.alwaysHiddenSectionShown")
}
