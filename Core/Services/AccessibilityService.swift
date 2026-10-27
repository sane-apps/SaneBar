import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityService")


@inline(__always)
func safeAXUIElement(_ ref: CFTypeRef) -> AXUIElement? {
    guard CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
    return unsafeDowncast(ref as AnyObject, to: AXUIElement.self)
}

@inline(__always)
func safeAXValue(_ ref: CFTypeRef) -> AXValue? {
    guard CFGetTypeID(ref) == AXValueGetTypeID() else { return nil }
    return unsafeDowncast(ref as AnyObject, to: AXValue.self)
}


private extension Notification.Name {
    static let AXPermissionsChanged = Notification.Name(rawValue: "com.apple.accessibility.api")
}


extension Notification.Name {
    static let menuBarIconsDidChange = Notification.Name("com.sanebar.menuBarIconsDidChange")
}


@MainActor
final class AccessibilityService: ObservableObject {

    static let shared = AccessibilityService()
    nonisolated static let accessibilitySettingsURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"

    nonisolated let automaticMoveGate = MenuBarAutomaticMoveGate()


    @Published private(set) var isGranted: Bool


    private var permissionMonitorTask: Task<Void, Never>?
    private var permissionPollingTask: Task<Void, Never>?
    private var streamContinuations: [UUID: AsyncStream<Bool>.Continuation] = [:]


    struct MenuBarItemPosition: Equatable, Sendable {
        let app: RunningApp
        let x: CGFloat
        let width: CGFloat
    }

    var menuBarItemCache: [MenuBarItemPosition] = []
    var menuBarItemCacheTime: Date = .distantPast
    let menuBarItemCacheValiditySeconds: TimeInterval = 5.0

    var menuBarOwnersCache: [RunningApp] = []
    var menuBarOwnersCacheTime: Date = .distantPast
    let menuBarOwnersCacheValiditySeconds: TimeInterval = 10.0

    var menuBarOwnersRefreshTask: Task<[RunningApp], Never>?
    var menuBarItemsRefreshTask: Task<[MenuBarItemPosition], Never>?
    var menuBarKnownItemsRefreshTask: Task<[MenuBarItemPosition], Never>?
    var menuBarCacheWarmupTask: Task<Void, Never>?
    var menuBarCacheWarmupSuppressionDepth = 0
    var deferredMenuBarCacheWarmupReason: CacheWarmupReason?
    private var bundlesWithoutExtrasMenuBar: Set<String> = []

    enum CacheWarmupReason: String, Sendable {
        case launch
        case reveal
        case conceal
        case structuralChange
    }

    struct KnownOwnerRefreshDiagnostics: Sendable, Equatable {
        var attemptCount = 0
        var acceptedCount = 0
        var fullFallbackCount = 0
        var lastOutcome = "idle"
        var lastSeededItemCount = 0
        var lastSeededOwnerCount = 0
        var lastFirstResultCount = 0
        var lastFirstCoverage = 0.0
        var lastRetryOwnerCount = 0
        var lastRetryResultCount = 0
        var lastRetryCoverage = 0.0
    }

    var knownOwnerRefreshDiagnostics = KnownOwnerRefreshDiagnostics()

    nonisolated static func cacheWarmupDelay(for reason: CacheWarmupReason) -> TimeInterval {
        AccessibilityMenuBarCacheStore.cacheWarmupDelay(for: reason)
    }

    nonisolated static func cacheWarmupUsesKnownOwnerRefresh(for reason: CacheWarmupReason) -> Bool {
        AccessibilityMenuBarCacheStore.cacheWarmupUsesKnownOwnerRefresh(for: reason)
    }

    nonisolated static func mergedDeferredCacheWarmupReason(
        current: CacheWarmupReason?,
        new: CacheWarmupReason
    ) -> CacheWarmupReason {
        AccessibilityMenuBarCacheStore.mergedDeferredCacheWarmupReason(current: current, new: new)
    }

