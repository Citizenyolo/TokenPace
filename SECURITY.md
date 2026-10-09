# Security Policy

## Supported Versions
Currently, only the latest `main` branch of TokenPace is supported with security updates.

## Reporting a Vulnerability
If you discover a security vulnerability within TokenPace, please open an Issue
marked as `Security` or contact the repository owner directly.
Do not include credentials or conversation data in public vulnerability reports.

## Data and execution boundaries

TokenPace has no direct HTTP client, but executes your authenticated Agy CLI for
quota retrieval; that CLI can contact upstream services. The host application is
unsandboxed and publishes quota into the sandboxed widget's container. Relevant
boundaries include the local CLI executable and authentication, installer/signing,
container access and cached quota data. TokenPace observes directory write events
without reading conversation content. See the
[data flow and storage guide](docs/architecture.md#data-flow-and-storage).
