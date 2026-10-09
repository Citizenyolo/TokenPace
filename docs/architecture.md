# TokenPace architecture and operational decisions

This is the detailed companion to the [README](../README.md). It documents the
current implementation and its rationale as audited on **2026-10-09**. Historical
runtime evidence remains in the [Issue #2 validation report](validation/issue-2.md).
A source review alone cannot establish upstream freshness or identify the build
macOS is currently displaying; those require the evidence and procedures below.

## Data flow and storage

TokenPace has an invisible SwiftUI application (the daemon) and a sandboxed
WidgetKit extension. The host is unsandboxed; `LSUIElement` removes its Dock icon,
and its settings scene has no visible controls. There is no menu bar item.

1. The daemon watches `~/.gemini/antigravity-cli/conversations` and
   `~/.gemini/antigravity-ide/conversations` with
   `DispatchSourceFileSystemObject` write notifications. These are activity hints,
   not answer-completion signals. Conversation content is never inspected.
   Missing directories cannot be watched; periodic reads do not depend on those hints.
2. Startup, periodic, activity, reset and connectivity-recovery triggers share
   one refresh coordinator. It invokes
   `~/.local/bin/agy --output-format json -p /usage`, using Agy's existing authentication.
   TokenPace has no direct HTTP client; the CLI can contact upstream services.
3. A complete valid response is converted to `QuotaData`, including local
   successful read time (`fetchedAt`) and the publishing build (`producerRevision`).
4. The unsandboxed daemon writes the snapshot into the widget's Documents directory:
   `~/Library/Containers/io.github.citizenyolo.TokenPaceExtension/Data/Documents/quota.json`.
   This is the current publication destination; the daemon does not also maintain
   a host Documents copy. The sandboxed extension reads `Documents/quota.json`
   relative to its own container home.
5. A successful atomic file write is followed by `WidgetCenter.reloadAllTimelines()`.
   The extension builds a timeline from that snapshot; each minute entry does not
   invoke Agy again.

The cache holds four quota fractions, four upstream reset timestamps, `fetchedAt`
and an optional producer revision. It is not a conversation/history database.
`fetchedAt` uses Swift Codable's default Date encoding: seconds since
**2001-01-01 UTC**, not Unix seconds. File modification time is supporting evidence,
not the freshness clock. [Security boundaries](../SECURITY.md) include the
unsandboxed host, CLI executable/authentication and locally stored quota data.

### Why this arrangement

The repo uses an unsandboxed publisher, a sandboxed widget and ad-hoc signing for
local builds without a configured development team. The arrangement describes
this project; it is not a claim that all WidgetKit apps require a paid account.
The extension's sandbox entitlement must survive project generation and signing.
Installation/signing details and the historical entitlement regression are in the
[installation guide](installation.md#installation-sequence).

## Response contract and freshness

A read is accepted only after zero process exit status and a JSON envelope with
`status: SUCCESS` and `command.name: usage`. All four recognized buckets must
appear exactly once under their expected group, with a fraction and reset time:

| Group name in CLI JSON | Bucket IDs | Duration |
| --- | --- | --- |
| `Gemini Models` | `gemini-5h`, `gemini-weekly` | 5 hours, 7 days |
| `Claude and GPT models` | `3p-5h`, `3p-weekly` | 5 hours, 7 days |

Unknown buckets are ignored; missing, duplicate or misgrouped recognized buckets
are rejected. Fractions must be finite and in `[0, 1]`. Reset timestamps accept
ISO 8601 with or without fractional seconds. Each reset must be later than the
read time and no more than its cycle duration plus **60 seconds** away. This is
an implementation plausibility bound, not a verified backend clock-skew guarantee.

A snapshot is fresh only when:

- `fetchedAt` exists and is not in the future;
- local age is **strictly less than 300 seconds**;
- all buckets were valid at `fetchedAt`;
- every reset is still in the future at the display entry's date.

The whole snapshot is treated as stale if any reset expires. Last known valid
percentages remain visible with stale labels and no pacing. Invalid/undecodable
cache data shows the unavailable message. Legacy files can decode without
`fetchedAt` or `producerRevision`, but cannot establish freshness without a valid
read timestamp. A reset never assumes the allowance has refilled to 100%.

**Why:** old values must not silently appear authoritative. Successful local
completion is the strongest timestamp the present CLI response provides, but it
cannot prove when the upstream service actually observed the quota.

## Pacing calculation

Pacing is a comparison with a linear allowance, not a measured tokens-per-minute
rate and not a prediction of remaining work time. There is no usage-history
database. The cycle is inferred from the reported deadline:

```text
cycle_start = reported_reset_time - cycle_duration
time_elapsed = entry_date - cycle_start
ideal_remaining = 1 - time_elapsed / cycle_duration
percentage_point_deviation = round((actual_remaining - ideal_remaining) * 100)
```

For dates at or before the inferred cycle start, the implementation uses an ideal
remaining fraction of `1`. At/after reset, or for any stale snapshot, pacing is
hidden. Inside the cycle, rounding happens **before** color selection:

| Rounded deviation | Label interpretation | Color |
| --- | --- | --- |
| Greater than +2 percentage points | Conserving | Green |
| From −2 through +2 | On track | Blue |
| Less than −2 | Overburn | Red |

For example, halfway through a cycle the ideal remaining fraction is 50%.
Actual 40% yields −10 percentage points (red); actual 60% yields +10 (green).
The displayed `%` is a percentage-point difference from the allowance, not a
percentage increase in speed. The separate 25-block quota bar reflects remaining
balance: green at 50% or above, yellow from 25% to below 50%, red below 25%.

A moved upstream reset changes the inferred cycle start and therefore can change
pacing without consumption. Do not use this indicator as a measured burn rate.

## Refresh behavior

| Event | CLI quota read? | Widget behavior |
| --- | --- | --- |
| Conversation-directory write | Requests a read after a 3-second activity delay, subject to backoff/single-flight | Reload after successful publication |
| Minute passes | No | Advances timeline countdown/pacing |
| Reset timestamp reached | No | Snapshot becomes stale; no invented quota |
| Earliest reported reset + 60 seconds | Requests a read, subject to connectivity/backoff/single-flight | Reload after successful publication |
| Application startup | Requests one read; idempotent start | Reload after successful publication |
| 240 seconds after successful publication | Requests a read | Reload after successful publication |
| Failed read or publication | Retry after 10, 20, 40, 80, 160, then 300 seconds indefinitely | Retain snapshot; it ages into stale |
| No usable network path | No new CLI invocation | Retain snapshot; it ages into stale |
| Usable path restored | One immediate attempt without waiting for the pending retry | Reload after successful publication |
| Last successful read + 300 seconds | No | Stale labels; pacing hidden |

### Coordination and failure boundaries

All coordinator methods run on the main queue; subprocess work alone runs off
queue. Startup is idempotent and only one read is in flight at a time. The daemon
checks deadlines on a one-second timer; these are scheduling targets rather than
hard timing guarantees. Shutdown invalidates pending work and late responses.

The activity delay is anchored to the **first** pending write, rather than
continually postponed by later writes. Continuous activity cannot starve a read.
Periodic, activity and reset triggers do not bypass failure backoff or overlap a
running read. Retry deadlines begin after failed completion; success resets the
failure count and schedules the next poll/reset.

`NWPathMonitor` pauses new invocations while no usable path exists. A genuine
unavailable-to-available transition resets backoff for one immediate attempt;
identical path notifications cannot continually bypass retries. A response that
spans a path loss is discarded, even if the path is restored before completion.
The coordinator retains the in-flight slot until that invocation completes,
then can start its replacement. A usable path does not prove upstream reachability:
service failures still back off. On startup, the daemon waits for the first
usable-path report before fetching.

CLI reads have a **30-second** deadline and **1 MiB** stdout cap. Output is drained
to avoid pipe-buffer deadlocks; timeout/overflow fails the read. Only the owned
child process is killed if it is still running. stderr is discarded, so the
current fetcher does not preserve detailed CLI diagnostic output.

Publication failure is a refresh failure: it retains the previous atomic snapshot
and enters backoff. Widget reload is requested only after publication succeeds.
Atomic replacement protects readers from partially written JSON; it does not
prove server freshness or promise immediate WidgetKit display.

### Why the timing values matter

The **240-second** poll interval leaves a nominal **60-second** margin before the
**300-second** stale boundary, including the bounded **30-second** CLI invocation.
Failures still lead to stale state; the margin is not a freshness guarantee.
The reset read is delayed **60 seconds** beyond the reported deadline so the
widget does not invent replenishment while waiting for an authoritative response.
The **3-second** activity delay coalesces bursts, and capped backoff avoids repeatedly
hammering a failing service. These are current policy choices, not verified
upstream service requirements or claims of globally optimal values.

## Widget timelines and build identity

The provider generates **120 minute entries** from the current time, adds exact
reset and `fetchedAt + 300 seconds` transitions within the two-hour horizon,
deduplicates/sorts them and uses `.atEnd` for the next timeline. This updates
countdown/pacing without a quota read each minute. macOS independently controls
WidgetKit budgets and scheduling, so redraws can be deferred by power/performance
conditions. An exact transition in the timeline is not a guaranteed display deadline.
The widget currently supports the large family; system colors adapt to appearance.

`install.sh` stamps both targets using `TOKENPACE_SOURCE_REVISION`. A modified or
untracked build input adds `-dirty`; checked inputs are `Sources`, `project.yml`,
both plists, both entitlements files and `install.sh`. Documentation-only changes
do not add that suffix. Manual builds can pass `TOKENPACE_SOURCE_REVISION=<commit>`
to `xcodebuild`; unstamped builds display `unversioned`.

The footer reports **Widget** (extension revision) and **Data** (publishing daemon
revision; `legacy` when absent). It is outside the quota stack so diagnostics do
not push quota rows offscreen. Inspecting the installed app alone is insufficient:
macOS may still display an old WidgetKit snapshot. Compare both visible identities
when accepting runtime behavior, then check age and values. Revision strings are
diagnostics supplied by the build, not cryptographic integrity verification.

## Reset countdown interpretation and upstream limits

TokenPace copies successful CLI `reset_time` values; it does not invent or extend
them. Between reads, the widget counts down against the stored deadline. A later
response can provide a later deadline, so the five-hour countdown can return
toward five hours even without usage.

During **2026-10-09** acceptance, full reported availability initially showed
`4h 57m`, then later `4h 59m`; weekly countdowns decreased normally. A successful
snapshot placed both five-hour resets about five hours after `fetchedAt`, and
CodexBar also showed approximately five hours. The user ultimately confirmed
synchronization. This explains the display change but **does not establish the
backend's exact rolling/reset policy**. Preserve that distinction when changing
countdown or pacing logic. See the [dated observations](validation/issue-2.md#reset-countdown-observations).

On **2026-10-07**, an isolated Agy CLI **1.3.1** probe with outbound internet denied
and localhost allowed returned an `ERROR` envelope with no quota, both before and
after an online `/usage` read. This supports that tested offline scenario only;
it does not establish every backend cache condition or future CLI behavior. The
CLI version used in the later installed acceptance was not independently reverified.
The macOS path guard additionally prevents responses spanning a path loss from
renewing freshness, but cannot detect every service-side cache condition.

Agy's CLI path and JSON contract are integration dependencies. Google/CLI changes
may break parsing or alter reset semantics. Local read age, path availability,
atomic storage and matching builds establish different facts; none substitutes
for a server observation timestamp that the current interface does not provide.

## Validation and further review

[Contributing](../CONTRIBUTING.md#isolated-checks) describes deterministic production-code
checks with fixtures, an injected clock and fake executables, plus installer staging
and macOS CI. Covered cases include offline aging/recovery to actual fractions,
reset/event/poll/retry interactions, publication failure, idempotent lifecycle,
late responses, malformed/partial payloads and subprocess bounds. Isolated checks
do not invoke live Agy, alter installed caches, install/restart apps or change connectivity.

The [validation report](validation/issue-2.md) preserves the tested full commit,
86 checks/typechecks/build evidence, dated file timestamps, approximately one-minute
stale and 30-second recovery observations, the repeatable protocol and its limits.
The report also preserves the CLI executable fingerprint and scoped cache-probe
method, the fresh/stale geometry measurement and the staging registration/signing
pitfalls recovered from implementation records. These are dated observations, not
universal macOS guarantees.

CI does not replace an installed runtime test; macOS redraw and upstream behavior
must still be observed separately.

## Documentation audit corrections

This guide preserves the detailed content moved out of the README during the
**2026-10-09** documentation audit. The [pre-audit README](https://github.com/Citizenyolo/TokenPace/blob/c58c3c5a962b52f2972056c307104ca46c57d821/README.md)
remains available in Git history. The following corrections are explicit so older
claims are not accidentally treated as current knowledge:

- **“Burn rate”** referred to linear pacing, not measured consumption over time.
- **“Xcode Command Line Tools”** was insufficient for app builds: full selected
  Xcode is required. See [installation requirements](installation.md#requirements).
- The blanket **paid Developer Account restriction** was not established.
  This repo's unsandboxed host/sandboxed extension and ad-hoc signing describe its
  local setup, not a universal Apple limitation.
- The claimed **host and widget Documents copies** did not match the current
  publisher: it writes only the widget container cache.
- The old five-step **manual install** omitted extension signing and LaunchAgent
  creation/bootstrap. It has been replaced by the complete script's documented
  [sequence](installation.md#installation-sequence), not silently retained as a working recipe.
- **“Completely local”** did not mean network-free: authenticated Agy quota reads
  can contact upstream services even though TokenPace has no HTTP client.

Historical release notes retain their original context; use this guide for current
behavior. In particular, older notes referred to SQLite observation, whereas the
current observer uses directory write notifications. The old description alone
does not establish which implementation was actually shipped at that time.
The v1.1.2 note about a modern Date parsing strategy does not describe the current
`QuotaPolicy.resetDate` implementation, which uses `ISO8601DateFormatter` with
fractional/nonfractional fallbacks. These historical descriptions are not evidence
of the current implementation.

Source entry points: [model/policy/store](../Sources/Shared/QuotaModel.swift),
[CLI fetcher](../Sources/TokenPace/QuotaFetcher.swift),
[coordinator](../Sources/TokenPace/QuotaRefreshCoordinator.swift),
[observer](../Sources/TokenPace/QuotaObserver.swift) and
[widget](../Sources/TokenPaceExtension/TokenPaceExtension.swift).
