#!/bin/bash
# Stop any running agent-browser containers quickly
set -euo pipefail
docker ps --filter "name=agent-browser-" --format '{{.Names}}' | xargs -r -n1 docker kill
