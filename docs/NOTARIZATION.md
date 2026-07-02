# Notarization Notes (SaneBar)

What has caused Apple notarization to pass or fail for SaneBar.

## TL;DR pattern

Notarization succeeds when **every executable Apple can see** is:

- signed with **Developer ID Application** (correct Team ID)
- signed with a **secure timestamp**
- free of debug-only entitlements (especially `com.apple.security.get-task-allow`)

## The core gotcha

`codesign --verify --deep --strict SaneBar.app` **does not inspect executables embedded inside `.zip` resources** — Apple's notarization service does. A locally "clean" bundle can still be rejected for a bad binary hiding inside a zip in Resources.

Historical note: a LaunchAtLogin helper app shipped inside a zip in Resources once caused a notarization rejection (unsigned, debug-entitled helper) that local verification missed. That dependency is long gone; the lesson — validate zip contents, not just the outer bundle — is what matters.

## How to validate before submitting

- Run a release build locally (without notarizing):
  - `./Scripts/SaneMaster.rb release --skip-notarize --version X.Y.Z`
- Verify the exported app:
  - `codesign --verify --deep --strict build/Export/SaneBar.app`
  - `spctl -a -vvv build/Export/SaneBar.app`
- Submit:
  - `xcrun notarytool submit <archive> --keychain-profile notarytool --wait`
- If rejected, download the log:
  - `xcrun notarytool log <JOB_ID> --keychain-profile notarytool`

## Notes

- Apple's `notarytool log` includes a `sha256` of the uploaded archive. If it doesn't match your local artifact, you are comparing against the wrong build.
- If any zip in Resources ships executables, they must be Release builds signed with Developer ID + timestamp and without `get-task-allow`.
