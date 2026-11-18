"""Bluetooth settings for Raspberry Pi OS (BlueZ + PipeWire/WirePlumber).

Talks to BlueZ through `bluetoothctl` and to the user's audio session through
`wpctl`/`pw-dump`. The codec/role preferences are written to the user's
WirePlumber config:

    ~/.config/wireplumber/wireplumber.conf.d/51-pi-dash-bluez.conf

Both A2DP roles are enabled (the Pi can send audio to headphones and act as
a speaker for a phone) plus HFP for headsets. HID devices (keyboards, mice)
are just BlueZ pair/trust/connect operations.

No root privileges are needed: BlueZ allows the session user to manage the
adapter, and WirePlumber reads per-user configuration.
"""
from __future__ import annotations

import glob
import json
import logging
import os
import pwd
import re
import shutil
import subprocess
import threading
import time
from pathlib import Path

from PySide6.QtCore import Property, QObject, QTimer, Signal, Slot

log = logging.getLogger("pi-dash.bluetooth")

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")

CODECS = [
    {"id": "sbc", "label": "SBC", "mandatory": True, "plugin": "sbc"},
    {"id": "sbc_xq", "label": "SBC-XQ", "mandatory": False, "plugin": "sbc"},
    {"id": "aac", "label": "AAC", "mandatory": False, "plugin": "aac"},
    {"id": "aptx", "label": "aptX", "mandatory": False, "plugin": "aptx"},
    {"id": "aptx_hd", "label": "aptX HD", "mandatory": False, "plugin": "aptx"},
    {"id": "ldac", "label": "LDAC", "mandatory": False, "plugin": "ldac"},
    {"id": "opus_05", "label": "Opus 05", "mandatory": False, "plugin": "opus"},
    {"id": "faststream", "label": "FastStream", "mandatory": False,
     "plugin": "faststream"},
]
DEFAULT_CODECS = ["sbc", "sbc_xq", "aac", "aptx", "aptx_hd", "ldac"]
ROLES = "[ a2dp_sink a2dp_source hfp_hf hfp_ag ]"

CONFIG_PATH = Path(
    ".config/wireplumber/wireplumber.conf.d/51-pi-dash-bluez.conf")


def _clean(text: str) -> str:
    return ANSI.sub("", text or "").strip()


def _home() -> Path:
    try:
        return Path(pwd.getpwuid(os.getuid()).pw_dir)
    except KeyError:
        return Path.home()


