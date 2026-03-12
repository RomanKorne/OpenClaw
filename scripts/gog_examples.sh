#!/bin/bash
# Examples wrapper for gog commands (server-side)
set -euo pipefail
export GOG_KEYRING_PASSWORD=${GOG_KEYRING_PASSWORD:-paperclip}

case "$1" in
  gmail-search)
    shift
    gog gmail search "$@" --no-input --json
    ;;
  calendar-events)
    shift
    gog calendar events primary --from "$(date -I -d 'now -7 days')" --to "$(date -I)" --max 10 --json
    ;;
  drive-search)
    shift
    gog drive search "$@" --max 10 --json
    ;;
  *)
    echo "Usage: $0 {gmail-search|calendar-events|drive-search} [args]"
    exit 2
    ;;
esac
