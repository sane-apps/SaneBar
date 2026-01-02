import Foundation
import AppKit
@preconcurrency import ApplicationServices

// MARK: - PermissionState

enum PermissionState: Equatable {
    case unknown
    case notGranted
    case granted

    var displayName: String {
        switch self {
        case .unknown: return "Checking..."
        case .notGranted: return "Not Granted"
        case .granted: return "Granted"
        }
    }

    var systemImage: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .notGranted: return "xmark.circle.fill"
        case .granted: return "checkmark.circle.fill"
        }
    }
}

// MARK: - PermissionService

/// Service for managing accessibility permission state
@MainActor
final class PermissionService: ObservableObject {

    @Published private(set) var permissionState: PermissionState = .unknown
    @Published var showingPermissionAlert = false

    private nonisolated(unsafe) var checkTimer: Timer?

    // MARK: - Lifecycle

    init() {
        checkPermission()
    }

    // MARK: - Permission Checking

    /// Check current permission state
    func checkPermission() {
        let trusted = AXIsProcessTrusted()
        permissionState = trusted ? .granted : .notGranted
    }

    /// Request permission (opens System Settings)
    nonisolated func requestPermission() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)

        // Start polling for permission grant
        Task { @MainActor in
            startPermissionPolling()
        }
    }

    /// Open System Settings directly to Privacy & Security > Accessibility
    func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)

        // Start polling for permission grant
        startPermissionPolling()
    }

    // MARK: - Polling

    /// Start polling for permission changes (user might grant in System Settings)
    func startPermissionPolling() {
        stopPermissionPolling()

        checkTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkPermission()
                if self?.permissionState == .granted {
                    self?.stopPermissionPolling()
                }
            }
        }
    }

    /// Stop polling
    func stopPermissionPolling() {
        checkTimer?.invalidate()
        checkTimer = nil
    }

    // MARK: - UI Helpers

    /// Show the permission request flow
    func showPermissionRequest() {
        showingPermissionAlert = true
    }

    /// Instructions for granting permission
    static let permissionInstructions = """
    SaneBar needs Accessibility permission to manage your menu bar items.

    1. Click "Open System Settings"
    2. Find SaneBar in the list
    3. Toggle the switch to enable access
    4. You may need to quit and reopen SaneBar
    """
}
