#!/bin/bash
# frozen_string_literal: false
#
# Generic Release Script
# Creates a signed DMG for distribution
#

set -e

# Configuration
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="$(basename "${PROJECT_ROOT}")"
# Convert APP_NAME to lowercase for bundle ID (e.g. SaneBar -> sanebar)
LOWER_APP_NAME="$(echo "${APP_NAME}" | tr '[:upper:]' '[:lower:]')"
BUNDLE_ID="com.${LOWER_APP_NAME}.app"

TEAM_ID="M78L6FXD48"
SIGNING_IDENTITY="Developer ID Application: Stephan Joseph (M78L6FXD48)"
BUILD_DIR="${PROJECT_ROOT}/build"
ARCHIVE_PATH="${BUILD_DIR}/${APP_NAME}.xcarchive"
EXPORT_PATH="${BUILD_DIR}/Export"
DMG_PATH="${BUILD_DIR}/${APP_NAME}.dmg"
RELEASE_DIR="${PROJECT_ROOT}/releases"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

ensure_cmd() {
    if ! command -v "$1" >/dev/null 2>&1; then
        log_error "Required command not found: $1"
        exit 1
    fi
}

create_empty_entitlements_plist() {
    local entitlements_path="$1"
    cat > "${entitlements_path}" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict/>
</plist>
PLIST
}

binary_has_get_task_allow() {
    local binary_path="$1"
    if codesign -d --entitlements :- "${binary_path}" 2>/dev/null | grep -q "get-task-allow"; then
        return 0
    fi
    return 1
}

sign_app_bundle_developer_id() {
    local bundle_path="$1"
    local entitlements_path="$2"

    # --deep is intentional here because helper apps embedded in zips frequently
    # contain Swift runtime dylibs and frameworks which also need a Developer ID signature.
    codesign --force --sign "${SIGNING_IDENTITY}" --options runtime --timestamp \
        --entitlements "${entitlements_path}" --deep "${bundle_path}"
}

fix_and_verify_zipped_apps_in_app() {
    local host_app_path="$1"

    # Some libraries embed helper .app bundles inside .zip resources. Apple notarization
    # validates those payloads, but codesign --verify --deep does NOT inspect inside zips.
    local tmp_root
    tmp_root=$(/usr/bin/mktemp -d /tmp/release_notary_preflight.XXXX)
    local empty_entitlements="${tmp_root}/empty.entitlements"
    create_empty_entitlements_plist "${empty_entitlements}"

    # Only scan Resources for zips to keep runtime low.
    local resources_path="${host_app_path}/Contents/Resources"
    if [ ! -d "${resources_path}" ]; then
        rm -rf "${tmp_root}"
        return 0
    fi

    local zip_found=false
    while IFS= read -r -d '' zip_path; do
        zip_found=true

        local unzip_dir="${tmp_root}/unzip"
        rm -rf "${unzip_dir}"
        mkdir -p "${unzip_dir}"

        # If the zip doesn't contain an .app, skip it.
        if ! ditto -x -k "${zip_path}" "${unzip_dir}" 2>/dev/null; then
            log_warn "Could not unzip resource: ${zip_path} (skipping)"
            continue
        fi

        local apps_in_zip
        apps_in_zip=$(find "${unzip_dir}" -name "*.app" -maxdepth 6 2>/dev/null || true)
        if [ -z "${apps_in_zip}" ]; then
            continue
        fi

        log_info "Fixing embedded helper app(s) in: ${zip_path}"

        # Re-sign each embedded app bundle.
        while IFS= read -r embedded_app; do
            [ -n "${embedded_app}" ] || continue

            local embedded_exec
            embedded_exec=$(defaults read "${embedded_app}/Contents/Info" CFBundleExecutable 2>/dev/null || true)
            if [ -n "${embedded_exec}" ] && [ -f "${embedded_app}/Contents/MacOS/${embedded_exec}" ]; then
                if binary_has_get_task_allow "${embedded_app}/Contents/MacOS/${embedded_exec}"; then
                    log_warn "Removing get-task-allow by re-signing: ${embedded_app}"
                fi
            fi

            sign_app_bundle_developer_id "${embedded_app}" "${empty_entitlements}"

            if [ -n "${embedded_exec}" ] && [ -f "${embedded_app}/Contents/MacOS/${embedded_exec}" ]; then
                if binary_has_get_task_allow "${embedded_app}/Contents/MacOS/${embedded_exec}"; then
                    log_error "Embedded helper still has get-task-allow after signing: ${embedded_app}"
                    rm -rf "${tmp_root}"
                    exit 1
                fi
            fi
        done <<< "${apps_in_zip}"

        # Recreate zip from the extracted directory.
        rm -f "${zip_path}"
        (cd "${unzip_dir}" && ditto -c -k --sequesterRsrc . "${zip_path}")
    done < <(find "${resources_path}" -type f -name "*.zip" -print0 2>/dev/null || true)

    if [ "${zip_found}" = true ]; then
        log_info "Embedded zip helper preflight complete."
    fi

    rm -rf "${tmp_root}"
}

