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

## How it works

TokenPace is split into two components: an invisible macOS application (the daemon) and a WidgetKit Extension.

1. **Detection:** The daemon observes your `~/.gemini/antigravity-cli/conversations` and `~/.gemini/antigravity-ide/conversations` directories for SQLite database modifications (indicating active CLI or GUI usage).
2. **Quota Fetching:** When activity is detected, the daemon fetches quota purely by invoking your locally installed `~/.local/bin/agy --output-format json -p /usage`. TokenPace itself makes no network requests; quota retrieval is delegated entirely to the authenticated Agy CLI.
3. **Sandbox Handoff:** Apple strictly limits WidgetKit apps unless you possess a paid Developer Account. To allow free compilation and installation, TokenPace uses an unsandboxed helper daemon that writes the fetched JSON directly into the Widget Extension's secure sandbox (`~/Library/Containers/<BundleID>Extension/Data/Documents/quota.json`), and then triggers a timeline reload.
4. **Widget Timelines:** Once the widget receives the JSON, it generates a timeline of 120 minute-by-minute entries. This allows the widget to tick down the "Refreshes in Xh Ym" text dynamically on your desktop *without* waking up the daemon or spamming the Agy API.
5. **Optimistic Resets:** If a timeline entry surpasses a cached reset timestamp, the widget artificially (and optimistically) displays 100% quota and a "Quota available" label until the background daemon performs its scheduled authoritative fetch.

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
| Cycle Reset Timestamp Reached | No | Yes (Optimistic 100%) |
| Reset + 60 seconds | Yes (Scheduled Timer) | Yes (Authoritative Sync) |
| Application Startup | Yes | Yes (Reloads Timeline) |

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
killall TokenPace
killall TokenPaceExtension
rm -rf ~/Applications/TokenPace.app
rm -rf ~/Library/Containers/$(osascript -e 'id of app "TokenPace"' 2>/dev/null || echo "io.github.citizenyolo.TokenPace")Extension
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
- **API Stability:** Relies on the internal JSON structure of `agy /usage`. Changes by Google could break parsing.

## License

MIT License. See LICENSE file.
