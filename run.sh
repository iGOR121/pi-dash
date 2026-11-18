#!/usr/bin/env bash
# Run pi-dash on your desktop in an 800x480 window (Fedora in this case).
# Add --fullscreen to preview kiosk mode.
set -euo pipefail
cd "$(dirname "$0")"
exec .venv/bin/python main.py "$@"
