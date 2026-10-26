"""When does the app listen? (microphone policy)

Rules agreed for the apps:
  * Listening starts when the app is opened (foreground).
  * If the phone lies flat and still (on the shelf / by the sink) it keeps
    listening even if the screen locks or the app goes to the background.
    It does not matter whether it was put down after opening the app or was
    already lying there when the app was opened.
  * Opening the app from a reminder notification "arms" it: brushing is
    expected right away, so detection starts faster and waits longer.
  * Listening stops when
      - the app is in the background and the phone is picked up,
      - nothing (no water, no brushing) was heard for `idle_timeout_s`
        (`armed_timeout_s` when armed),
      - a brushing session finished (after a short grace period, unless the
        app is still on screen).

Platform notes: iOS keeps an audio session running in the background only if
it was started in the foreground (background mode "audio"); Android needs a
foreground service of type "microphone", also started from the foreground.
So the mic is always started by opening the app, never from the background.
The accelerometer gives the gravity vector (gx, gy, gz) in g.
"""

from __future__ import annotations

import math
from collections import deque
from dataclasses import dataclass

from .session import SessionConfig


@dataclass(frozen=True)
class ListeningConfig:
    flat_max_tilt_deg: float = 20.0
    still_max_std_g: float = 0.03
    still_window_s: float = 2.0
    idle_timeout_s: float = 300.0
    armed_timeout_s: float = 600.0
    after_session_grace_s: float = 30.0


class ListeningPolicy:
    def __init__(self, cfg: ListeningConfig | None = None):
        self.cfg = cfg or ListeningConfig()
        self.listening = False
        self.foreground = False
        self.armed = False
        self.placed = False  # flat and still
        self._motion: deque[tuple[float, float, float, float]] = deque()
        self._last_activity = 0.0
        self._session_end: float | None = None
        self.stop_reason = ""

    # -- events from the app -------------------------------------------------
    def app_opened(self, t: float, from_notification: bool = False) -> None:
        self.foreground = True
        self.listening = True
        self.armed = self.armed or from_notification
        self._last_activity = t
        self._session_end = None
        self.stop_reason = ""

    def app_backgrounded(self, t: float) -> None:
        self.foreground = False
        if self.listening and not self.placed:
            self._stop("app háttérbe került, a telefon nincs letéve")

    def motion(self, t: float, gx: float, gy: float, gz: float) -> None:
        self._motion.append((t, gx, gy, gz))
        while self._motion and self._motion[0][0] < t - self.cfg.still_window_s:
            self._motion.popleft()
        span = self._motion[-1][0] - self._motion[0][0]
        was_placed = self.placed
        self.placed = span >= self.cfg.still_window_s * 0.9 and self._flat_and_still()
        if was_placed and not self._flat_now(gx, gy, gz) and self.listening and not self.foreground:
            self._stop("felvették a telefont")

    def activity(self, t: float) -> None:
        """Water or brushing was heard."""
        self._last_activity = t

    def session_finished(self, t: float) -> None:
        self._session_end = t
        self.armed = False

    def tick(self, t: float) -> None:
        if not self.listening:
            return
        if self._session_end is not None and not self.foreground \
                and t - self._session_end >= self.cfg.after_session_grace_s:
            self._stop("a fogmosás véget ért")
            return
        timeout = self.cfg.armed_timeout_s if self.armed else self.cfg.idle_timeout_s
        if t - self._last_activity >= timeout:
            self._stop("hosszú ideig nem hallatszott víz vagy fogmosás")

    # -- outputs ---------------------------------------------------------------
    def session_config(self) -> SessionConfig:
        """Armed (opened from a reminder): start the timer sooner, even without a water cue."""
        if self.armed:
            return SessionConfig(fallback_s=3.0, arm_s=40.0)
        return SessionConfig()

    # -- helpers -----------------------------------------------------------------
    def _stop(self, reason: str) -> None:
        self.listening = False
        self.armed = False
        self.stop_reason = reason

    def _flat_now(self, gx, gy, gz) -> bool:
        n = math.sqrt(gx * gx + gy * gy + gz * gz) or 1.0
        return abs(gz) / n >= math.cos(math.radians(self.cfg.flat_max_tilt_deg))

    def _flat_and_still(self) -> bool:
        if len(self._motion) < 3:
            return False
        if not all(self._flat_now(gx, gy, gz) for _, gx, gy, gz in self._motion):
            return False
        for axis in (1, 2, 3):
            vals = [m[axis] for m in self._motion]
            mean = sum(vals) / len(vals)
            if math.sqrt(sum((v - mean) ** 2 for v in vals) / len(vals)) > self.cfg.still_max_std_g:
                return False
        return True
