#!/bin/bash
# Capture real Quick Look panels (via qlmanage) for the README.
# Usage: scripts/screenshots.sh [OUTDIR]   (default docs/screenshots)
# Also renders light-mode variants off-screen with mdbuddy-render, so the system
# appearance never has to be changed.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/docs/screenshots}"
mkdir -p "$OUT" "$ROOT/build"

swiftc -O "$ROOT/scripts/qlwindow.swift" -o "$ROOT/build/qlwindow"
(cd "$ROOT/Core" && swift build -c release >/dev/null)
RENDER="$(cd "$ROOT/Core" && swift build -c release --show-bin-path)/mdbuddy-render"

capture_ql() {  # FILE NAME
  pkill -x qlmanage 2>/dev/null || true
  sleep 0.5
  qlmanage -p "$1" >/dev/null 2>&1 &
  local id=""
  for _ in $(seq 1 40); do
    sleep 0.25
    id="$("$ROOT/build/qlwindow" qlmanage | head -1 | cut -d' ' -f1)"
    [[ -n "$id" ]] && break
  done
  [[ -n "$id" ]] || { echo "no Quick Look window for $1" >&2; return 1; }
  sleep 2  # let WebKit paint
  screencapture -x -o -l "$id" "$OUT/$2.png"
  pkill -x qlmanage 2>/dev/null || true
  echo "  $OUT/$2.png"
}

echo "==> Quick Look panels (system appearance)"
capture_ql "$ROOT/examples/showcase.md" quicklook-markdown
capture_ql "$ROOT/examples/code/analysis.py" quicklook-python
capture_ql "$ROOT/examples/code/server.ts" quicklook-typescript
capture_ql "$ROOT/examples/code/notes.txt" quicklook-text

echo "==> Full-page renders"
for appearance in light dark; do
  "$RENDER" "$ROOT/examples/showcase.md" --png "$OUT/showcase-full-$appearance.png" --full --appearance "$appearance"
  echo "  $OUT/showcase-full-$appearance.png"
done
"$RENDER" "$ROOT/examples/code/analysis.py" --png "$OUT/code-light.png" --height 420 --appearance light
echo "  $OUT/code-light.png"
