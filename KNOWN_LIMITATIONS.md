# Known Limitations

## Touch ID Configuration Storage

**Status**: Planned Improvement (v1.1)
**Risk Level**: Low (Edge Case)

### Description
The "Require Touch ID to Show Hidden Icons" setting is currently stored in the application's secure sandbox preference file (`settings.json`), rather than the macOS System Keychain.

### Context
This is an **extreme edge case**. To exploit this, an attacker would need to **already have code execution access** on your specific machine (i.e., they are already running scripts as your user account). If an attacker has this level of access, they typically already control the system. This limitation simply means SaneBar's self-defense against a _local, already-compromised_ user is not yet cryptographic.

### Roadmap
We are moving this specific configuration boolean to the **macOS Keychain** in v1.1. This will ensure that even if a local script tries to modify the settings file to "disable" auth, the app will respect the secure value stored in the hardware enclave.