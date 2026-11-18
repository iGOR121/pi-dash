#!/usr/bin/env bash
# One-time setup. Run ON THE PI, from the synced project directory:
#
#     cd ~/pi-dash && ./deploy/setup-pi.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

echo "== pi-dash setup =="

sudo apt-get update -y
sudo apt-get install -y \
    python3-venv \
    libegl1 libgl1 libglib2.0-0 libdbus-1-3 libxkbcommon0 \
    fontconfig fonts-dejavu-core \
    gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good \
    gstreamer1.0-plugins-bad gstreamer1.0-libav \
    bluez pipewire-bin wireplumber libspa-0.2-bluetooth

# AirPlay dashlet (optional). If the repos don't carry uxplay, the app will
# explain how to install it; the dashboard still works without it.
sudo apt-get install -y uxplay 2>/dev/null \
    || echo "note: uxplay not in the configured repos — install it manually for AirPlay."

if [ ! -d .venv ]; then
    echo "== creating venv =="
    python3 -m venv .venv
fi
.venv/bin/pip install --upgrade pip

# Pick a PySide6 build matching this system's glibc:
#   glibc >= 2.39 (Trixie or newer)   -> latest wheels
#   glibc >= 2.31 (Bullseye/Bookworm) -> 6.7.x wheels (manylinux_2_31)
glibc="$(ldd --version | head -n1 | awk '{print $NF}')"
pin=""
if printf '%s\n' "2.39" "$glibc" | sort -C -V; then
    echo "== glibc $glibc >= 2.39 -> installing latest PySide6 =="
else
    echo "== glibc $glibc < 2.39 -> pinning PySide6-Essentials 6.7.3 =="
    pin="==6.7.3"
fi
.venv/bin/pip install "PySide6-Essentials${pin}"

echo "== permissions (touchscreen / GPU / audio) =="
sudo usermod -aG video,render,input,audio "$USER" || true
sudo systemctl enable --now bluetooth || true
# Keep the user's PipeWire/WirePlumber alive after boot even without a
# graphical login: needed for Bluetooth audio and codec changes.
sudo loginctl enable-linger "$USER" || true

echo "== systemd service =="
sed "s|/home/pi|$HOME|g; s|^User=pi$|User=$USER|" \
    deploy/pi-dash.service > /tmp/pi-dash.service
sudo cp /tmp/pi-dash.service /etc/systemd/system/pi-dash.service
sudo systemctl daemon-reload
sudo systemctl enable pi-dash

cat <<'EOF'

Done. Start it:

    sudo systemctl start pi-dash        # dashboard takes over the screen
    journalctl -u pi-dash -f            # logs

Notes:
- If a desktop session is running, it owns the GPU; prefer Pi OS Lite or
  disable the session: sudo systemctl disable lightdm
- To stop the kiosk: sudo systemctl stop pi-dash
- AirPlay: open Dashlets → AirPlay and press Start (or enable Auto-start).
  UxPlay 1.73+ is needed for embedded video (-vrtp).

EOF
