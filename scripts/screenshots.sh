#!/bin/bash
# Capture README screenshots from real Finder Quick Look panels (select file, press Space),
# plus light/dark full-page renders made off-screen by mdbuddy-render.
# Needs: MD Buddy installed; Terminal allowed Screen Recording + Accessibility (System Events).
# Usage: scripts/screenshots.sh [OUTDIR]   (default docs/screenshots)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${1:-$ROOT/docs/screenshots}"
mkdir -p "$OUT" "$ROOT/build"

swiftc -O "$ROOT/scripts/qlwindow.swift" -o "$ROOT/build/qlwindow"
swiftc -O "$ROOT/scripts/scroll.swift" -o "$ROOT/build/scroll"
(cd "$ROOT/Core" && swift build -c release >/dev/null)
RENDER="$(cd "$ROOT/Core" && swift build -c release --show-bin-path)/mdbuddy-render"

press_space() { osascript -e 'tell application "System Events" to keystroke space'; }

# capture FILE NAME [SCROLL_LINES]: select FILE in Finder, open Quick Look, capture the panel.
capture() {
  local file="$1" name="$2" lines="${3:-0}" before row=""
  osascript -e "tell application \"Finder\"
      activate
      set f to POSIX file \"$file\" as alias
      reveal f
      select f
    end tell" >/dev/null
  sleep 0.8
  # The panel's title isn't visible to CoreGraphics, so find it as the window Space adds.
  before="$("$ROOT/build/qlwindow" Finder | cut -d' ' -f1)"
  press_space
  for _ in $(seq 1 40); do
    sleep 0.25
    row="$("$ROOT/build/qlwindow" Finder | grep -vwF "$before" | head -1 || true)"
    [[ -n "$row" ]] && break
  done
  [[ -n "$row" ]] || { echo "no Quick Look panel for $file" >&2; return 1; }
  read -r id x y w h <<< "$row"
  sleep 1.5
  if [[ "$lines" != 0 ]]; then
    "$ROOT/build/scroll" $((x + w / 2)) $((y + h / 2)) "$lines"
    sleep 0.8
  fi
  screencapture -x -o -l "$id" "$OUT/$name.png"
  press_space  # close the panel
  sleep 0.5
  echo "  $OUT/$name.png"
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
