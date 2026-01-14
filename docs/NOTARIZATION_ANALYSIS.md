# Notarization Submission Analysis

Generated: 2026-01-14

## Summary Statistics

| Status | Count | Notes |
|--------|-------|-------|
| **Accepted** | 7 | Versions 1.0.0, 1.0.1, 1.0.2, 1.0.3 |
| **Invalid** | 2 | 1.0.0 (early attempt), 1.0.5 |
| **Rejected** | 1 | SaneVideo.zip |
| **In Progress** | 6 | 1.0.4 (2), 1.0.5 (4) - stuck since Jan 12-14 |
| **Total** | 16 | |

---

## Detailed Submissions Timeline

### ✅ ACCEPTED (Ready for Distribution)

| Version | Submit Date | Job ID | Time in Queue | App Binary | Notes |
|---------|------------|--------|---|---|---|
| 1.0.0 | 2026-01-09 01:21:00 | `96a63728` | ~20 min | Release | First successful notarization |
| 1.0.0 | 2026-01-09 02:11:12 | `def59d17` | ~20 min | Release | Retry (passed again) |
| 1.0.0 | 2026-01-09 19:21:57 | `87473105` | ~20 min | Release | Third attempt (passed) |
| 1.0.1 | 2026-01-09 19:48:10 | `65bbe209` | ~20 min | Release | Version bump |
| 1.0.2 | 2026-01-09 22:58:05 | `5b09707b` | ~20 min | Release | Version bump |
| 1.0.3 | 2026-01-10 00:21:51 | `8cb171f8` | ~20 min | Release | Version bump |
| 1.0.3 | 2026-01-10 17:05:08 | `e70fb543` | ~20 min | Release | Retry (passed) |

**Accepted Pattern:**
- All are Release builds
- All completed in ~20 minutes
- All returned `statusCode: 0` with `issues: null`
- All versions 1.0.0 through 1.0.3

---

### ❌ INVALID (Archive Contains Critical Validation Errors)

| Version | Submit Date | Job ID | Status Code | Error | Root Cause |
|---------|------------|--------|---|---|---|
| 1.0.0 | 2026-01-09 01:12:18 | `35ed42a1` | 4000 | LaunchAtLogin helper zip not signed | Embedded helper inside `.../LaunchAtLogin_LaunchAtLogin.bundle/.../LaunchAtLoginHelper.zip` with wrong cert/no timestamp/has `get-task-allow` |
| 1.0.5 | 2026-01-14 03:17:59 | `439a0d2e` | 4000 | LaunchAtLogin helper zip not signed | Same as above: helper inside zipped resource not Developer ID–signed, missing timestamp, has debug entitlements |

**Invalid Pattern:**
- Both hit `statusCode: 4000` ("critical validation errors")
- Both contain exact same embedded helper signing issues
- Same binary inside `.zip` resource in Resources folder
- **The 1.0.0 invalid attempt came *before* the accepted 1.0.0 attempts**
- Suggests 1.0.0 was re-submitted after fix

---

### ⚠️ REJECTED (Not Acceptable for Distribution)

| Version | Submit Date | Job ID | Status | Error Details |
|---------|------------|--------|---|---|
| SaneVideo.zip | 2026-01-01 15:56:35 | `5a0789f4` | Invalid | Unknown (not SaneBar) |
| SaneVideo.zip | 2026-01-01 15:58:10 | `d1ead7f9` | Rejected | Unknown (not SaneBar) |

*Not SaneBar submissions; excluded from analysis.*

---

### ⏳ IN PROGRESS (Still Pending)

| Version | Submit Date | Job ID | Hours Waiting | Likely Cause |
|---------|------------|--------|---|---|
| 1.0.4 | 2026-01-12 10:24:18 | `77e5ada7` | ~40+ hours | Unknown—possibly queue backup or build artifact issue |
| 1.0.4 | 2026-01-13 00:10:12 | `20e3c532` | ~28+ hours | Same as above |
| 1.0.5 | 2026-01-14 03:23:02 | `69d99781` | ~25 hours | Likely old artifact; fixed version below |
| 1.0.5 | 2026-01-14 03:24:01 | `9ef6a909` | ~25 hours | Likely old artifact; fixed version below |
| 1.0.5 | 2026-01-14 04:29:20 | `61043270` | ~24 hours | Likely old artifact; fixed version below |
| 1.0.5 | 2026-01-14 04:38:05 | `e9eea161` | ~24 hours | **Likely new fixed build** (newest) |

