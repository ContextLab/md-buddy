#!/bin/bash
# Capture one real Finder Quick Look panel: select FILE in Finder, press Space, save the panel.
# Needs: MD Buddy installed; Terminal allowed Screen Recording + Accessibility (System Events).
# Usage: scripts/qlcapture.sh FILE OUT.png [SCROLL_LINES]
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -ge 2 ]] || { sed -n '4p' "$0" >&2; exit 2; }
mkdir -p "$ROOT/build"
[[ -x "$ROOT/build/qlwindow" ]] || swiftc -O "$ROOT/scripts/qlwindow.swift" -o "$ROOT/build/qlwindow"
[[ -x "$ROOT/build/scroll" ]] || swiftc -O "$ROOT/scripts/scroll.swift" -o "$ROOT/build/scroll"

press_space() { osascript -e 'tell application "System Events" to keystroke space'; }

# capture FILE NAME [SCROLL_LINES]: select FILE in Finder, open Quick Look, capture the panel.
capture() {
  local file="$1" out="$2" lines="${3:-0}" before row=""
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
  screencapture -x -o -l "$id" "$out"
  press_space  # close the panel
  sleep 0.5
  echo "  $out"
}

capture "$@"
