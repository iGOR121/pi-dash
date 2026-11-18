# Writing a pi-dash addon

A widget **is** an addon: a folder under `addons/` containing a
`manifest.json` and one QML file. The shell discovers the folder at startup,
loads the QML once per instance and injects the `WidgetBase` API. No Python,
no build step, no registration — drop a folder in and it appears.

The fastest start is to copy the reference addon:

```sh
cp -r addons/hello addons/my-widget
```

Then edit `addons/my-widget/manifest.json` and `HelloWidget.qml`, restart the
dashboard, and add the widget through edit mode (long-press any widget →
**+ Add widget**).

---

## Folder layout

```
addons/
  my-widget/
    manifest.json      # metadata + settings schema (required)
    MyWidget.qml       # entry QML, root must be a WidgetBase (required)
    MyApp.qml          # optional full-page dashlet (see below)
    ...                # any extra assets the QML references
```

Rules:

- The **folder name is the addon id**. `manifest.json`'s `id` is informational
  only (a mismatch logs a warning).
- Folders starting with `.` or `_` are ignored — use `_notes/` for scratch
  files you don't want loaded.
- Addons are rescanned at startup; restart the dashboard after installing or
  editing a manifest. Editing an addon's QML also needs a restart (a layout
  change reloads instances but does not rescan folders).
- The entry file must compile standalone with `import shell` available. The
  shell adds the project root to QML's import path before loading widgets.

---

## manifest.json

```json
{
  "id": "my-widget",
  "name": "My Widget",
  "version": "0.1.0",
  "author": "you",
  "entry": "MyWidget.qml",
  "minSize": { "w": 1, "h": 1 },
  "defaultSize": { "w": 2, "h": 2 },
  "settings": [
    { "key": "label", "label": "Label", "type": "string", "default": "Hi" }
  ]
}
```

| Field         | Required | Meaning                                                        |
|---------------|----------|----------------------------------------------------------------|
| `name`        | no       | Display name (defaults to the folder name).                    |
| `version`     | no       | Free-form string shown in the add-widget picker.               |
| `author`      | no       | Free-form string, currently informational.                     |
| `entry`       | **yes**  | QML file to load, relative to the addon folder.                |
| `minSize`     | no       | Smallest allowed `{ "w", "h" }` in grid cells (default 1×1).   |
| `defaultSize` | no       | Size used by **+ Add widget** (default 2×2).                   |
| `settings`    | no       | List of setting specs, see below.                              |
| `app`         | no       | QML file for an optional full-page **dashlet** app.            |
| `appIcon`     | no       | Glyph shown in the dashlet launcher (e.g. `"☁"`).              |
| `appDescription` | no    | One-line description shown in the launcher.                    |

### Settings schema

Every entry declares one setting. The shell uses this schema to build the
settings sheet automatically (sliders button in edit mode / gear in an app) —
you never write a settings UI yourself.

If the addon also ships a dashlet (`"app"`), these settings are **shared**:
they are stored once under `"apps": { "<id>": { ... } }` in
`config/dashboard.json` and used by every widget instance and the app page.

| `type`   | Control            | Notes                                    |
|----------|--------------------|------------------------------------------|
| `string` | text field         | On the Pi, text input needs an on-screen keyboard (see tips). |
| `bool`   | toggle switch      |                                          |
| `int`    | − / + stepper      | Whole numbers.                           |
| `real`   | − / + stepper      | One decimal place.                       |

Unknown types fall back to `string` with a warning in the log.

Without a dashlet, overrides are stored per instance under `"settings"` in
`config/dashboard.json`; with a dashlet they are stored once under
`"apps": { "<id>": ... }` and shared by every instance and the app.
Manifest defaults fill in anything missing.

---

## The WidgetBase API

An addon's root item must be a `WidgetBase`:

```qml
import QtQuick
import shell

WidgetBase {
    id: root
    // ...
}
```

Injected properties:

| Property     | Type     | Meaning                                              |
|--------------|----------|------------------------------------------------------|
| `instanceId` | string   | Unique id of this widget instance (`clock-main`, …). |
| `addon`      | string   | The addon id (folder name).                          |
| `settings`   | var      | Merged manifest defaults + saved overrides.          |

