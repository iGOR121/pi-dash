"""The Host bridge: everything QML is allowed to call into Python.

Exposed to QML as the context property `Host` (see main.py). Addons get a
per-instance view of it through WidgetBase (shell/WidgetBase.qml).
"""
from __future__ import annotations

import logging
from datetime import datetime
from pathlib import Path
from typing import Any
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

from PySide6.QtCore import QObject, QTimer, Signal, Slot

from .addon import Addon, scan_addons
from .config import Config

log = logging.getLogger("pi-dash.host")

WALLPAPER_EXTS = (".jpg", ".jpeg", ".png", ".webp", ".bmp")
WALLPAPER_MODES = ("fill", "align", "stretch")


class Host(QObject):
    # The layout (grid, widget list, geometry) changed: re-pull widgetModel().
    layoutChanged = Signal()
    # One instance's settings changed (merged manifest defaults + overrides).
    settingsChanged = Signal(str, "QVariant")
    # Wallpaper image or fit mode changed.
    wallpaperChanged = Signal()
    # Auto-lock / lock-at-boot options changed.
    optionsChanged = Signal()
    # An app-level (dashlet) settings map changed; widgets of that addon
    # receive settingsChanged as well.
    appSettingsChanged = Signal(str, "QVariant")
    # Notifications were added / dismissed / cleared.
    notificationsChanged = Signal()

    def __init__(self, config_path: Path, addons_dir: Path, parent: QObject | None = None):
        super().__init__(parent)
        self._config = Config(config_path)
        self._root = addons_dir.parent
        self._addons: dict[str, Addon] = scan_addons(addons_dir)
        self._notifications: list[dict] = []
        self._notification_seq = 0

        migrated = self._migrate_app_settings()
        self._model = self._build_model()

        # Debounced save: widgets may flip settings rapidly (a toggle being
        # mashed); we coalesce writes into one atomic save per second.
        self._save_timer = QTimer(self)
        self._save_timer.setSingleShot(True)
        self._save_timer.setInterval(1000)
        self._save_timer.timeout.connect(self._config.save)
        if migrated:
            self._save_timer.start()

    # ------------------------------------------------------------------ grid

    @Slot(result=int)
    def gridCols(self) -> int:
        return self._config.grid["cols"]

    @Slot(result=int)
    def gridRows(self) -> int:
        return self._config.grid["rows"]

    @Slot(result="QVariant")
    def widgetModel(self) -> list[dict]:
        """List of widget instance descriptors for the QML grid.

        Each entry: instanceId, addon, addonName, entryUrl, x, y, w, h,
        minW, minH, schema, settings (manifest defaults + config overrides),
        missing.
        """
        return self._model

    def _build_model(self) -> list[dict]:
        cols, rows = self._config.grid["cols"], self._config.grid["rows"]
        out: list[dict] = []

        for index, widget in enumerate(self._config.widgets):
            instance_id = str(widget.get("id") or f"w{index}")
            addon_id = str(widget.get("addon", ""))
            addon = self._addons.get(addon_id)

            x, y, w, h = self._safe_geometry(widget, cols, rows)
            entry: dict[str, Any] = {
                "instanceId": instance_id,
                "addon": addon_id,
                "addonName": addon.name if addon else addon_id,
                "page": str(widget.get("page") or self._config.main_page_id()),
                "x": x,
                "y": y,
                "w": w,
                "h": h,
                "minW": addon.min_w if addon else 1,
                "minH": addon.min_h if addon else 1,
                "schema": addon.settings_schema() if addon else [],
                "hasApp": bool(addon and addon.app_entry),
                "settings": {},
                "missing": addon is None,
            }
            if addon is not None:
                entry["entryUrl"] = addon.entry_url
                # Addons that ship a dashlet share one app-level settings map
                # between every widget instance and the app page.
                if addon.app_entry:
                    entry["settings"] = self._app_settings(addon.folder)
                else:
                    entry["settings"] = addon.merged_settings(widget.get("settings"))
            else:
                log.warning(
                    "widget %r references missing addon %r (placeholder shown)",
                    instance_id,
                    addon_id,
                )
            out.append(entry)
        return out

    @staticmethod
    def _safe_geometry(widget: dict, cols: int, rows: int) -> tuple[int, int, int, int]:
        def as_int(value: Any, fallback: int) -> int:
            try:
                return int(value)
            except (TypeError, ValueError):
                return fallback

        w = max(1, min(as_int(widget.get("w"), 2), cols))
        h = max(1, min(as_int(widget.get("h"), 2), rows))
        x = max(0, min(as_int(widget.get("x"), 0), cols - w))
        y = max(0, min(as_int(widget.get("y"), 0), rows - h))
        return x, y, w, h

    # ------------------------------------------------------------- settings

    @Slot(str, str, "QVariant")
    def setSetting(self, instance_id: str, key: str, value: Any) -> None:
        """Persist a setting (debounced).

        For addons that ship a dashlet, widget settings are app settings:
        they are stored once and shared with every instance and the app page.
        """
        widget = self._config.find_widget(instance_id)
        addon = self._addons.get(str(widget.get("addon", ""))) if widget else None
        if addon is not None and addon.app_entry:
            self.setAppSetting(addon.folder, key, value)
            return

        self._config.set_widget_setting(instance_id, key, value)

        for entry in self._model:
            if entry["instanceId"] == instance_id:
                settings = dict(entry.get("settings") or {})
                settings[key] = value
                entry["settings"] = settings
                self.settingsChanged.emit(instance_id, settings)
                break

        self._save_timer.start()

    # ------------------------------------------------------ dashlet settings

    def _app_settings(self, addon_id: str) -> dict:
        addon = self._addons.get(addon_id)
        if addon is None:
            return {}
        merged = {spec.key: spec.default for spec in addon.settings}
        apps = self._config.data.get("apps")
        store = apps.get(addon_id) if isinstance(apps, dict) else None
        if isinstance(store, dict):
            merged.update(store)
        return merged

    def _migrate_app_settings(self) -> bool:
        """Move old per-instance settings into the shared app map, once."""
        apps = self._config.data.get("apps")
        if not isinstance(apps, dict):
            apps = {}
            self._config.data["apps"] = apps
        changed = False

        for addon in self._addons.values():
            if not addon.app_entry:
                continue
            store = apps.get(addon.folder)
            if not isinstance(store, dict):
                store = {}
                apps[addon.folder] = store
                changed = True
            keys = {spec.key for spec in addon.settings}
            for widget in self._config.widgets:
                if str(widget.get("addon")) != addon.folder:
                    continue
                overrides = widget.get("settings")
                if not isinstance(overrides, dict):
                    continue
                for key, value in overrides.items():
                    if key in keys and key not in store:
                        store[key] = value
                        changed = True
        return changed

    @Slot(str, result="QVariant")
    def appSettings(self, addon_id: str) -> dict:
        return self._app_settings(addon_id)

    @Slot(str, result="QVariant")
    def appSchema(self, addon_id: str) -> list[dict]:
        addon = self._addons.get(addon_id)
        return addon.settings_schema() if addon and addon.app_entry else []

    @Slot(str, str, "QVariant")
    def setAppSetting(self, addon_id: str, key: str, value: Any) -> None:
        addon = self._addons.get(addon_id)
        if addon is None or not addon.app_entry:
            log.warning("setAppSetting: %r is not a dashlet addon", addon_id)
            return

        apps = self._config.data.get("apps")
        if not isinstance(apps, dict):
            apps = {}
            self._config.data["apps"] = apps
        store = apps.get(addon_id)
        if not isinstance(store, dict):
            store = {}
            apps[addon_id] = store
        store[key] = value

        merged = self._app_settings(addon_id)
        for entry in self._model:
            if entry["addon"] == addon_id:
                entry["settings"] = merged
                self.settingsChanged.emit(entry["instanceId"], merged)
        self.appSettingsChanged.emit(addon_id, merged)
        self._save_timer.start()

    @Slot(result="QVariant")
    def appCatalog(self) -> list[dict]:
        """Installed dashlets (addons that ship a full-page app)."""
        return [
            {
                "id": addon.folder,
                "name": addon.name,
                "version": addon.version,
                "entryUrl": addon.app_entry_url,
                "icon": addon.app_icon,
                "description": addon.app_description,
            }
            for addon in sorted(self._addons.values(), key=lambda a: a.name.lower())
            if addon.app_entry
        ]

    # ---------------------------------------------------------- notifications

    @Slot(str, str, result=int)
    def notify(self, title: str, text: str) -> int:
        """Post an in-app notification (DE-agnostic: no DBus involved)."""
        self._notification_seq += 1
        item = {
            "id": self._notification_seq,
            "title": str(title),
            "text": str(text),
            "time": datetime.now().strftime("%H:%M"),
        }
        self._notifications.insert(0, item)
        del self._notifications[60:]
        self.notificationsChanged.emit()
        return int(item["id"])

    @Slot(result="QVariant")
    def notifications(self) -> list[dict]:
        return list(self._notifications)

    @Slot(result=int)
    def notificationCount(self) -> int:
        return len(self._notifications)

    @Slot(int)
    def dismissNotification(self, notification_id: int) -> None:
        before = len(self._notifications)
        self._notifications = [n for n in self._notifications
                               if n["id"] != notification_id]
        if len(self._notifications) != before:
            self.notificationsChanged.emit()

    @Slot()
    def clearNotifications(self) -> None:
        if self._notifications:
            self._notifications = []
            self.notificationsChanged.emit()

    # --------------------------------------------------------------- clocks

    @Slot("QVariant", result="QVariant")
    def clockTimes(self, zones) -> list[dict]:
        """Local time plus the requested IANA zones (DST-safe via zoneinfo)."""
        now = datetime.now()
        out = [self._clock_entry("local", "Local", now)]
        if isinstance(zones, list):
            for name in zones:
                try:
                    zone = ZoneInfo(str(name))
                except (ZoneInfoNotFoundError, ValueError, OSError):
                    log.warning("clockTimes: unknown timezone %r", name)
                    continue
                local = now.astimezone(zone)
                label = str(name).rsplit("/", 1)[-1].replace("_", " ")
                out.append(self._clock_entry(str(name), label, local))
        return out

    @staticmethod
    def _clock_entry(zone: str, label: str, moment: datetime) -> dict:
        return {
            "zone": zone,
            "label": label,
            "hour": moment.hour,
            "minute": moment.minute,
            "second": moment.second,
            "day": moment.strftime("%a"),
            "date": moment.strftime("%d %b"),
        }

    # ------------------------------------------------------------ wallpaper

    @Slot(result=str)
    def wallpaperUrl(self) -> str:
        """file:// URL of the wallpaper, or "" to use the built-in gradient."""
        path = self._wallpaper_path()
        return path.as_uri() if path is not None else ""

    @Slot(result=bool)
    def startLocked(self) -> bool:
        return bool(self._config.data.get("lockScreen", True))

    @Slot(bool)
    def setLockScreen(self, enabled: bool) -> None:
        self._config.data["lockScreen"] = bool(enabled)
        self._save_timer.start()
        self.optionsChanged.emit()

    @Slot(result=int)
    def autoLockSeconds(self) -> int:
        try:
            return max(0, int(self._config.data.get("autoLockSeconds", 300)))
        except (TypeError, ValueError):
            return 300

    @Slot(int)
    def setAutoLockSeconds(self, seconds: int) -> None:
        self._config.data["autoLockSeconds"] = max(0, int(seconds))
        self._save_timer.start()
        self.optionsChanged.emit()

    @Slot(result="QVariant")
    def wallpaperCatalog(self) -> list[dict]:
        """Images available in assets/, for the settings picker."""
        assets = self._root / "assets"
        if not assets.is_dir():
            return []

        out: list[dict] = []
        for item in sorted(assets.iterdir()):
            if not item.is_file() or item.suffix.lower() not in WALLPAPER_EXTS:
                continue
            try:
                value = str(item.relative_to(self._root))
            except ValueError:
                value = str(item)
            out.append({"name": item.name, "value": value, "url": item.as_uri()})
        return out

    @Slot(result=str)
    def wallpaperMode(self) -> str:
        mode = str(self._config.data.get("wallpaperMode", "fill")).lower()
        return mode if mode in WALLPAPER_MODES else "fill"

    @Slot(str)
    def setWallpaper(self, value: str) -> None:
        """Select a wallpaper: a path (relative to the project) or "" for none."""
        value = (value or "").strip()
        if value.lower() == "auto":
            stored = "auto"
        elif value == "":
            stored = ""
        else:
            candidate = Path(value).expanduser()
            if not candidate.is_absolute():
                candidate = self._root / candidate
            candidate = candidate.resolve()
            if not candidate.is_file():
                log.warning("setWallpaper: %r not found", value)
                return
            try:
                stored = str(candidate.relative_to(self._root))
            except ValueError:
                stored = str(candidate)

        self._config.data["wallpaper"] = stored
        self._save_timer.start()
        self.wallpaperChanged.emit()

    @Slot(str)
    def setWallpaperMode(self, mode: str) -> None:
        mode = (mode or "").strip().lower()
        if mode not in WALLPAPER_MODES:
            log.warning("setWallpaperMode: unknown mode %r", mode)
            return
        self._config.data["wallpaperMode"] = mode
        self._save_timer.start()
        self.wallpaperChanged.emit()

    def _wallpaper_path(self) -> Path | None:
        raw = self._config.data.get("wallpaper", "auto")
        if isinstance(raw, str):
            value = raw.strip()
            if value.lower() in ("", "none"):
                return None          # explicit "no wallpaper"
            if value.lower() != "auto":
                candidate = Path(value).expanduser()
                if not candidate.is_absolute():
                    candidate = self._root / candidate
                candidate = candidate.resolve()
                if candidate.is_file():
                    return candidate
                log.warning("wallpaper %r not found — falling back", value)

        # missing / null / "auto": the drop-in convention
        assets = self._root / "assets"
        if assets.is_dir():
            for item in sorted(assets.iterdir()):
                if (item.is_file()
                        and item.stem.lower() == "wallpaper"
                        and item.suffix.lower() in WALLPAPER_EXTS):
                    return item
        return None

    # --------------------------------------------------------------- layout

    @Slot(str, int, int)
    def moveWidget(self, instance_id: str, x: int, y: int) -> None:
        widget = self._config.find_widget(instance_id)
        if widget is not None:
            cols, rows = self._config.grid["cols"], self._config.grid["rows"]
            w = self._int(widget.get("w"), 2, 1, cols)
            h = self._int(widget.get("h"), 2, 1, rows)
            nx = max(0, min(int(x), cols - w))
            ny = max(0, min(int(y), rows - h))
            page_id = str(widget.get("page") or self._config.main_page_id())
            if self._overlaps(widget, nx, ny, w, h, page_id):
                log.debug("move %s -> (%d,%d) rejected: overlaps another widget",
                          instance_id, nx, ny)
            else:
                self._config.set_widget_geometry(instance_id, nx, ny, w, h)
                self._save_timer.start()
        # Always notify: if the move was rejected the dragged widget snaps
        # back to its committed position.
        self._refresh()

    @Slot(str, int, int)
    def resizeWidget(self, instance_id: str, w: int, h: int) -> None:
        widget = self._config.find_widget(instance_id)
        if widget is not None:
            cols, rows = self._config.grid["cols"], self._config.grid["rows"]
            addon = self._addons.get(str(widget.get("addon", "")))
            min_w = addon.min_w if addon else 1
            min_h = addon.min_h if addon else 1
            x = self._int(widget.get("x"), 0, 0, cols - 1)
            y = self._int(widget.get("y"), 0, 0, rows - 1)
            nw = max(min_w, min(int(w), cols - x))
            nh = max(min_h, min(int(h), rows - y))
            page_id = str(widget.get("page") or self._config.main_page_id())
            if self._overlaps(widget, x, y, nw, nh, page_id):
                log.debug("resize %s -> %dx%d rejected: overlaps another widget",
                          instance_id, nw, nh)
            else:
                self._config.set_widget_geometry(instance_id, x, y, nw, nh)
                self._save_timer.start()
        self._refresh()

    @Slot(str)
    def removeWidget(self, instance_id: str) -> None:
        if self._config.remove_widget(instance_id):
            self._save_timer.start()
            self._refresh()

    @Slot(str, result=str)
    def addWidget(self, addon_id: str) -> str:
        """Place a new instance on the main widgets page (legacy entry point)."""
        return self.addWidgetToPage(addon_id, self._config.main_page_id())

    @Slot(str, str, result=str)
    def addWidgetToPage(self, addon_id: str, page_id: str) -> str:
        """Place a new instance of `addon_id` in the first free cell of a page.

        Returns the new instance id, or "" when the addon is unknown or the
        page has no room left.
        """
        addon = self._addons.get(addon_id)
        if addon is None:
            log.warning("addWidgetToPage: unknown addon %r", addon_id)
            return ""

        valid_pages = {str(page["id"]) for page in self._config.widget_pages}
        if page_id not in valid_pages:
            page_id = self._config.main_page_id()

        cols, rows = self._config.grid["cols"], self._config.grid["rows"]
        w = max(1, min(addon.def_w, cols))
        h = max(1, min(addon.def_h, rows))

        for y in range(rows - h + 1):
            for x in range(cols - w + 1):
                if not self._overlaps(None, x, y, w, h, page_id):
                    widget = self._config.add_widget(addon_id, x, y, w, h,
                                                     page_id)
                    self._save_timer.start()
                    self._refresh()
                    return str(widget["id"])

        log.warning("addWidgetToPage: no free space for %r on %r",
                    addon_id, page_id)
        return ""

    # ---------------------------------------------------------- widget pages

    @Slot(result="QVariant")
    def widgetPages(self) -> list[dict]:
        """Ordered widget pages, with a count of widgets on each."""
        counts: dict[str, int] = {}
        for widget in self._config.widgets:
            page_id = str(widget.get("page") or self._config.main_page_id())
            counts[page_id] = counts.get(page_id, 0) + 1
        return [
            {
                "id": str(page["id"]),
                "name": str(page.get("name") or page["id"]),
                "main": bool(page.get("main")),
                "widgetCount": counts.get(str(page["id"]), 0),
            }
            for page in self._config.widget_pages
        ]

    @Slot(str, bool, result=str)
    def addWidgetPage(self, relative_id: str, before: bool) -> str:
        page = self._config.add_widget_page(relative_id, before)
        self._save_timer.start()
        self._refresh()
        return str(page["id"])

    @Slot(str, int)
    def moveWidgetPage(self, page_id: str, direction: int) -> None:
        if self._config.move_widget_page(page_id, direction):
            self._save_timer.start()
            self._refresh()

    @Slot(str)
    def setMainWidgetPage(self, page_id: str) -> None:
        if self._config.set_main_widget_page(page_id):
            self._save_timer.start()
            self._refresh()

    @Slot(str, result=bool)
    def removeWidgetPage(self, page_id: str) -> bool:
        removed = self._config.remove_widget_page(page_id)
        if removed:
            self._save_timer.start()
            self._refresh()
        return removed

    @Slot(result="QVariant")
    def addonCatalog(self) -> list[dict]:
        """Installed addons, for the edit-mode picker."""
        return [
            {
                "id": addon.folder,
                "name": addon.name,
                "version": addon.version,
                "w": addon.def_w,
                "h": addon.def_h,
                "minW": addon.min_w,
                "minH": addon.min_h,
            }
            for addon in sorted(self._addons.values(), key=lambda a: a.name.lower())
        ]

    @Slot()
    def saveNow(self) -> None:
        """Flush pending writes (called on sheet close and app quit)."""
        if self._save_timer.isActive():
            self._save_timer.stop()
        self._config.save()

    # --------------------------------------------------------------- helpers

    def _refresh(self) -> None:
        self._model = self._build_model()
        self.layoutChanged.emit()

    @staticmethod
    def _int(value: Any, fallback: int, low: int, high: int) -> int:
        try:
            result = int(value)
        except (TypeError, ValueError):
            result = fallback
        return max(low, min(result, high))

    def _overlaps(self, ignore: dict | None, x: int, y: int, w: int, h: int,
                  page_id: str) -> bool:
        for other in self._config.widgets:
            if other is ignore:
                continue
            if str(other.get("page") or self._config.main_page_id()) != page_id:
                continue
            ox = self._int(other.get("x"), 0, 0, 999)
            oy = self._int(other.get("y"), 0, 0, 999)
            ow = self._int(other.get("w"), 1, 1, 999)
            oh = self._int(other.get("h"), 1, 1, 999)
            if x < ox + ow and x + w > ox and y < oy + oh and y + h > oy:
                return True
        return False
