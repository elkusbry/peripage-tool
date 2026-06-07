#!/bin/bash
# Wrapper for Automator Quick Action: print one or more image files to the Peripage.
# Usage: print_to_peripage.sh <file1> [file2 ...]
# Receives file paths as positional args (how Automator's "Run Shell Script" with
# "as arguments" passes selected Finder items).

set -u

REPO="/Users/bryanelkus/Repo/peripage-tool"
PYTHON="$REPO/venv/bin/python"
SCRIPT="$REPO/print_photo.py"
LOG="$HOME/Library/Logs/peripage-tool.log"

notify() {
    /usr/bin/osascript -e "display notification \"$1\" with title \"Peripage\""
}

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
}

if [ "$#" -eq 0 ]; then
    notify "No files selected"
    exit 1
fi

failures=0
for f in "$@"; do
    log "Printing: $f"
    notify "Printing $(basename "$f")…"
    if "$PYTHON" "$SCRIPT" "$f" >> "$LOG" 2>&1; then
        log "OK: $f"
    else
        log "FAILED: $f"
        notify "Failed: $(basename "$f") — see $LOG"
        failures=$((failures + 1))
    fi
done

if [ "$failures" -eq 0 ]; then
    notify "Done ($# printed)"
fi
exit "$failures"
