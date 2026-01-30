# Known Limitations

## Sticky Electron Icons (Claude, VibeProxy, etc.)

**Status**: Open Issue / Known Limitation
**Last Tested**: Jan 22, 2026

### Description
Certain applications, particularly those built with the Electron framework (like **Claude** and **VibeProxy**), do not reliably respond to the automated "Move to Visible" action in the Find Icon window. When attempting to move these icons, the Find Icon window may close unexpectedly, and the icon remains in the hidden section.

### Hypothesis
These apps use non-standard, "web-view" based wrappers for their menu bar status items. Unlike standard macOS `NSStatusItem` objects, these Electron wrappers appear to have a "settle lag" when the menu bar expands. By the time SaneBar attempts to "grab" the icon using Accessibility APIs, the app has not yet reported its new coordinates to the system, causing the drag operation to miss or be rejected by the WindowServer.

### Workaround
- **Manual Move**: Use the standard macOS `Cmd+drag` to move these icons manually across the separator.
- **Direct Interaction**: You can still "click" these icons from the Find Icon window to open their menus; only the automated "Move" command is affected.

### Technical Details
- **Verification Result**: `Move verification failed: expected toHidden=false ... afterX=[old position]`
- **Experiments Conducted**:
    - Increased settle delay (up to 600ms): Failed (caused UI lag without fixing the move).
    - Single-step drag: Failed (too fast for WindowServer).
    - 6-step stealth drag with cursor restoration: **Stable for most apps**, but still fails for Electron-based ones.

## Touch ID Configuration Storage

**Status**: Planned Improvement (v1.1)
**Risk Level**: Low (Edge Case)

### Description
The "Require Touch ID to Show Hidden Icons" setting is currently stored in the application's secure sandbox preference file (`settings.json`), rather than the macOS System Keychain.

### Context
This is an **extreme edge case**. To exploit this, an attacker would need to **already have code execution access** on your specific machine (i.e., they are already running scripts as your user account). If an attacker has this level of access, they typically already control the system. This limitation simply means SaneBar's self-defense against a _local, already-compromised_ user is not yet cryptographic.

### Roadmap
We are moving this specific configuration boolean to the **macOS Keychain** in v1.1. This will ensure that even if a local script tries to modify the settings file to "disable" auth, the app will respect the secure value stored in the hardware enclave.
