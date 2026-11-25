# Changelog

All notable changes to this project will be documented in this file.

Release entries retain their historical wording. For current behavior and explicit
corrections to older parsing/observation descriptions, see the
[architecture audit notes](docs/architecture.md#documentation-audit-corrections).

## [1.2.1] - 2026-11-25

### Fixed
- Accept the Unix epoch reset placeholder for full quota buckets so Claude/GPT
  placeholders cannot block Gemini refreshes. Show `100%` and `Unknown reset time`.
- Accept valid fractions for disabled five-hour buckets after weekly exhaustion,
  including 100% after a reset. Continue showing the disabled bucket as `N/A`.
- Give background Agy reads an empty stdin so prompts fail promptly.

## [1.2.0] - 2026-10-20

### Changed
- Rename the widget's Gemini group to `Gemini Models (Antigravity)` to distinguish the
  agentic Antigravity allowance from the separate Google AI Pro Gemini chat quota.
- Align pacing percentages directly above usage percentages in a shared trailing
  column, and remove the technical build footer from the widget. Build identities
  remain available in bundle metadata and the local quota snapshot.

### Fixed
- Increment the app/extension build version for the new medium family so macOS can
  invalidate the old large-only widget descriptor during registration.
- Accept explicitly disabled five-hour buckets after weekly exhaustion, so one
  exhausted model group cannot freeze all quota updates. Show `N/A` / `Weekly limit
  reached` without fabricating a reset or pacing; retain legacy cache compatibility.

### Added
- Medium widget size displaying the same Gemini quota block as large; large retains
  both model groups. Size selection does not require subscription/date detection.
- Regression coverage for the real exhausted-weekly CLI response, both model groups,
  strict invalid-state rejection, cache roundtrips and recovery to active quotas.
- Privacy-safe unified-log reasons for CLI and quota-response rejection.

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

See the [previous changelog](https://github.com/Citizenyolo/TokenPace/blob/62a37925e0c00ee2b04290c100f1783a2b21dd17/CHANGELOG.md) for releases 1.0.0 through 1.1.0.
