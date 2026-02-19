# Session Handoff — SaneBar

**Date:** 2026-02-19 (release + stabilization session)  
**Last released version:** `v2.1.6` (build `2106`) — released on Feb 19, 2026  
**Working tree:** clean (`main` == `origin/main`)

---

## Current State

- Persistent corrupted-state recovery is fixed and shipped in `v2.1.6`.
- Accessibility grant loop and second menu bar drag/drop regressions are fixed and shipped.
- Release deployment is complete across all channels.
- Open GitHub issues: **none** (all remaining issues were responded to and closed).

---

## What Shipped in v2.1.6

1. Fixed persistent hidden/corrupted status-item state after Cmd-drag removal by clearing app + ByHost visibility overrides at launch, including legacy lowercased ByHost keys.
2. Fixed Accessibility grant loop by centralizing Grant behavior and forcing fresh permission re-check on retry.
3. Fixed second-menu-bar drag/drop transition handling across Hidden/Visible/Always Hidden routes (including previously no-op paths).
4. Added migration for legacy keychain-backed `requireAuthToShowHiddenIcons` into settings JSON, with tests.
5. Expanded regression coverage for corrupted-state recovery, zone transitions, and auth-setting migration.

---

## Release Verification (Independent)

- Direct ZIP live: `https://dist.sanebar.com/updates/SaneBar-2.1.6.zip` (`200 OK`)
- ZIP SHA-256 verified: `b82673ac260ef3c6e22896a6846ef66a134c2560d8e6f4e2205b7b49a80d8035`
- Appcast live and updated: `https://sanebar.com/appcast.xml` (`2.1.6` top item, correct signature/version/build)
- GitHub release live: `https://github.com/sane-apps/SaneBar/releases/tag/v2.1.6`
- Homebrew tap updated: `sane-apps/homebrew-tap` cask now `2.1.6` with matching SHA
- Checkout redirect verified: `https://go.saneapps.com/buy/sanebar` -> LemonSqueezy checkout (`200`)
- Artifact trust checks passed on downloaded release app:
  - `codesign --verify --deep --strict`
  - `spctl -a -vv` accepted notarized app
  - `stapler validate` passed

---

## GitHub Issues Status

- Closed in this release cycle:
  - `#77` second bar drag/drop + responsiveness
  - `#76` accessibility grant loop
  - `#74` earlier duplicate/related second-bar report
  - `#65` outreach/help-wanted tracker (closed as non-product release blocker)
- Current open issue count: **0**

---

## Tooling Notes

- GitHub MCP bridge is hardened at `~/.codex/bin/github-mcp-bridge.mjs` with safer token and framing handling.
- Bridge path works in direct protocol tests, but this current Codex thread still reports `Transport closed` for `mcp__github__*`; `gh` CLI remains the reliable fallback for live GitHub operations in-session.

---

## Active Research / Follow-ups

- Active `research.md` topics requiring immediate action: **none** for this release.
- Recommended next follow-up: monitor support inbox + new issue creation for 24h post-release.

---

## Session Summary

### Done
- Shipped `v2.1.6` with corrupted-state, accessibility, and second-bar fixes.
- Verified all distribution channels and release notes quality.
- Closed all remaining open GitHub issues after release verification.

### Docs
- `SESSION_HANDOFF.md` refreshed to current release state and issue status.

### SOP
- 9/10 (all release gates passed; in-thread GitHub MCP transport remains stale despite bridge hardening and direct protocol success).

### Next
- Watch for regressions from real-world upgrades to `2.1.6`.
- Restart Codex session before relying on `mcp__github__*` calls again.
