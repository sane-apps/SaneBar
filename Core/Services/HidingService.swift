import AppKit
import Foundation
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "HidingService")


enum HidingState: String, Codable, Sendable {
    case hidden
    case expanded
}


@MainActor
protocol StatusItemProtocol: AnyObject {
    var length: CGFloat { get set }
}

extension NSStatusItem: StatusItemProtocol {}


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

    func showAll() async

    func restoreFromShowAll() async
}


private enum StatusItemLength {
    static let expanded: CGFloat = 20

    static let collapsed: CGFloat = 10000
}


@MainActor
final class HidingService: ObservableObject, HidingServiceProtocol {
    private static let rehideGuardRetryDelay: TimeInterval = 0.2

    @Published private(set) var state: HidingState = .expanded
    @Published private(set) var isAnimating = false
    @Published private(set) var isTransitioning = false


    private var delimiterItem: StatusItemProtocol?

    private weak var alwaysHiddenDelimiterItem: StatusItemProtocol?

    private static let alwaysHiddenVisualLength: CGFloat = 14

    var isConfigured: Bool {
        delimiterItem != nil
    }

    var delimiterLength: CGFloat? {
        delimiterItem?.length
    }


    init() {
    }


    func configure(delimiterItem: StatusItemProtocol) {
        self.delimiterItem = delimiterItem

        delimiterItem.length = StatusItemLength.expanded
        state = .expanded

        logger.info("HidingService configured with delimiter")
    }

    func reconfigure(
        delimiterItem: StatusItemProtocol,
        preserving preservedState: HidingState,
        deferApplyingState: Bool = false
    ) {
        self.delimiterItem = delimiterItem
        state = preservedState
        if deferApplyingState {
            delimiterItem.length = StatusItemLength.expanded
            logger.info("HidingService reconfigured with delimiter while deferring \(preservedState.rawValue) restore")
            return
        }
        applyDelimiterStateToLiveItems()
        logger.info("HidingService reconfigured with delimiter while preserving \(preservedState.rawValue)")
    }

    func applyCurrentStateToLiveItems() {
        applyDelimiterStateToLiveItems()
        logger.info("HidingService applied current \(self.state.rawValue) state to live delimiters")
    }

    func configureAlwaysHiddenDelimiter(_ item: StatusItemProtocol?) {
        alwaysHiddenDelimiterItem = item
        guard let item else {
            logger.info("Always-hidden delimiter cleared")
            return
        }

        applyAlwaysHiddenDelimiterState(item)
    }

    private func applyDelimiterStateToLiveItems() {
        guard let delimiterItem else { return }

        switch state {
        case .hidden:
            delimiterItem.length = StatusItemLength.collapsed
        case .expanded:
            delimiterItem.length = StatusItemLength.expanded
        }

        if let alwaysHiddenDelimiterItem {
            applyAlwaysHiddenDelimiterState(alwaysHiddenDelimiterItem)
        }
    }

