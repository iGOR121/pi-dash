"""Addon discovery and manifest parsing.

An addon is a folder under addons/ containing:
    manifest.json   metadata + settings schema (see docs/addon-dev.md)
    <Entry>.qml     the widget UI, rooted on the shell's WidgetBase type

Folder name == addon id (the manifest's "id" field is ignored if different).
Folders starting with "." or "_" are skipped (reserves _template etc.).
"""
from __future__ import annotations

import json
import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

log = logging.getLogger("pi-dash.addon")

SETTING_TYPES = ("string", "bool", "int", "real")


@dataclass
class SettingSpec:
    """One user-configurable setting declared in a manifest."""

    key: str
    type: str = "string"  # string | bool | int | real
    label: str = ""
    default: Any = None

    @staticmethod
    def from_dict(data: dict) -> "SettingSpec":
        kind = str(data.get("type", "string")).lower()
        if kind not in SETTING_TYPES:
            log.warning("setting %r: unknown type %r — using string",
                        data.get("key"), kind)
            kind = "string"
        return SettingSpec(
            key=str(data.get("key", "")),
            type=kind,
            label=str(data.get("label", data.get("key", ""))),
            default=data.get("default"),
        )

    def as_dict(self) -> dict:
        return {
            "key": self.key,
            "type": self.type,
            "label": self.label,
            "default": self.default,
        }


@dataclass
class Addon:
    folder: str
    name: str
    version: str
    path: Path
    entry: str
    # Optional dashlet (full-page app) provided by this addon.
    app_entry: str = ""
    app_icon: str = ""
    app_description: str = ""
    author: str = ""
    min_w: int = 1
    min_h: int = 1
    def_w: int = 2
    def_h: int = 2
    settings: list[SettingSpec] = field(default_factory=list)

    @property
    def entry_url(self) -> str:
        return (self.path / self.entry).as_uri()

    @property
    def app_entry_url(self) -> str:
        return (self.path / self.app_entry).as_uri() if self.app_entry else ""

    def merged_settings(self, overrides: dict | None) -> dict:
        """Manifest defaults + per-instance overrides from dashboard.json."""
        merged = {s.key: s.default for s in self.settings}
        if overrides:
            merged.update(overrides)
        return merged

    def settings_schema(self) -> list[dict]:
        """Settings metadata for the auto-generated settings sheet (QML)."""
        return [spec.as_dict() for spec in self.settings]


def load_addon(folder: Path) -> Addon | None:
    manifest_path = folder / "manifest.json"
    try:
        data = json.loads(manifest_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        log.warning("addons/%s: no manifest.json — skipped", folder.name)
        return None
    except (json.JSONDecodeError, OSError) as exc:
        log.warning("addons/%s: bad manifest (%s) — skipped", folder.name, exc)
        return None

    entry = data.get("entry", "")
    if not entry or not (folder / entry).is_file():
        log.warning("addons/%s: entry %r not found — skipped", folder.name, entry)
        return None

    if data.get("id") and data["id"] != folder.name:
        log.warning(
            "addons/%s: manifest id %r ignored (folder name is the addon id)",
            folder.name,
            data["id"],
        )

    # Optional dashlet page (full-screen app) shipped with the addon.
    app_entry = str(data.get("app", "")).strip()
    if app_entry and not (folder / app_entry).is_file():
        log.warning("addons/%s: app entry %r not found — app hidden",
                    folder.name, app_entry)
        app_entry = ""

    min_size = data.get("minSize") or {}
    def_size = data.get("defaultSize") or {}

    def size_int(source: dict, key: str, fallback: int) -> int:
        try:
            return max(1, int(source.get(key, fallback)))
        except (TypeError, ValueError):
            return fallback

    return Addon(
        folder=folder.name,
        name=str(data.get("name", folder.name)),
        version=str(data.get("version", "0.0.0")),
        path=folder,
        entry=str(entry),
        app_entry=app_entry,
        app_icon=str(data.get("appIcon", "")),
        app_description=str(data.get("appDescription", "")),
        author=str(data.get("author", "")),
        min_w=size_int(min_size, "w", 1),
        min_h=size_int(min_size, "h", 1),
        def_w=size_int(def_size, "w", 2),
        def_h=size_int(def_size, "h", 2),
        settings=[
            SettingSpec.from_dict(s)
            for s in data.get("settings", [])
            if isinstance(s, dict) and s.get("key")
        ],
    )


def scan_addons(addons_dir: Path) -> dict[str, Addon]:
    """Return {addon_id: Addon} for every valid folder in addons_dir."""
    registry: dict[str, Addon] = {}
    if not addons_dir.is_dir():
        log.warning("addon directory %s does not exist", addons_dir)
        return registry

    for folder in sorted(addons_dir.iterdir()):
        if not folder.is_dir() or folder.name.startswith((".", "_")):
            continue
        addon = load_addon(folder)
        if addon is not None:
            registry[addon.folder] = addon
            log.info("addon %-12s v%-6s %s", addon.folder, addon.version, addon.name)
    return registry
