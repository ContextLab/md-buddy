#!/bin/bash
# Build MD Buddy from source and install it as a Quick Look extension.
# Usage: scripts/install.sh [--prefix /Applications] [--no-build]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PREFIX="/Applications"
BUILD=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix) PREFIX="$2"; shift 2 ;;
    --no-build) BUILD=0; shift ;;
    -h|--help) sed -n '2,3p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done

APP_NAME="MD Buddy.app"
BUNDLE_ID="org.contextlab.mdbuddy"
EXT_ID="org.contextlab.mdbuddy.preview"
PRODUCT="$ROOT/build/DerivedData/Build/Products/Release/$APP_NAME"
DEST="$PREFIX/$APP_NAME"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

if [[ $BUILD -eq 1 ]]; then
  command -v xcodebuild >/dev/null || { echo "Xcode is required (xcode-select --install is not enough)." >&2; exit 1; }
  echo "==> Building (Release)…"
  LOG="$(mktemp -t mdbuddy-build)"
  if ! xcodebuild -project "$ROOT/MDBuddy.xcodeproj" -scheme MDBuddy -configuration Release \
       -derivedDataPath "$ROOT/build/DerivedData" build -quiet >"$LOG" 2>&1; then
    grep -E "error: " "$LOG" | grep -vE "DVTPlugIn|CoreSimulator|SimServiceContext" >&2 || tail -40 "$LOG" >&2
    echo "Build failed (full log: $LOG)" >&2
    exit 1
  fi
  rm -f "$LOG"
fi
[[ -d "$PRODUCT" ]] || { echo "Build product not found: $PRODUCT" >&2; exit 1; }

# Xcode's incremental builds can re-copy the Swift package's resource bundle after the
# extension was sealed, leaving a stale signature. Re-sign (ad hoc), inside out, every time.
APPEX="$PRODUCT/Contents/PlugIns/MD Buddy Preview.appex"
codesign --force --sign - --options runtime --timestamp=none \
  --entitlements "$ROOT/PreviewExtension/MDBuddyPreview.entitlements" "$APPEX"
codesign --force --sign - --options runtime --timestamp=none \
  --entitlements "$ROOT/App/MDBuddy.entitlements" "$PRODUCT"
codesign --verify --deep --strict "$PRODUCT"

if [[ -d "$DEST" ]]; then
  existing_id="$(defaults read "$DEST/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || true)"
  if [[ "$existing_id" != "$BUNDLE_ID" ]]; then
    echo "$DEST exists but is not MD Buddy ($existing_id); refusing to replace it." >&2
    exit 1
  fi
  echo "==> Replacing existing $DEST"
  pluginkit -r "$DEST/Contents/PlugIns/MD Buddy Preview.appex" 2>/dev/null || true
  rm -rf "$DEST"
fi

echo "==> Installing to $DEST"
mkdir -p "$PREFIX"
ditto "$PRODUCT" "$DEST"
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "==> Registering the Quick Look extension"
"$LSREGISTER" -f -R "$DEST"
pluginkit -a "$DEST/Contents/PlugIns/MD Buddy Preview.appex"
pluginkit -e use -i "$EXT_ID"
qlmanage -r >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

if pluginkit -m -i "$EXT_ID" | grep -q "$EXT_ID"; then
  echo "==> Done. Select a Markdown, code or text file in Finder and press Space."
else
  echo "!! The extension did not register. Open '$DEST' once, then check" >&2
  echo "   System Settings > General > Login Items & Extensions > Quick Look." >&2
  exit 1
fi