Injected functions:

```qml
// Read a setting with a fallback (null-safe).
property string label: setting("label", "Hello")

// Persist a setting for THIS instance. Host saves dashboard.json
// (debounced, atomic) and updates this instance's `settings` live.
function toggle() {
    root.on = !root.on
    setSetting("state", root.on)
}

// Post an in-app (DE-agnostic) notification.
notify("Weather", "Update failed")
```

For a dashlet-backed addon, `setSetting()` writes the shared app settings and
all instances update. `setting()` used in a property initializer stays in sync
when the values change: the shell assigns a fresh `settings` object and the
binding re-evaluates. No reload, no restart.

### Live example

```qml
import QtQuick
import shell

WidgetBase {
    id: root

    property bool on: setting("state", false)
    property string label: setting("label", "Lamp")

    function toggle() {
        root.on = !root.on
        setSetting("state", root.on)
    }

    Column {
        anchors.centerIn: parent
        spacing: 10

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            color: Theme.textPrimary
            font.pixelSize: 18
            font.weight: Font.DemiBold
        }

        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 80
            height: 40
            radius: 20
            color: root.on ? Theme.accent : Theme.track

            TapHandler { onTapped: root.toggle() }
        }
    }
}
```

The widget's size is controlled by the grid — never hard-code `width`/`height`
on the root. Everything inside should lay out relative to `parent`, because
instances can be resized to any w×h allowed by `minSize`.

---

## Dashlets (full-page apps)

A dashlet is an optional full-screen app shipped with an addon. It appears on
the right page (**Dashlets**) and shares the widget's settings.

```json
"app": "MyApp.qml",
"appIcon": "◷",
"appDescription": "World clocks and time zones"
```

The app root is a `DashletBase`:

```qml
import QtQuick
import shell

DashletBase {
    id: root

    property string label: setting("label", "Hi")   // shared with the widget

    function rename() {
        setSetting("label", "Hello")
    }
}
```

| Property   | Meaning                                                    |
|------------|------------------------------------------------------------|
| `addon`    | Addon id.                                                  |
| `settings` | Shared app settings (the same map the widgets see).        |
| `glass`    | True when a wallpaper is set; use `Theme.surfaceGlass`.    |

Functions: `setting(key, fallback)`, `setSetting(key, value)` (writes the
shared store, so every widget instance updates too) and
`notify(title, text)`.

The shell gives the app a header with a back button, the app name and a
Settings gear (editing the same schema), and your app fills the area below
it. Put long content in a `Flickable`; the area is about 800×390 on the Pi.
A plain tap on a dashlet-backed widget opens its app, so avoid assigning an
important single-tap action to such a widget.

---

## Theme tokens

`import shell` also gives you the `Theme` singleton, so third-party widgets
match the rest of the dashboard.

| Group    | Tokens                                                        |
|----------|---------------------------------------------------------------|
| Colors   | `bg`, `surface`, `surfaceBorder`, `textPrimary`, `textMuted`, `accent`, `good`, `warn`, `bad`, `track` |
| Metrics  | `radius` (14), `gap` (8), `padding` (10)                      |

Use `Theme.textPrimary` / `Theme.textMuted` for text, `Theme.accent` for the
"on"/highlight state, `Theme.track` for inactive tracks.

---

## Input & gestures

- Touch/click events go straight to the addon: use `TapHandler` (or
  `DragHandler`, `WheelHandler`, …) inside your widget.
- The dashboard has three pages (notifications / widgets / dashlets). Swiping
  horizontally on the widgets page changes page; in edit mode paging is
  disabled so widget drags win.
- **Long-press anywhere on a widget** (800 ms, handled by the shell) enters
  edit mode. On an empty dashboard, long-press the background instead. While
  editing, the addon is disabled and the cell grid is drawn: dragging moves
  the card one whole cell at a time, the bottom-right grip resizes it in whole
  cells, the sliders button opens settings, × removes it. Touch input
  is not delivered to the widget in edit mode, so don't rely on a
  press-and-hold gesture inside your own widget unless it is shorter than the
  shell's.
