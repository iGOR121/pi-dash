#!/usr/bin/env bash
# Push the project to the Pi and restart the dashboard service.
#
#     ./deploy/rsync.sh [user@host]      # default: pi@raspberrypi.local
#
set -euo pipefail
cd "$(dirname "$0")/.."

TARGET="${1:-pi@raspberrypi.local}"
REMOTE_DIR="pi-dash"

rsync -av --delete \
    --exclude .venv/ \
    --exclude __pycache__/ \
    --exclude .git/ \
    --exclude '*.pyc' \
    --exclude 'assets/wallpaper.*' \
    ./ "$TARGET:$REMOTE_DIR/"

ssh "$TARGET" \
    "sudo systemctl restart pi-dash 2>/dev/null \
     || echo 'service not installed yet — run ./deploy/setup-pi.sh on the Pi'"
