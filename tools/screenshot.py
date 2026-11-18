#!/usr/bin/env python3
"""Headless smoke test + screenshot for pi-dash.

Renders the whole dashboard without a display and writes a PNG:

    .venv/bin/python tools/screenshot.py [--wait 4000] [--out file.png]
    .venv/bin/python tools/screenshot.py --lock
    .venv/bin/python tools/screenshot.py --edit
    .venv/bin/python tools/screenshot.py --settings clock-main
    .venv/bin/python tools/screenshot.py --config /tmp/other-dashboard.json

By default it captures the *unlocked* dashboard; --lock captures the boot
lock screen. Doubles as a CI-ish check: any QML error shows up on stderr.
"""
import argparse
import os
import sys
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(APP_ROOT))

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
# threaded render loop deadlocks under offscreen; basic is synchronous
os.environ.setdefault("QSG_RENDER_LOOP", "basic")

from PySide6.QtCore import Q_ARG, QMetaObject, QTimer, QUrl, Qt
from PySide6.QtGui import (QBrush, QColor, QFont, QGuiApplication, QImage,
                           QLinearGradient, QPainter)
from PySide6.QtQml import QQmlApplicationEngine
# importing this makes shiboken resolve the QML Window wrapper as
# QQuickWindow (so .grabWindow() exists below)
from PySide6.QtQuick import QQuickWindow  # noqa: F401

