# Changelog

All notable changes to this project will be documented in this file.

## [1.1.1] - 2026-10-03
### Fixed
- **Daemon Lifecycle:** Hardened `install.sh` and uninstall instructions to use modern `launchctl bootout/bootstrap` targeting service identities, cleanly preventing zombie respawns and ghost processes.
- **Cache Staleness Logic:** The widget now correctly detects when it has lost contact with the background daemon (or if an active network connection is unavailable) and conservatively falls back to "Data stale", completely eliminating false "100% Quota available" inferences.
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
