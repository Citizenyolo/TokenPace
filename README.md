# TokenPace

TokenPace is a native, headless macOS widget that monitors your Google Antigravity (Agy) quota and usage pace. It sits quietly on your desktop or Notification Center, tracking both your 5-hour and 7-day limits, visually warning you if your usage pace is overburning or safely conserving quota.

*Note: TokenPace is an independent open-source project and is not affiliated with, endorsed by, or sponsored by Google. Google, Antigravity, and Agy are trademarks of their respective owners.*

![TokenPace Widget Preview](Preview.png)

## Features

- **Dual Group Tracking:** Independently tracks both the "Gemini Models" group and "Claude and GPT Models" group.
- **Multiple Timeframes:** Monitors the weekly (7-day) remaining limit and the five-hour rolling remaining quota.
- **Pacing Indicator:** Quantifies your consumption rate versus an ideal linear burn, showing a percentage of underutilization or overburn.
  - 🟢 **Conserving:** (Green) You have >2% more quota remaining than a strict linear timeline dictates.
  - 🔵 **On Track:** (Blue) Your usage is perfectly in line with the timeline (within ±2%).
  - 🔴 **Overburn:** (Red) You are burning quota >2% faster than your cycle replenishes it.
- **Authoritative Resets:** Intelligently schedules a lightweight background refresh exactly one minute after your cycle officially resets to keep the widget precisely synced.
- **Invisible Daemon:** Runs entirely in the background. No Dock icon, no Menu Bar clutter.


## Known Issues

