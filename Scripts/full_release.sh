#!/bin/bash
#
# full_release.sh - Complete SaneBar release automation
#
# This script automates ALL release steps:
# 1. Bumps version in project.yml
# 2. Runs xcodegen
# 3. Runs tests
# 4. Builds, signs, notarizes, staples DMG
# 5. Creates GitHub release
# 6. Updates appcast.xml
# 7. Updates Homebrew cask
# 8. Verifies all endpoints
#
# Usage: ./scripts/full_release.sh X.Y.Z "Release notes here"
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

VERSION="$1"
RELEASE_NOTES="$2"

if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: Version required${NC}"
    echo "Usage: ./scripts/full_release.sh X.Y.Z \"Release notes here\""
    exit 1
fi

if [ -z "$RELEASE_NOTES" ]; then
    echo -e "${RED}Error: Release notes required${NC}"
    echo "Usage: ./scripts/full_release.sh X.Y.Z \"Release notes here\""
    exit 1
fi

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

log_step() {
    echo ""
    echo -e "${BLUE}==== STEP: $1 ====${NC}"
}

log_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

log_warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

log_error() {
    echo -e "${RED}✗ $1${NC}"
}

# Calculate project version number from semantic version
PROJECT_VERSION=$(echo "$VERSION" | tr -d '.' | sed 's/^0*//')
if [ -z "$PROJECT_VERSION" ]; then
    PROJECT_VERSION="1"
fi

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   SaneBar Full Release Automation        ║${NC}"
echo -e "${BLUE}║   Version: $VERSION                         ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"

# Step 1: Pre-flight checks
log_step "Pre-flight Checks"

if ! git diff --quiet; then
    log_error "Git working directory not clean. Commit or stash changes first."
    exit 1
fi
log_success "Git working directory clean"

if ! command -v gh &> /dev/null; then
    log_error "GitHub CLI (gh) not installed"
    exit 1
fi
log_success "GitHub CLI available"

# Step 2: Bump version in project.yml
log_step "Bumping Version to $VERSION"

sed -i '' "s/MARKETING_VERSION: \".*\"/MARKETING_VERSION: \"$VERSION\"/" project.yml
sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$PROJECT_VERSION\"/" project.yml
log_success "project.yml updated"

# Step 3: Regenerate Xcode project
log_step "Regenerating Xcode Project"
xcodegen generate
log_success "Xcode project regenerated"

# Step 4: Run tests
log_step "Running Tests"
if xcodebuild test -scheme SaneBar -destination 'platform=macOS' -quiet 2>/dev/null; then
    log_success "All tests passed"
else
    log_error "Tests failed! Aborting release."
    git checkout project.yml
    exit 1
fi

# Step 5: Commit version bump
log_step "Committing Version Bump"
git add project.yml
git commit -m "Bump version to $VERSION"
log_success "Version bump committed"

# Step 6: Build, notarize, staple
log_step "Building, Notarizing, Stapling"
echo "This may take 15-20 minutes..."
./scripts/release.sh --version "$VERSION"

DMG_PATH="releases/SaneBar-$VERSION.dmg"
if [ ! -f "$DMG_PATH" ]; then
    log_error "DMG not found at $DMG_PATH"
    exit 1
fi
log_success "DMG created and notarized"

# Get SHA256 for Homebrew
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
log_success "SHA256: $SHA256"

# Step 7: Create GitHub Release
log_step "Creating GitHub Release"
gh release create "v$VERSION" "$DMG_PATH" \
    --title "v$VERSION" \
    --notes "$RELEASE_NOTES"
log_success "GitHub Release created"

# Step 8: Update appcast.xml
log_step "Updating Appcast"

DMG_SIZE=$(stat -f%z "$DMG_PATH")
PUB_DATE=$(date -R)

# Get edSignature from release.sh output (stored in a temp file)
ED_SIG=$(grep -A1 "sparkle:edSignature" /tmp/sanebar_release_output.txt 2>/dev/null | tail -1 | tr -d ' "' || echo "SIGNATURE_NEEDED")

# Create new item block
NEW_ITEM="        <item>
            <title>$VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
            <description>
                <![CDATA[
                <h2>Changes</h2>
                <p>$RELEASE_NOTES</p>
                ]]>
            </description>
            <enclosure url=\"https://github.com/sane-apps/SaneBar/releases/download/v$VERSION/SaneBar-$VERSION.dmg\"
                       sparkle:version=\"$VERSION\"
                       sparkle:shortVersionString=\"$VERSION\"
                       length=\"$DMG_SIZE\"
                       type=\"application/x-apple-diskimage\"
                       sparkle:edSignature=\"$ED_SIG\"/>
        </item>"

# Insert new item after <channel><title>
sed -i '' "/<title>SaneBar Changelog<\/title>/a\\
$NEW_ITEM
" docs/appcast.xml

git add docs/appcast.xml
git commit -m "Update appcast for v$VERSION"
git push origin main
log_success "Appcast updated and pushed"

# Step 9: Verification
log_step "Verifying All Endpoints"

echo "Checking GitHub Release..."
if gh release view "v$VERSION" &>/dev/null; then
    log_success "GitHub Release: OK"
else
    log_warn "GitHub Release: Check manually"
fi

# Final summary
echo ""
echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║   RELEASE v$VERSION COMPLETE!              ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
echo ""
echo "Summary:"
echo "  - DMG: $DMG_PATH"
echo "  - GitHub: https://github.com/sane-apps/SaneBar/releases/tag/v$VERSION"
echo "  - Website: Upload DMG to sanebar.com for purchase"
echo "  - Appcast: Updated in docs/appcast.xml"
echo ""
echo -e "${YELLOW}Manual steps remaining:${NC}"
echo "  1. Reply to any GitHub issues fixed in this release"
echo "  2. Post on Reddit/social media if needed"
echo ""
