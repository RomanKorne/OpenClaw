#!/bin/bash
# Minimal healthcheck script (read-only checks)
set -euo pipefail
echo "OS: $(uname -a)"
if [ -f /etc/os-release ]; then . /etc/os-release && echo "Distro: $NAME $VERSION"; fi
if command -v openclaw >/dev/null 2>&1; then echo "openclaw status:"; openclaw status || true; else echo "openclaw CLI not found"; fi
if command -v ufw >/dev/null 2>&1; then echo "ufw:"; ufw status || true; fi
if command -v ss >/dev/null 2>&1; then echo "listening ports:"; ss -ltnp || true; fi