from app.activity import ActivityMonitor
from app.bluetooth import BluetoothService
from app.host import Host
from app.uxplay import CastFrameProvider, UxPlayService


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", default="/tmp/opencode/pi-dash-screenshot.png")
    parser.add_argument("--wait", type=int, default=4000, help="ms to settle (weather fetch)")
    parser.add_argument("--config", default=str(APP_ROOT / "config" / "dashboard.json"))
    parser.add_argument("--lock", action="store_true", help="capture the lock screen")
    parser.add_argument("--edit", action="store_true", help="capture edit mode")
    parser.add_argument("--settings", default="",
                        help="open the settings sheet for this instance id")
    parser.add_argument("--settings-page", action="store_true",
                        help="open the app settings page (wallpaper picker)")
    parser.add_argument("--page", choices=["notifications", "widgets", "dashlets"],
                        default="", help="capture a specific page")
    parser.add_argument("--widget-page", type=int, default=-1,
                        help="capture a specific vertical widget page (0-based)")
    parser.add_argument("--pages-sheet", action="store_true",
                        help="open the widget-pages manager")
    parser.add_argument("--app", default="", help="open a dashlet by addon id")
    parser.add_argument("--test-notifications", action="store_true",
                        help="post a couple of demo notifications")
    parser.add_argument("--apps-popup", action="store_true",
                        help="expand the active-dashlets popup")
    parser.add_argument("--cast", action="store_true",
                        help="show a demo AirPlay cast (test frame)")
    parser.add_argument("--uxplay-demo", action="store_true",
                        help="open the AirPlay app with demo metadata")
    parser.add_argument("--bluetooth-demo", action="store_true",
                        help="open the Bluetooth app with demo devices")
    parser.add_argument("--bluetooth-codecs", action="store_true",
                        help="capture the Bluetooth app scrolled to the codecs")
    parser.add_argument("--add", action="store_true", help="open the add-widget picker")
    args = parser.parse_args()

    app = QGuiApplication(sys.argv)
    app.setApplicationName("pi-dash-screenshot")

    engine = QQmlApplicationEngine()
    engine.addImportPath(str(APP_ROOT))

    host = Host(
        config_path=Path(args.config).resolve(),
        addons_dir=APP_ROOT / "addons",
    )
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
    if not engine.rootObjects():
        print("ERROR: failed to load Main.qml", file=sys.stderr)
        return 1

    window = engine.rootObjects()[0]

    # Default capture is the dashboard itself; --lock shows the boot screen.
    window.setProperty("locked", bool(args.lock))

    if args.edit:
        window.setProperty("editMode", True)
    if args.settings:
        ok = QMetaObject.invokeMethod(window, "openSettingsFor",
                                      Q_ARG("QVariant", args.settings))
        if not ok:
            print("ERROR: could not open settings for", args.settings, file=sys.stderr)
            return 1
    if args.settings_page:
        if not QMetaObject.invokeMethod(window, "openSettings"):
            print("ERROR: could not open the settings page", file=sys.stderr)
            return 1
    if args.test_notifications:
        host.notify("Weather", "Forecast updated for Moscow")
        host.notify("pi-dash", "Notifications are working")

    if args.apps_popup:
        window.setProperty("appsExpanded", True)

    if args.cast or args.uxplay_demo:
        demo = QImage(640, 360, QImage.Format_RGB32)
        painter = QPainter(demo)
        gradient = QLinearGradient(0, 0, 640, 360)
        gradient.setColorAt(0.0, QColor("#0f172a"))
        gradient.setColorAt(0.55, QColor("#1e3a8a"))
        gradient.setColorAt(1.0, QColor("#0e7490"))
        painter.fillRect(demo.rect(), QBrush(gradient))
        painter.setPen(QColor("#ffffff"))
        painter.setFont(QFont("sans", 38, QFont.Bold))
        painter.drawText(demo.rect(), Qt.AlignCenter, "AirPlay cast")
        painter.end()

    if args.uxplay_demo:
        uxplay._running = True
        uxplay._now = {"title": "Midnight City", "artist": "M83",
                       "album": "Hurry Up, We're Dreaming"}
        uxplay.runningChanged.emit()
        uxplay.metadataChanged.emit()
        QMetaObject.invokeMethod(window, "openDashlet", Q_ARG("QVariant", "uxplay"))

    if args.cast:
        uxplay.set_test_frame(demo)

    if args.bluetooth_demo or args.bluetooth_codecs:
        bluetooth._timer.stop()
        bluetooth._refreshing = True   # keep the demo state for the capture
        bluetooth._ctl = bluetooth._ctl or "bluetoothctl"
        bluetooth._adapter = {
            "present": True, "address": "B8:27:EB:67:CE:49",
            "name": "raspy", "alias": "pi-dash", "powered": True,
            "discoverable": True, "pairable": True,
        }
        bluetooth._paired = [
            {"address": "C7:45:9C:4B:75:9D", "name": "Keychron B1 Pro",
             "connected": True, "trusted": True, "icon": "input-keyboard",
             "kind": "hid", "phone": False, "codec": "", "profile": "",
             "output": False},
            {"address": "38:18:4C:AA:12:34", "name": "WH-1000XM4",
             "connected": True, "trusted": True, "icon": "audio-headphones",
             "kind": "audio", "phone": False, "codec": "ldac",
             "profile": "a2dp-source", "output": True},
            {"address": "A4:50:46:01:23:45", "name": "Pixel 9",
             "connected": True, "trusted": True, "icon": "phone",
             "kind": "audio", "phone": True, "codec": "aac",
             "profile": "a2dp-sink", "output": False},
        ]
        bluetooth._nearby = [
            {"address": "D0:03:4B:11:22:33", "name": "JBL Flip 6"},
            {"address": "E1:2A:3B:44:55:66", "name": "MX Master 3S"},
        ]
        bluetooth._codecs = ["sbc", "sbc_xq", "aac", "aptx", "aptx_hd", "ldac"]
        bluetooth._message = "Scan finished"
        bluetooth.stateChanged.emit()
        QMetaObject.invokeMethod(window, "openDashlet", Q_ARG("QVariant", "bluetooth"))

        if args.bluetooth_codecs:
            def scroll_bluetooth():
                queue = list(window.contentItem().childItems())
                while queue:
                    item = queue.pop()
                    queue.extend(item.childItems())
                    try:
                        if item.property("pendingCodecs") is None:
                            continue
                        inner = list(item.childItems())
                        while inner:
                            child = inner.pop()
                            inner.extend(child.childItems())
                            height = child.property("contentHeight")
                            visible = child.property("height")
                            if (height and visible and height > visible
                                    and child.property("contentY") is not None):
                                child.setProperty("contentY", height - visible)
                                return
                    except (RuntimeError, TypeError):
                        continue
            QTimer.singleShot(600, scroll_bluetooth)

    def prepare():
        # after the window has been laid out (the pager needs a width)
        if args.page:
            page = {"notifications": 0, "widgets": 1, "dashlets": 2}[args.page]
            QMetaObject.invokeMethod(window, "goToPage", Q_ARG("QVariant", page))
        if args.app:
            QMetaObject.invokeMethod(window, "openDashlet", Q_ARG("QVariant", args.app))
        if args.widget_page >= 0:
            QMetaObject.invokeMethod(window, "goToWidgetPage",
                                     Q_ARG("QVariant", args.widget_page))
        if args.pages_sheet:
            window.setProperty("editMode", True)
            QMetaObject.invokeMethod(window, "openPagesSheet")

    QTimer.singleShot(300, prepare)

    if args.add:
        window.setProperty("editMode", True)
        if not QMetaObject.invokeMethod(window, "openAddSheet"):
            print("ERROR: could not open the add-widget picker", file=sys.stderr)
            return 1

    def grab():
        image = window.grabWindow()
        Path(args.out).parent.mkdir(parents=True, exist_ok=True)
        ok = image.save(args.out)
        print(("saved " if ok else "FAILED to save ") + args.out)
        app.exit(0 if ok else 2)

    QTimer.singleShot(args.wait, grab)
    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
