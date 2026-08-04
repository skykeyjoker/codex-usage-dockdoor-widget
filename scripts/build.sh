#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UPSTREAM_REPOSITORY="${DOCKDOOR_WIDGETS_REPOSITORY:-https://github.com/ejbills/dockdoorpro-widgets.git}"
BUILD_ROOT="$(mktemp -d)"

cleanup() {
    rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

command -v git >/dev/null || { echo "git is required." >&2; exit 1; }
command -v swiftc >/dev/null || { echo "swiftc is required. Install Xcode Command Line Tools." >&2; exit 1; }
command -v lipo >/dev/null || { echo "lipo is required. Install Xcode Command Line Tools." >&2; exit 1; }

echo "Cloning DockDoor Pro widget build infrastructure..."
git clone --depth 1 "$UPSTREAM_REPOSITORY" "$BUILD_ROOT/dockdoorpro-widgets"

TARGET="$BUILD_ROOT/dockdoorpro-widgets/Widgets/CodexUsageMonitor"
mkdir -p "$TARGET"
cp -R "$ROOT_DIR/CodexUsageMonitor/." "$TARGET/"

echo "Building CodexUsageMonitor for arm64 and x86_64..."
bash "$BUILD_ROOT/dockdoorpro-widgets/scripts/build-widgets.sh" "$TARGET"

SOURCE_ARCHIVE="$BUILD_ROOT/dockdoorpro-widgets/build/CodexUsageMonitor.bundle.zip"
SOURCE_BINARY="$BUILD_ROOT/dockdoorpro-widgets/build/CodexUsageMonitor.bundle/Contents/MacOS/CodexUsageMonitor"
ARCHS="$(lipo -archs "$SOURCE_BINARY")"
[[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]] || {
    echo "Expected a universal arm64/x86_64 binary, got: $ARCHS" >&2
    exit 1
}

mkdir -p "$ROOT_DIR/dist"
cp "$SOURCE_ARCHIVE" "$ROOT_DIR/dist/CodexUsageMonitor.bundle.zip"

echo "Built: $ROOT_DIR/dist/CodexUsageMonitor.bundle.zip"
echo "Architectures: $ARCHS"
shasum -a 256 "$ROOT_DIR/dist/CodexUsageMonitor.bundle.zip"
