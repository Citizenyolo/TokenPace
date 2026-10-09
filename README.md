# TokenPace

TokenPace is a native macOS widget for Google Antigravity (Agy) quota. It shows
remaining five-hour and weekly allowances for **Gemini** and **Claude/GPT**, plus
whether your usage is ahead of or behind an even allowance over each cycle.
The background app has no Dock or menu bar icon.

TokenPace is an independent open-source project, not affiliated with, endorsed
by or sponsored by Google. Google, Antigravity and Agy are trademarks of their
respective owners.

![TokenPace Widget Preview](Preview.png)

## Install

Requirements: **macOS 14 (Sonoma) or newer**, full **Xcode** installed and selected
for command-line builds, [XcodeGen](https://github.com/yonaskolb/XcodeGen)
(`brew install xcodegen`), and an authenticated Agy CLI at `~/.local/bin/agy`.
The project supports Apple Silicon and Intel Macs.

```bash
git clone https://github.com/Citizenyolo/TokenPace.git
cd TokenPace
./install.sh
```

This builds and ad-hoc signs the app and extension, installs to
`~/Applications/TokenPace.app`, registers the widget and starts a login daemon.
It replaces an existing TokenPace installation and restarts its processes.
Then add **TokenPace** from the macOS desktop or Notification Center widget gallery.
The commands above use current `main`; [v1.1.2](https://github.com/Citizenyolo/TokenPace/releases/tag/v1.1.2)
is also available as source. No prebuilt or notarized app is included.

See the [installation guide](docs/installation.md) for Xcode setup, installation
steps, troubleshooting and uninstall commands. To build without installing,
see [Contributing](CONTRIBUTING.md#build-without-installing).

## Read the widget

- **Remaining quota** and **Resets in** come from Agy's reported fractions and deadlines.
- **Pacing** compares remaining quota with an even allowance over the cycle:
  green above +2 percentage points, blue within ±2, red below −2, after rounding.
  It is not a measured tokens-per-minute burn rate or a time-left prediction.
- **Data stale** means the last successful local read is at least five minutes old
  or a reported reset has expired. Last known percentages remain visible; pacing
  is hidden. Missing or invalid data shows an unavailable message.
- Reads normally occur four minutes after a successful publication, with additional
  startup, activity, reset and connectivity-recovery triggers. Failed reads use
  bounded retries; a reset never fabricates fresh 100% quota.

macOS controls WidgetKit redraw timing, so countdowns and stale/recovery changes
can appear late. A new Agy response can move a reset deadline forward, even
without usage. Local read age does not prove server-side freshness, and changes
to Agy's JSON format can break parsing. See [technical details and limits](docs/architecture.md).

## Privacy

TokenPace watches conversation-directory write notifications **without reading
conversation content**. It stores quota data locally and delegates network quota
retrieval to your authenticated Agy CLI; TokenPace itself has no HTTP client.
See [data flow and storage](docs/architecture.md#data-flow-and-storage)
and the [security policy](SECURITY.md).

## Documentation and validation

| Guide | Contents |
| --- | --- |
| [Installation](docs/installation.md) | Setup, signing/registration, login daemon, troubleshooting and uninstall |
| [Architecture](docs/architecture.md) | Data contract, pacing formula, refresh rules, design rationale, build identity and limits |
| [Contributing](CONTRIBUTING.md) | Source layout, build-only workflow, isolated tests and GitHub Actions macOS CI |
| [Issue #2 validation](docs/validation/issue-2.md) | Dated evidence, tested revision, offline/reconnection protocol and unresolved upstream questions |
| [Changelog](CHANGELOG.md) | Release history |

[Issue #2](https://github.com/Citizenyolo/TokenPace/issues/2) was accepted and closed
on **2026-10-09** for installed build `c8691cbf4168`: offline/reconnection and
usage/pacing comparison with CodexBar passed. The implementation was also checked
with 86 isolated regression checks, daemon/widget typechecks and an installer
staging check. These checks run in [macOS CI](.github/workflows/macos-ci.yml);
CI does not test the installed widget or call the live Agy service.

## License

[MIT](LICENSE).
