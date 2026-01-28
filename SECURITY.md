# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

---

## Reporting a Vulnerability

**Please do NOT report security vulnerabilities through public GitHub issues.**

Instead, please report them via email to: **security@sanebar.com** (or create a private security advisory on GitHub if available).

Include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Any suggested fixes (optional)

You should receive a response within 48 hours. We'll work with you to understand and address the issue.

---

## Security Model

SaneBar is a **menu bar utility** that:

1. **Requires Accessibility permissions** to read and manipulate menu bar items
2. **Stores settings locally** in `~/Library/Application Support/SaneBar/`
3. **Makes zero network requests** — no analytics, telemetry, or updates phoning home (Sparkle update checks are user-initiated)

### Known Limitations

#### Touch ID / Password Protection

The "Require Authentication to Reveal Hidden Icons" feature is designed as a **casual privacy feature**, not a security boundary.

**What it protects against:**
- Casual snooping (someone glancing at your screen)
- Accidental reveals

**What it does NOT protect against:**
- Determined attackers with local access
- Users who can edit `~/Library/Application Support/SaneBar/settings.json`

The authentication flag is stored in a plaintext JSON file. An attacker with filesystem access could disable it.

**AppleScript behavior:** When Touch ID protection is enabled, AppleScript commands (`toggle`, `show hidden`, `hide items`) that would reveal hidden icons are **blocked** and return an error. This prevents programmatic bypasses via `osascript`.

**Remediation considered:** Moving the lock state to the System Keychain. Not implemented due to complexity vs. actual threat model for a menu bar organizer.

#### WiFi Network Names

SaneBar stores WiFi network names (SSIDs) in plaintext for the "Show on specific networks" trigger feature. This is stored locally and not transmitted anywhere.

---

## Security Audits

### Internal Audit — January 2026

An independent code review was conducted in January 2026. Key findings:

| Finding | Severity | Status |
|---------|----------|--------|
| AppleScript auth bypass | Critical | ✅ Fixed (v1.0.17) |
| Auth bypass via config file | Medium | Documented (see above) |
| Plaintext SSID storage | Low | Accepted (local only) |
| Force casts in AX code | Medium | ✅ Fixed (v1.0.17) |

Full audit report: [outputs/SECURITY_AUDIT_2026-01-25.md](outputs/SECURITY_AUDIT_2026-01-25.md)

### Third-Party Audit — January 2026

A third-party security and privacy audit was conducted via [BaseHub Forums](https://forums.basehub.com/sane-apps/SaneBar/1). The audit examined SaneBar's entitlements, data storage, network behavior, update system, authentication, and diagnostic data handling.

**Result: Zero critical or high-severity issues.**

Key findings:
- Single entitlement (AppleScript automation only)
- All data stored locally with no cloud sync
- Sparkle updates use EdDSA cryptographic signing with system profiling disabled
- Diagnostic data sanitization removes paths, emails, and API key patterns
- Authentication rate limiting (5 attempts, 60-second lockout)
- No telemetry, analytics, or user identifiers detected
- Remote attack surface effectively zero

Minor concerns (all documented with mitigations above):
- Touch ID config stored as plaintext JSON — documented design limitation
- WiFi SSIDs in unencrypted local storage — local-only mitigation
- Focus Mode reads undocumented Apple private files — graceful error handling

---

## Hardening Measures

SaneBar implements:

- **Hardened Runtime** — Required for notarization
- **No network entitlements** — App cannot make network connections
- **Notarized by Apple** — Scanned for malware before distribution
- **Open source** — Full code available for inspection

---

## Privacy

SaneBar collects **zero** user data:

- No analytics
- No telemetry
- No crash reporting to external services
- No account required

See [PRIVACY.md](PRIVACY.md) for our full privacy policy.
