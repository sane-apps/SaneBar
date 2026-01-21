import AppKit
import ApplicationServices
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "AccessibilityService")

// MARK: - Accessibility Prompt Helper

/// Request accessibility with system prompt
/// Uses the string key directly to avoid concurrency issues with kAXTrustedCheckOptionPrompt
private nonisolated func requestAccessibilityWithPrompt() -> Bool {
    // "AXTrustedCheckOptionPrompt" is the string value of kAXTrustedCheckOptionPrompt
    let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
    return AXIsProcessTrustedWithOptions(options)
}

// MARK: - Permission Change Notification

private extension Notification.Name {
    /// System notification sent when ANY app's accessibility permission changes
    /// Not publicly documented, but reliable. From HIServices.framework
    static let AXPermissionsChanged = Notification.Name(rawValue: "com.apple.accessibility.api")
}

// MARK: - Public Notifications

extension Notification.Name {
    /// Posted when menu bar icons have been moved/reorganized
    static let menuBarIconsDidChange = Notification.Name("com.sanebar.menuBarIconsDidChange")
}

// MARK: - AccessibilityService

/// Service for interacting with other apps' menu bar items via Accessibility API.
///
/// **Apple Best Practice**:
/// - Uses standard `AXUIElement` API.
/// - Does NOT use `CGEvent` cursor hijacking (mouse simulation).
/// - Does NOT use private APIs.
/// - Handles `AXPress` actions to simulate clicks natively.
///
/// **Permission Monitoring**:
/// - Listens for system-wide permission change notifications
/// - Streams permission status changes via AsyncStream
/// - UI can react immediately when user grants permission in System Settings
@MainActor
final class AccessibilityService: ObservableObject {

    // MARK: - Singleton

    static let shared = AccessibilityService()

    // MARK: - Published State

    /// Current permission status - updates reactively when permission changes
    @Published private(set) var isGranted: Bool

    // MARK: - Permission Monitoring

    private var permissionMonitorTask: Task<Void, Never>?
    private var streamContinuations: [UUID: AsyncStream<Bool>.Continuation] = [:]

    // MARK: - Menu Bar Item Cache

    /// Public struct to avoid "Large Tuple" lint errors
    struct MenuBarItemPosition: Equatable, Sendable {
        let app: RunningApp
        let x: CGFloat
        let width: CGFloat
    }

    /// Cache for menu bar item positions to avoid expensive rescans
    internal var menuBarItemCache: [MenuBarItemPosition] = []
    internal var menuBarItemCacheTime: Date = .distantPast
    internal let menuBarItemCacheValiditySeconds: TimeInterval = 5.0  // Refresh every 5 seconds for accurate positions

    /// Cache for menu bar item owners (apps only, no positions) - used by Find Icon
    internal var menuBarOwnersCache: [RunningApp] = []
    internal var menuBarOwnersCacheTime: Date = .distantPast
    internal let menuBarOwnersCacheValiditySeconds: TimeInterval = 10.0  // Refresh every 10 seconds for responsive UI

    internal var menuBarOwnersRefreshTask: Task<[RunningApp], Never>?
    internal var menuBarItemsRefreshTask: Task<[MenuBarItemPosition], Never>?

    // MARK: - Initialization

    private init() {
        self.isGranted = AXIsProcessTrusted()
        startPermissionMonitoring()
    }

    deinit {
        permissionMonitorTask?.cancel()
        for continuation in streamContinuations.values {
            continuation.finish()
        }
    }

    // MARK: - Permission Streaming

    /// Stream permission status changes. Use this for reactive UI updates.
    /// - Parameter includeInitial: Whether to emit the current status immediately
    /// - Returns: AsyncStream that yields `true` when granted, `false` when revoked
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
                // Small delay - notification fires before status update sometimes
                try? await Task.sleep(for: .milliseconds(250))

                await MainActor.run {
                    self?.checkAndUpdatePermissionStatus()
                }
            }
        }
    }

    private func checkAndUpdatePermissionStatus() {
        let newStatus = AXIsProcessTrusted()
        guard newStatus != isGranted else { return }

        isGranted = newStatus
        logger.info("Accessibility permission changed: \(newStatus ? "GRANTED" : "REVOKED")")

        // Notify all streams
        for continuation in streamContinuations.values {
            continuation.yield(newStatus)
        }
    }

    // MARK: - API Verification

    /// Checks if we have accessibility permissions (legacy - prefer `isGranted` property)
    nonisolated var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Request accessibility permission - shows system prompt if not trusted
    /// Returns true if already trusted, false if user needs to grant permission
    @discardableResult
    func requestAccessibility() -> Bool {
        let trusted = requestAccessibilityWithPrompt()
        if !trusted {
            logger.info("Accessibility not trusted - system prompt shown")
        } else {
            // Update our cached state if already granted
            if !isGranted {
                isGranted = true
                for continuation in streamContinuations.values {
                    continuation.yield(true)
                }
            }
        }
        return trusted
    }
}
