#!/usr/bin/env python3
"""Headless interaction smoke test for pi-dash.

Drives the real QML UI with synthetic mouse input (offscreen Qt) and checks
edit mode, drag snap, resize, settings persistence and add/remove. Runs
against a temporary copy of config/dashboard.json, never the real one:

    .venv/bin/python tools/test_interactions.py

Exits non-zero if any check fails, so it can gate a deploy.
"""
import os
import shutil
import sys
import tempfile
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(APP_ROOT))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
os.environ.setdefault("QSG_RENDER_LOOP", "basic")

from PySide6.QtCore import Q_ARG, QMetaObject, QPoint, Qt, QUrl
from PySide6.QtGui import QGuiApplication, QImage
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow  # noqa: F401  (grabWindow typing)
from PySide6.QtTest import QTest

from app.activity import ActivityMonitor
from app.bluetooth import BluetoothService
from app.host import Host
from app.uxplay import CastFrameProvider, UxPlayService

TOP, BOTTOM, GAP = 52, 62, 8
SYSTEM_BAR = 44   # page dots / active-dashlets bar when not editing
WINDOW_W, WINDOW_H = 800, 480
COLS, ROWS = 8, 5
FAILS: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    print(("PASS " if ok else "FAIL ") + name + (f"  {detail}" if detail else ""))
    if not ok:
        FAILS.append(name)


def rect(entry: dict, top: int = 0, bottom: int = 0):
    cw = (WINDOW_W - GAP * (COLS + 1)) / COLS
    ch = (WINDOW_H - top - bottom - GAP * (ROWS + 1)) / ROWS
    x = GAP + entry["x"] * (cw + GAP)
    y = top + GAP + entry["y"] * (ch + GAP)
    w = entry["w"] * cw + (entry["w"] - 1) * GAP
    h = entry["h"] * ch + (entry["h"] - 1) * GAP
    return x, y, w, h


def center(entry: dict, top: int = 0, bottom: int = 0) -> QPoint:
    x, y, w, h = rect(entry, top, bottom)
    return QPoint(int(x + w / 2), int(y + h / 2))


def find_item(window, predicate):
    queue = list(window.contentItem().childItems())
    while queue:
        item = queue.pop()
        queue.extend(item.childItems())
        if predicate(item):
            return item
    return None


def epoch_ms(value):
    if value is None:
        return None
    if hasattr(value, "toMSecsSinceEpoch"):
        return value.toMSecsSinceEpoch()
    return int(value.timestamp() * 1000)


