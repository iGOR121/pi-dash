"""dashboard.json handling: load, normalize, mutate, atomic save."""
from __future__ import annotations

import json
import logging
import os
from pathlib import Path
from typing import Any

log = logging.getLogger("pi-dash.config")

DEFAULT_COLS = 8
DEFAULT_ROWS = 5


def default_config() -> dict:
    """Fallback layout used when no dashboard.json exists yet."""
    return {
        "grid": {"cols": DEFAULT_COLS, "rows": DEFAULT_ROWS},
        # "auto" = use assets/wallpaper.*; "" = no wallpaper; or a path
        "wallpaper": "auto",
        "wallpaperMode": "fill",   # fill | align | stretch
        "lockScreen": True,
        "autoLockSeconds": 300,    # 0 = never auto-lock
        "widgetPages": [
            {"id": "main", "name": "Main", "main": True},
        ],
        "widgets": [
            {
                "id": "clock-main",
                "addon": "clock",
                "page": "main",
                "x": 0,
                "y": 0,
                "w": 3,
                "h": 2,
                "settings": {},
            }
        ],
    }


class Config:
    def __init__(self, path: Path):
        self.path = path
        self.data = self._load()
        changed = self._normalize()
        if changed or not self.path.exists():
            try:
                self.save()
            except OSError as exc:
                log.warning("could not write %s: %s", self.path, exc)

    def _load(self) -> dict:
        if self.path.exists():
            try:
                data = json.loads(self.path.read_text(encoding="utf-8"))
                if isinstance(data, dict):
                    return data
                log.warning("%s: root is not an object — using default", self.path)
            except (json.JSONDecodeError, OSError) as exc:
                log.warning("%s: %s — using default", self.path, exc)
        else:
            log.info("no config found, creating %s", self.path)

        return default_config()

    def _normalize(self) -> bool:
        """Coerce shapes the rest of the app relies on.

        Every widget gets a stable, unique string id; grid dimensions become
        positive ints. Returns True when anything was rewritten (so hand-edited
        files that omit ids get persisted after the first load).
        """
        changed = False

        widgets = self.data.get("widgets")
        if not isinstance(widgets, list):
            widgets = []
            self.data["widgets"] = widgets
            changed = True

        seen: set[str] = set()
        clean: list[dict] = []
        for index, widget in enumerate(widgets):
            if not isinstance(widget, dict):
                changed = True
                continue
            wid = str(widget.get("id") or f"w{index}")
            if wid != widget.get("id"):
                changed = True
            while wid in seen:
                wid += "_"
                changed = True
            seen.add(wid)
            widget["id"] = wid
            clean.append(widget)
        if len(clean) != len(widgets):
            changed = True
        self.data["widgets"] = clean

        # ---- widget pages (the vertical stack inside the widgets tab)
        raw_pages = self.data.get("widgetPages")
        if not isinstance(raw_pages, list):
            raw_pages = []
            changed = True

        seen_pages: set[str] = set()
        pages: list[dict] = []
        for index, page in enumerate(raw_pages):
            if not isinstance(page, dict):
                changed = True
                continue
            pid = str(page.get("id") or f"page-{index + 1}")
            if pid != page.get("id"):
                changed = True
            while pid in seen_pages:
                pid += "_"
                changed = True
            page["id"] = pid
            name = page.get("name")
            if not isinstance(name, str) or not name.strip():
                page["name"] = "Main" if index == 0 else f"Page {index + 1}"
                changed = True
            if not isinstance(page.get("main"), bool):
                page["main"] = False
                changed = True
            seen_pages.add(pid)
            pages.append(page)

        if not pages:
            pages = [{"id": "main", "name": "Main", "main": True}]
            seen_pages = {"main"}
            changed = True

        mains = [page for page in pages if page.get("main")]
        if not mains:
            pages[0]["main"] = True
            changed = True
        else:
            for page in mains[1:]:
                page["main"] = False
                changed = True

        self.data["widgetPages"] = pages
        main_id = next(page["id"] for page in pages if page.get("main"))
        for widget in clean:
            page_id = widget.get("page")
            if not isinstance(page_id, str) or page_id not in seen_pages:
                widget["page"] = main_id
                changed = True

        grid = self.data.get("grid")
        if not isinstance(grid, dict):
            grid = {}
            self.data["grid"] = grid
            changed = True
        for key, fallback in (("cols", DEFAULT_COLS), ("rows", DEFAULT_ROWS)):
            try:
                value = max(1, int(grid.get(key, fallback)))
            except (TypeError, ValueError):
                value = fallback
            if grid.get(key) != value:
                changed = True
            grid[key] = value

        return changed

    @property
    def grid(self) -> dict:
        grid = self.data.get("grid") or {}
        try:
            return {"cols": int(grid.get("cols", DEFAULT_COLS)),
                    "rows": int(grid.get("rows", DEFAULT_ROWS))}
        except (TypeError, ValueError):
            return {"cols": DEFAULT_COLS, "rows": DEFAULT_ROWS}

    @property
    def widgets(self) -> list[dict]:
        widgets = self.data.get("widgets")
        if isinstance(widgets, list):
            return [w for w in widgets if isinstance(w, dict)]
        return []

    # ------------------------------------------------------------ pages

    def _page_list(self) -> list[dict]:
        """The live page list (mutations must affect dashboard.json)."""
        pages = self.data.get("widgetPages")
        if not isinstance(pages, list):
            pages = [{"id": "main", "name": "Main", "main": True}]
            self.data["widgetPages"] = pages
        return pages

    @property
    def widget_pages(self) -> list[dict]:
        return self._page_list()

    def find_page(self, page_id: str) -> dict | None:
        for page in self._page_list():
            if page.get("id") == page_id:
                return page
        return None

    def main_page_id(self) -> str:
        pages = self._page_list()
        for page in pages:
            if page.get("main"):
                return str(page["id"])
        return str(pages[0]["id"]) if pages else "main"

    def widget_count(self, page_id: str) -> int:
        return sum(1 for widget in self.widgets
                   if str(widget.get("page")) == page_id)

    def add_widget_page(self, relative_id: str = "", before: bool = False) -> dict:
        pages = self._page_list()
        used = {str(page["id"]) for page in pages}
        number = 1
        while f"page-{number}" in used:
            number += 1
        page = {
            "id": f"page-{number}",
            "name": f"Page {len(pages) + 1}",
            "main": False,
        }
        index = len(pages)
        if relative_id:
            for position, existing in enumerate(pages):
                if existing.get("id") == relative_id:
                    index = position if before else position + 1
                    break
        pages.insert(index, page)
        return page

    def move_widget_page(self, page_id: str, direction: int) -> bool:
        pages = self._page_list()
        index = next((i for i, page in enumerate(pages)
                      if page.get("id") == page_id), -1)
        target = index + (1 if direction > 0 else -1)
        if index < 0 or target < 0 or target >= len(pages):
            return False
        pages[index], pages[target] = pages[target], pages[index]
        return True

    def set_main_widget_page(self, page_id: str) -> bool:
        pages = self._page_list()
        if not any(page.get("id") == page_id for page in pages):
            return False
        for page in pages:
            page["main"] = page.get("id") == page_id
        return True

    def remove_widget_page(self, page_id: str) -> bool:
        pages = self._page_list()
        if len(pages) <= 1:
            return False
        page = self.find_page(page_id)
        if page is None or self.widget_count(page_id) > 0:
            return False
        was_main = bool(page.get("main"))
        pages.remove(page)
        if was_main:
            pages[0]["main"] = True
        return True

    # ------------------------------------------------------------- mutation

    def find_widget(self, instance_id: str) -> dict | None:
        for widget in self.widgets:
            if widget.get("id") == instance_id:
                return widget
        return None

    def set_widget_setting(self, instance_id: str, key: str, value: Any) -> None:
        widget = self.find_widget(instance_id)
        if widget is None:
            log.warning("set_widget_setting: unknown instance id %r", instance_id)
            return
        settings = widget.get("settings")
        if not isinstance(settings, dict):
            settings = {}
            widget["settings"] = settings
        settings[key] = value

    def set_widget_geometry(self, instance_id: str, x: int, y: int, w: int, h: int) -> bool:
        widget = self.find_widget(instance_id)
        if widget is None:
            return False
        widget.update({"x": x, "y": y, "w": w, "h": h})
        return True

    def remove_widget(self, instance_id: str) -> bool:
        widgets = self.data.get("widgets")
        if not isinstance(widgets, list):
            return False
        for index, widget in enumerate(widgets):
            if isinstance(widget, dict) and widget.get("id") == instance_id:
                del widgets[index]
                return True
        return False

    def add_widget(self, addon_id: str, x: int, y: int, w: int, h: int,
                   page_id: str = "") -> dict:
        """Append a widget instance and return it (id is unique and stable)."""
        widgets = self.data.get("widgets")
        if not isinstance(widgets, list):
            widgets = []
            self.data["widgets"] = widgets

        used = {str(w.get("id")) for w in widgets if isinstance(w, dict)}
        number = 1
        while f"{addon_id}-{number}" in used:
            number += 1

        widget = {
            "id": f"{addon_id}-{number}",
            "addon": addon_id,
            "page": page_id or self.main_page_id(),
            "x": x,
            "y": y,
            "w": w,
            "h": h,
            "settings": {},
        }
        widgets.append(widget)
        return widget

    # ----------------------------------------------------------------- save

    def save(self) -> None:
        """Atomic write: never leaves a half-written dashboard.json behind."""
        self.path.parent.mkdir(parents=True, exist_ok=True)
        tmp = self.path.with_name(self.path.name + ".tmp")
        tmp.write_text(
            json.dumps(self.data, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        os.replace(tmp, self.path)
        log.debug("saved %s", self.path)
