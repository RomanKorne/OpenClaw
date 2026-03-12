#!/bin/bash
# Usage: ./run_browser.sh <task-id> <url>
set -euo pipefail
TASK_ID=${1:?}
URL=${2:?}
HOST=$(echo "$URL" | sed -E 's#https?://([^/]+).*#\1#')
WL_FILE="$(dirname "$0")/whitelist.txt"
if ! grep -Fxq "$HOST" "$WL_FILE"; then
  echo "Host $HOST not in whitelist. Aborting." >&2
  exit 2
fi
CONTAINER_NAME="agent-browser-$TASK_ID"
# Build image if needed
docker build -t agent-browser-sandbox $(dirname "$0") || true
# Run ephemeral container
docker run --rm --name "$CONTAINER_NAME" agent-browser-sandbox node index.js "$URL" > "$(pwd)/agent-browser-$TASK_ID.log" 2>&1 &
CID=$!
echo "Started container $CONTAINER_NAME (pid $CID). Logs: ./agent-browser-$TASK_ID.log"
# Wait for completion (simple wait)
wait $CID || echo "Container finished with non-zero exit"
echo "Run complete."
