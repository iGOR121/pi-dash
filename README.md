# pi-dash

A touchscreen dashboard for a Raspberry Pi (800×480 DSI display). The shell
renders a grid of widgets; every widget is a self-contained addon — a folder
you drop into `addons/`. Layout and settings live in `config/dashboard.json`.

## Features

- Fullscreen Qt/QML kiosk, runs on `eglfs` (no desktop session needed)
- Addon widgets loaded at runtime (clock, weather, demo switch/gauge, template)
- Touch layout editor: long-press → drag / resize / delete / add widgets
- Auto-generated settings sheets from each addon's manifest
- Boot lock screen with a wallpaper; the dashboard shows it blurred behind
  translucent widgets
- Idle auto-lock (default 5 min, adjustable/disableable in Settings)
- Settings page (in edit mode) with a wallpaper picker, fit modes (fill,
  align, stretch) and lock-screen / auto-lock options
- Three top-level pages: **notifications** (left), **widgets** (center) and
  **dashlets** (right)
- Multiple vertical **widget pages** inside the widgets tab, with a main page
  and an editor for their order
- In-app, DE-agnostic notifications with a badge and a notification page
- **Dashlets**: full-page apps bundled with widgets (Weather, Clock)
- Weather app: next-24-hours + 7-day forecast; clock app: world clocks,
  analog dials, multiple time zones
- AirPlay (UxPlay) dashlet: audio metadata in notifications, and mirrored
  video in a fullscreen cast with a close button
- Bluetooth dashlet for Raspberry Pi OS: scan/pair HID devices, A2DP audio
  sender + sink, and an A2DP codec picker (SBC/SBC-XQ/AAC/aptX/LDAC)
- Widget settings and app settings are the same shared values

## Pages & dashlets

Swipe horizontally, or tap the dots in the bottom bar:

| Page | Contents |
|---|---|
| Notifications (left) | In-app notifications, dismiss/clear, badge count |
| Widgets (center) | The widget grid |
| Dashlets (right) | Launcher for the installed dashlet apps |

The bottom bar shows the page name, the page dots (the bright dot is the
current page) and the active dashlets. When more than one dashlet is in use
it reads “N active dashlets”; tap it to expand the list and open one. The
lock screen shows the same summary above the unlock hint.

**Dashlets** are what we call the full-page apps: they only exist inside
pi-dash (not normal OS apps), share settings with their widgets, and are
listed on the right page. Tap a Weather or Clock widget to open its dashlet
directly, or use the launcher.

## Run on a desktop

```sh
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
./run.sh                 # 800×480 window
./run.sh --fullscreen    # kiosk preview
```

## Lock screen & wallpaper

- The dashboard **starts locked**: wallpaper sharp, large clock, date.
  Swipe up, tap, or press any key to unlock.
- Lock again with **Ctrl+L** on a desktop, or long-press a widget → **Lock**
  in the edit toolbar (touch).
- **Pick a wallpaper in the UI:** long-press a widget → **Settings** →
  choose a thumbnail from `assets/`, then **Fill**, **Align** (fit inside the
  screen) or **Stretch**. Changes apply live and are saved.
- Or just drop images into `assets/` (`.jpg`, `.jpeg`, `.png`, `.webp`,
  `.bmp`). The picker lists everything in that folder. Without a choice, an
  image named `assets/wallpaper.*` is used automatically.
- You can also set it by hand in `config/dashboard.json` (restart required):

  ```json
  "wallpaper": "assets/my-photo.jpg",   // or "auto" / ""
  "wallpaperMode": "fill",              // fill | align | stretch
  "autoLockSeconds": 300                // 0 = never auto-lock
  ```

  `"auto"` (default) uses `assets/wallpaper.*`; `""` means no wallpaper.
- On the dashboard the image is shown blurred, with translucent widget cards
  so it stays visible. No wallpaper → a built-in gradient.
- Prefer to boot straight to the widgets? Set `"lockScreen": false` (or use
  the toggle in **Settings**).
- **Auto-lock:** the dashboard locks after 5 minutes without any touch, click
  or key press. Change it in **Settings → Auto-lock after**
  (Off / 1m / 5m / 15m / 30m) or with `"autoLockSeconds": 300` in the config
  (`0` disables it). Any interaction restarts the countdown.

`assets/wallpaper.*` is treated as device-local: `deploy/rsync.sh` skips it,
so editing/deploying code won't delete the Pi's wallpaper. Copy it manually
if you set it on your laptop (`scp`).

## Widget pages

The widgets tab is itself a vertical stack of pages:

- Swipe **up/down** inside the widgets tab; the bottom bar shows
  `↑↓ <page> · n/N`, and the main page is selected at startup.
