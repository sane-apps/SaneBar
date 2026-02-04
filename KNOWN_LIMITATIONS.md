# Known Limitations

## Touch ID Configuration Storage

**Status**: ✅ Implemented (2026-02-04)
**Risk Level**: N/A (Fixed)

### Description
The "Require Touch ID to Show Hidden Icons" setting is stored in the **macOS Keychain**, not `settings.json`.

### Context
Previously, this boolean lived in `settings.json`, which could theoretically be modified by a local process running as your user. Storing it in Keychain raises the bar for tampering and better matches the "lock behind Touch ID" promise.

### Roadmap
Existing installs are migrated automatically on launch; the legacy JSON key is stripped from `settings.json`.
