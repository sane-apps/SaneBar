# Notarization Notes (SaneBar)

This document captures what has caused Apple notarization to pass/fail for SaneBar, based on local `xcrun notarytool` submission history and logs.

## TL;DR pattern

Notarization succeeds when **every executable Apple can see** is:

- signed with **Developer ID Application** (correct Team ID)
- signed with a **secure timestamp**
- does **not** contain debug-only entitlements (especially `com.apple.security.get-task-allow`)

Notarization fails when the app bundle contains an **embedded helper app inside a `.zip` resource** (e.g. LaunchAtLogin helper zips) that violates any of the above.

## What Apple rejected (specific failure)

Recent failures are consistently caused by a nested helper inside:

- `SaneBar.app/Contents/Resources/LaunchAtLogin_LaunchAtLogin.bundle/.../LaunchAtLoginHelper.zip/.../LaunchAtLoginHelper`
- and sometimes also `LaunchAtLoginHelper-with-runtime.zip`

Apple’s notarization log reports errors like:

- “The binary is not signed with a valid Developer ID certificate.”
- “The signature does not include a secure timestamp.”
- “The executable requests the `com.apple.security.get-task-allow` entitlement.”

These errors show up for both `arm64` and `x86_64` architectures when present.

### Why local `codesign --deep` can still look fine

A key gotcha: `codesign --verify --deep --strict SaneBar.app` **does not inspect executables embedded inside `.zip` payloads** that sit in Resources.

Apple’s notarization service *does* unpack/inspect those and rejects the archive.

### Important: verify you’re looking at the same artifact

Apple’s `notarytool log` includes a `sha256` of the uploaded archive.

If your local DMG hash doesn’t match that `sha256`, you are comparing against the wrong build artifact.

## Local acceptance history (from `notarytool history`)

Examples of accepted DMGs:

- `SaneBar-1.0.1.dmg` – Accepted
- `SaneBar-1.0.2.dmg` – Accepted
- `SaneBar-1.0.3.dmg` – Accepted

Examples of failed/invalid attempts:

- Early `SaneBar-1.0.0.dmg` attempt – Invalid (LaunchAtLogin helper zip issues)
- `SaneBar-1.0.5.dmg` attempt – Invalid (same LaunchAtLogin helper zip issues)

## What we changed in the release pipeline

We hardened the release script so the failure can’t slip through silently.

### Patch: zip-helper preflight

See: `infra/SaneProcess/scripts/release.sh` (invoked via `./scripts/SaneMaster.rb release`)

New behavior before DMG creation:

1. Scan `SaneBar.app/Contents/Resources` for `*.zip` resources.
2. For each zip:
   - unzip to a temp directory
   - if it contains any `*.app`, re-sign those bundles with:
     - `Developer ID Application` identity
     - `--options runtime`
     - `--timestamp`
     - **empty entitlements** (this strips `get-task-allow`)
   - re-zip the payload back into the original zip path
3. Enforce that no executables inside the main app bundle have `get-task-allow`.

This specifically targets the recurring rejection pattern: helper apps embedded in Resources zips.

## How to validate before submitting

Recommended checks:

- Run release build locally (without notarizing):
  - `./scripts/SaneMaster.rb release --skip-notarize --version X.Y.Z`
- Verify the exported app:
  - `codesign --verify --deep --strict build/Export/SaneBar.app`
  - `spctl -a -vvv build/Export/SaneBar.app`
- Submit:
  - `xcrun notarytool submit releases/SaneBar-X.Y.Z.dmg --keychain-profile notarytool --wait`
- If rejected, download the log:
  - `xcrun notarytool log <JOB_ID> --keychain-profile notarytool`

## Notes

- If LaunchAtLogin helper zips are expected to ship, the *source* fix is to ensure they’re produced as Release / non-debug and signed correctly upstream.
- The release-script preflight is a safety net to prevent shipping an invalid DMG even if upstream packaging regresses.