sanity_check_app_for_notarization() {
    local host_app_path="$1"
    local main_exec
    main_exec=$(defaults read "${host_app_path}/Contents/Info" CFBundleExecutable 2>/dev/null || true)
    if [ -z "${main_exec}" ] || [ ! -f "${host_app_path}/Contents/MacOS/${main_exec}" ]; then
        log_error "Could not determine main executable for: ${host_app_path}"
        exit 1
    fi

    if binary_has_get_task_allow "${host_app_path}/Contents/MacOS/${main_exec}"; then
        log_error "Main app executable has get-task-allow (Debug entitlement). Release builds must not include this."
        exit 1
    fi

    # Check all executables inside the bundle for debug entitlement.
    while IFS= read -r -d '' exec_path; do
        if binary_has_get_task_allow "${exec_path}"; then
            log_error "Found get-task-allow in embedded executable: ${exec_path}"
            exit 1
        fi
    done < <(find "${host_app_path}" -type f -path "*/Contents/MacOS/*" -print0 2>/dev/null || true)
}

# Parse arguments
SKIP_NOTARIZE=false
SKIP_BUILD=false
VERSION=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --skip-notarize)
            SKIP_NOTARIZE=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --skip-notarize  Skip notarization (for local testing)"
            echo "  --skip-build     Skip build step (use existing archive)"
            echo "  --version X.Y.Z  Set version number"
            echo "  -h, --help       Show this help"
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Clean up previous builds
log_info "Cleaning previous build artifacts..."
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
mkdir -p "${RELEASE_DIR}"

# Generate project
log_info "Generating Xcode project..."
cd "${PROJECT_ROOT}"
xcodegen generate

ensure_cmd xcodebuild
ensure_cmd codesign
ensure_cmd xcrun
ensure_cmd hdiutil
ensure_cmd ditto

verify_archive_bundle_id() {
    local archive_app_path="${ARCHIVE_PATH}/Products/Applications/${APP_NAME}.app"
    if [ ! -d "${archive_app_path}" ]; then
        log_error "Archive app not found at ${archive_app_path}"
        exit 1
    fi

    local archive_bundle_id
    archive_bundle_id=$(defaults read "${archive_app_path}/Contents/Info" CFBundleIdentifier 2>/dev/null || true)
    if [ -z "${archive_bundle_id}" ]; then
        log_error "Unable to read CFBundleIdentifier from archive app"
        exit 1
    fi

    if [ "${archive_bundle_id}" != "${BUNDLE_ID}" ]; then
        log_error "Bundle ID mismatch: expected ${BUNDLE_ID}, got ${archive_bundle_id}"
        exit 1
    fi
}

if [ "$SKIP_BUILD" = false ]; then
    # Build archive
    # Note: Don't override CODE_SIGN_IDENTITY - let project.yml handle it
    # to avoid conflicts with SPM packages (they use automatic signing)
    log_info "Building release archive..."
    xcodebuild archive \
        -scheme "${APP_NAME}" \
        -configuration Release \
        -archivePath "${ARCHIVE_PATH}" \
        -destination "generic/platform=macOS" \
        OTHER_CODE_SIGN_FLAGS="--timestamp" \
        2>&1 | tee "${BUILD_DIR}/build.log"

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        log_error "Archive build failed! Check ${BUILD_DIR}/build.log"
        exit 1
    fi

    verify_archive_bundle_id
fi

# Create export options plist
log_info "Creating export options..."
cat > "${BUILD_DIR}/ExportOptions.plist" << OPT
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>${TEAM_ID}</string>
    <key>signingStyle</key>
    <string>manual</string>
    <key>signingCertificate</key>
    <string>Developer ID Application</string>
</dict>
</plist>
OPT

# Export archive
log_info "Exporting signed app..."
xcodebuild -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${BUILD_DIR}/ExportOptions.plist" \
    2>&1 | tee -a "${BUILD_DIR}/build.log"

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    log_error "Export failed! Check ${BUILD_DIR}/build.log"
    exit 1
fi

APP_PATH="${EXPORT_PATH}/${APP_NAME}.app"

# Notarization preflight: fix helper apps embedded inside zip resources, and check entitlements.
fix_and_verify_zipped_apps_in_app "${APP_PATH}"
sanity_check_app_for_notarization "${APP_PATH}"

# Verify code signature
log_info "Verifying code signature..."
codesign --verify --deep --strict "${APP_PATH}"
log_info "Code signature verified!"

# Get version from app
if [ -z "$VERSION" ]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "1.0.0")
fi
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "1")
log_info "Version: ${VERSION} (${BUILD_NUMBER})"

