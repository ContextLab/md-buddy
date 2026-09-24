#!/bin/bash
# Re-sign a built MD Buddy.app ad hoc, inside out, and verify it.
# Xcode's incremental builds can re-copy the Swift package's resource bundle after the
# extension was sealed, leaving a stale signature, so install and dist both sign here.
# Usage: scripts/sign.sh "path/to/MD Buddy.app"
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?usage: scripts/sign.sh path/to/MD\ Buddy.app}"
APPEX="$APP/Contents/PlugIns/MD Buddy Preview.appex"
codesign --force --sign - --options runtime --timestamp=none \
  --entitlements "$ROOT/PreviewExtension/MDBuddyPreview.entitlements" "$APPEX"
codesign --force --sign - --options runtime --timestamp=none \
  --entitlements "$ROOT/App/MDBuddy.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
