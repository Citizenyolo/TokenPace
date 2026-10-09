#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
STAGING=$(mktemp -d "${TMPDIR:-/tmp}/tokenpace-quota-tests.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
swiftc Sources/Shared/QuotaModel.swift Sources/TokenPace/QuotaFetcher.swift \
    Sources/TokenPace/QuotaRefreshCoordinator.swift Tests/QuotaRegression.swift -o "$STAGING/quota-tests"
"$STAGING/quota-tests"
swiftc -typecheck Sources/Shared/QuotaModel.swift Sources/TokenPace/QuotaFetcher.swift \
    Sources/TokenPace/QuotaRefreshCoordinator.swift Sources/TokenPace/QuotaObserver.swift Sources/TokenPace/TokenPaceApp.swift
swiftc -typecheck Sources/Shared/QuotaModel.swift Sources/TokenPaceExtension/TokenPaceExtension.swift
