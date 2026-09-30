#!/bin/bash
set -e

echo "==> Building TokenPace..."
# Ensure dependencies are installed
if ! command -v xcodegen &> /dev/null; then
    echo "Error: xcodegen is not installed. Please install it with 'brew install xcodegen'."
    exit 1
fi

if ! command -v xcodebuild &> /dev/null; then
    echo "Error: xcodebuild is not installed. Please install Xcode Command Line Tools."
    exit 1
fi

if [ ! -f ~/.local/bin/agy ]; then
    echo "Warning: ~/.local/bin/agy not found. The widget requires the Agy CLI to function."
fi

xcodegen generate
xcodebuild -project TokenPace.xcodeproj -scheme TokenPace SYMROOT="$(pwd)/build" build | grep -v 'note:' | grep -v 'warning:'

# Find the built app
APP_BUNDLE="$(pwd)/build/Debug/TokenPace.app"
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: TokenPace.app not found in expected build directory."
    exit 1
fi

echo "==> Manually signing extension and app (bypassing Developer Account restriction)..."
codesign --force --sign - --entitlements ExtensionEntitlements.entitlements "$APP_BUNDLE/Contents/PlugIns/TokenPaceExtension.appex"
codesign --force --sign - --entitlements Entitlements.entitlements "$APP_BUNDLE"

echo "==> Installing to ~/Applications..."
mkdir -p ~/Applications
killall TokenPace 2>/dev/null || true
killall TokenPaceExtension 2>/dev/null || true
rm -rf ~/Applications/TokenPace.app
cp -R "$APP_BUNDLE" ~/Applications/TokenPace.app

echo "==> Registering with macOS LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/TokenPace.app

echo "==> Starting TokenPace daemon..."
open ~/Applications/TokenPace.app

echo "✅ Installation complete! You can now add the TokenPace widget to your desktop or Notification Center."
