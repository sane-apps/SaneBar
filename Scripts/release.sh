#!/bin/bash
# frozen_string_literal: false
#
# SaneBar Release Script
# Creates a signed DMG for distribution
#

set -e

# Configuration
APP_NAME="SaneBar"
BUNDLE_ID="com.sanevideo.SaneBar"
TEAM_ID="M78L6FXD48"
SIGNING_IDENTITY="Developer ID Application: Stephan Joseph (M78L6FXD48)"
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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
fi

# Create export options plist
log_info "Creating export options..."
cat > "${BUILD_DIR}/ExportOptions.plist" << EOF
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
EOF

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

# Create DMG
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_TEMP}" \
    -ov -format UDZO \
    "${DMG_PATH}"

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
        --keychain-profile "AC_PASSWORD" \
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
log_info ""
log_info "To test: open \"${FINAL_DMG}\""
log_info "To upload: Upload to GitHub Releases"

# Open the releases folder
open "${RELEASE_DIR}"
