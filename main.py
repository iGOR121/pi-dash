#!/usr/bin/env python3
"""pi-dash — a touchscreen dashboard shell where every widget is an addon.

Usage:
    python main.py                 # windowed 800x480 (desktop development)
    python main.py --fullscreen    # kiosk mode (automatic under eglfs on the Pi)
"""
import argparse
import logging
import sys
from pathlib import Path

APP_ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(APP_ROOT))

from PySide6.QtCore import QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine

from app.activity import ActivityMonitor
from app.bluetooth import BluetoothService
from app.host import Host
from app.uxplay import CastFrameProvider, UxPlayService


def main() -> int:
    logging.basicConfig(
        level=logging.INFO,
        format="%(levelname)-7s %(name)s: %(message)s",
    )

    parser = argparse.ArgumentParser(description="pi-dash kiosk dashboard")
    parser.add_argument(
        "--config",
        default=str(APP_ROOT / "config" / "dashboard.json"),
        help="path to dashboard.json (default: config/dashboard.json)",
    )
    parser.add_argument(
        "--fullscreen",
        action="store_true",
        help="start fullscreen (windows are always fullscreen under eglfs anyway)",
    )
    args = parser.parse_args()

    app = QGuiApplication(sys.argv)
    app.setApplicationName("pi-dash")
    app.setOrganizationName("pi-dash")

    engine = QQmlApplicationEngine()
    # Makes the `shell` qmldir module (shell/qmldir) importable from any QML
    # file, including addons loaded dynamically at runtime.
    engine.addImportPath(str(APP_ROOT))

    host = Host(
        config_path=Path(args.config).resolve(),
        addons_dir=APP_ROOT / "addons",
    )
    activity = ActivityMonitor(app)
    app.installEventFilter(activity)
    uxplay = UxPlayService(host, app)
    engine.addImageProvider("cast", CastFrameProvider(uxplay))
    bluetooth = BluetoothService(app)

    engine.rootContext().setContextProperty("Host", host)
    engine.rootContext().setContextProperty("Activity", activity)
    engine.rootContext().setContextProperty("UxPlay", uxplay)
    engine.rootContext().setContextProperty("Bluetooth", bluetooth)
    app.aboutToQuit.connect(uxplay.stop)
    app.aboutToQuit.connect(bluetooth.stop)
    app.aboutToQuit.connect(host.saveNow)
    engine.load(QUrl.fromLocalFile(str(APP_ROOT / "shell" / "Main.qml")))

    if not engine.rootObjects():
        logging.getLogger("pi-dash").error("failed to load shell/Main.qml")
        return 1
    if args.fullscreen:
        engine.rootObjects()[0].showFullScreen()

    return app.exec()


if __name__ == "__main__":
    sys.exit(main())
