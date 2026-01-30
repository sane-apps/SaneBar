# SaneBar Security & Privacy Audit - Third Party Review

> **Source:** https://forums.basehub.com/sane-apps/SaneBar/1
> **Saved:** 2026-01-25

---

## Executive Overview

The audit identifies SaneBar as a privacy-respecting macOS menu bar utility with solid security fundamentals. The codebase demonstrates responsible handling of sensitive permissions and minimal data collection practices.

---

## Key Strengths

**Privacy Architecture**: The application collects no telemetry, analytics, or user tracking data. All information remains stored locally in `~/Library/Application Support/SaneBar/`.

**Update Security**: Updates use EdDSA cryptographic signatures for verification, and the application explicitly disables system profiling with runtime checks that log faults if profiling becomes enabled.

**Minimal Attack Surface**: Only one entitlement (Apple Events) is requested. The hardened runtime is enabled, and the application is Apple-notarized.

**Logging Practices**: WiFi SSIDs are marked as private in logs using proper privacy annotations. Diagnostic information submitted by users undergoes sanitization that redacts file paths and filters for sensitive patterns like email addresses.

---

## Identified Vulnerabilities

### CRITICAL - AppleScript Auth Bypass

**Severity:** Critical
**Status:** 🔴 NEEDS FIX

Commands like `toggle`, `show hidden`, and `hide items` execute without authentication checks, even when `requireAuthToShowHiddenIcons` is enabled. An attacker could bypass the Touch ID requirement via osascript commands.

**Attack Vector:**
```bash
osascript -e 'tell application "SaneBar" to show hidden'
```
This reveals hidden icons WITHOUT triggering Touch ID, even when auth is required.

**Fix Required:** Add authentication checks to all AppleScript command implementations when the auth setting is enabled.

---

### MEDIUM - Force Casts in Accessibility Code

**Severity:** Medium
**Status:** 🟡 NEEDS FIX

Over 10 instances of force casting in Accessibility API code could cause crashes if Apple modifies underlying behavior. SwiftLint disables warnings but doesn't eliminate the risk.

**Fix Required:** Replace force casts with safe optional casting patterns in AccessibilityService code.

---

### LOW - Plaintext Configuration

**Severity:** Low
**Status:** 🟢 DOCUMENT

The auth setting and WiFi network names for triggers store in unencrypted JSON, accessible to filesystem-level threats.

**Action:** Update SECURITY.md to explicitly note this limitation.

---

## Recommendations Summary

| Priority | Action |
|----------|--------|
| **Immediate** | Add authentication checks to all AppleScript command implementations when auth setting is enabled |
| **Short-term** | Replace force casts with safe optional casting patterns in AccessibilityService code |
| **Documentation** | Update SECURITY.md to note AppleScript auth bypass and plaintext config limitations |

---

## Compliance Status

✅ No hardcoded secrets
✅ No embedded API keys
✅ Code signing enabled
✅ Apple notarization
✅ Accurate privacy documentation
✅ Known limitations properly disclosed
