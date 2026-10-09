# Changelog

All notable changes to this project will be documented in this file.

Release entries retain their historical wording. For current behavior and explicit
corrections to older parsing/observation descriptions, see the
[architecture audit notes](docs/architecture.md#documentation-audit-corrections).

## [Unreleased]

## [1.1.2] - 2026-10-09

Source release for the accepted quota freshness/recovery fix. Install from source with `./install.sh`; no prebuilt or notarized app is distributed.

### Changed
- Replaced `ISO8601DateFormatter` with modern `Date(_:strategy: .iso8601)` parsing strategy.

### Fixed
- **Quota freshness and recovery ([#2](https://github.com/Citizenyolo/TokenPace/issues/2)):** Track successful local read age; mark snapshots stale after 300 seconds or an expired reset and hide stale pacing. Reject malformed, partial, out-of-range and implausible-reset responses without fabricating availability.
- **Refresh coordination:** Share one in-flight read across startup, activity, 240-second polling, reset and retry triggers. Bound CLI reads to 30 seconds and 1 MiB stdout; retry with capped exponential backoff and publish snapshots atomically.
- **Connectivity recovery:** Pause new reads without a usable network path, discard responses spanning a path loss and request a fresh read on recovery. Prevent identical path notifications and activity events from bypassing backoff.
- **Widget layout:** Fit all four quota rows within the desktop widget frame and place build diagnostics outside the quota layout.

### Added
- Source revision stamping for the daemon and widget, with visible Widget/Data revisions for runtime verification.
- 86 isolated production-code regression checks, daemon/widget typechecks and an installer-staging check.
- [Runtime acceptance evidence and repeatable offline/reconnection protocol](docs/validation/issue-2.md), accepted on 2026-10-09 for installed build `c8691cbf4168`. Upstream cache freshness and exact reset-window semantics remain documented limitations.

## [1.1.1] - 2026-10-03
### Fixed
- **Daemon Lifecycle:** Hardened `install.sh` and uninstall instructions to use modern `launchctl bootout/bootstrap` targeting service identities, cleanly preventing zombie respawns and ghost processes.
- **Cache Staleness Logic:** The widget now correctly detects when an explicit reset timestamp has expired and conservatively signals "Data stale". *(Note: comprehensive network/data-age tracking is still [WIP in ISSUE1 (#2)](https://github.com/Citizenyolo/TokenPace/issues/2)).*
- **Quota Synchronization:** `QuotaObserver` now utilizes an exponential backoff loop for transient network failures. Strict sequence IDs ensure that obsolete, delayed network responses can no longer silently overwrite fresh data fetches.

## [1.1.0] - 2026-10-02
### Added
- Dark Mode Support: The widget now natively supports macOS Dark Mode. Text and background colors dynamically adapt to the system appearance setting for a seamless visual experience.

## [1.0.2] - 2026-10-02
### Changed
- Improved remaining time formatting: displays as "Resets in X days Yh Zm" for durations over 24 hours.
- Shortened "Refreshes in" to "Resets in" to improve layout in the weekly view.

## [1.0.1] - 2026-09-30
### Fixed
- Fixed an issue where the installation script would silently erase the `com.apple.security.app-sandbox` entitlement during the XcodeGen phase, causing macOS to reject the widget.
- Restored explicit `app-sandbox` property injection into `project.yml` for correct build generation.

## [1.0.0] - 2026-09-30
### Added
- Initial release of TokenPace.
- Support for monitoring Gemini and Claude/GPT API usage.
- Dual 5-hour and Weekly cycle tracking.
- Live pacing/burn-rate calculation (Conserving, On Track, Overburn).
- Headless daemon with SQLite database observation.
- Optimistic WidgetKit timelines with delayed authoritative sync.
