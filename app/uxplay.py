"""UxPlay (AirPlay) integration.

UxPlay runs as a subprocess. We start it with:

  * -md <file>   : receives audio-mode metadata (title/artist/album) as text
  * -ca <file>   : exports cover art
  * -vrtp <pipe> : forwards the mirrored H.264 video as RTP instead of
                   rendering it itself

A second `gst-launch-1.0` process receives that RTP stream, decodes it and
writes raw RGB frames to stdout; a reader thread wraps each frame in a QImage
which QML displays fullscreen (see shell/CastOverlay.qml). Audio is still
played by UxPlay itself.

Everything is optional: if `uxplay` or `gst-launch-1.0` is missing the service
starts/reports an error instead of crashing, and audio-only AirPlay still
works (metadata + notifications, no cast overlay).
"""
from __future__ import annotations

import logging
import shlex
import shutil
import subprocess
import tempfile
import threading
import time
from collections import deque
from pathlib import Path

from PySide6.QtCore import Property, QObject, QTimer, Signal, Slot
from PySide6.QtGui import QImage
from PySide6.QtQuick import QQuickImageProvider

log = logging.getLogger("pi-dash.uxplay")

FRAME_W = 640
FRAME_H = 360
FRAME_BYTES = FRAME_W * FRAME_H * 3
VIDEO_IDLE_SECONDS = 1.5


class CastFrameProvider(QQuickImageProvider):
    """Serves the newest decoded frame as image://cast/frame?<tick>."""

    def __init__(self, service: "UxPlayService"):
        super().__init__(QQuickImageProvider.Image)
        self._service = service

    def requestImage(self, image_id, size, requested_size):
        image = self._service.latest_frame()
        if image is None:
            image = QImage(2, 2, QImage.Format_RGBA8888)
            image.fill(0)
        return image