- **Edit mode → Pages** opens the page manager: reorder with ↑/↓, choose the
  **main** page, add a page **above/below the current one**, and delete empty
  pages. The edit bar also has `‹ / ›` page arrows and a page counter.
- **+ Add widget** places the new widget on the page currently shown.
- Pages share the grid dimensions; the same cell can be used on different
  pages, and moving/resizing only checks collisions on the same page.

The layout in `config/dashboard.json`:

```json
"widgetPages": [
  { "id": "up",   "name": "Page Up", "main": false },
  { "id": "main", "name": "Main",    "main": true  },
  { "id": "down", "name": "Page Down", "main": false }
],
"widgets": [
  { "id": "clock-main", "addon": "clock", "page": "main", "x": 0, "y": 0, "w": 3, "h": 2 }
]
```

Existing configs are migrated to a single `main` page automatically. The
main page opens at startup; with pages above and below it, it is the middle.

## Notifications

Notifications are **in-app and DE-agnostic**: there is no DBus / desktop
notification daemon involved. Addons call:

```qml
Host.notify("Weather", "Forecast updated")   // or notify(...) inside WidgetBase
```

They appear on the left page with a count badge on the notifications dot.
The weather widget posts one notification when updates start failing (and
does not repeat until it recovers). **Settings → Notifications** has “Send
test notification” and “Clear all”. Notifications are in-memory (they reset
on restart).

## Gestures

| Gesture | Result |
|---|---|
| Swipe up / tap on lock screen | Unlock |
| Swipe horizontally (widgets/notifications/dashlets) | Change top-level page |
| Swipe up/down in the widgets tab | Change widget page |
| Tap a page dot | Go to that page |
| Tap a clock/weather widget | Open its dashlet app |
| Tap “N active dashlets” | Expand the active-dashlet list |
| Long-press a widget | Enter edit mode |
| Edit toolbar → Pages | Reorder / main / add / delete widget pages |
| Edit toolbar → Settings | Wallpaper picker, fit mode, lock options |
| Drag a widget (edit mode) | Move, one cell at a time |
| Drag the bottom-right grip | Resize in whole cells |
| Sliders button / × / Done | Settings / remove / exit edit mode |
| Long-press the background | Enter edit mode on an empty dashboard |

## Addons

A widget is an addon folder:

```
addons/my-widget/
  manifest.json      # name, version, entry QML, sizes, settings schema
  MyWidget.qml       # root is a WidgetBase (import shell)
```

Copy `addons/hello/` to start, then add the widget through edit mode →
**+ Add widget**. Full reference: [`docs/addon-dev.md`](docs/addon-dev.md).

An addon can also ship a **dashlet** by adding `app: "MyApp.qml"` to its
manifest. Dashlet and widget settings are shared: editing the weather
location from either side updates both.

### Weather widget & app

The weather addon uses Open-Meteo (no API key). The widget shows the current
condition and description, feels-like/high/low, humidity, wind,
precipitation (when any), sunrise/sunset, plus the last and next update. The
**↻** button refreshes immediately and restarts the countdown; the interval
is a setting (default 30 min).

The **Weather** dashlet (right page, or tap the widget) adds the next
24 hours (hour, icon, temperature, rain chance) and a 7-day forecast with
min/max temperatures and rain chances.

### Clock widget & app

The **Clock** dashlet manages the widget's world clocks: tap cities to
add/remove them, toggle analog dials, 24-hour time, seconds and whether the
local clock is shown. The widget shows the local clock plus up to two world
clocks (`+N more` beyond that); the app lists all of them. Both use the same
settings, and time zones are DST-aware via the system `zoneinfo` database.

### AirPlay (UxPlay) dashlet

