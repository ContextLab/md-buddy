#!/bin/bash
# Remove MD Buddy and its Quick Look extension.
# Usage: scripts/uninstall.sh [--prefix /Applications]
set -euo pipefail
PREFIX="/Applications"
[[ "${1:-}" == "--prefix" ]] && PREFIX="$2"
DEST="$PREFIX/MD Buddy.app"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [[ ! -d "$DEST" ]]; then
  echo "MD Buddy is not installed at $DEST"
  exit 0
fi
[[ "$(defaults read "$DEST/Contents/Info.plist" CFBundleIdentifier 2>/dev/null)" == "org.contextlab.mdbuddy" ]] \
  || { echo "$DEST is not MD Buddy; refusing to remove it." >&2; exit 1; }

pluginkit -r "$DEST/Contents/PlugIns/MD Buddy Preview.appex" 2>/dev/null || true
"$LSREGISTER" -u "$DEST" 2>/dev/null || true
rm -rf "$DEST"
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true
echo "MD Buddy removed."