    private func applyAlwaysHiddenDelimiterState(_ item: StatusItemProtocol) {
        switch state {
        case .hidden:
            item.length = Self.alwaysHiddenVisualLength
            if let nsItem = item as? NSStatusItem, let button = nsItem.button {
                button.title = "┊"
                button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .light)
                button.cell?.isEnabled = true
                button.alphaValue = 0.5
                button.image = nil
            }
        case .expanded:
            item.length = StatusItemLength.collapsed
            if let nsItem = item as? NSStatusItem, let button = nsItem.button {
                button.image = nil
                button.title = ""
                button.cell?.isEnabled = false
            }
        }
    }


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

    func show() async {
        guard !isAnimating, !isTransitioning else { return }
        guard state == .hidden else { return }
        guard let delimiterItem else {
            logger.error("show() called but delimiterItem is nil")
            return
        }

        isAnimating = true
        defer { isAnimating = false }

        if let ahItem = alwaysHiddenDelimiterItem {
            if let nsItem = ahItem as? NSStatusItem, let button = nsItem.button {
                button.image = nil
                button.title = ""
                button.cell?.isEnabled = false
            }
            ahItem.length = StatusItemLength.collapsed
        }

        delimiterItem.length = StatusItemLength.expanded
        state = .expanded

        NotificationCenter.default.post(
            name: .hiddenSectionShown,
            object: nil
        )

        AccessibilityService.shared.invalidateMenuBarItemCache(scheduleWarmupAfter: .reveal)
    }

    func hide() async {
        guard !isAnimating, !isTransitioning else { return }
        guard let delimiterItem else {
            logger.error("hide() called but delimiterItem is nil")
            return
        }

        let wasAlreadyHidden = state == .hidden
        isAnimating = true
        defer { isAnimating = false }
        if wasAlreadyHidden {
            logger.info("Reapplying hidden menu bar layout (length → \(StatusItemLength.collapsed))")
        } else {
            logger.info("Hiding items (length → \(StatusItemLength.collapsed))")
        }

        delimiterItem.length = StatusItemLength.collapsed

        if let alwaysHiddenDelimiterItem {
            alwaysHiddenDelimiterItem.length = Self.alwaysHiddenVisualLength
            if let nsItem = alwaysHiddenDelimiterItem as? NSStatusItem, let button = nsItem.button {
                button.title = "┊"
                button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .light)
                button.cell?.isEnabled = true
                button.alphaValue = 0.5
            }
        }

        state = .hidden

        if !wasAlreadyHidden {
            NotificationCenter.default.post(
                name: .hiddenSectionHidden,
                object: nil
            )
        }

        AccessibilityService.shared.invalidateMenuBarItemCache(scheduleWarmupAfter: .conceal)
    }


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

        delimiterItem.length = StatusItemLength.collapsed

        if let ahItem = alwaysHiddenDelimiterItem {
            ahItem.length = Self.alwaysHiddenVisualLength
            if let nsItem = ahItem as? NSStatusItem, let button = nsItem.button {
                button.title = "┊"
                button.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .light)
                button.cell?.isEnabled = true
                button.alphaValue = 0.5
            }
        }

        delimiterItem.length = StatusItemLength.expanded
        state = .expanded

        AccessibilityService.shared.invalidateMenuBarItemCache(scheduleWarmupAfter: .reveal)
        NotificationCenter.default.post(name: .hiddenSectionShowAll, object: nil)
    }

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

        delimiterItem.length = StatusItemLength.collapsed

        if let ahItem = alwaysHiddenDelimiterItem {
            ahItem.length = StatusItemLength.collapsed
            if let nsItem = ahItem as? NSStatusItem, let button = nsItem.button {
                button.image = nil
                button.title = ""
                button.cell?.isEnabled = false
            }
        }

        delimiterItem.length = StatusItemLength.expanded
        state = .expanded

        AccessibilityService.shared.invalidateMenuBarItemCache(scheduleWarmupAfter: .structuralChange)
        NotificationCenter.default.post(name: .hiddenSectionRestoredFromShowAll, object: nil)
    }


    private var rehideTask: Task<Void, Never>?
    private var rehideGeneration: UInt64 = 0

    var shouldRehide: (() -> Bool)?

    func scheduleRehide(after delay: TimeInterval) {
        rehideGeneration &+= 1
        let generation = rehideGeneration

        rehideTask?.cancel()

        rehideTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                guard !Task.isCancelled else { return }
                guard generation == self.rehideGeneration else { return }

                if let shouldRehide, !shouldRehide() {
                    logger.debug("Rehide deferred — fire-time guard active")
                    if self.state == .expanded, generation == self.rehideGeneration {
                        self.scheduleRehide(after: Self.rehideGuardRetryDelay)
                    }
                    return
                }

                guard !Task.isCancelled else { return }
                guard generation == self.rehideGeneration else { return }
                await self.hide()
            } catch {
            }
        }
    }

    func cancelRehide() {
        rehideGeneration &+= 1
        rehideTask?.cancel()
        rehideTask = nil
    }
}


extension Notification.Name {
    static let hiddenSectionShown = Notification.Name("SaneBar.hiddenSectionShown")
    static let hiddenSectionHidden = Notification.Name("SaneBar.hiddenSectionHidden")
    static let hiddenSectionShowAll = Notification.Name("SaneBar.hiddenSectionShowAll")
    static let hiddenSectionRestoredFromShowAll = Notification.Name("SaneBar.hiddenSectionRestoredFromShowAll")
}
