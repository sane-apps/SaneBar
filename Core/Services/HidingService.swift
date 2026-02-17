import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "HidingService")

// MARK: - HidingState

enum HidingState: String, Codable, Sendable {
    case hidden // Hidden items are collapsed (pushed off screen)
    case expanded // Hidden items are visible
}

// MARK: - StatusItemProtocol

/// Protocol to abstract NSStatusItem for testing
@MainActor
protocol StatusItemProtocol: AnyObject {
    var length: CGFloat { get set }
}

extension NSStatusItem: StatusItemProtocol {}

// MARK: - HidingServiceProtocol

/// @mockable
@MainActor
protocol HidingServiceProtocol {
    var state: HidingState { get }
    var isAnimating: Bool { get }
    var isTransitioning: Bool { get }

    func configure(delimiterItem: StatusItemProtocol)
    func configureAlwaysHiddenDelimiter(_ item: StatusItemProtocol?)
    func toggle() async
    func show() async
    func hide() async

    /// Reveal ALL items including always-hidden using the shield pattern.
    /// Must be followed by `restoreFromShowAll()` when done.
    func showAll() async

    /// Restore from `showAll()`: re-block always-hidden items using the shield pattern.
    func restoreFromShowAll() async
}

// MARK: - StatusItem Length Constants

private enum StatusItemLength {
    /// Length when EXPANDED (hidden items are VISIBLE) - separator shows as small icon
    static let expanded: CGFloat = 20

    /// Length when COLLAPSED (hidden items are HIDDEN) - separator expands to push items off
    static let collapsed: CGFloat = 10000
}

// MARK: - HidingService

/// Service that manages hiding/showing menu bar items using the length toggle technique.
///
/// HOW IT WORKS:
/// 1. User Cmd+drags their menu bar icons to position them left or right of our delimiter
/// 2. Icons to the RIGHT of delimiter = always visible
/// 3. Icons to the LEFT of delimiter = can be hidden
/// 4. To HIDE: Set delimiter's length to 10,000 → pushes everything to its left off screen (x < 0)
/// 5. To SHOW: Set delimiter's length back to 20 → reveals the hidden icons
///
/// This is the standard length-toggle technique for menu bar managers. No CGEvent needed.
@MainActor
final class HidingService: ObservableObject, HidingServiceProtocol {
    // MARK: - Published State

    /// Start expanded for safe position validation - MenuBarManager will hide after validation passes
    @Published private(set) var state: HidingState = .expanded
    @Published private(set) var isAnimating = false
    @Published private(set) var isTransitioning = false

    // MARK: - Configuration

    /// The delimiter status item whose length we toggle
    private weak var delimiterItem: StatusItemProtocol?

    /// The always-hidden delimiter — when expanded, this stays large to keep always-hidden items off-screen
    private weak var alwaysHiddenDelimiterItem: StatusItemProtocol?

    /// Normal visual length of the always-hidden separator
    private static let alwaysHiddenVisualLength: CGFloat = 14

    var isConfigured: Bool {
        delimiterItem != nil
    }

    var delimiterLength: CGFloat? {
        delimiterItem?.length
    }

    // MARK: - Initialization

    init() {
        // Simple init - configure with delimiterItem later
    }

    // MARK: - Configuration

    /// Set the delimiter status item that controls hiding
    func configure(delimiterItem: StatusItemProtocol) {
        self.delimiterItem = delimiterItem

        // Start EXPANDED (not collapsed)
        delimiterItem.length = StatusItemLength.expanded
        state = .expanded

        logger.info("HidingService configured with delimiter")
    }

    /// Set or clear the always-hidden delimiter item.
    /// When the hidden section is expanded (revealed), this delimiter stays large
    /// to keep always-hidden items pushed off-screen.
    func configureAlwaysHiddenDelimiter(_ item: StatusItemProtocol?) {
        alwaysHiddenDelimiterItem = item
        guard let item else {
            logger.info("Always-hidden delimiter cleared")
            return
        }

        // Always start at visual length. show() will set the blocking length.
        item.length = Self.alwaysHiddenVisualLength
    }

    // MARK: - Show/Hide Operations

    /// Toggle visibility between hidden and expanded states
    func toggle() async {
        guard !isAnimating, !isTransitioning else { return }
        guard delimiterItem != nil else {
            logger.error("toggle() called but delimiterItem is nil - was configure() called?")
            return
        }
        let currentState = state
        logger.info("toggle() called, current state: \(currentState.rawValue)")

        switch currentState {
        case .hidden:
            await show()
        case .expanded:
            await hide()
        }
    }