# Create DMG
DMG_NAME="${APP_NAME}-${VERSION}"
DMG_PATH="${BUILD_DIR}/${DMG_NAME}.dmg"
DMG_TEMP="${BUILD_DIR}/dmg_temp"

log_info "Creating DMG..."
rm -rf "${DMG_TEMP}"
mkdir -p "${DMG_TEMP}"

# Copy app to temp folder
cp -R "${APP_PATH}" "${DMG_TEMP}/"

# Create Applications symlink
ln -s /Applications "${DMG_TEMP}/Applications"

# Create DMG (Standard)
hdiutil_args=(create -volname "${APP_NAME}" -srcfolder "${DMG_TEMP}" -ov -format UDZO)
# Custom icon application via hdiutil is unreliable, we use a swift script below instead.
# However, we still create the DMG here.

hdiutil "${hdiutil_args[@]}" "${DMG_PATH}"

# Apply Custom Icon if present (Fallback for Finder icon)
if [ -f "${PROJECT_ROOT}/Resources/DMGIcon.icns" ]; then
    log_info "Setting custom Finder icon for DMG..."
    
    if swift "${PROJECT_ROOT}/scripts/set_dmg_icon.swift" "${PROJECT_ROOT}/Resources/DMGIcon.icns" "${DMG_PATH}"; then
        log_info "Custom icon applied to file"
    else
        log_warn "Failed to apply custom icon to file"
    fi
fi

# Sign DMG
log_info "Signing DMG..."
codesign --sign "${SIGNING_IDENTITY}" --timestamp "${DMG_PATH}"

# Verify DMG signature
codesign --verify "${DMG_PATH}"
log_info "DMG signature verified!"

# Notarize (if not skipped)
if [ "$SKIP_NOTARIZE" = false ]; then
    log_info "Submitting for notarization..."
    log_warn "This may take several minutes..."

    # Submit for notarization
    xcrun notarytool submit "${DMG_PATH}" \
        --keychain-profile "notarytool" \
        --wait

    # Staple the notarization ticket
    log_info "Stapling notarization ticket..."
    xcrun stapler staple "${DMG_PATH}"

    log_info "Notarization complete!"
else
    log_warn "Skipping notarization (--skip-notarize flag set)"
fi

# Copy to releases folder
FINAL_DMG="${RELEASE_DIR}/${DMG_NAME}.dmg"
cp "${DMG_PATH}" "${FINAL_DMG}"

# Clean up
rm -rf "${DMG_TEMP}"

log_info "========================================"
log_info "Release build complete!"
log_info "========================================"
log_info "DMG: ${FINAL_DMG}"
log_info "Version: ${VERSION}"

# Generate Sparkle Signature and Homebrew Hash
if command -v swift >/dev/null 2>&1; then
    log_info ""
    log_info "--- Generating Release Metadata ---"    
    # Calculate SHA256
    SHA256=$(shasum -a 256 "${FINAL_DMG}" | awk '{print $1}')
    
    # Try to fetch Sparkle Private Key
    log_info "Fetching Sparkle Private Key from Keychain..."
    SPARKLE_KEY=$(security find-generic-password -w -s "https://sparkle-project.org" -a "EdDSA Private Key" 2>/dev/null || echo "")
    
    if [ -n "$SPARKLE_KEY" ]; then
        log_info "Sparkle Key found. Generating signature..."
        
        SIGNATURE=$(swift "${PROJECT_ROOT}/scripts/sign_update.swift" "${FINAL_DMG}" "$SPARKLE_KEY" 2>/dev/null || echo "")
        
        if [ -n "$SIGNATURE" ]; then
            FILE_SIZE=$(stat -f%z "${FINAL_DMG}")
            DATE=$(date +"%a, %d %b %Y %H:%M:%S %z")
            
            echo -e "${GREEN}Sparkle AppCast Item:${NC}"
            cat <<EOF
<item>
    <title>${VERSION}</title>
    <pubDate>${DATE}</pubDate>
    <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
    <enclosure url="https://github.com/sane-apps/${APP_NAME}/releases/download/v${VERSION}/${APP_NAME}-${VERSION}.dmg"
               sparkle:version="${BUILD_NUMBER}"
               sparkle:shortVersionString="${VERSION}"
               length="${FILE_SIZE}"
               type="application/x-apple-diskimage"
               sparkle:edSignature="${SIGNATURE}"/>
</item>
EOF
        else
            log_warn "Failed to generate Sparkle signature Check Swift Key format"
        fi
    else
        log_warn "Sparkle Private Key not found in Keychain. Skipping signature generation."
    fi
    
    echo ""
    echo -e "${GREEN}Release Info:${NC}"
    echo "Version: ${VERSION}"
    echo "SHA256: ${SHA256}"
fi

log_info ""
log_info "To test: open \"${FINAL_DMG}\""
log_info "To upload: Upload to GitHub Releases"

# Open the releases folder
open "${RELEASE_DIR}"
