import CoreWLAN
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "NetworkTrigger")

// MARK: - NetworkTriggerServiceProtocol

/// @mockable
@MainActor
protocol NetworkTriggerServiceProtocol {
    var currentSSID: String? { get }
    func configure(menuBarManager: MenuBarManager)
    func startMonitoring()
    func stopMonitoring()
}

// MARK: - NetworkTriggerService

/// Service that monitors WiFi network changes and triggers menu bar visibility.
///
/// When the device connects to a network in the trigger list, the hidden menu bar
/// items are automatically shown. This is useful for workflows like:
/// - Show VPN icon when connecting to work WiFi
/// - Show certain apps on home network
@MainActor
final class NetworkTriggerService: NSObject, NetworkTriggerServiceProtocol, CWEventDelegate {

    // MARK: - Properties

    private let wifiClient = CWWiFiClient.shared()
    private var isMonitoring = false
    private weak var menuBarManager: MenuBarManager?

    /// Current WiFi network SSID, if connected
    var currentSSID: String? {
        wifiClient.interface()?.ssid()
    }

    // MARK: - Configuration

    func configure(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isMonitoring else { return }

        wifiClient.delegate = self

        do {
            try wifiClient.startMonitoringEvent(with: .ssidDidChange)
            try wifiClient.startMonitoringEvent(with: .linkDidChange)
            isMonitoring = true
            logger.info("Started WiFi monitoring")
        } catch {
            logger.error("Failed to start WiFi monitoring: \(error.localizedDescription)")
        }
    }

    func stopMonitoring() {
        guard isMonitoring else { return }

        do {
            try wifiClient.stopMonitoringAllEvents()
        } catch {
            logger.error("Failed to stop WiFi monitoring: \(error.localizedDescription)")
        }
        isMonitoring = false
        logger.info("Stopped WiFi monitoring")
    }

    // MARK: - Private

    private func handleNetworkChange() {
        guard let manager = menuBarManager else { return }

        // Check if feature is enabled
        guard manager.settings.showOnNetworkChange else { return }

        guard let ssid = currentSSID else {
            logger.debug("No WiFi network connected")
            return
        }

        // Check if this network is in our trigger list
        let triggerNetworks = manager.settings.triggerNetworks
        if triggerNetworks.contains(ssid) {
            logger.info("Connected to trigger network: \(ssid, privacy: .private) - showing hidden items")
            manager.showHiddenItems()
        } else {
            logger.debug("Network '\(ssid, privacy: .private)' not in trigger list")
        }
    }

    // MARK: - CWEventDelegate

    nonisolated func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in
            logger.info("SSID changed on interface: \(interfaceName)")
            self.handleNetworkChange()
        }
    }

    nonisolated func linkDidChangeForWiFiInterface(withName interfaceName: String) {
        Task { @MainActor in
            logger.debug("Link state changed on interface: \(interfaceName)")
            self.handleNetworkChange()
        }
    }

    nonisolated func clientConnectionInterrupted() {
        Task { @MainActor in
            logger.warning("WiFi subsystem connection interrupted")
        }
    }

    nonisolated func clientConnectionInvalidated() {
        Task { @MainActor in
            logger.error("WiFi subsystem connection invalidated - restarting monitoring")
            self.isMonitoring = false
            self.startMonitoring()
        }
    }
}