class BluetoothService(QObject):
    stateChanged = Signal()

    def __init__(self, parent: QObject | None = None, manage_agent: bool = True):
        super().__init__(parent)
        self._ctl = shutil.which("bluetoothctl")
        self._wpctl = shutil.which("wpctl")
        self._pwdump = shutil.which("pw-dump")
        self._env = self._session_env()
        # A persistent NoInputNoOutput agent accepts incoming pairing (needed
        # when a phone pairs with the Pi in speaker mode). Dev tools opt out.
        self._manage_agent = manage_agent
        self._agent_proc: subprocess.Popen | None = None

        self._adapter: dict = {"present": False}
        self._paired: list[dict] = []
        self._nearby: list[dict] = []
        self._scanning = False
        self._busy = False
        self._refreshing = False
        self._message = "" if self._ctl else "bluetoothctl is not installed"

        self._codec_catalog = self._build_catalog()
        self._codecs = self._read_codecs()

        self._codec_map: dict[str, str] = {}
        self._profile_map: dict[str, str] = {}
        self._output_nodes: dict[str, int] = {}

        self._ensure_agent()
        self._timer = QTimer(self)
        self._timer.setInterval(20000)
        self._timer.timeout.connect(self.requestRefresh)
        self._timer.start()
        self.requestRefresh()

    # ------------------------------------------------------------- properties

    def _get_available(self) -> bool:
        return bool(self._ctl)

    available = Property(bool, _get_available, notify=stateChanged)

    def _get_adapter(self) -> dict:
        return dict(self._adapter)

    adapter = Property("QVariant", _get_adapter, notify=stateChanged)

    def _get_paired(self) -> list:
        return list(self._paired)

    paired = Property("QVariant", _get_paired, notify=stateChanged)

    def _get_nearby(self) -> list:
        return list(self._nearby)

    nearby = Property("QVariant", _get_nearby, notify=stateChanged)

    def _get_scanning(self) -> bool:
        return self._scanning

    scanning = Property(bool, _get_scanning, notify=stateChanged)

    def _get_busy(self) -> bool:
        return self._busy

    busy = Property(bool, _get_busy, notify=stateChanged)

    def _get_message(self) -> str:
        return self._message

    message = Property(str, _get_message, notify=stateChanged)

    def _get_codecs(self) -> list:
        return list(self._codecs)

    codecs = Property("QVariant", _get_codecs, notify=stateChanged)

    def _get_codec_catalog(self) -> list:
        return [dict(item) for item in self._codec_catalog]

    codecCatalog = Property("QVariant", _get_codec_catalog, notify=stateChanged)

    # --------------------------------------------------------------- helpers

    @staticmethod
    def _session_env() -> dict:
        env = os.environ.copy()
        runtime = Path(f"/run/user/{os.getuid()}")
        if runtime.is_dir():
            env.setdefault("XDG_RUNTIME_DIR", str(runtime))
            env.setdefault("DBUS_SESSION_BUS_ADDRESS",
                           f"unix:path={runtime}/bus")
        return env

    @staticmethod
    def parse_adapter(text: str) -> dict:
        info: dict = {}
        for raw in text.splitlines():
            line = _clean(raw)
            controller = re.match(r"^Controller\s+(\S+)", line)
            if controller:
                info["address"] = controller.group(1)
                continue
            match = re.match(r"^(Address|Name|Alias|Powered|"
                             r"Discoverable|Pairable):\s*(.*)$",
                             line)
            if not match:
                continue
            key, value = match.group(1), match.group(2).strip()
            if key == "Powered":
                info["powered"] = value.lower() == "yes"
            elif key == "Discoverable":
                info["discoverable"] = value.lower() == "yes"
            elif key == "Pairable":
                info["pairable"] = value.lower() == "yes"
            elif key == "Name":
                info["name"] = value
            elif key == "Alias":
                info["alias"] = value
            elif key == "Address":
                info["address"] = value
        info["present"] = bool(info.get("address"))
        return info

    @staticmethod
    def parse_info(text: str) -> dict:
        info: dict = {"uuids": []}
        for raw in text.splitlines():
            line = _clean(raw)
            if line.startswith("UUID:"):
                info["uuids"].append(line)
                continue
            match = re.match(r"^(Name|Alias|Address|Paired|Bonded|Trusted|"
                             r"Connected|Icon|Blocked):\s*(.*)$", line)
            if not match:
                continue
            key, value = match.group(1), match.group(2).strip()
            if key in ("Paired", "Trusted", "Connected", "Bonded", "Blocked"):
                info[key.lower()] = value.lower() == "yes"
            else:
                info[key.lower()] = value

        uuids = " ".join(info["uuids"]).lower()
        icon = str(info.get("icon", ""))
        if (icon.startswith("input-") or "00001812" in uuids):
            info["kind"] = "hid"
        elif (icon.startswith("audio-") or icon == "phone"
              or any(u in uuids for u in ("0000110b", "0000110a",
                                          "0000111e", "00001108"))):
            info["kind"] = "audio"
        else:
            info["kind"] = "other"
        info["phone"] = icon == "phone"
        return info

    @staticmethod
    def parse_codecs(text: str) -> list:
        match = re.search(r"bluez5\.codecs\s*=\s*\[([^\]]*)\]", text)
        if not match:
            return []
        known = {c["id"] for c in CODECS}
        return [token for token in match.group(1).split() if token in known]

    def _build_catalog(self) -> list:
        plugin_dirs = glob.glob("/usr/lib*/**/spa-0.2/bluez5", recursive=True)
        plugins: set[str] = set()
        for folder in plugin_dirs:
            try:
                plugins.update(item.name for item in Path(folder).iterdir())
            except OSError:
                pass
        detected = bool(plugins)

        catalog = []
        for codec in CODECS:
            supported = True
            if detected:
                supported = any(codec["plugin"] in name for name in plugins)
            if codec["id"] == "sbc_xq":
                supported = supported or any("sbc" in name for name in plugins)
            catalog.append({
                "id": codec["id"],
                "label": codec["label"],
                "mandatory": codec["mandatory"],
                "supported": supported,
            })
        return catalog

    def _ensure_agent(self) -> None:
        if not self._manage_agent or not self._ctl:
            return
        if self._agent_proc is not None and self._agent_proc.poll() is None:
            return
        try:
            self._agent_proc = subprocess.Popen(
                [self._ctl, "--agent", "NoInputNoOutput"],
                stdin=subprocess.PIPE,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                env=self._env,
            )
        except OSError:
            self._agent_proc = None

    def _config_path(self) -> Path:
        return _home() / CONFIG_PATH

    def _supported_codec_ids(self) -> set[str]:
        return {item["id"] for item in self._codec_catalog if item["supported"]}

    def _read_codecs(self) -> list:
        try:
            text = self._config_path().read_text(encoding="utf-8",
                                                 errors="replace")
        except OSError:
            text = ""
        selected = self.parse_codecs(text)
        supported = self._supported_codec_ids()
        selected = [codec for codec in selected if codec in supported]
        if not selected:
            selected = [c["id"] for c in self._codec_catalog
                        if c["supported"] and c["id"] in DEFAULT_CODECS]
        if "sbc" not in selected:
            selected.insert(0, "sbc")
        return selected

    # --------------------------------------------------------------- commands

    def _run(self, args: list[str], timeout: float = 8.0) -> subprocess.CompletedProcess:
        if not self._ctl:
            raise RuntimeError("bluetoothctl is not installed")
        return subprocess.run(
            [self._ctl, *args],
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout,
            env=self._env,
        )

    @staticmethod
    def _failure_text(result: subprocess.CompletedProcess) -> str:
        text = _clean((result.stdout or "") + "\n" + (result.stderr or ""))
        lines = [line for line in text.splitlines() if line.strip()]
        return lines[-1] if lines else "Bluetooth operation failed"

    # --------------------------------------------------------------- refresh

    @Slot()
    def requestRefresh(self) -> None:
        if self._refreshing or not self._ctl:
            return
        self._refreshing = True
        threading.Thread(target=self._refresh_worker, daemon=True).start()

    def _refresh_worker(self) -> None:
        try:
            self.refresh()
        finally:
            self._refreshing = False

    @Slot()
    def refresh(self) -> None:
        self._ensure_agent()
        if not self._ctl:
            self._adapter = {"present": False}
            self._paired = []
            self.stateChanged.emit()
            return

        try:
            show = self._run(["show"], timeout=6)
            self._adapter = self.parse_adapter(show.stdout)
        except (subprocess.TimeoutExpired, OSError):
            self._adapter = {"present": False}
        except RuntimeError:
            self._adapter = {"present": False}

        paired: list[dict] = []
        if self._adapter.get("present"):
            try:
                listing = self._run(["devices", "Paired"], timeout=6)
                for line in listing.stdout.splitlines():
                    parts = _clean(line).split(" ", 2)
                    if len(parts) != 3 or parts[0] != "Device":
                        continue
                    address, listed_name = parts[1], parts[2].strip()
                    info = self._device_info(address, listed_name)
                    if info:
                        paired.append(info)
            except (subprocess.TimeoutExpired, OSError, RuntimeError):
                paired = []

        paired.sort(key=lambda d: (not d.get("connected"), d["name"].lower()))

        # audio details are only needed when something audio-related is
        # connected, and pw-dump can be large
        if any(d.get("kind") == "audio" and d.get("connected") for d in paired):
            self._read_audio()
        else:
            self._codec_map = {}
            self._profile_map = {}
            self._output_nodes = {}

        for device in paired:
            device["codec"] = self._codec_map.get(device["address"], "")
            device["profile"] = self._profile_map.get(device["address"], "")
            device["output"] = device["address"] in self._output_nodes

        self._paired = paired
        self.stateChanged.emit()

    def _device_info(self, address: str, listed_name: str) -> dict | None:
        try:
            result = self._run(["info", address], timeout=6)
        except (subprocess.TimeoutExpired, OSError):
            return None
        if result.returncode != 0:
            return None
        info = self.parse_info(result.stdout)
        return {
            "address": address,
            "name": info.get("name") or info.get("alias") or listed_name or address,
            "connected": info.get("connected", False),
            "trusted": info.get("trusted", False),
            "paired": info.get("paired", False),
            "icon": info.get("icon", ""),
            "kind": info.get("kind", "other"),
            "phone": info.get("phone", False),
            "codec": "",
            "profile": "",
            "output": False,
        }

    def _read_audio(self) -> None:
        if not self._pwdump:
            return
        try:
            result = subprocess.run([self._pwdump], capture_output=True,
                                    text=True, timeout=10, env=self._env)
            data = json.loads(result.stdout or "[]")
        except (subprocess.TimeoutExpired, OSError, ValueError):
            return

        codecs: dict[str, str] = {}
        profiles: dict[str, str] = {}
        outputs: dict[str, int] = {}
        for obj in data:
            if not isinstance(obj, dict):
                continue
            props = (obj.get("info") or {}).get("props") or {}
            address = props.get("api.bluez5.address") or props.get("device.string")
            node_name = str(props.get("node.name", ""))
            if not address:
                match = re.match(r"bluez_(?:output|input)\.([0-9A-Fa-f_]+)",
                                 node_name)
                if match:
                    address = match.group(1)
            if not address:
                continue
            address = str(address).upper().replace("_", ":")
            codec = props.get("api.bluez5.codec")
            profile = props.get("api.bluez5.profile")
            if codec:
                codecs[address] = str(codec)
            if profile:
                profiles[address] = str(profile)
            media = str(props.get("media.class", ""))
            if media == "Audio/Sink" and node_name.startswith("bluez_output"):
                outputs[address] = int(obj.get("id", -1))

        self._codec_map = codecs
        self._profile_map = profiles
        self._output_nodes = outputs

    # ---------------------------------------------------------------- actions

    def _action(self, description: str, func) -> None:
        if self._busy:
            return
        self._busy = True
        self._message = description
        self.stateChanged.emit()

        def worker():
            try:
                func()
            except subprocess.TimeoutExpired:
                self._message = "Timed out — is the device in pairing mode?"
            except Exception as exc:  # noqa: BLE001 - surface to the UI
                self._message = str(exc)
            finally:
                self._busy = False
                try:
                    self.refresh()
                except Exception:  # noqa: BLE001
                    log.exception("refresh after a Bluetooth action failed")
                self.stateChanged.emit()

        threading.Thread(target=worker, daemon=True).start()

    @Slot()
    def scan(self) -> None:
        if self._scanning or not self._ctl or not self._adapter.get("present"):
            return
        self._scanning = True
        self._nearby = []
        self._message = "Scanning for nearby devices…"
        self.stateChanged.emit()

        def worker():
            proc = None
            try:
                proc = subprocess.Popen(
                    [self._ctl, "--timeout", "12", "scan", "on"],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                    env=self._env)
                while proc.poll() is None:
                    self._update_nearby()
                    time.sleep(1.5)
                self._update_nearby()
                self._message = "Scan finished"
            except Exception as exc:  # noqa: BLE001
                self._message = f"Scan failed: {exc}"
            finally:
                if proc is not None and proc.poll() is None:
                    proc.terminate()
                self._scanning = False
                self.stateChanged.emit()

        threading.Thread(target=worker, daemon=True).start()

    def _update_nearby(self) -> None:
        paired = {d["address"] for d in self._paired}
        found: dict[str, str] = {}
        try:
            result = self._run(["devices"], timeout=5)
        except (subprocess.TimeoutExpired, OSError, RuntimeError):
            return
        for line in result.stdout.splitlines():
            parts = _clean(line).split(" ", 2)
            if len(parts) != 3 or parts[0] != "Device":
                continue
            address, name = parts[1], parts[2].strip()
            if address in paired or not name:
                continue
            # skip BlueZ's placeholder names for unnamed devices
            compact = name.replace("-", "").replace(":", "").upper()
            if compact == address.replace(":", "").upper():
                continue
            found[address] = name
        self._nearby = [
            {"address": address, "name": name}
            for address, name in sorted(found.items(), key=lambda item: item[1].lower())
        ]
        self.stateChanged.emit()

    @Slot(str)
    def pair(self, address: str) -> None:
        def work():
            # --agent registers a NoInputNoOutput agent for this invocation
            # (Just Works). Passkey-only devices report an error instead of
            # leaving the pairing half-done.
            try:
                result = subprocess.run(
                    [self._ctl, "--agent", "NoInputNoOutput",
                     "--timeout", "35", "pair", address],
                    capture_output=True, text=True, errors="replace",
                    timeout=45, env=self._env)
            except subprocess.TimeoutExpired as exc:
                raise RuntimeError("Pairing timed out") from exc

            after = self._device_info(address, address)
            name = (after or {}).get("name") or address
            if not after or not (after.get("paired") or after.get("connected")):
                text = _clean((result.stdout or "") + "\n" + (result.stderr or ""))
                failure = BluetoothService._failure_text(result)
                if "passkey" in text.lower() or "authentication" in text.lower():
                    failure += (" — this device may require an interactive "
                                "pairing code")
                raise RuntimeError(failure)

            self._run(["trust", address], timeout=10)
            try:
                self._run(["connect", address], timeout=25)
            except (subprocess.TimeoutExpired, OSError, RuntimeError) as exc:
                log.warning("paired %s but connect failed: %s", address, exc)

            after = self._device_info(address, address) or after
            if after.get("connected"):
                self._message = f"Paired and connected to {name}"
            else:
                self._message = f"Paired {name} (not connected)"

        self._action(f"Pairing {address}…", work)

    @Slot(str)
    def connectDevice(self, address: str) -> None:
        def work():
            result = self._run(["connect", address], timeout=25)
            if result.returncode != 0:
                raise RuntimeError(BluetoothService._failure_text(result))
            self._message = "Connected"

        self._action(f"Connecting {address}…", work)

    @Slot(str)
    def disconnectDevice(self, address: str) -> None:
        def work():
            result = self._run(["disconnect", address], timeout=15)
            if result.returncode != 0:
                raise RuntimeError(BluetoothService._failure_text(result))
            self._message = "Disconnected"

        self._action(f"Disconnecting {address}…", work)

    @Slot(str)
    def forget(self, address: str) -> None:
        def work():
            result = self._run(["remove", address], timeout=10)
            if result.returncode != 0:
                raise RuntimeError(BluetoothService._failure_text(result))
            self._message = "Device removed"

        self._action(f"Removing {address}…", work)

    @Slot(bool)
    def setPowered(self, enabled: bool) -> None:
        def work():
            result = self._run(["power", "on" if enabled else "off"], timeout=10)
            if result.returncode != 0:
                raise RuntimeError(BluetoothService._failure_text(result))
            self._message = "Bluetooth on" if enabled else "Bluetooth off"

        self._action("Updating adapter…", work)

    @Slot(bool)
    def setDiscoverable(self, enabled: bool) -> None:
        def work():
            result = self._run(["discoverable", "on" if enabled else "off"],
                               timeout=10)
            if result.returncode != 0:
                raise RuntimeError(BluetoothService._failure_text(result))
            self._message = ("Visible to nearby devices" if enabled
                             else "Not discoverable")

        self._action("Updating visibility…", work)

    @Slot(bool)
    def setPairable(self, enabled: bool) -> None:
        def work():
            result = self._run(["pairable", "on" if enabled else "off"],
                               timeout=10)
            if result.returncode != 0:
                raise RuntimeError(BluetoothService._failure_text(result))
            self._message = "Pairable" if enabled else "Pairing disabled"

        self._action("Updating pairing…", work)

    @Slot(str)
    def setAlias(self, name: str) -> None:
        name = (name or "").strip()
        if not name:
            return

        def work():
            result = self._run(["system-alias", name], timeout=10)
            if result.returncode != 0:
                raise RuntimeError(BluetoothService._failure_text(result))
            self._message = "Adapter name applied"

        self._action(f'Renaming adapter to "{name}"…', work)

    @Slot(str)
    def useAsOutput(self, address: str) -> None:
        def work():
            self._read_audio()
            node = self._output_nodes.get(address.upper())
            if node is None or node < 0:
                raise RuntimeError(
                    "No audio output found — connect the device first.")
            if not self._wpctl:
                raise RuntimeError("wpctl is not installed")
            result = subprocess.run(
                [self._wpctl, "set-default", str(node)],
                capture_output=True, text=True, errors="replace",
                timeout=8, env=self._env)
            if result.returncode != 0:
                raise RuntimeError(BluetoothService._failure_text(result))
            self._message = "Audio output set"

        self._action("Setting audio output…", work)

    # ---------------------------------------------------------------- codecs

    @Slot("QVariant")
    def applyCodecs(self, codecs) -> None:
        selected = []
        if isinstance(codecs, list):
            known = self._supported_codec_ids()
            for item in codecs:
                if str(item) in known and str(item) not in selected:
                    selected.append(str(item))
        if "sbc" not in selected:
            selected.insert(0, "sbc")

        def work():
            path = self._config_path()
            path.parent.mkdir(parents=True, exist_ok=True)
            body = (
                "# Managed by pi-dash Bluetooth settings\n"
                "monitor.bluez.properties = {\n"
                f"  bluez5.roles = {ROLES}\n"
                f"  bluez5.codecs = [ {' '.join(selected)} ]\n"
                f"  bluez5.enable-sbc-xq = "
                f"{'true' if 'sbc_xq' in selected else 'false'}\n"
                "  bluez5.enable-msbc = true\n"
                "  bluez5.enable-hw-volume = true\n"
                "}\n"
            )
            path.write_text(body, encoding="utf-8")
            self._codecs = selected

            systemctl = shutil.which("systemctl")
            if not systemctl:
                self._message = "Codecs saved; reboot to apply"
                return
            result = subprocess.run(
                [systemctl, "--user", "restart", "wireplumber"],
                capture_output=True, text=True, errors="replace",
                timeout=20, env=self._env)
            if result.returncode == 0:
                self._message = "Codecs applied — audio devices reconnect"
            else:
                self._message = ("Codecs saved, but WirePlumber restart failed "
                                 "— restart the desktop session or reboot.")

        self._action("Applying codecs…", work)

    # ---------------------------------------------------------------- cleanup

    @Slot()
    def stop(self) -> None:
        self._timer.stop()
        proc = self._agent_proc
        self._agent_proc = None
        if proc is not None:
            try:
                proc.terminate()
            except OSError:
                pass
            try:
                proc.wait(timeout=2)
            except subprocess.TimeoutExpired:
                proc.kill()