The **AirPlay** dashlet wraps [UxPlay](https://github.com/FDH2/UxPlay) —
an AirPlay mirror/audio receiver. It is the grey `▣` icon on the right page
(or add its status widget to the grid; tapping either opens the app).

Requirements (Raspberry Pi OS / Debian):

```sh
sudo apt install uxplay gstreamer1.0-tools gstreamer1.0-plugins-base \
     gstreamer1.0-plugins-good gstreamer1.0-plugins-bad gstreamer1.0-libav
```

`deploy/setup-pi.sh` installs the GStreamer pieces and tries `uxplay`.
UxPlay 1.72+ is needed for `-md` metadata and 1.73+ for `-vrtp` video; if
your distro package is older than that, build UxPlay from source.

- Open **Dashlets → AirPlay**, press **Start**, then connect from the
  iPhone/iPad/Mac (Control Center → Screen Mirroring / AirPlay → the name in
  the app, default `pi-dash`).
- **Audio mode:** title/artist/album are parsed from UxPlay's metadata file
  and posted to **Notifications**; the current track and cover art appear in
  the app and status widget.
- **Mirror mode:** UxPlay forwards the H.264 stream as local RTP; the app
  decodes it and opens a **fullscreen cast** automatically, with a grey **×**
  in the upper-right corner (always visible) that stops the receiver. Auto-lock
  pauses while video is playing.
- Settings (gear): UxPlay binary, server name, RTP port, extra `uxplay`
  arguments and **Auto-start at boot**. Audio is played by UxPlay on the Pi;
  video is decoded at 640×360 and scaled to the screen, so very high-bitrate
  4K/H.265 mirroring is not supported in the embedded view.
- If `uxplay` or `gst-launch-1.0` is missing, the app shows what to install;
  the rest of the dashboard is unaffected.
- For Bluetooth audio output with UxPlay, add `-as pipewiresink` to the
  AirPlay extra arguments (otherwise UxPlay may pick ALSA directly and
  bypass the Bluetooth headphones).

### Bluetooth dashlet

Works with Raspberry Pi OS's standard BlueZ + PipeWire/WirePlumber stack
(verified on Debian 13/Trixie, BlueZ 5.82, WirePlumber 0.5.8). Open
**Dashlets → Bluetooth**.

- **Adapter:** power, visibility (discoverable) and pairability, current
  adapter name/address, scan and refresh.
- **HID:** put a keyboard/mouse in pairing mode, **Scan**, then **Pair**.
  Already-paired devices have Connect/Disconnect/Forget. Trust is set on
  pairing so devices can reconnect automatically.
- **Audio sender (Pi → headphones/speaker):** pair/connect the device, then
  **Use output** (sets the PipeWire default sink). Both A2DP roles are
  enabled, so the Pi can also be used as a speaker:
- **Audio sink (phone → Pi):** press **Visible**, then pair with the Pi from
  the phone and play audio; it comes out of the Pi's default output.
  HFP/HSP are enabled for headsets.
- **Codec picker:** SBC (always), SBC-XQ, AAC, aptX, aptX HD, LDAC, Opus 05
  and FastStream, limited to the codecs present in the PipeWire build
  (on the tested Pi, AAC is not shipped and is shown dimmed).
  **Apply codecs** writes
  `~/.config/wireplumber/wireplumber.conf.d/51-pi-dash-bluez.conf`
  and restarts the user WirePlumber service; connected audio reconnects.
- **Adapter name:** set it in the app's Settings gear
  (`adapterName`, default `pi-dash`); an **Set name** button appears when
  the adapter alias differs.

Bluetooth audio depends on the user's PipeWire/WirePlumber session. For a
headless kiosk, the setup script enables lingering
(`loginctl enable-linger $USER`) so that session starts at boot. If changing
codecs reports that WirePlumber could not be restarted, log in once or
reboot.

## Deploy to the Pi

```sh
# one-time, on the Pi:
cd ~/pi-dash && ./deploy/setup-pi.sh

# from the dev machine:
./deploy/rsync.sh pi@raspberrypi.local
```

`rsync.sh` pushes the tree and restarts the `pi-dash` systemd service
(`QT_QPA_PLATFORM=eglfs`). The service and setup script adapt the paths and
user for the Pi account.

## Tests

```sh
.venv/bin/python tools/test_interactions.py   # synthetic touch smoke test
.venv/bin/python tools/screenshot.py          # unlocked dashboard → PNG
.venv/bin/python tools/screenshot.py --lock   # boot lock screen
.venv/bin/python tools/screenshot.py --edit   # edit chrome
.venv/bin/python tools/screenshot.py --settings clock-main
.venv/bin/python tools/screenshot.py --settings-page
.venv/bin/python tools/screenshot.py --page notifications --test-notifications
.venv/bin/python tools/screenshot.py --page dashlets
.venv/bin/python tools/screenshot.py --widget-page 1   # vertical widget page
.venv/bin/python tools/screenshot.py --pages-sheet     # page manager
.venv/bin/python tools/screenshot.py --app weather
.venv/bin/python tools/screenshot.py --app uxplay
.venv/bin/python tools/screenshot.py --uxplay-demo   # AirPlay app + fake track
.venv/bin/python tools/screenshot.py --cast          # fullscreen cast overlay
.venv/bin/python tools/screenshot.py --app bluetooth
.venv/bin/python tools/screenshot.py --bluetooth-demo
.venv/bin/python tools/screenshot.py --bluetooth-codecs
.venv/bin/python tools/screenshot.py --apps-popup
.venv/bin/python tools/screenshot.py --add
```

Screenshots run offscreen with the software renderer, so they work over SSH
and double as a QML compile check.
