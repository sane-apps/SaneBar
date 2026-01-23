#!/bin/bash
# SaneBar Complete Uninstallation Script
# This script completely removes SaneBar and its traces from your system.

set -e

APP_NAME="SaneBar"
BUNDLE_ID="com.sanebar.app"
DEV_BUNDLE_ID="com.sanebar.dev"

echo "🗑️ --- Uninstalling SaneBar ---"

# 1. Quit the app if running
echo "⏹️  Stopping SaneBar..."
osascript -e 'quit app "SaneBar"' 2>/dev/null || true
killall SaneBar 2>/dev/null || true

# 2. Unregister from SMAppService (Launch at Login)
# This is the most common reason for "reinstalling" behavior
echo "🔓 Unregistering from background services..."
# We try to use the app itself to unregister if it exists
if [ -d "/Applications/SaneBar.app" ]; then
    /Applications/SaneBar.app/Contents/MacOS/SaneBar --unregister 2>/dev/null || true
fi

# 3. Remove Preferences and Application Support
echo "🧹 Cleaning up preferences and support files..."
rm -rf ~/Library/Application\ Support/com.sanebar.app
rm -rf ~/Library/Application\ Support/com.sanebar.dev
rm -rf ~/Library/Application\ Support/SaneBar
rm -f ~/Library/Preferences/com.sanebar.app.plist
rm -f ~/Library/Preferences/com.sanebar.dev.plist
rm -f ~/Library/Preferences/com.sanebar.app.SharedFileList.plist
defaults delete com.sanebar.app 2>/dev/null || true
defaults delete com.sanebar.dev 2>/dev/null || true

# 4. Remove Sparkle and System artifacts
echo "✨ Cleaning up update and system artifacts..."
rm -rf ~/Library/Caches/com.sanebar.app
rm -rf ~/Library/Caches/com.sanebar.dev
rm -rf ~/Library/HTTPStorages/com.sanebar.app
rm -rf ~/Library/HTTPStorages/com.sanebar.dev
rm -rf ~/Library/WebKit/com.sanebar.app
rm -rf ~/Library/WebKit/com.sanebar.dev

# 5. Reset Privacy Permissions (TCC)
echo "🔐 Resetting privacy permissions..."
tccutil reset Accessibility com.sanebar.app 2>/dev/null || true
tccutil reset Accessibility com.sanebar.dev 2>/dev/null || true
tccutil reset All com.sanebar.app 2>/dev/null || true
tccutil reset All com.sanebar.dev 2>/dev/null || true

# 6. Remove the App
echo "📂 Removing application binary..."
# Check common locations
for loc in "/Applications/SaneBar.app" "$HOME/Applications/SaneBar.app" "./build/SaneBar.app" "./build/Release/SaneBar.app" "./build/Debug/SaneBar.app"; do
    if [ -d "$loc" ]; then
        echo "   Removing $loc"
        rm -rf "$loc"
    fi
done

# 7. Clean up DerivedData for SaneBar
echo "🛠️  Cleaning up build artifacts..."
rm -rf ~/Library/Developer/Xcode/DerivedData/SaneBar-* 2>/dev/null || true

# 6. Verify SMAppService status (Optional, requires sfltool or similar if available)
# On modern macOS, SMAppService doesn't have a simple CLI to unregister by ID easily without the binary
# but removing the binary and the login item data usually stops it.

echo "✅ SaneBar has been completely uninstalled."
echo "💡 Tip: If it still appears in System Settings -> General -> Login Items, it is likely a ghost entry that macOS will clear after a restart or when you try to toggle it."
