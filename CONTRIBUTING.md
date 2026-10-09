# Contributing to TokenPace

Contributions are welcome! Please feel free to submit a Pull Request.

1. Fork the Project
2. Create your Feature Branch (`git checkout -b feature/AmazingFeature`)
3. Commit your Changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the Branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## Development Setup

TokenPace is a Swift macOS application with a WidgetKit extension. Development
requires macOS 14 or newer, Xcode and XcodeGen. See [README.md](README.md) for
installation requirements and runtime behavior.

### Repository layout

- `Sources/TokenPace`: background application, CLI quota reads and refresh coordination.
- `Sources/TokenPaceExtension`: widget views and timelines.
- `Sources/Shared`: quota model, validation, freshness policy and local file storage.
- `project.yml`: XcodeGen configuration for both targets; generate the Xcode project from this file.
- `Tests/QuotaRegression.swift`: isolated production-code regression checks.
- `docs/validation/issue-2.md`: installed runtime acceptance evidence and repeatable network test protocol.

### Build without installing

Run these commands from a clean source checkout:

```bash
xcodegen generate
xcodebuild -project TokenPace.xcodeproj -scheme TokenPace \
  -configuration Debug -derivedDataPath build/DerivedData \
  TOKENPACE_SOURCE_REVISION="$(git -c core.fsmonitor=false rev-parse --short=12 HEAD)" \
  build
```

This builds the app and extension without installing or launching them. The
project uses ad-hoc signing for local development. Keep target settings in
`project.yml`, rather than only editing the generated Xcode project.
The source revision is displayed in the widget footer after installation;
`install.sh` also marks modified build inputs with a `-dirty` suffix.

### Isolated checks

```bash
bash test_quota.sh
bash -n install.sh
bash test_install_staging.sh
git diff --check
```

- `test_quota.sh` requires macOS and Swift. It compiles production code against
  deterministic fixtures, an injected clock and temporary fake CLI executables,
  then typechecks the app and widget. It does not invoke the installed Agy CLI,
  access live quota files, install/restart the app or change connectivity.
- `test_install_staging.sh` extracts the installer's temporary staging logic and
  checks allocation, permissions, cleanup and failure handling against fixtures.
  It does not build, sign, install or restart TokenPace.

Choose checks relevant to your change and include results in the pull request.
macOS builds and WidgetKit runtime behavior cannot be validated on Linux;
shell-only checks do not establish application or widget correctness.

The same checks run automatically on a standard GitHub-hosted macOS 15 runner
for pull requests targeting `main` and pushes to `main`. See the
[workflow definition](.github/workflows/macos-ci.yml). Its permissions are
read-only; it does not need secrets, call the live Agy service, install the app
or change network connectivity. Results appear in the PR, but are not currently
a required merge check.

### Installation and runtime testing

`./install.sh` is an installation operation: it builds and signs the app,
replaces `~/Applications/TokenPace.app`, registers the widget and restarts the
background daemon. Use it when you intend to update the local installation,
rather than as an isolated test command.

The running application retrieves quota through the authenticated
`~/.local/bin/agy --output-format json -p /usage` command. Runtime tests can
therefore contact the upstream service through Agy. Keep credentials and
conversation content out of public logs, screenshots and pull requests.

For freshness or recovery changes, follow the
[installed offline/reconnection protocol](docs/validation/issue-2.md#repeatable-installed-test-protocol).
Check both Widget/Data revisions, snapshot age and actual recovered values;
allow for WidgetKit redraw scheduling. Record remaining limits instead of
treating a successful local read as proof of server-side freshness.
