"""Streaming brushing timer: turns a per-window detection score into brushing time.

This is the state machine the apps will run. It is fed one score per hop
and keeps no history, so it ports directly to Swift/Kotlin.

States:
    IDLE      - waiting; a session starts after `min_on_s` of score >= `on`
    BRUSHING  - time accumulates while score >= `off` (hysteresis)
    PAUSED    - score dropped; pauses up to `pause_tolerance_s` (spitting,
                switching side) are counted as brushing, longer ones are not;
                after `session_end_s` of silence the session is closed.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class TimerConfig:
    on: float = 0.6
    off: float = 0.4
    min_on_s: float = 1.0
    pause_tolerance_s: float = 3.0
    session_end_s: float = 20.0
    target_s: float = 120.0


@dataclass
class Session:
    start: float
    end: float = 0.0
    active_s: float = 0.0
    intervals: list[tuple[float, float]] = field(default_factory=list)


class BrushTimer:
    IDLE, BRUSHING, PAUSED = "IDLE", "BRUSHING", "PAUSED"

    def __init__(self, cfg: TimerConfig | None = None):
        self.cfg = cfg or TimerConfig()
        self.state = self.IDLE
        self.sessions: list[Session] = []
        self._candidate = 0.0
        self._pause = 0.0
        self._interval_start = 0.0
        self._t = 0.0

    @property
    def current(self) -> Session | None:
        return self.sessions[-1] if self.state != self.IDLE else None

    def update(self, t: float, score: float, dt: float) -> None:
        """Feed the score of the window that ends at time `t` (seconds)."""
        c = self.cfg
        self._t = t
        if self.state == self.IDLE:
            if score >= c.on:
                self._candidate += dt
                if self._candidate >= c.min_on_s:
                    start = t - self._candidate
                    self.sessions.append(Session(start=start, active_s=self._candidate))
                    self._interval_start = start
                    self.state = self.BRUSHING
            else:
                self._candidate = 0.0
        elif self.state == self.BRUSHING:
            if score >= c.off:
                self.current.active_s += dt
            else:
                self.current.intervals.append((self._interval_start, t - dt))
                self._pause = dt
                self.state = self.PAUSED
        else:  # PAUSED
            s = self.current
            if score >= c.on:
                if self._pause <= c.pause_tolerance_s:
                    # Short pause: count it and merge with the previous interval.
                    s.active_s += self._pause
                    self._interval_start = s.intervals.pop()[0]
                else:
                    self._interval_start = t - dt
                s.active_s += dt
                self.state = self.BRUSHING
            else:
                self._pause += dt
                if self._pause >= c.session_end_s:
                    s.end = t - self._pause
                    self.state = self.IDLE
                    self._candidate = 0.0

    def finish(self) -> list[Session]:
        """Close any open session (end of recording) and return all sessions."""
        if self.state == self.BRUSHING:
            self.current.intervals.append((self._interval_start, self._t))
            self.current.end = self._t
        elif self.state == self.PAUSED:
            self.current.end = self._t - self._pause
        self.state = self.IDLE
        return self.sessions


def run_timer(times, scores, dt: float, cfg: TimerConfig | None = None) -> list[Session]:
    timer = BrushTimer(cfg)
    for t, s in zip(times, scores):
        timer.update(float(t) + dt / 2, float(s), dt)
    return timer.finish()
