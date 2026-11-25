#!/bin/bash
# Capture README screenshots from real Finder Quick Look panels (select file, press Space),
# plus light/dark full-page renders made off-screen by mdbuddy-render.
# Needs: MD Buddy installed; Terminal allowed Screen Recording + Accessibility (System Events).
# Usage: scripts/screenshots.sh [OUTDIR]   (default docs/screenshots)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/docs/screenshots}"
mkdir -p "$OUT" "$ROOT/build"

(cd "$ROOT/Core" && swift build -c release >/dev/null)
RENDER="$(cd "$ROOT/Core" && swift build -c release --show-bin-path)/mdbuddy-render"

# capture FILE NAME [SCROLL_LINES]: a real Finder Quick Look panel, via scripts/qlcapture.sh.
capture() {
  "$ROOT/scripts/qlcapture.sh" "$1" "$OUT/$2.png" "${3:-0}"
}

echo "==> Finder Quick Look panels (current system appearance)"
capture "$ROOT/examples/showcase.md" quicklook-markdown
capture "$ROOT/examples/showcase.md" quicklook-markdown-code -24
capture "$ROOT/examples/showcase.md" quicklook-markdown-media -44
capture "$ROOT/examples/code/analysis.py" quicklook-python

echo "==> Off-screen renders"
for appearance in light dark; do
  "$RENDER" "$ROOT/examples/showcase.md" --png "$OUT/showcase-$appearance.png" --height 1000 --appearance "$appearance"
  echo "  $OUT/showcase-$appearance.png"
done
"$RENDER" "$ROOT/examples/code/analysis.py" --png "$OUT/code-light.png" --height 420 --appearance light
echo "  $OUT/code-light.png"
