#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ARCHIVE="${1:-$ROOT_DIR/dist/CodexUsageMonitor.bundle.zip}"
WIDGETS_DIR="$HOME/Library/Application Support/DockDoorPro/Widgets"
TARGET="$WIDGETS_DIR/CodexUsageMonitor.bundle"
EXPAND_ROOT="$(mktemp -d)"
PREFERENCES_DOMAIN="com.ejbills.DockDoorPro"
WIDGET_ID="codex-usage-monitor"
MAX_SLOT_SPAN=3

cleanup() {
    rm -rf "$EXPAND_ROOT"
}
trap cleanup EXIT

[[ -f "$ARCHIVE" ]] || { echo "Bundle archive not found: $ARCHIVE" >&2; exit 1; }
ditto -x -k "$ARCHIVE" "$EXPAND_ROOT"
SOURCE="$EXPAND_ROOT/CodexUsageMonitor.bundle"
[[ -f "$SOURCE/Contents/Info.plist" ]] || { echo "Archive does not contain CodexUsageMonitor.bundle." >&2; exit 1; }
[[ -f "$SOURCE/Contents/MacOS/CodexUsageMonitor" ]] || { echo "Bundle executable is missing." >&2; exit 1; }

mkdir -p "$WIDGETS_DIR"
if [[ -e "$TARGET" ]]; then
    BACKUP="$WIDGETS_DIR/CodexUsageMonitor.bundle.backup-$(date +%Y%m%d-%H%M%S)"
    mv "$TARGET" "$BACKUP"
    echo "Previous bundle backed up to: $BACKUP"
fi

ditto "$SOURCE" "$TARGET"
if defaults read "$PREFERENCES_DOMAIN" marketplaceWidgetMaxSlotSpans >/dev/null 2>&1; then
    defaults write "$PREFERENCES_DOMAIN" marketplaceWidgetMaxSlotSpans \
        -dict-add "$WIDGET_ID" -int "$MAX_SLOT_SPAN"
else
    defaults write "$PREFERENCES_DOMAIN" marketplaceWidgetMaxSlotSpans \
        -dict "$WIDGET_ID" -int "$MAX_SLOT_SPAN"
fi
echo "Installed: $TARGET"
echo "Registered slot support: $WIDGET_ID supports up to $MAX_SLOT_SPAN slots"
echo "Quit and reopen DockDoor Pro, then add Codex Usage from the Installed widgets list."
