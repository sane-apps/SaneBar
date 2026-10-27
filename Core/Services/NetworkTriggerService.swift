import CoreWLAN
import os.log

private let logger = Logger(subsystem: "com.sanebar.app", category: "NetworkTrigger")


@MainActor
protocol NetworkTriggerServiceProtocol {
    var currentSSID: String? { get }
    func configure(menuBarManager: MenuBarManager)
    func startMonitoring()
    func stopMonitoring()
}


@MainActor
final class NetworkTriggerService: NSObject, NetworkTriggerServiceProtocol, CWEventDelegate {


    private let wifiClient = CWWiFiClient.shared()
    private var isMonitoring = false
    private weak var menuBarManager: MenuBarManager?

    var currentSSID: String? {
        wifiClient.interface()?.ssid()
    }


    func configure(menuBarManager: MenuBarManager) {
        self.menuBarManager = menuBarManager
    }


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


    private func handleNetworkChange() {
        guard let manager = menuBarManager else { return }

        guard manager.settings.showOnNetworkChange else { return }

        guard let ssid = currentSSID else {
            logger.debug("No WiFi network connected")
            return
        }

        let triggerNetworks = manager.settings.triggerNetworks
        if triggerNetworks.contains(ssid) {
            logger.info("Connected to trigger network: \(ssid, privacy: .private)")
            manager.profileWorkflow.runTriggerAction(
                manager.settings.networkTriggerAction,
                profileId: manager.settings.networkTriggerProfileId,
                reason: "network"
            )
        } else {
            logger.debug("Network '\(ssid, privacy: .private)' not in trigger list")
        }
    }


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
