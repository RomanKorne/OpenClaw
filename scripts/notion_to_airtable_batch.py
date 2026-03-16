#!/usr/bin/env python3
"""Backward-compatible batch entrypoint."""
import os
import subprocess
import sys


def main():
    script = os.path.join(os.path.dirname(__file__), "notion_to_airtable.py")
    cmd = [sys.executable, script, "--batch-size", "10"]
    cmd.extend(sys.argv[1:])
    return subprocess.call(cmd)


if __name__ == "__main__":
    raise SystemExit(main())
