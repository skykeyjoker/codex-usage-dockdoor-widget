#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$(mktemp -d)"
trap 'rm -rf "$BUILD"' EXIT
if [[ -n "${DOCKDOOR_WIDGETS_SOURCE:-}" ]]; then
    SDK="$DOCKDOOR_WIDGETS_SOURCE/Sources/DockDoorWidgetSDK"
else
    git clone --depth 1 https://github.com/ejbills/dockdoorpro-widgets.git "$BUILD/upstream"
    SDK="$BUILD/upstream/Sources/DockDoorWidgetSDK"
fi
ARCH="$(uname -m)"
swiftc -target "$ARCH-apple-macosx14.0" -module-name DockDoorWidgetSDK -emit-module -emit-library \
    -emit-module-path "$BUILD/DockDoorWidgetSDK.swiftmodule" -o "$BUILD/libDockDoorWidgetSDK.dylib" "$SDK"/*.swift
swiftc -target "$ARCH-apple-macosx14.0" -parse-as-library -D CODEX_USAGE_TESTING \
    -I "$BUILD" -L "$BUILD" -lDockDoorWidgetSDK -Xlinker -rpath -Xlinker "$BUILD" \
    "$ROOT"/CodexUsageMonitor/*.swift "$ROOT/tests/ClaudeUsageTests.swift" -o "$BUILD/claude-tests"
"$BUILD/claude-tests" "$@"