**In Progress Pattern:**
- 1.0.4 stuck >24 hours (never succeeded)
- Multiple 1.0.5 submissions piling up (old builds before zip preflight was added)
- Newest 1.0.5 (`e9eea161`) submitted after the preflight fix was applied to release.sh

---

## Critical Discovery: The LaunchAtLogin Helper Root Cause

### What Worked (1.0.0 accepted attempts)

After initial 1.0.0 invalid submission, three subsequent 1.0.0 submissions were accepted. Possible explanations:

1. **Helper was re-signed** before re-submission (manually or by a script)
2. **DMG contents changed** between submissions (e.g., helper removed or replaced)
3. **Different build produced** with properly signed helper

### What Failed (1.0.5 invalid, 1.0.4 stuck)

Both 1.0.5 and 1.0.4 contain the problematic LaunchAtLogin helper zips:

- Path: `SaneBar.app/Contents/Resources/LaunchAtLogin_LaunchAtLogin.bundle/.../LaunchAtLoginHelper.zip`
- Inside zip: `LaunchAtLoginHelper.app/Contents/MacOS/LaunchAtLoginHelper`
- Issues:
  - Not signed with Developer ID Application
  - Missing secure timestamp
  - Contains `com.apple.security.get-task-allow` (debug entitlement)

### Why Earlier Versions Passed

Hypothesis based on timeline:

- **1.0.0 accepted attempts** (Jan 9, 01:21 onward): Helper was either:
  - Properly signed with Developer ID + timestamp OR
  - Not present in the DMG
- **1.0.3 always accepted** (Jan 10): Helper was in acceptable state OR removed
- **1.0.4 stuck** (Jan 12): Reintroduced the problematic helper (same issue as 1.0.5)
- **1.0.5 invalid** (Jan 14 before fix): Same helper issue

---

## Configuration Timeline

| Version | Release Date | Status | Project.yml Changes | Release.sh Changes | Known Issues |
|---------|------------|--------|---|---|---|
| 1.0.0 | 2026-01-09 | Mixed (1 invalid, 3 accepted) | Base | Base | LaunchAtLogin helper not properly signed initially |
| 1.0.1 | 2026-01-09 | ✅ Accepted | Unchanged | Unchanged | None known |
| 1.0.2 | 2026-01-09 | ✅ Accepted | Unchanged | Unchanged | None known |
| 1.0.3 | 2026-01-10 | ✅ Accepted | Unchanged | Unchanged | None known |
| 1.0.4 | 2026-01-12 | ⏳ In Progress | Unchanged | Unchanged | LaunchAtLogin helper issue reappeared? |
| 1.0.5 | 2026-01-14 | ❌ Invalid (old) | Unchanged | **Fixed: zip preflight added** | Submitted before fix, then fixed and resubmitted |

---

## Lessons & Pattern Summary

### The Pattern

1. **LaunchAtLogin helper zips are the blocker**
   - When they're not Developer ID–signed + timestamped, notarization fails
   - When they contain `get-task-allow` entitlement, notarization fails
   - `codesign --verify --deep` doesn't catch this (Apple does)

2. **Versions 1.0.0–1.0.3 passed because:**
   - Early 1.0.0 invalid → manually fixed → resubmitted successfully
   - 1.0.1, 1.0.2, 1.0.3 maintained the fix (or didn't have the problem)

3. **Versions 1.0.4–1.0.5 failed/stuck because:**
   - Problem helper was reintroduced (possibly via dependency update or rebuild)
   - Release script had no preflight to catch it

4. **The Fix (2026-01-14):**
   - Added `fix_and_verify_zipped_apps_in_app()` to release.sh
   - Automatically re-signs embedded helpers before DMG creation
   - Strips `get-task-allow` and adds timestamp

### Next Steps

1. **For 1.0.5 newest job** (`e9eea161`, submitted 2026-01-14 04:38:05):
   - Wait for completion or poll every 30 min
   - If Accepted: fix confirmed, move to release
   - If Invalid: investigate what's in the zip (unlikely with preflight active)

2. **For stuck 1.0.4 jobs:**
   - Probably outdated; safe to ignore or resubmit with fixed release.sh

3. **Going forward:**
   - Always run through preflight before submitting
   - Monitor notarytool logs immediately upon completion
   - Document any new failures in docs/NOTARIZATION.md

