# P0: WiFi/Network Trigger Research

**Date**: 2026-01-04
**Feature**: Show hidden menu bar items when connecting to specific WiFi networks

## Competitor Implementations

### Bartender 5
- Supports "Triggers" that can show/hide items based on conditions
- WiFi network is one of the trigger conditions (based on SSID)
- Can configure multiple networks (e.g., "Work WiFi" shows VPN icon)
- Uses triggers as part of a broader "Presets" system

### Ice (jordanbaird/Ice)
- Does NOT have WiFi/network-based triggers as of current version
- Focuses on hover, click, and keyboard triggers only
- Good reference for event monitoring patterns (EventManager.swift)

## APIs to Use

### CoreWLAN Framework (macOS 10.6+)
Primary API for WiFi network detection on macOS.

**Key classes:**
- `CWWiFiClient` - Singleton for accessing WiFi subsystem
- `CWInterface` - Represents a WiFi network interface
- `CWEventDelegate` - Protocol for receiving network change events

**Get current SSID:**
```swift
import CoreWLAN

let interface = CWWiFiClient.shared().interface()
let ssid = interface?.ssid() // Returns String?
```

**Monitor network changes:**
```swift
let client = CWWiFiClient.shared()
client.delegate = self
try client.startMonitoringEvent(with: .ssidDidChange)
try client.startMonitoringEvent(with: .linkDidChange)

// CWEventDelegate method
func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
    if let newSSID = CWWiFiClient.shared().interface()?.ssid() {
        // Check if this SSID is in our trigger list
    }
}
```

**Event types available:**
- `.ssidDidChange` - Network switched
- `.linkDidChange` - Connected/disconnected
- `.powerStateDidChange` - WiFi on/off
- `.bssidDidChange` - Base station switched

## Permission Requirements

**No special permissions required**:
- CoreWLAN APIs work without accessibility permissions
- No entitlements needed (unlike Location Services)
- **IMPORTANT**: App must be unsandboxed (SaneBar already is)
- If sandboxed, CoreWLAN returns nil

## Implementation Approach

### Architecture
Create `NetworkTriggerService` in Core/Services:

```swift
@MainActor
final class NetworkTriggerService: NSObject, CWEventDelegate {
    private let wifiClient = CWWiFiClient.shared()
    private var triggerNetworks: Set<String> = []
    private var onNetworkTrigger: ((String) -> Void)?

    func configure(networks: [String], onTrigger: @escaping (String) -> Void) {
        self.triggerNetworks = Set(networks)
        self.onNetworkTrigger = onTrigger
    }

    func startMonitoring() {
        wifiClient.delegate = self
        try? wifiClient.startMonitoringEvent(with: .ssidDidChange)
    }

    func ssidDidChangeForWiFiInterface(withName interfaceName: String) {
        guard let ssid = wifiClient.interface()?.ssid() else { return }
        if triggerNetworks.contains(ssid) {
            onNetworkTrigger?(ssid)
        }
    }
}
```

### Settings
Add to SaneBarSettings:
- `showOnNetwork: Bool` - Enable/disable feature
- `triggerNetworks: [String]` - List of SSIDs that trigger show

### UI
Settings > Triggers section:
- Toggle for "Show on network change"
- List editor for network names
- "Add current network" button for convenience

## Gotchas / Edge Cases

1. **SSID can be nil** - When not connected, no WiFi available
2. **Multiple interfaces** - Rare but possible on Mac Pro with multiple WiFi adapters
3. **SSIDs with special characters** - Use `ssidData()` for binary comparison if needed
4. **Event flooding** - Debounce events, only trigger on actual change
5. **Case sensitivity** - SSIDs are case-sensitive, store and compare exactly
6. **Hidden networks** - SSID may appear as empty string for hidden networks

## Testing Strategy

1. Mock CWWiFiClient for unit tests
2. Real device testing needed for integration
3. Test cases:
   - Connect to trigger network → show items
   - Disconnect from any network → configurable behavior
   - Switch between networks → correct trigger/no-trigger
   - WiFi disabled → graceful handling