- Edit mode is exited with **Done**; the layout is saved immediately
  (debounced ~1 s) to `config/dashboard.json`.

---

## Network access

Addons can use `XMLHttpRequest` from QML — see `addons/weather/` for a real
example that talks to the free Open-Meteo API (geocoding + current weather, no
API key). Keep failures visible and retryable: the weather widget shows an
error message and refetches when tapped, plus a 30-minute timer.

---

## Installing & arranging

1. Copy the folder into `addons/`.
2. Restart the dashboard (addons are scanned at startup).
3. Long-press an existing widget → **+ Add widget** → pick your addon.
4. Drag/resize it, then **Done**.

Or edit `config/dashboard.json` by hand:

```json
{
  "grid": { "cols": 8, "rows": 5 },
  "widgets": [
    {
      "id": "my-widget-1",
      "addon": "my-widget",
      "page": "main",
      "x": 0, "y": 3, "w": 2, "h": 2,
      "settings": { "label": "Desk lamp" }
    }
  ]
}
```

Every widget needs a unique `id`; the dashboard assigns one automatically when
you add through the UI, and generates `w0`, `w1`, … for hand-written entries
that omit it. `page` selects the vertical widget page (`widgetPages` in the
config; omit it to use the main page). Coordinates are clamped to the grid and
widgets may not overlap on the same page (a rejected move snaps back).

---

## Testing

On the desktop (Fedora/any Qt desktop):

```sh
./run.sh                    # 800×480 window
./run.sh --fullscreen       # kiosk preview
```

Headless render + smoke test (QML errors go to stderr):

```sh
.venv/bin/python tools/screenshot.py --out /tmp/dash.png   # unlocked dashboard
.venv/bin/python tools/screenshot.py --lock                # boot lock screen
.venv/bin/python tools/screenshot.py --edit                # edit chrome
.venv/bin/python tools/screenshot.py --settings hello-main
.venv/bin/python tools/screenshot.py --settings-page       # wallpaper picker
.venv/bin/python tools/screenshot.py --page dashlets       # dashlet launcher
.venv/bin/python tools/screenshot.py --app weather         # open a dashlet
.venv/bin/python tools/screenshot.py --test-notifications  # notification page
.venv/bin/python tools/screenshot.py --add                 # add-widget picker
.venv/bin/python tools/screenshot.py --config /tmp/other.json
```

Full interaction smoke test (synthetic touch: long-press, drag, resize,
settings, add/remove) against a temporary config copy:

```sh
.venv/bin/python tools/test_interactions.py
```

On the Pi:

```sh
./deploy/rsync.sh pi@raspberrypi.local
journalctl -u pi-dash -f
```

---

## Tips & gotchas

- **QML only.** Addons are declarative; there is no Python entry point. If you
  need a device/hub API, that belongs in the shell's `Host` bridge (a later
  phase) exposed through `WidgetBase`.
- **No emoji fonts on a stock Pi.** Prefer glyphs covered by DejaVu Sans.
  Verified against DejaVu 2.37: ☀ ☁ ☂ ☃ ⚡ ⚠ × − · … ° ← ↑ → ↓. (⛅ U+26C5 is
  missing — Qt may substitute another font on your desktop but not on a
  minimal Pi image.) Test on the Pi, not just on your desktop.
- **Text entry needs a keyboard.** Under `eglfs` there is no system keyboard;
  text settings are best edited from a desktop or you add Qt Virtual Keyboard
  later. Everything touch-driven (toggles, steppers, dragging) works today.
- **Don't assume a size.** A 1×1 cell is roughly 90×85 px on the 800×480
  screen. Use `anchors`/`Column`/`Row` and `elide: Text.ElideRight`.
- **Keep touch targets ≥ 40 px.** Fingers are bigger than mouse pointers.
- **Guard asynchronous data.** `visible: false` does not stop a `text`
  binding from evaluating — guard with the state (`state === "ready" ? … : ""`)
  as the weather widget does.
- **Long-running work belongs in C++/Python**, not JS timers. QML `Timer`s are
  fine for clock ticks and refresh intervals.
