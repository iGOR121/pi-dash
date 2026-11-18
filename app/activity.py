"""Global user-activity detection for idle auto-lock.

Installed as an event filter on the QGuiApplication, so every touch, click,
drag, wheel or key press anywhere in the app resets the QML idle timer. The
signal is throttled: the timer only needs to know "something happened
recently", not the exact event count.
"""
from __future__ import annotations

import time

from PySide6.QtCore import QEvent, QObject, Signal

ACTIVITY_EVENTS = frozenset({
    QEvent.MouseButtonPress,
    QEvent.MouseButtonRelease,
    QEvent.MouseButtonDblClick,
    QEvent.MouseMove,
    QEvent.TouchBegin,
    QEvent.TouchUpdate,
    QEvent.TouchEnd,
    QEvent.KeyPress,
    QEvent.Wheel,
    QEvent.TabletPress,
    QEvent.TabletMove,
    QEvent.TabletRelease,
})


class ActivityMonitor(QObject):
    """Emits `activity` when the user interacts with any part of the UI."""

    activity = Signal()

    def __init__(self, parent=None, throttle_ms: int = 200):
        super().__init__(parent)
        self._interval = throttle_ms / 1000.0
        self._last = 0.0

    def eventFilter(self, obj, event) -> bool:  # noqa: N802 (Qt override)
        if event.type() in ACTIVITY_EVENTS:
            now = time.monotonic()
            if now - self._last >= self._interval:
                self._last = now
                self.activity.emit()
        return False