- **[ISSUE1 (#2): Quota freshness and recovery after network interruptions (WIP)](https://github.com/Citizenyolo/TokenPace/issues/2)**
  The local implementation now tracks successful CLI read age and retries failed reads. Installed-build verification, upstream CLI cache semantics and end-to-end offline/recovery acceptance remain outstanding; this is not approved for release.

## How it works

TokenPace is split into two components: an invisible macOS application (the daemon) and a WidgetKit Extension.

1. **Detection:** The daemon observes your `~/.gemini/antigravity-cli/conversations` and `~/.gemini/antigravity-ide/conversations` directories for SQLite database modifications (indicating active CLI or GUI usage).
2. **Quota Fetching:** When activity is detected, the daemon fetches quota purely by invoking your locally installed `~/.local/bin/agy --output-format json -p /usage`. TokenPace itself makes no network requests; quota retrieval is delegated entirely to the authenticated Agy CLI.
3. **Sandbox Handoff:** Apple strictly limits WidgetKit apps unless you possess a paid Developer Account. To allow free compilation and installation, TokenPace uses an unsandboxed helper daemon that writes the fetched JSON directly into the Widget Extension's secure sandbox (`~/Library/Containers/<BundleID>Extension/Data/Documents/quota.json`), and then triggers a timeline reload.
4. **Widget Timelines:** Once the widget receives the JSON, it generates a timeline of 120 minute-by-minute entries. This allows the widget to tick down the "Refreshes in Xh Ym" text dynamically on your desktop *without* waking up the daemon or spamming the Agy API.
5. **Stale Cache Detection:** A successful, complete CLI read records `fetchedAt`. At 300 seconds old (or any expired reset), the widget labels the last known percentages "Data stale" and hides pacing indicators. Missing/future fetch timestamps cannot establish freshness. Malformed, partial, out-of-range or implausible-reset payloads are rejected; no reset fabricates 100% availability. Exact age/reset transitions are included in the timeline, subject to WidgetKit scheduling. This measures local read age, not guaranteed upstream freshness.

## Burn-rate / pacing calculation

TokenPace computes your burn rate mathematically inside the widget UI without requiring historical databases.

```swift
// Pseudocode
ideal_remaining = 1.0 - (time_elapsed / total_cycle_duration)
deviation = actual_remaining_fraction - ideal_remaining
```

- If `deviation > +0.02`: Conserving (+X% Green)
- If `deviation < -0.02`: Overburn (-X% Red)
- Otherwise: On Track (±X% Blue)

## Refresh Behavior

| Event | Quota/API fetch? | Widget Update? |
| :--- | :--- | :--- |
| Completed Agy CLI answer | Yes (via SQLite observation) | Yes (Reloads Timeline) |
| Completed Antigravity GUI answer | Yes (via SQLite observation) | Yes (Reloads Timeline) |
| Minute passes | No | Yes (Advances Timeline) |
| Cycle Reset Timestamp Reached | No | Yes (Data stale) |
| Reset + 60 seconds | Yes (Scheduled Timer) | Yes (Authoritative Sync) |
| Application Startup | Yes (idempotent, single-flight) | On successful publication |
| 240 seconds after successful publication | Yes | On successful publication |
| Failed read or publication | Retry after 10, 20, 40, 80, 160, then 300 seconds indefinitely | Retains last known data; ages into stale |
| Last successful read + 300 seconds | No | Data stale; no pacing indicator |

The 240-second cadence leaves a 60-second margin before the 300-second stale boundary, including a bounded 30-second CLI invocation. Periodic, debounced activity and reset triggers share one coordinator; none bypass failure backoff or overlap a running read. Shutdown invalidates pending work and late responses. Reads also cap stdout at 1 MiB and require a zero exit status. Widget reload occurs only after atomic `quota.json` publication succeeds. Existing legacy cache files decode but are not considered fresh without `fetchedAt`.

### Isolated regression checks

Run `bash test_quota.sh` on macOS with Swift installed. This compiles production parsing, freshness, scheduling, subprocess and atomic file-store code against deterministic fixtures, an injected clock and temporary fake CLI executables; it also typechecks the daemon and widget. It never invokes the installed Agy CLI, accesses live quota files, installs/restarts the app, or changes connectivity. Covered cases include offline aging/recovery to actual fractions, reset/event/poll/retry coordination, publication failure, idempotent startup/shutdown, late responses, malformed/partial payloads and bounded subprocess failures.

## Requirements

- macOS 14.0 (Sonoma) or newer. Apple Silicon & Intel supported.
- Xcode Command Line Tools installed.
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
- Google Antigravity / Agy CLI installed and authenticated at `~/.local/bin/agy`.

## Installation

### Quick Install

Simply run the provided bash script to generate the Xcode project, compile the binaries, perform ad-hoc code signing, and register the widget.

```bash
./install.sh
```

### Manual Install

If you prefer to inspect the process:
1. `xcodegen generate`
2. Open `TokenPace.xcodeproj` in Xcode.
3. Build the `TokenPace` scheme.
4. Apply the entitlements using `codesign --force --sign - --entitlements Entitlements.entitlements /path/to/app`.
5. Copy to `~/Applications` and run `lsregister -f` on the `.app`.

## Uninstall

To completely remove TokenPace:
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

# 5. (Optional) Remove the widget sandbox data (contains cached quota.json)
# rm -rf ~/Library/Containers/io.github.citizenyolo.TokenPaceExtension
```

## Privacy & Security

TokenPace respects your privacy and is completely local.
- **What it watches:** It uses `DispatchSourceFileSystemObject` to monitor the modification timestamps of your Antigravity SQLite conversation databases. 
- **What it reads:** It never reads your conversation content. It only invokes `agy --output-format json -p /usage`.
- **What it stores:** It stores a single JSON struct containing numbers (percentages and timestamps) in your local app sandbox.
- **Network access:** TokenPace itself makes zero network requests. Quota checks are routed exclusively through your authenticated local Agy CLI binary.

## Limitations

- **Timeline Precision:** Apple's WidgetKit independently controls timeline redraw budgets and scheduling logic. Therefore, widget updates and countdown changes are not guaranteed to occur at exact minute boundaries, and updates may be deferred based on system power or performance conditions.
- **Path Dependency:** Assumes `agy` is installed at `~/.local/bin/agy`.
- **Upstream Cache:** A successful CLI response may be cached upstream or inside Agy. `fetchedAt` is the local read completion time, not an upstream observation timestamp. This needs a controlled runtime check before release.
- **API Stability:** Relies on the internal JSON structure of `agy /usage`. Changes by Google could break parsing.

## License

MIT License. See LICENSE file.