    /// Show hidden items by shrinking separator to normal size (20px)
    func show() async {
        guard !isAnimating, !isTransitioning else { return }
        guard state == .hidden else { return }
        guard let delimiterItem else {
            logger.error("show() called but delimiterItem is nil")
            return
        }

        isAnimating = true
        defer { isAnimating = false }

        // With AH seeded at position 10000 (far left of all items), the blocking
        // approach is simple: set AH to StatusItemLength.collapsed (10000) FIRST
        // while main still shields everything, then contract main to reveal.
        // Items to AH's right (hidden + visible) appear. Items to AH's left
        // (pinned always-hidden) stay off-screen because AH is 10000px wide.
        if let ahItem = alwaysHiddenDelimiterItem {
            if let nsItem = ahItem as? NSStatusItem, let button = nsItem.button {
                button.image = nil
                button.title = ""
                button.cell?.isEnabled = false
            }
            ahItem.length = StatusItemLength.collapsed
        }

        // Now contract main to reveal hidden items
        delimiterItem.length = StatusItemLength.expanded
        state = .expanded

        NotificationCenter.default.post(
            name: .hiddenSectionShown,
            object: nil
        )

        AccessibilityService.shared.invalidateMenuBarItemCache()
    }

    /// Hide items by expanding delimiter to push them off screen
    func hide() async {
        guard !isAnimating, !isTransitioning else { return }
        guard state != .hidden else { return }
        guard let delimiterItem else {
            logger.error("hide() called but delimiterItem is nil")
            return
        }

        isAnimating = true
        defer { isAnimating = false }
        logger.info("Hiding items (length → \(StatusItemLength.collapsed))")

        delimiterItem.length = StatusItemLength.collapsed

        // Restore always-hidden delimiter to visual length — main delimiter
        // already pushes everything off-screen, so the always-hidden separator
        // can return to its normal small size
        if let alwaysHiddenDelimiterItem {
            alwaysHiddenDelimiterItem.length = Self.alwaysHiddenVisualLength
            // Restore button content after expand
            if let nsItem = alwaysHiddenDelimiterItem as? NSStatusItem, let button = nsItem.button {
                button.title = "┊"
                button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .light)
                button.cell?.isEnabled = true
                button.alphaValue = 0.5
            }
        }

        state = .hidden

        NotificationCenter.default.post(
            name: .hiddenSectionHidden,
            object: nil
        )

        AccessibilityService.shared.invalidateMenuBarItemCache()
    }

    // MARK: - Show All / Restore (Shield Pattern)

    /// Reveal ALL items including always-hidden, using the shield pattern.
    ///
    /// Safe transition sequence:
    /// 1. main → 10,000 (shield — push everything off-screen)
    /// 2. ah → 14       (contract — safe because main shields)
    /// 3. main → 20     (reveal — all items slide in together)
    ///
    /// This avoids the invariant violation where both separators are at visual
    /// size simultaneously during a transition, which causes always-hidden items
    /// to flood the menu bar and corrupt UserDefaults preferred positions.
    func showAll() async {
        guard !isTransitioning else {
            logger.warning("showAll() skipped — already transitioning")
            return
        }
        guard let delimiterItem else {
            logger.error("showAll() called but delimiterItem is nil")
            return
        }

        isTransitioning = true
        defer { isTransitioning = false }

        // Step 1: Shield — push everything off-screen with main separator
        delimiterItem.length = StatusItemLength.collapsed

        // Step 2: Contract always-hidden separator (safe — main shields everything)
        if let ahItem = alwaysHiddenDelimiterItem {
            ahItem.length = Self.alwaysHiddenVisualLength
            if let nsItem = ahItem as? NSStatusItem, let button = nsItem.button {
                button.title = "┊"
                button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .light)
                button.cell?.isEnabled = true
                button.alphaValue = 0.5
            }
        }

        // Step 3: Reveal — all items slide in together
        delimiterItem.length = StatusItemLength.expanded
        state = .expanded

        AccessibilityService.shared.invalidateMenuBarItemCache()
        NotificationCenter.default.post(name: .hiddenSectionShowAll, object: nil)
    }

    /// Restore from `showAll()`: re-block always-hidden items using the shield pattern.
    ///
    /// Safe transition sequence:
    /// 1. main → 10,000 (shield — push everything off-screen)
    /// 2. ah → 10,000   (re-block — safe because main shields)
    /// 3. main → 20     (reveal — only hidden+visible items appear)
    func restoreFromShowAll() async {
        guard !isTransitioning else {
            logger.warning("restoreFromShowAll() skipped — already transitioning")
            return
        }
        guard let delimiterItem else {
            logger.error("restoreFromShowAll() called but delimiterItem is nil")
            return
        }

        isTransitioning = true
        defer { isTransitioning = false }

        // Step 1: Shield — push everything off-screen with main separator
        delimiterItem.length = StatusItemLength.collapsed

        // Step 2: Re-block always-hidden separator (safe — main shields everything)
        if let ahItem = alwaysHiddenDelimiterItem {
            ahItem.length = StatusItemLength.collapsed
            if let nsItem = ahItem as? NSStatusItem, let button = nsItem.button {
                button.image = nil
                button.title = ""
                button.cell?.isEnabled = false
            }
        }

        // Step 3: Reveal — only hidden+visible items slide in
        delimiterItem.length = StatusItemLength.expanded
        state = .expanded

        AccessibilityService.shared.invalidateMenuBarItemCache()
        NotificationCenter.default.post(name: .hiddenSectionRestoredFromShowAll, object: nil)
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
    static let hiddenSectionShowAll = Notification.Name("SaneBar.hiddenSectionShowAll")
    static let hiddenSectionRestoredFromShowAll = Notification.Name("SaneBar.hiddenSectionRestoredFromShowAll")
}
