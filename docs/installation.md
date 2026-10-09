# Installing, updating and removing TokenPace

This guide describes the current local source-install workflow. Release
[v1.1.2](https://github.com/Citizenyolo/TokenPace/releases/tag/v1.1.2) contains source,
not a prebuilt or notarized application. Current behavior and policy are described
in the [architecture guide](architecture.md); isolated builds/tests are in
[Contributing](../CONTRIBUTING.md).

## Requirements

- macOS **14.0 (Sonoma) or newer**; project supports Apple Silicon and Intel.
- **Full Xcode**, with its developer directory selected. Apple's standalone
  Command Line Tools package does not supply `xcodebuild`:
  see [Apple's command-line tool reference](https://developer.apple.com/documentation/xcode/xcode-command-line-tool-reference).
  Open Xcode and complete its first-launch setup, then select that installation
  under Xcode Settings > Locations > Command Line Tools. Apple's
  [selection guide](https://developer.apple.com/documentation/xcode/configuring-command-line-tools-settings)
  also documents `xcode-select`.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen); with Homebrew, run
  `brew install xcodegen`.
- An installed, authenticated Agy CLI executable at **`~/.local/bin/agy`**.
  The daemon uses this exact path, not a shell alias or another executable on `PATH`.

## Install or update

From a source checkout:

```bash
git clone https://github.com/Citizenyolo/TokenPace.git
cd TokenPace
./install.sh
```

This clones current `main`. For the tagged source release, select `v1.1.2` before
installing (`git checkout v1.1.2`). For an existing checkout, choose the source
revision you want and run `./install.sh` there; cloning again is unnecessary.
A Git checkout lets the installer record its revision in the widget. Builds from
an extracted archive without Git metadata may display `unversioned`.

Add **TokenPace** from the desktop or Notification Center widget gallery. The
current extension provides a large widget. Its daemon starts at login through a
per-user LaunchAgent; the main app has no visible Dock/menu bar controls.

Running the installer updates **the local installation**, replaces the existing
app and restarts its processes. It is not a build-only check. To inspect the build
without changing the installed app, follow the
[build-only commands](../CONTRIBUTING.md#build-without-installing).

## Installation sequence

[install.sh](../install.sh) is the complete installation recipe. In order, it:

1. Checks for XcodeGen and `xcodebuild`, then generates the project from `project.yml`.
2. Allocates a secure, unique temporary build directory with `mktemp`, and installs
   cleanup traps for normal exit, failure and interruption. This prevents staging
   collisions/predictable paths and removes build detritus while preserving exit status.
3. Builds the app and embedded extension, stamping both with
   `TOKENPACE_SOURCE_REVISION` (or `unversioned`, with `-dirty` for changed build inputs).
4. Clears bundle extended attributes, then ad-hoc signs **the extension first**
   using `ExtensionEntitlements.entitlements`, followed by the host using
   `Entitlements.entitlements`. The extension needs `com.apple.security.app-sandbox`;
   the host is unsandboxed. No development team is configured for these local builds.
5. If present, unloads the existing daemon by its `gui/<uid>/io.github.citizenyolo.TokenPaceDaemon`
   service identity and stops the TokenPace app/extension processes.
6. Replaces `~/Applications/TokenPace.app` and registers it with LaunchServices.
7. Writes `~/Library/LaunchAgents/io.github.citizenyolo.TokenPaceDaemon.plist`
   with the installed host executable, `RunAtLoad` and `KeepAlive`, escaping the
   executable path for XML.
8. Bootstraps that LaunchAgent in the current user's GUI domain.

There is no app-group entitlement in the current setup; the unsandboxed host
publishes into the extension container. This describes the repo's local workflow,
not general Apple distribution or Developer Account requirements. A notarized
redistributable release would need separate packaging/signing work.

**Historical installation lessons:** v1.0.1 restored explicit sandbox entitlement
injection in `project.yml` after XcodeGen could otherwise erase the extension's
entitlement. v1.1.1 changed daemon lifecycle management to service-targeted
`launchctl bootout/bootstrap` to avoid unwanted respawns/ghost processes.
Secure temporary staging was subsequently verified with isolated fixtures.
Keep those behaviors when editing installer or project settings; see the
[changelog](../CHANGELOG.md) and [staging checks](../CONTRIBUTING.md#isolated-checks).

## Troubleshooting and acceptance

- **Build tools missing:** verify `xcodebuild -version`, `xcode-select -p` and
  `xcodegen --version`. If the installer mentions Command Line Tools, still select
  full Xcode as described above; that older error wording is incomplete.
- **Quota unavailable/stale:** confirm the CLI exists at the configured path and
  is authenticated. A manual `~/.local/bin/agy --output-format json -p /usage`
  tests the integration but can contact the upstream service. Do not share keys
  or conversation data in public diagnostics.
- **Daemon state:** `launchctl print "gui/$(id -u)/io.github.citizenyolo.TokenPaceDaemon"`
  inspects the installed service without restarting it.
- **Old or mismatched widget:** compare the visible **Widget** and **Data** revisions.
  An app on disk does not identify the cached timeline macOS is displaying.
  Allow for WidgetKit scheduling before concluding a build/refresh failed.
- **Network recovery:** use the [repeatable installed test](validation/issue-2.md#repeatable-installed-test-protocol).
  Offline detection and file publication alone do not prove server-side freshness.

## Uninstall

Unload the KeepAlive service before deleting its app so it cannot respawn. These
commands remove the installed daemon and app; the optional final command removes
cached widget data. Remove the visible widget from the desktop/Notification Center
as well.

```bash
set -e

# 1. Unload the daemon by service identity
SERVICE_TARGET="gui/$(id -u)/io.github.citizenyolo.TokenPaceDaemon"
if launchctl print "$SERVICE_TARGET" &>/dev/null; then
    launchctl bootout "$SERVICE_TARGET"
fi

# 2. Remove the LaunchAgent plist
rm -f ~/Library/LaunchAgents/io.github.citizenyolo.TokenPaceDaemon.plist

# 3. Ensure all processes are fully stopped
killall TokenPace 2>/dev/null || true
killall TokenPaceExtension 2>/dev/null || true

# 4. Delete the application
rm -rf ~/Applications/TokenPace.app

# 5. (Optional) Remove widget sandbox data, including cached quota.json
# rm -rf ~/Library/Containers/io.github.citizenyolo.TokenPaceExtension
```