def drag(window, start: QPoint, dx: int, dy: int, steps: int = 8,
         delay: int = 20) -> None:
    QTest.mousePress(window, Qt.LeftButton, Qt.NoModifier, start)
    QTest.qWait(50)
    for step in range(1, steps + 1):
        QTest.mouseMove(window, QPoint(start.x() + dx * step // steps,
                                       start.y() + dy * step // steps))
        QTest.qWait(delay)
    QTest.mouseRelease(window, Qt.LeftButton, Qt.NoModifier,
                       QPoint(start.x() + dx, start.y() + dy))


def main() -> int:
    tmp_dir = Path(tempfile.mkdtemp(prefix="pi-dash-test-"))
    config_path = tmp_dir / "dashboard.json"
    shutil.copy(APP_ROOT / "config" / "dashboard.json", config_path)

    app = QGuiApplication(sys.argv)
    engine = QQmlApplicationEngine()
    engine.addImportPath(str(APP_ROOT))
    host = Host(config_path=config_path, addons_dir=APP_ROOT / "addons")
    activity = ActivityMonitor(app)
    app.installEventFilter(activity)
    uxplay = UxPlayService(host, app)
    engine.addImageProvider("cast", CastFrameProvider(uxplay))
    bluetooth = BluetoothService(app, manage_agent=False)
    engine.rootContext().setContextProperty("Host", host)
    engine.rootContext().setContextProperty("Activity", activity)
    engine.rootContext().setContextProperty("UxPlay", uxplay)
    engine.rootContext().setContextProperty("Bluetooth", bluetooth)
    app.aboutToQuit.connect(uxplay.stop)
    app.aboutToQuit.connect(bluetooth.stop)
    engine.load(QUrl.fromLocalFile(str(APP_ROOT / "shell" / "Main.qml")))
    assert engine.rootObjects(), "shell/Main.qml failed to load"
    window = engine.rootObjects()[0]
    QTest.qWait(500)

    def model() -> dict:
        return {w["instanceId"]: w for w in host.widgetModel()}

    # 0) lock screen ------------------------------------------------------
    check("starts locked", window.property("locked") is True)
    lock_item = find_item(window, lambda it: it.property("dragOffset") is not None
                          and it.property("active") is not None)
    check("lock screen is visible", lock_item is not None
          and lock_item.property("visible") is True)
    QTest.mouseClick(window, Qt.LeftButton, Qt.NoModifier,
                     center(model()["toggle-lamp"], 0, SYSTEM_BAR))
    QTest.qWait(500)
    check("tap unlocks", window.property("locked") is False)
    check("locked tap does not reach the widget",
          model()["toggle-lamp"]["settings"].get("state") is not True)

    # swipe up unlocks, then continue with the dashboard tests
    window.setProperty("locked", True)
    QTest.qWait(300)
    drag(window, QPoint(400, 300), 0, -160)
    QTest.qWait(600)
    check("swipe up unlocks", window.property("locked") is False)

    # any key unlocks too (desktop / keyboard attached)
    window.setProperty("locked", True)
    QTest.qWait(300)
    QTest.keyClick(window, Qt.Key_Space)
    QTest.qWait(500)
    check("any key unlocks", window.property("locked") is False)

    # Ctrl+L toggles the lock screen from the dashboard
    QTest.keyClick(window, Qt.Key_L, Qt.ControlModifier)
    QTest.qWait(300)
    check("Ctrl+L locks", window.property("locked") is True)
    QTest.keyClick(window, Qt.Key_Space)
    QTest.qWait(500)
    check("Ctrl+L round-trip unlock", window.property("locked") is False)

    # widget pages -------------------------------------------------------
    pages = window.property("widgetPages")
    check("starts on one main widget page",
          len(pages) == 1 and pages[0]["id"] == "main"
          and pages[0]["main"] is True)
    check("main widget page selected",
          window.property("widgetPageIndex") == 0)

    page_id = host.addWidgetPage("main", False)
    QTest.qWait(300)
    pages = window.property("widgetPages")
    check("widget page added",
          len(pages) == 2 and pages[1]["id"] == page_id)

    above_id = host.addWidgetPage("main", True)
    QTest.qWait(300)
    check("page can be added above",
          window.property("widgetPages")[0]["id"] == above_id)
    host.removeWidgetPage(above_id)
    QTest.qWait(300)

    page_gauge = host.addWidgetToPage("demo-gauge", page_id)
    QTest.qWait(300)
    gauge_entry = next(w for w in host.widgetModel()
                       if w["instanceId"] == page_gauge)
    check("widget lands on its page at its own free cell",
          gauge_entry["page"] == page_id
          and gauge_entry["x"] == 0 and gauge_entry["y"] == 0)
    check("page widget count tracked",
          next(p for p in window.property("widgetPages")
               if p["id"] == page_id)["widgetCount"] == 1)

    drag(window, QPoint(400, 400), 0, -200)   # swipe up : main -> below
    QTest.qWait(700)
    check("vertical swipe changes widget page",
          window.property("widgetPageIndex") == 1,
          str(window.property("widgetPageIndex")))

    QMetaObject.invokeMethod(window, "openPagesSheet")
    QTest.qWait(300)
    pages_sheet = find_item(window, lambda it: it.property("currentId") is not None)
    check("widget pages sheet opens",
          pages_sheet is not None and pages_sheet.property("visible") is True)
    if pages_sheet is not None:
        QMetaObject.invokeMethod(pages_sheet, "close")
        QTest.qWait(200)

    host.moveWidgetPage(page_id, -1)
    QTest.qWait(300)
    check("widget page reordered",
          window.property("widgetPages")[0]["id"] == page_id)

    host.setMainWidgetPage(page_id)
    QTest.qWait(300)
    check("main widget page changed",
          next(p for p in window.property("widgetPages")
               if p["id"] == page_id)["main"] is True)

    check("non-empty page cannot be deleted",
          host.removeWidgetPage(page_id) is False)
    host.setMainWidgetPage("main")
    host.removeWidget(page_gauge)
    QTest.qWait(200)
    check("empty page can be deleted",
          host.removeWidgetPage(page_id) is True)
    QTest.qWait(300)
    check("back to one widget page",
          len(window.property("widgetPages")) == 1)
    QMetaObject.invokeMethod(window, "goToWidgetPage", Q_ARG("QVariant", 0))
    QTest.qWait(500)

    # 1) long press enters edit mode -------------------------------------
    weather = model()["weather-main"]
    check("weather exposes refresh interval",
          any(s["key"] == "refreshMinutes" for s in weather["schema"]))

    weather_item = find_item(window, lambda it: it.property("instanceId") == "weather-main"
                             and it.property("addon") == "weather")
    check("found weather widget", weather_item is not None)
    if weather_item is not None:
        before = epoch_ms(weather_item.property("nextUpdate"))
        QTest.qWait(150)
        QMetaObject.invokeMethod(weather_item, "fetch")   # what the ↻ button calls
        QTest.qWait(300)
        after = epoch_ms(weather_item.property("nextUpdate"))
        check("manual refresh reschedules the next update",
              before is not None and after is not None and after > before)

    # dashlet metadata + shared settings
    catalog = host.appCatalog()
    app_ids = {app["id"] for app in catalog}
    check("dashlet catalog includes clock and weather",
          {"clock", "weather"} <= app_ids)
    check("uxplay dashlet installed", "uxplay" in app_ids)
    check("bluetooth dashlet installed", "bluetooth" in app_ids)
    check("dashlet app entries resolve",
          all(app["entryUrl"].startswith("file:") for app in catalog))
    check("two active dashlets",
          window.property("activeAppsText") == "2 active dashlets",
          str(window.property("activeAppsText")))

    original_location = model()["weather-main"]["settings"].get("location", "Berlin")
    host.setAppSetting("weather", "location", "Paris")
    QTest.qWait(100)
    check("app setting syncs into widget settings",
          model()["weather-main"]["settings"]["location"] == "Paris")
    host.setSetting("weather-main", "units", "imperial")
    QTest.qWait(100)
    check("widget setting routes to app settings",
          host.appSettings("weather")["units"] == "imperial")
    host.setAppSetting("weather", "location", original_location)
    host.setAppSetting("weather", "units", "metric")
    QTest.qWait(100)
    check("weather settings restored",
          model()["weather-main"]["settings"]["location"] == original_location)

    host.setAppSetting("clock", "zones", ["Europe/Berlin"])
    QTest.qWait(150)
    check("clock zones sync to the widget",
          "Europe/Berlin" in model()["clock-main"]["settings"].get("zones", []))
    host.setAppSetting("clock", "zones", [])

    times = host.clockTimes(["Europe/Berlin", "America/New_York", "Nope/Invalid"])
    check("clock times include local + valid zones", len(times) == 3,
          str([t["label"] for t in times]))
    check("clock zone labels", times[1]["label"] == "Berlin"
          and times[2]["label"] == "New York")

    # tapping an app-backed widget opens its dashlet
    QTest.mouseClick(window, Qt.LeftButton, Qt.NoModifier,
                     center(model()["clock-main"], 0, SYSTEM_BAR))
    QTest.qWait(600)
    check("tapping the clock opens its dashlet",
          window.property("openApp") == "clock")
    QMetaObject.invokeMethod(window, "closeDashlet")
    QMetaObject.invokeMethod(window, "goToPage", Q_ARG("QVariant", 1))
    QTest.qWait(500)

    point = center(model()["clock-main"], 0, SYSTEM_BAR)
    QTest.mousePress(window, Qt.LeftButton, Qt.NoModifier, point)
    QTest.qWait(1100)
    QTest.mouseRelease(window, Qt.LeftButton, Qt.NoModifier, point)
    QTest.qWait(200)
    check("long-press enters edit mode", window.property("editMode") is True)

    # 2) normal taps still reach addons ----------------------------------
    window.setProperty("editMode", False)
    QTest.qWait(400)
    QTest.mouseClick(window, Qt.LeftButton, Qt.NoModifier,
                     center(model()["toggle-lamp"], 0, SYSTEM_BAR))
    QTest.qWait(250)
    check("tap reaches addon in normal mode",
          model()["toggle-lamp"]["settings"].get("state") is True)

    # 3) resize through the grip -----------------------------------------
    window.setProperty("editMode", True)
    QTest.qWait(200)
    gauge = model()["gauge-power"]
    gx, gy, gw, gh = rect(gauge, TOP, BOTTOM)
    cell_h = (WINDOW_H - TOP - BOTTOM - GAP * (ROWS + 1)) / ROWS
    drag(window, QPoint(int(gx + gw - 23), int(gy + gh - 23)), 0, int(cell_h))
    QTest.qWait(400)
    grown = model()["gauge-power"]
    check("grip drag resizes the widget", grown["h"] == gauge["h"] + 1,
          f'{gauge["w"]}x{gauge["h"]} -> {grown["w"]}x{grown["h"]}')
    host.resizeWidget("gauge-power", gauge["w"], gauge["h"])
    QTest.qWait(300)

    # 4) drag a widget, snap to the grid ---------------------------------
    hello = model()["hello-main"]
    drag(window, center(hello, TOP, BOTTOM), 0, int(cell_h))
    QTest.qWait(400)
    moved = model()["hello-main"]
    check("drag moves and snaps", moved["y"] == hello["y"] + 1,
          f'{hello["x"]},{hello["y"]} -> {moved["x"]},{moved["y"]}')

    # 5) settings button opens the generated sheet -----------------------
    clock = model()["clock-main"]
    cx, cy, _, _ = rect(clock, TOP, BOTTOM)
    QTest.mouseClick(window, Qt.LeftButton, Qt.NoModifier,
                     QPoint(int(cx + 22), int(cy + 22)))
    QTest.qWait(300)
    sheet = find_item(window, lambda it: it.property("values") is not None)
    check("settings button opens the sheet",
          sheet is not None and sheet.property("visible") is True
          and sheet.property("instanceId") == "clock-main")
    if sheet is not None:
        QTest.mouseClick(window, Qt.LeftButton, Qt.NoModifier, QPoint(6, 6))
        QTest.qWait(200)
        check("backdrop closes the sheet", sheet.property("visible") is False)

    # 6) delete badge removes the widget ---------------------------------
    hello = model()["hello-main"]
    hx, hy, hw, _ = rect(hello, TOP, BOTTOM)
    QTest.mouseClick(window, Qt.LeftButton, Qt.NoModifier,
                     QPoint(int(hx + hw - 22), int(hy + 22)))
    QTest.qWait(400)
    check("delete badge removes the widget", "hello-main" not in model())

    # 7) live settings propagation ---------------------------------------
    QTest.qWait(200)
    clock_item = find_item(window, lambda it: it.property("instanceId") == "clock-main"
                           and it.property("addon") == "clock")
    check("found running clock widget", clock_item is not None)
    if clock_item is not None:
        check("clock starts 24h", clock_item.property("format24h") is True)
        host.setSetting("clock-main", "format24h", False)
        QTest.qWait(100)
        check("settings update live in the widget",
              clock_item.property("format24h") is False)
        host.setSetting("clock-main", "format24h", True)

    # 8) overlap rejection -----------------------------------------------
    before = (model()["clock-main"]["x"], model()["clock-main"]["y"])
    host.moveWidget("clock-main", 3, 0)          # weather lives there
    after = model()["clock-main"]
    check("overlapping move rejected", (after["x"], after["y"]) == before)

    # 9) add / remove and auto-placement ---------------------------------
    count = len(host.widgetModel())
    new_id = host.addWidget("demo-toggle")        # hello freed a 2x2 hole
    check("addWidget returns an id", bool(new_id), new_id)
    check("addWidget grows the model", len(host.widgetModel()) == count + 1)
    host.removeWidget(new_id)
    check("removeWidget shrinks the model", len(host.widgetModel()) == count)

    added = host.addWidget("demo-gauge")
    layout = host.widgetModel()
    clash = any(
        a["x"] < b["x"] + b["w"] and a["x"] + a["w"] > b["x"]
        and a["y"] < b["y"] + b["h"] and a["y"] + a["h"] > b["y"]
        for i, a in enumerate(layout) for b in layout[i + 1:]
    )
    check("auto-placement does not overlap", not clash)
    check("auto-placement stays in bounds",
          all(w["x"] >= 0 and w["y"] >= 0 and w["x"] + w["w"] <= COLS
              and w["y"] + w["h"] <= ROWS for w in layout))
    host.removeWidget(added)

    # 10) an empty grid can still enter edit mode ------------------------
    for widget_id in list(model()):
        host.removeWidget(widget_id)
    window.setProperty("editMode", False)
    QTest.qWait(400)
    check("all widgets removed", len(host.widgetModel()) == 0)
    QTest.mousePress(window, Qt.LeftButton, Qt.NoModifier, QPoint(400, 240))
    QTest.qWait(1100)
    QTest.mouseRelease(window, Qt.LeftButton, Qt.NoModifier, QPoint(400, 240))
    QTest.qWait(200)
    check("long-press background enters edit mode on an empty grid",
          window.property("editMode") is True)
    host.addWidget("clock")
    QTest.qWait(200)
    check("a widget can be added again", len(host.widgetModel()) == 1)

    # 11) wallpaper picker + app settings page ---------------------------
    wallpaper = Path(tempfile.gettempdir()) / "pi-dash-test-wallpaper.png"
    image = QImage(320, 180, QImage.Format_RGB32)
    image.fill(0xFF7A3E9D)
    image.save(str(wallpaper))

    check("wallpaper catalog is a list", isinstance(host.wallpaperCatalog(), list))
    host.setWallpaper(str(wallpaper))
    QTest.qWait(200)
    check("wallpaper resolves to the chosen file",
          host.wallpaperUrl() == wallpaper.as_uri(), host.wallpaperUrl())
    check("dashboard picked up the wallpaper live",
          window.property("wallpaperUrl") == wallpaper.as_uri())
    host.setWallpaperMode("stretch")
    QTest.qWait(150)
    check("fit mode applies live", window.property("wallpaperMode") == "stretch")
    host.setWallpaperMode("bogus")
    check("invalid fit mode rejected", host.wallpaperMode() == "stretch")

    QMetaObject.invokeMethod(window, "openSettings")
    QTest.qWait(300)
    settings_page = find_item(window, lambda it: it.property("lockAtBoot") is not None)
    check("settings page opens",
          settings_page is not None and settings_page.property("visible") is True)
    if settings_page is not None:
        QMetaObject.invokeMethod(settings_page, "close")
        QTest.qWait(150)
        check("settings page closes", settings_page.property("visible") is False)

        # locking must never leave the settings page on top
        QMetaObject.invokeMethod(window, "openSettings")
        QTest.qWait(200)
        window.setProperty("locked", True)
        QTest.qWait(200)
        check("locking closes the settings page",
              settings_page.property("visible") is False)
        QTest.keyClick(window, Qt.Key_Space)
        QTest.qWait(500)

    host.setWallpaper("")
    host.setWallpaperMode("fill")
    QTest.qWait(150)
    wallpaper.unlink(missing_ok=True)

    # 12) pages, notifications, dashlet apps -----------------------------
    QMetaObject.invokeMethod(window, "goToPage", Q_ARG("QVariant", 0))
    QTest.qWait(400)
    check("notifications page selected", window.property("currentPage") == 0)
    QMetaObject.invokeMethod(window, "goToPage", Q_ARG("QVariant", 2))
    QTest.qWait(400)
    check("dashlets page selected", window.property("currentPage") == 2)
    QMetaObject.invokeMethod(window, "goToPage", Q_ARG("QVariant", 1))
    QTest.qWait(400)
    check("widgets page selected", window.property("currentPage") == 1)

    drag(window, QPoint(650, 400), -450, 0)   # swipe left : widgets -> dashlets
    QTest.qWait(700)
    check("horizontal swipe changes page", window.property("currentPage") == 2)
    check("swipe settles fully on a page",
          window.property("pageSettled") is True)

    QMetaObject.invokeMethod(window, "goToPage", Q_ARG("QVariant", 1))
    QTest.qWait(500)

    drag(window, QPoint(600, 400), -120, 0, 8, 60)   # partial drag
    QTest.qWait(700)
    check("partial drag settles fully on a page",
          window.property("pageSettled") is True)
    check("page indicator is always a valid page",
          window.property("currentPage") in (1, 2))
    QMetaObject.invokeMethod(window, "goToPage", Q_ARG("QVariant", 1))
    QTest.qWait(500)

    host.clearNotifications()
    first_id = host.notify("Test", "Hello from the test")
    check("notification stored", host.notificationCount() == 1)
    check("notification badge updates",
          window.property("notificationCount") == 1)
    host.dismissNotification(first_id)
    check("notification dismissed", host.notificationCount() == 0)
    host.notify("Test 2", "Another")
    host.clearNotifications()
    check("notifications cleared", host.notificationCount() == 0)

    QMetaObject.invokeMethod(window, "openDashlet", Q_ARG("QVariant", "weather"))
    QTest.qWait(900)
    check("weather dashlet opens", window.property("openApp") == "weather")
    weather_app = find_item(window, lambda it: it.property("days") is not None)
    check("weather app content loaded", weather_app is not None)
    QMetaObject.invokeMethod(window, "closeDashlet")
    QTest.qWait(250)
    check("weather dashlet closes", window.property("openApp") == "")

    QMetaObject.invokeMethod(window, "openDashlet", Q_ARG("QVariant", "clock"))
    QTest.qWait(700)
    check("clock dashlet opens", window.property("openApp") == "clock")
    clock_app = find_item(window, lambda it: it.property("cities") is not None)
    check("clock app content loaded", clock_app is not None)
    QMetaObject.invokeMethod(window, "closeDashlet")
    QTest.qWait(250)

    QMetaObject.invokeMethod(window, "openAppSettings", Q_ARG("QVariant", "clock"))
    QTest.qWait(300)
    app_sheet = find_item(window, lambda it: it.property("appMode") is True
                          and it.property("visible") is True)
    check("app settings sheet uses shared mode", app_sheet is not None)
    if app_sheet is not None:
        QMetaObject.invokeMethod(app_sheet, "close")
        QTest.qWait(150)

    # 13) UxPlay / AirPlay dashlet ---------------------------------------
    parsed = UxPlayService.parse_metadata(
        "Title: Midnight City\nArtist: M83\nAlbum: Hurry Up\nGenre: Pop")
    check("uxplay metadata parsed",
          parsed.get("title") == "Midnight City"
          and parsed.get("artist") == "M83"
          and parsed.get("album") == "Hurry Up")

    before = host.notificationCount()
    uxplay._notify_track({"title": "Midnight City", "artist": "M83",
                          "album": "Hurry Up"})
    check("now-playing notification posted",
          host.notificationCount() == before + 1)
    uxplay._notify_track({"title": "Midnight City", "artist": "M83",
                          "album": "Hurry Up"})
    check("now-playing notification deduped",
          host.notificationCount() == before + 1)
    host.clearNotifications()
    uxplay._last_track = None

    original_binary = host.appSettings("uxplay").get("binary", "uxplay")
    host.setAppSetting("uxplay", "binary", "definitely-not-uxplay")
    started = uxplay.start()
    check("uxplay start fails cleanly without the binary", started is False)
    check("uxplay reports the missing binary",
          "not found" in uxplay.lastError.lower()
          or "install" in uxplay.lastError.lower())
    host.setAppSetting("uxplay", "binary", original_binary)

    QMetaObject.invokeMethod(window, "openDashlet", Q_ARG("QVariant", "uxplay"))
    QTest.qWait(600)
    check("uxplay dashlet opens", window.property("openApp") == "uxplay")
    uxplay_app = find_item(window, lambda it: it.property("hasTrack") is not None)
    check("uxplay app content loaded", uxplay_app is not None)
    QMetaObject.invokeMethod(window, "closeDashlet")
    QMetaObject.invokeMethod(window, "goToPage", Q_ARG("QVariant", 1))
    QTest.qWait(400)

    demo_frame = QImage(320, 180, QImage.Format_RGB32)
    demo_frame.fill(0xFF336699)
    uxplay.set_test_frame(demo_frame)
    QTest.qWait(400)
    overlay = find_item(window, lambda it: it.property("tick") is not None)
    check("cast overlay opens with video",
          overlay is not None and overlay.property("visible") is True)
    QTest.mouseClick(window, Qt.LeftButton, Qt.NoModifier,
                     QPoint(window.width() - 37, 37))
    QTest.qWait(300)
    check("grey cross closes the cast", uxplay.videoActive is False)
    check("cast overlay hides",
          overlay is not None and overlay.property("visible") is False)

    # 14) Bluetooth dashlet ----------------------------------------------
    adapter_info = BluetoothService.parse_adapter(
        "Controller B8:27:EB:67:CE:49 (public)\n"
        "\tName: raspy\n\tAlias: pi-dash\n\tPowered: yes\n"
        "\tDiscoverable: no\n\tPairable: yes\n")
    check("bluetooth adapter parsed",
          adapter_info.get("present") is True
          and adapter_info.get("alias") == "pi-dash"
          and adapter_info.get("powered") is True
          and adapter_info.get("discoverable") is False)

    hid_info = BluetoothService.parse_info(
        "Device C7:45:9C:4B:75:9D (random)\n"
        "\tName: Keychron B1 Pro\n\tIcon: input-keyboard\n"
        "\tPaired: yes\n\tTrusted: yes\n\tConnected: no\n"
        "\tUUID: Human Interface Device    (00001812-0000-1000-8000-00805f9b34fb)\n")
    check("bluetooth HID device parsed",
          hid_info.get("kind") == "hid"
          and hid_info.get("paired") is True
          and hid_info.get("connected") is False)

    codecs_parsed = BluetoothService.parse_codecs(
        "monitor.bluez.properties = {\n"
        "  bluez5.codecs = [ sbc aac ldac ]\n}\n")
    check("bluetooth codecs parsed",
          codecs_parsed == ["sbc", "aac", "ldac"])

    check("bluetooth codec catalog has SBC",
          any(c["id"] == "sbc" and c["label"] == "SBC"
              for c in bluetooth.codecCatalog))

    QMetaObject.invokeMethod(window, "openDashlet", Q_ARG("QVariant", "bluetooth"))
    QTest.qWait(600)
    check("bluetooth dashlet opens", window.property("openApp") == "bluetooth")
    bt_app = find_item(window, lambda it: it.property("pendingCodecs") is not None)
    check("bluetooth app content loaded", bt_app is not None)
    QMetaObject.invokeMethod(window, "closeDashlet")
    QMetaObject.invokeMethod(window, "goToPage", Q_ARG("QVariant", 1))
    QTest.qWait(400)

    # 15) auto-lock -------------------------------------------------------
    host.setAutoLockSeconds(120)
    QTest.qWait(150)
    check("auto-lock option updates live",
          window.property("autoLockSeconds") == 120)

    host.setAutoLockSeconds(0)
    window.setProperty("autoLockSeconds", 0)
    QTest.qWait(200)
    check("auto-lock off keeps the dashboard unlocked",
          window.property("locked") is False)

    # 2 s timeout: input postpones it, idling fires it
    window.setProperty("autoLockSeconds", 2)
    QTest.qWait(1000)
    QTest.keyClick(window, Qt.Key_A)      # counts as activity
    QTest.qWait(1500)
    check("activity postpones auto-lock", window.property("locked") is False)
    QTest.qWait(1000)
    check("auto-lock fires after inactivity", window.property("locked") is True)
    QTest.keyClick(window, Qt.Key_Space)  # unlock
    QTest.qWait(400)
    window.setProperty("autoLockSeconds", 0)
    QTest.qWait(200)

    # an active cast keeps the screen awake
    window.setProperty("autoLockSeconds", 1)
    uxplay.set_test_frame(demo_frame)
    QTest.qWait(1600)
    check("auto-lock pauses during a cast", window.property("locked") is False)
    uxplay.stop()
    QTest.qWait(1700)
    check("auto-lock resumes after the cast", window.property("locked") is True)
    QTest.keyClick(window, Qt.Key_Space)
    QTest.qWait(400)
    window.setProperty("autoLockSeconds", 0)
    QTest.qWait(200)

    host.saveNow()
    shutil.rmtree(tmp_dir, ignore_errors=True)

    print()
    print("FAILURES:", FAILS if FAILS else "none")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
