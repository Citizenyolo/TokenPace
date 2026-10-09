# Issue #2: quota freshness and recovery validation

**Status:** Accepted on 2026-10-09; [issue #2](https://github.com/Citizenyolo/TokenPace/issues/2) closed as completed.

**Installed code tested:** `c8691cbf4168709fad43be927decdb4da3761502`.
The widget footer reported matching Widget/Data revision `c8691cbf4168`.
Documentation commits following that revision do not change production code or build inputs.
Acceptance applies to this tested installation, not every upstream configuration. The fix is distributed in the v1.1.2 source release; no prebuilt or notarized app is included.

## Problem and resulting behavior

Previously, interrupted quota reads could leave old percentages looking current, and recovery was not reliably coordinated with polling, activity and reset triggers. The fix gives snapshots an explicit local read time, hides pacing when data is stale, rejects invalid reads and coordinates bounded retries and network recovery.

| Condition | Expected behavior |
| --- | --- |
| Successful complete CLI read | Store actual fractions and CLI reset timestamps, plus local `fetchedAt` and publishing build revision |
| Snapshot age reaches 300 seconds, or a reset expires | Label last known values as stale; hide pacing |
| No usable network path | Start no new CLI invocation; retained snapshot continues aging |
| Usable path returns | Request one fresh read without waiting for an old retry deadline |
| Fetch spans a path loss | Discard its result; wait for completion before starting a replacement |
| Invalid payload, nonzero exit, timeout or failed publication | Retain the last snapshot; retry after 10, 20, 40, 80, 160, then 300 seconds |
| Reset expires | Do not fabricate 100% availability; schedule a read at reset + 60 seconds |

All triggers share one coordinator. Successful publication schedules the next poll 240 seconds later. Directory activity is debounced by 3 seconds; activity and reset triggers cannot bypass failure backoff. CLI invocation has a 30-second deadline and a 1 MiB stdout limit. Only a complete, valid `SUCCESS` envelope for `usage` with zero process exit status is accepted. Publication uses atomic file writes before requesting a WidgetKit reload.

## Automated and build evidence

Validated during implementation:

- **86 isolated regression checks passed**, compiling production parsing, freshness, coordinator, subprocess and file-store code against fixtures, an injected clock and temporary fake CLI executables.
- **Daemon and widget typechecks passed.**
- **Installer staging check passed** against temporary fixtures.
- **Complete unsigned Debug Xcode build passed** before installation.
- **Git diff whitespace check passed.**

The regression checks cover age boundaries, expired/future/missing timestamps, malformed and partial payloads, atomic publication, single-flight coordination, poll/reset/activity/retry interactions, offline startup, path recovery, duplicate path notifications, late responses and shutdown. Temporary fake executables test successful reads, nonzero exits, oversized output and timeout behavior. These checks do not call the installed Agy CLI, alter live quota files, install/restart the app or change connectivity.

Reproduce isolated checks on macOS with Swift available:

```bash
bash test_quota.sh
bash test_install_staging.sh
git diff --check
```

## Preserved implementation evidence and lessons

The following details were recovered from local implementation records during the
2026-10-09 documentation audit. They supplement the acceptance report; they are
not new test runs.

### Scoped CLI cache probe (2026-10-07)

- Tested Agy CLI version: **1.3.1**; executable SHA-256:
  `88db8b4d21ece4999fa58e0b54cea77154e47b319ee178d086c446262317f3fa`.
- The sandbox restriction applied only to the spawned CLI, leaving the Mac's
  connectivity unchanged. Localhost was allowed because this CLI needs a local
  bind; outbound internet was denied.
- An initial probe denying *all* networking failed at the localhost bind. That
  result was **not** treated as cache evidence. The corrected probes returned an
  `ERROR` envelope with no quota before and after a successful online read.
- The online response had `SUCCESS`, the `usage` command and all four real bucket
  IDs. The warmed offline response failed during the eligibility/loadCodeAssist
  request. Both recorded calls reported zero model turns and zero generation/cache
  tokens; this is an observation from their usage counters, not a general pricing guarantee.
- The [sanitized evidence record](cli-cache-probe-2026-10-07.json) preserves the
  successful online and warmed-offline summaries without keys or conversation data.
  It does not contain a separate pre-online probe response; that observation is
  preserved in the implementation notes above. This is not a universal cache test.

### Layout regression and its measurement (2026-10-08)

The diagnostic footer initially occupied a row and pushed quota content outside
the desktop frame. The repair moved build identity into an overlay and kept stale
labels inside existing headings/reset rows. Vertical stack spacing changed from
20/10/4 to 12/8/3 points; the 14-point monospaced font was retained. WidgetKit's
automatic content margins were disabled while the view's own padding remained.

An `NSHostingView` geometry probe measured the quota view with a **344 × 344** frame,
using synthetic fractions 67%/100% for Gemini and 53%/100% for Claude/GPT, future
five-hour/weekly resets and a local fetch timestamp. Entries at read time and
600 seconds later exercised fresh and stale states. After layout, both reported
fitting size **328 × 338**, compared with a previous fitting height of **362**.
This was a geometry check without screenshots or live quota, not proof of an
installed WidgetKit render; the later user runtime acceptance supplied that
separate observation. Preserve both fresh and stale layout cases when revisiting
spacing or diagnostics.

### Build registration and signing pitfalls

During staging, Xcode registered the built app even with
`REGISTER_APP_WITH_LAUNCH_SERVICES=NO`. That flag was not sufficient to keep the
staging widget out of registration. Only the staging app's path was unregistered;
subsequent PluginKit/path checks confirmed the installed extension remained.
A build-only command avoids explicit installation/restart, but must not be assumed
to prevent all LaunchServices side effects. Distinguish staging and installed
paths before removing registrations.

The staged bundles were ad-hoc signed extension-first with the repository
entitlements and passed `codesign --verify --deep --strict`. Finder metadata added
to a copied bundle caused an initial signature check failure without changed
program/dylib hashes; removing extended attributes only from that staging/install
copy allowed signing/verification. The installed Widget/Data revision and program
identity were checked separately. These are historical validation steps, not a
claim that current CI builds or verifies a distributable app.

## Installed runtime acceptance

The user performed an offline/reconnection test on 2026-10-09, then compared live usage and pacing with CodexBar. Evidence came from user-supplied screenshots, file timestamps and reported observations; it was not an automated end-to-end test.

| Observation | Result |
| --- | --- |
| Widget/Data build identity | Both showed `c8691cbf4168` |
| Two offline file-time samples | Both remained at `18:31:25`, rather than being rewritten as fresh |
| Stale indication | Appeared about one minute after disconnection |
| File time after connectivity returned | Advanced to `18:46:02` |
| Widget recovery | Current values appeared within about 30 seconds of reconnection |
| Usage/pacing comparison | User reported PASS, then confirmed all displayed values were synchronized with CodexBar |

Times above are local Europe/Budapest on 2026-10-09. Staleness is measured from the last successful read, **not** the moment of disconnection: an already-aged snapshot can become stale less than five minutes after going offline. Recovery timing also depends on CLI completion and WidgetKit redraw scheduling.

The user explicitly accepted closing the issue as successfully resolved after these observations.

## Repeatable installed test protocol

Run this separately from the isolated tests; it deliberately changes connectivity. Save other network-dependent work first.

1. Confirm the visible footer's Widget/Data revisions match the installed source revision. A matching app on disk alone cannot identify an old visible WidgetKit snapshot.
2. With connectivity available, wait for a successful publication. Record the time, displayed fractions/reset values and the cache's `fetchedAt`; file modification time is supporting evidence, not the freshness clock.
3. Disconnect all usable network paths. Record the disconnection time without manually editing the cache or restarting the daemon.
4. Check that the last known values become stale no later than the local read age reaches 300 seconds, allowing for WidgetKit redraw delay. Pacing must disappear; a reset must not invent fresh 100% quota.
5. While offline, confirm the quota file is not continually rewritten as fresh. Wait at least 300 seconds from the recorded successful read for a complete age-boundary test.
6. Restore connectivity. Record when `fetchedAt`/file time advance and when the visible widget recovers. Verify actual reported values return and no overlapping or repeated immediate reads occur.
7. Perform ordinary usage, then compare TokenPace and the control app after each has refreshed. Compare values from aligned observations; independently timed snapshots can differ temporarily.

Inspect the widget cache modification time without editing it:

```bash
stat -f '%Sm' -t '%Y-%m-%d %H:%M:%S' \
  "$HOME/Library/Containers/io.github.citizenyolo.TokenPaceExtension/Data/Documents/quota.json"
```

`fetchedAt` in the JSON uses the default Swift Codable date representation (seconds since 2001-01-01 UTC). It records completion of a valid local CLI read, not a server observation time. Do not treat the file modification time as an independent upstream freshness guarantee.

## Reset countdown observations

During acceptance, the five-hour countdown initially showed `4h 57m`, then later `4h 59m`, despite elapsed wall-clock time and full reported availability. Weekly countdowns decreased normally. Inspection of a successful local snapshot showed both five-hour reset timestamps about five hours after its `fetchedAt`; TokenPace copies these `reset_time` values directly from Agy.

The widget counts down against the stored deadline between reads. When a new CLI response supplies a later deadline, the countdown can increase. This explains how a local countdown can fall and then return toward five hours; it does **not** prove the backend's exact rolling/reset policy. CodexBar also showed approximately five hours, and the user ultimately confirmed synchronization.

TokenPace's pacing is the rounded percentage-point difference between actual remaining quota and an ideal linear allowance over the reported cycle. It is not a measured tokens-per-minute rate. A moved reset deadline can change that comparison even without consumption.

## Remaining limits

- **Upstream cache:** A successful local CLI read does not prove the server data was freshly observed. On 2026-10-07, an isolated Agy CLI 1.3.1 probe returned an `ERROR` envelope with no quota when outbound internet was denied while localhost remained available, both before and after an online read. This supports that tested scenario only; it does not establish all cache/backend behavior or future CLI versions. The CLI version used for the later runtime acceptance was not independently reverified.
- **Network reachability:** A usable macOS path does not guarantee the service is reachable. Service failures still use retry backoff.
- **WidgetKit scheduling:** The timeline includes exact stale/reset boundaries, but macOS controls redraw timing and may defer updates.
- **Reset semantics:** New upstream timestamps may move the five-hour deadline forward. No fixed idle countdown or backend window policy was established by this test.
- **Scope:** Acceptance covers the installed build and observed offline/recovery/usage scenario. No new release artifact, notarization or universal platform guarantee is implied.

## References

- [Issue #2 and runtime acceptance](https://github.com/Citizenyolo/TokenPace/issues/2)
- [Refresh behavior and build identity](../architecture.md#refresh-behavior)
- [Changelog](../../CHANGELOG.md)
