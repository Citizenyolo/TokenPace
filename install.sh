#!/bin/bash
set -e

echo "==> Building TokenPace..."
if ! command -v xcodegen &> /dev/null; then
    echo "Error: xcodegen is not installed. Please install it with 'brew install xcodegen'."
    exit 1
fi

if ! command -v xcodebuild &> /dev/null; then
    echo "Error: xcodebuild is not installed. Please install Xcode Command Line Tools."
    exit 1
fi

xcodegen generate

# Allocate a secure, collision-resistant temporary directory
BUILD_DIR=$(mktemp -d "${TMPDIR:-/tmp}/TokenPace_build_XXXXXXXX")

# Setup cleanup on script exit or interrupt
cleanup() {
    local ext_status=$?
    set +e
    if [ -n "$BUILD_DIR" ] && [ -d "$BUILD_DIR" ]; then
        rm -rf -- "$BUILD_DIR" >/dev/null 2>&1
    fi
    exit "$ext_status"
}
trap cleanup EXIT
trap "exit 129" HUP
trap "exit 130" INT
trap "exit 143" TERM

SOURCE_REVISION=$(git -c core.fsmonitor=false rev-parse --short=12 HEAD 2>/dev/null || printf 'unversioned')
if [ "$SOURCE_REVISION" != "unversioned" ]; then
    SOURCE_CHANGES=$(git -c core.fsmonitor=false status --porcelain --untracked-files=normal -- \
        Sources project.yml Info.plist ExtensionInfo.plist Entitlements.entitlements ExtensionEntitlements.entitlements install.sh)
    if [ -n "$SOURCE_CHANGES" ]; then SOURCE_REVISION="${SOURCE_REVISION}-dirty"; fi
fi
# Pass the same source identity to the daemon and widget; visible in the widget timeline.
xcodebuild -project TokenPace.xcodeproj -scheme TokenPace SYMROOT="$BUILD_DIR" TOKENPACE_SOURCE_REVISION="$SOURCE_REVISION" build | grep -v 'note:' | grep -v 'warning:'

APP_BUNDLE="$BUILD_DIR/Debug/TokenPace.app"
if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: TokenPace.app not found in expected build directory."
    exit 1
fi

echo "==> Stripping any remaining detritus before signing..."
xattr -cr "$APP_BUNDLE"

echo "==> Manually signing extension and app (bypassing Developer Account restriction)..."
codesign --force --sign - --entitlements ExtensionEntitlements.entitlements "$APP_BUNDLE/Contents/PlugIns/TokenPaceExtension.appex"
codesign --force --sign - --entitlements Entitlements.entitlements "$APP_BUNDLE"

PLIST_PATH="$HOME/Library/LaunchAgents/io.github.citizenyolo.TokenPaceDaemon.plist"
USER_ID=$(id -u)
SERVICE_TARGET="gui/$USER_ID/io.github.citizenyolo.TokenPaceDaemon"

echo "==> Unloading existing daemon..."
if launchctl print "$SERVICE_TARGET" &>/dev/null; then
    launchctl bootout "$SERVICE_TARGET"
fi

# Ensure process is dead
killall TokenPace 2>/dev/null || true
killall TokenPaceExtension 2>/dev/null || true

echo "==> Installing to ~/Applications..."
mkdir -p ~/Applications
rm -rf ~/Applications/TokenPace.app
cp -R "$APP_BUNDLE" ~/Applications/TokenPace.app

echo "==> Registering with macOS LaunchServices..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ~/Applications/TokenPace.app

echo "==> Configuring LaunchAgent daemon..."
mkdir -p "$HOME/Library/LaunchAgents"

# XML-escape the path just in case
APP_PATH="$HOME/Applications/TokenPace.app/Contents/MacOS/TokenPace"
ESCAPED_APP_PATH=$(echo "$APP_PATH" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g')

cat <<PLIST > "$PLIST_PATH"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.github.citizenyolo.TokenPaceDaemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>${ESCAPED_APP_PATH}</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Bootstrapping new daemon..."
launchctl bootstrap gui/$USER_ID "$PLIST_PATH"

echo "✅ Installation complete! You can now add the TokenPace widget to your desktop or Notification Center."