class UxPlayService(QObject):
    stateChanged = Signal()
    frameReady = Signal()
    runningChanged = Signal()
    videoChanged = Signal()
    metadataChanged = Signal()

    def __init__(self, host, parent: QObject | None = None):
        super().__init__(parent)
        self._host = host
        self._proc: subprocess.Popen | None = None
        self._receiver: subprocess.Popen | None = None
        self._threads: list[threading.Thread] = []
        self._lock = threading.Lock()

        self._frame: QImage | None = None
        self._last_frame = 0.0
        self._video_active = False
        self._running = False

        self._now: dict = {}
        self._last_track: tuple | None = None
        self._last_error = ""
        self._logs: deque[str] = deque(maxlen=100)

        tmp = Path(tempfile.gettempdir())
        self._meta_path = tmp / "pi-dash-uxplay-metadata.txt"
        self._cover_path = tmp / "pi-dash-uxplay-cover.jpg"
        self._cover_version = 0

        self._poll_timer = QTimer(self)
        self._poll_timer.setInterval(1000)
        self._poll_timer.timeout.connect(self._poll_metadata)

        self._video_timer = QTimer(self)
        self._video_timer.setInterval(1000)
        self._video_timer.timeout.connect(self._check_video)

    # ----------------------------------------------------------- properties

    def _get_running(self) -> bool:
        return self._running

    running = Property(bool, _get_running, notify=runningChanged)

    def _get_video(self) -> bool:
        return self._video_active

    videoActive = Property(bool, _get_video, notify=videoChanged)

    def _get_now(self) -> dict:
        return dict(self._now)

    nowPlaying = Property("QVariant", _get_now, notify=metadataChanged)

    def _get_error(self) -> str:
        return self._last_error

    lastError = Property(str, _get_error, notify=stateChanged)

    def _get_cover(self) -> str:
        if not self._cover_path.is_file():
            return ""
        try:
            version = self._cover_path.stat().st_mtime_ns
        except OSError:
            version = 0
        return f"{self._cover_path.as_uri()}?v={version}"

    coverUrl = Property(str, _get_cover, notify=metadataChanged)

    # --------------------------------------------------------------- control

    @Slot(result=bool)
    def start(self) -> bool:
        if self._running:
            return True

        opts: dict = {}
        try:
            opts = self._host.appSettings("uxplay") or {}
        except Exception:  # noqa: BLE001 - never crash the UI over settings
            log.exception("could not read uxplay settings")

        binary = str(opts.get("binary") or "uxplay").strip() or "uxplay"
        name = str(opts.get("serverName") or "pi-dash").strip() or "pi-dash"
        try:
            port = max(1024, min(65535, int(opts.get("videoPort") or 5010)))
        except (TypeError, ValueError):
            port = 5010
        extra = str(opts.get("extraArgs") or "")

        self._last_error = ""
        self._now = {}
        self._last_track = None
        self._cover_version = 0
        for path in (self._meta_path, self._cover_path):
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass
        self.metadataChanged.emit()

        if not shutil.which(binary):
            self._last_error = (
                f"'{binary}' was not found. Install UxPlay first "
                "(on Raspberry Pi OS / Debian: sudo apt install uxplay).")
            self.stateChanged.emit()
            return False

        cmd = [
            binary,
            "-n", name,
            "-md", str(self._meta_path),
            "-ca", str(self._cover_path),
            "-vrtp", f"config-interval=1 ! udpsink host=127.0.0.1 port={port}",
        ]
        if extra.strip():
            cmd.extend(shlex.split(extra))

        try:
            self._proc = subprocess.Popen(
                cmd,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                errors="replace",
                bufsize=1,
            )
        except OSError as exc:
            self._last_error = f"could not start UxPlay: {exc}"
            self.stateChanged.emit()
            return False

        self._running = True
        self.runningChanged.emit()
        self.stateChanged.emit()

        self._threads = [threading.Thread(target=self._read_log, daemon=True)]
        gst = shutil.which("gst-launch-1.0")
        if gst:
            self._start_receiver(gst, port)
        else:
            self._last_error = (
                "gst-launch-1.0 not found — video will not appear in the app "
                "(audio/metadata still work).")
            self.stateChanged.emit()

        for thread in self._threads:
            thread.start()

        self._poll_timer.start()
        self._video_timer.start()
        log.info("UxPlay started (video port %d)", port)
        return True

    @Slot()
    def stop(self) -> None:
        self._poll_timer.stop()
        self._video_timer.stop()
        self._running = False

        proc = self._proc
        self._proc = None
        if proc is not None:
            try:
                proc.terminate()
            except OSError:
                pass
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()

        self._stop_receiver()

        self._frame = None
        self._video_active = False
        self._now = {}
        self._last_track = None
        self._last_error = ""
        self._cover_version = 0
        self.runningChanged.emit()
        self.videoChanged.emit()
        self.metadataChanged.emit()
        self.stateChanged.emit()

        for path in (self._meta_path, self._cover_path):
            try:
                path.unlink(missing_ok=True)
            except OSError:
                pass
        log.info("UxPlay stopped")

    def _fail_running(self, message: str) -> None:
        if not self._running:
            return
        self._running = False
        self._last_error = message
        self.runningChanged.emit()
        self._poll_timer.stop()
        self._video_timer.stop()
        self._stop_receiver()
        if self._video_active:
            self._video_active = False
            self.videoChanged.emit()
        self._now = {}
        self._last_track = None
        self._cover_version = 0
        self.metadataChanged.emit()
        self.stateChanged.emit()

    # ---------------------------------------------------------------- video

    def _start_receiver(self, gst: str, port: int) -> None:
        args = [
            gst, "-q",
            "udpsrc", f"port={port}", "buffer-size=4194304",
            "caps=application/x-rtp,media=video,clock-rate=90000,"
            "encoding-name=H264,payload=96",
            "!", "rtph264depay", "!", "h264parse", "!", "decodebin",
            "!", "videoconvert", "!", "videoscale",
            "!", f"video/x-raw,format=RGB,width={FRAME_W},height={FRAME_H}",
            "!", "fdsink", "fd=1", "sync=false",
        ]
        try:
            self._receiver = subprocess.Popen(
                args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        except OSError as exc:
            self._last_error = f"video receiver failed: {exc}"
            self.stateChanged.emit()
            return
        self._threads.append(threading.Thread(target=self._read_frames, daemon=True))
        self._threads.append(threading.Thread(target=self._read_receiver_log, daemon=True))

    def _stop_receiver(self) -> None:
        proc = self._receiver
        self._receiver = None
        if proc is None:
            return
        try:
            proc.terminate()
        except OSError:
            pass
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()

    @staticmethod
    def _read_exact(stream, count: int) -> bytes | None:
        chunks = []
        remaining = count
        while remaining > 0:
            chunk = stream.read(remaining)
            if not chunk:
                return None
            chunks.append(chunk)
            remaining -= len(chunk)
        return b"".join(chunks)

    def _read_frames(self) -> None:
        proc = self._receiver
        if proc is None or proc.stdout is None:
            return
        stream = proc.stdout
        while self._running:
            data = self._read_exact(stream, FRAME_BYTES)
            if data is None:
                break
            image = QImage(data, FRAME_W, FRAME_H, FRAME_W * 3,
                           QImage.Format_RGB888).copy()
            with self._lock:
                self._frame = image
                self._last_frame = time.monotonic()
            if not self._video_active:
                self._video_active = True
                self.videoChanged.emit()
            self.frameReady.emit()
        log.info("video receiver stopped")

    def _read_receiver_log(self) -> None:
        proc = self._receiver
        if proc is None or proc.stderr is None:
            return
        for raw in proc.stderr:
            line = raw.decode(errors="replace").strip()
            if line:
                self._logs.append("gst: " + line)
        code = proc.wait()
        if self._running and code not in (0, None):
            self._last_error = (
                "video receiver stopped — check that GStreamer has an H.264 "
                "decoder (gstreamer1.0-libav / plugins-bad) and that the RTP "
                "port is free.")
            self.stateChanged.emit()

    def _check_video(self) -> None:
        if (self._video_active
                and time.monotonic() - self._last_frame > VIDEO_IDLE_SECONDS):
            self._video_active = False
            self.videoChanged.emit()

    def latest_frame(self) -> QImage | None:
        with self._lock:
            return self._frame

    def set_test_frame(self, image: QImage) -> None:
        """Dev helper: push a frame without UxPlay (screenshots/tests)."""
        with self._lock:
            self._frame = image
            self._last_frame = time.monotonic()
        if not self._video_active:
            self._video_active = True
            self.videoChanged.emit()
        self.frameReady.emit()

    # ------------------------------------------------------------- metadata

    @staticmethod
    def parse_metadata(text: str) -> dict:
        meta: dict = {}
        for raw in text.splitlines():
            line = raw.strip().strip("\x00")
            if not line:
                continue
            if ":" in line:
                key, value = line.split(":", 1)
            elif "=" in line:
                key, value = line.split("=", 1)
            else:
                continue
            key = key.strip().lstrip("\ufeff").lower()
            value = value.strip()
            if key in ("title", "track", "name", "track name", "song",
                       "song title"):
                meta["title"] = value
            elif key in ("artist", "album artist"):
                meta["artist"] = value
            elif key in ("album", "album name"):
                meta["album"] = value
            elif key == "genre":
                meta["genre"] = value
        return meta

    def _poll_metadata(self) -> None:
        if not self._running:
            return

        text = ""
        try:
            if self._meta_path.is_file():
                text = self._meta_path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            text = ""

        # UxPlay rewrites the metadata file in place; ignore an empty read
        # while a track is already known (avoids duplicate notifications).
        if text or not self._now:
            meta = self.parse_metadata(text)
            if meta != self._now:
                self._now = meta
                self.metadataChanged.emit()
                self._notify_track(meta)

        try:
            if self._cover_path.is_file():
                mtime = self._cover_path.stat().st_mtime_ns
                if mtime != self._cover_version:
                    self._cover_version = mtime
                    self.metadataChanged.emit()
            elif self._cover_version:
                self._cover_version = 0
                self.metadataChanged.emit()
        except OSError:
            pass

    def _notify_track(self, meta: dict) -> None:
        title = meta.get("title", "")
        artist = meta.get("artist", "")
        album = meta.get("album", "")
        if not (title or artist):
            self._last_track = None
            return
        key = (title, artist, album)
        if key == self._last_track:
            return
        self._last_track = key
        text = " — ".join(part for part in (title, artist) if part)
        if album:
            text += f" ({album})"
        try:
            self._host.notify("Now playing", text)
        except Exception:  # noqa: BLE001
            log.exception("could not post the now-playing notification")

    # ------------------------------------------------------------------ log

    def _read_log(self) -> None:
        proc = self._proc
        if proc is None or proc.stdout is None:
            return
        for raw in proc.stdout:
            line = raw.strip()
            if not line:
                continue
            self._logs.append(line)
            lowered = line.lower()
            if ("error" in lowered or "failed" in lowered
                    or "unknown option" in lowered):
                self._last_error = line[:300]
                self.stateChanged.emit()

        code = proc.wait()
        if self._running:
            self._fail_running(
                self._last_error or f"UxPlay exited (code {code}).")