    func bundlesWithoutExtrasMenuBarSnapshot() -> [String] {
        bundlesWithoutExtrasMenuBar.sorted()
    }

    func knownOwnerRefreshDiagnosticsSnapshot() -> KnownOwnerRefreshDiagnostics {
        knownOwnerRefreshDiagnostics
    }


    private init() {
        isGranted = AXIsProcessTrusted()
        startPermissionMonitoring()
        startPermissionPolling()
    }

    deinit {
        permissionMonitorTask?.cancel()
        permissionPollingTask?.cancel()
        for continuation in streamContinuations.values {
            continuation.finish()
        }
    }


    func permissionStream(includeInitial: Bool = true) -> AsyncStream<Bool> {
        AsyncStream<Bool> { continuation in
            let id = UUID()
            self.streamContinuations[id] = continuation

            if includeInitial {
                continuation.yield(self.isGranted)
            }

            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.streamContinuations[id] = nil
                }
            }
        }
    }

    private func startPermissionMonitoring() {
        permissionMonitorTask = Task { [weak self] in
            let notifications = DistributedNotificationCenter.default()
                .notifications(named: .AXPermissionsChanged)

            for await _ in notifications {
                try? await Task.sleep(for: .milliseconds(250))

                await MainActor.run {
                    self?.checkAndUpdatePermissionStatus()
                }
            }
        }
    }

    private func startPermissionPolling() {
        guard !isGranted else { return }

        permissionPollingTask = Task { [weak self] in
            var elapsed: TimeInterval = 0
            while !Task.isCancelled {
                let interval: TimeInterval = elapsed < 10 ? 0.5 : 2.0
                try? await Task.sleep(for: .seconds(interval))
                elapsed += interval

                guard let self, !Task.isCancelled else { break }

                let newStatus = AXIsProcessTrusted()
                if newStatus != isGranted {
                    isGranted = newStatus
                    logger.info("Accessibility permission detected via polling: \(newStatus ? "GRANTED" : "REVOKED")")
                    for continuation in streamContinuations.values {
                        continuation.yield(newStatus)
                    }
                }

                if newStatus {
                    logger.debug("Accessibility granted — stopping permission poll")
                    break
                }

                if elapsed > 300 {
                    logger.debug("Permission poll timed out after 5 minutes")
                    break
                }
            }
        }
    }

    private func checkAndUpdatePermissionStatus() {
        let newStatus = AXIsProcessTrusted()
        guard newStatus != isGranted else { return }

        isGranted = newStatus
        logger.info("Accessibility permission changed: \(newStatus ? "GRANTED" : "REVOKED")")

        for continuation in streamContinuations.values {
            continuation.yield(newStatus)
        }
    }


    nonisolated var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestAccessibility(promptUser: Bool = false) -> Bool {
        let trusted: Bool
        if promptUser {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            trusted = AXIsProcessTrustedWithOptions(options)
        } else {
            trusted = AXIsProcessTrusted()
        }
        if !trusted {
            logger.info("Accessibility not trusted")
        } else {
            if !isGranted {
                isGranted = true
                for continuation in streamContinuations.values {
                    continuation.yield(true)
                }
            }
        }
        return trusted
    }

    @discardableResult
    func openAccessibilitySettings() -> Bool {
        guard let url = URL(string: Self.accessibilitySettingsURLString) else { return false }
        return NSWorkspace.shared.open(url)
    }


    func markExtrasMenuBarUnavailable(bundleID: String) {
        bundlesWithoutExtrasMenuBar.insert(bundleID)
    }

    func markExtrasMenuBarAvailable(bundleID: String) {
        bundlesWithoutExtrasMenuBar.remove(bundleID)
    }

    func likelyLacksExtrasMenuBar(bundleID: String) -> Bool {
        bundlesWithoutExtrasMenuBar.contains(bundleID)
    }
}
