#!/bin/bash
# Claude Code Mascot - double-click to launch (dev mode, runs the source directly)

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v swift >/dev/null 2>&1; then
  # Detach so closing this Terminal window doesn't kill the mascot.
  # Quit it via: the ✻ menu bar item -> Quit Mascot, or hover Clawd
  # and click the ✕ above its head. (Menu-bar app: no Dock icon.)
  nohup swift "$DIR/MascotApp.swift" >/dev/null 2>&1 &
  disown
  exit 0
fi

# Fallback: open the HTML in the default browser with caffeinate
echo "swift not found - falling back to browser + caffeinate."
echo "Press Cmd+Ctrl+F to go fullscreen, Cmd+W to exit."
caffeinate -d -i &
CAFF=$!
trap "kill $CAFF 2>/dev/null" EXIT INT TERM
open "$DIR/mascot.html"
echo "Press Enter here when you're done to re-enable display sleep..."
read -r
