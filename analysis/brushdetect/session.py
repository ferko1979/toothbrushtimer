"""Whole-session logic: water cue -> brushing -> rinse, with water-waste tracking.

Main rule (as it would run in the app while the phone lies by the sink):

  LISTENING  listen continuously; running water for >= `water_min_s` -> WATER
  WATER      water is running (wetting the brush)
               water stops                       -> ARMED (start = moment it stopped)
               brushing heard while water still runs -> BRUSHING, tap left on (waste)
  ARMED      brushing (scrubbing or sonic hum) within `arm_s` -> BRUSHING
               "fogmosás észlelve", timer starts from the moment the water stopped
  BRUSHING   timer runs
               water switched on again           -> RINSE (end candidate)
               water keeps running              -> waste icon after `waste_icon_s`
               no brushing for `end_quiet_s`     -> session ends at last brushing
  RINSE      water stopped and brushing resumes  -> back to BRUSHING (it was a quick re-wet)
               otherwise                         -> session ends where the rinse began

Fallback: brushing heard for `fallback_s` without any water cue also starts
a session (e.g. someone wets the brush in a cup).

Inputs are per-window probabilities (water, brushing, sonic tone), one per
hop, so this ports directly to Swift/Kotlin.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass
class SessionConfig:
    on: float = 0.6
    off: float = 0.4
    # Water uses hysteresis: on above water_on, off only below water_off.
    water_on: float = 0.55
    water_off: float = 0.3
    water_min_s: float = 1.0
    water_stop_s: float = 1.0
    arm_s: float = 20.0
    brush_confirm_s: float = 2.0
    fallback_s: float = 6.0
    end_quiet_s: float = 15.0
    rinse_min_s: float = 2.0
    resume_s: float = 5.0
    rinse_done_s: float = 5.0
    min_brushing_before_rinse_s: float = 10.0
    waste_icon_s: float = 5.0


@dataclass
class BrushingSession:
    start: float
    end: float = 0.0
    cue: str = "water"  # "water" or "no_water"
    water_running_s: float = 0.0
    events: list[tuple[float, str]] = field(default_factory=list)

    @property
    def duration_s(self) -> float:
        return max(self.end - self.start, 0.0)

    @property
    def wasted_water(self) -> bool:
        return self.water_running_s >= 5.0


class SessionDetector:
    LISTENING, WATER, ARMED, BRUSHING, RINSE = "LISTENING", "WATER", "ARMED", "BRUSHING", "RINSE"

    def __init__(self, cfg: SessionConfig | None = None):
        self.cfg = cfg or SessionConfig()
        self.state = self.LISTENING
        self.sessions: list[BrushingSession] = []
        self.events: list[tuple[float, str]] = []
        self.waste_icon = False
        self._water_on = False
        self._reset_runs()
        self._t = 0.0

    def _reset_runs(self):
        self._water_run = 0.0  # consecutive water
        self._dry_run = 0.0  # consecutive no-water
        self._brush_run = 0.0  # consecutive brushing evidence
        self._quiet_run = 0.0  # consecutive no brushing
        self._water_end = 0.0
        self._rinse_start = 0.0
        self._last_brush = 0.0
        self._rinse_water = 0.0
        self._dry_before_water = 0.0  # time without water before the current water run
        self._since_water = 0.0  # time since water was last clearly heard

    @property
    def current(self) -> BrushingSession | None:
        return self.sessions[-1] if self.state in (self.BRUSHING, self.RINSE) else None

    def _event(self, t, name):
        self.events.append((t, name))
        if self.current is not None:
            self.current.events.append((t, name))

    def _start(self, t, start, cue):
        self.sessions.append(BrushingSession(start=start, cue=cue))
        self.state = self.BRUSHING
        self._last_brush = t
        self._quiet_run = 0.0
        self._event(t, "brushing_detected")

    def _end(self, t, end):
        s = self.current
        s.end = end
        if self.waste_icon:
            self.waste_icon = False
            self._event(t, "waste_icon_off")
        self._event(t, "session_end")
        self.state = self.LISTENING
        self._reset_runs()

    def update(self, t: float, water: float, brush: float, sonic: float, dt: float) -> None:
        c = self.cfg
        self._t = t
        brushing = max(brush, sonic)
        if water >= c.water_on:
            self._water_on = True
        elif water < c.water_off:
            self._water_on = False
        is_water = self._water_on
        no_water = not self._water_on
        if is_water and self._water_run == 0.0:
            self._dry_before_water = self._since_water
        self._since_water = 0.0 if is_water else self._since_water + dt
        self._water_run = self._water_run + dt if is_water else 0.0
        self._dry_run = self._dry_run + dt if no_water else 0.0
        self._brush_run = self._brush_run + dt if brushing >= c.on else 0.0

        if self.state == self.LISTENING:
            if self._water_run >= c.water_min_s:
                self.state = self.WATER
                self._event(t, "water_start")
            elif self._brush_run >= c.fallback_s:
                self._start(t, t - self._brush_run, "no_water")

        elif self.state == self.WATER:
            if self._dry_run >= c.water_stop_s:
                self._water_end = t - self._dry_run
                self.state = self.ARMED
                self._event(t, "water_stop")
            elif self._brush_run >= c.brush_confirm_s and self._water_run >= c.brush_confirm_s:
                # Brushing while the tap keeps running.
                self._start(t, t - self._brush_run, "water")

        elif self.state == self.ARMED:
            if self._water_run >= c.water_min_s:
                self.state = self.WATER
            elif self._brush_run >= c.brush_confirm_s:
                self._start(t, self._water_end, "water")
            elif t - self._water_end > c.arm_s:
                self.state = self.LISTENING

        elif self.state == self.BRUSHING:
            s = self.current
            if brushing >= c.off:
                self._last_brush = t
                self._quiet_run = 0.0
            else:
                self._quiet_run += dt
            if is_water:
                s.water_running_s += dt
            if (self._water_run >= c.rinse_min_s and not self.waste_icon
                    and self._dry_before_water >= c.waste_icon_s
                    and t - s.start >= c.min_brushing_before_rinse_s):
                # Tap opened again after brushing with the tap off: rinse.
                self._rinse_start = t - self._water_run
                self._rinse_water = self._water_run
                self.state = self.RINSE
                self._event(t, "rinse_start")
            elif self._water_run >= c.waste_icon_s and not self.waste_icon:
                self.waste_icon = True
                self._event(t, "waste_icon_on")
            elif self.waste_icon and self._dry_run >= c.water_stop_s:
                self.waste_icon = False
                self._event(t, "waste_icon_off")
            if self.state == self.BRUSHING and self._quiet_run >= c.end_quiet_s:
                self._end(t, self._last_brush)

        elif self.state == self.RINSE:
            s = self.current
            if is_water:
                self._rinse_water += dt
                s.water_running_s += dt
            if self._dry_run > 0 and self._brush_run >= c.resume_s and self._dry_run >= c.resume_s:
                # Quick re-wet in the middle of brushing: keep going.
                self.state = self.BRUSHING
                self._event(t, "brushing_resumed")
            elif self._dry_run >= c.rinse_done_s:
                # Rinse water is not waste: remove it from the running-water total.
                s.water_running_s = max(s.water_running_s - self._rinse_water, 0.0)
                self._end(t, self._rinse_start)

    def finish(self) -> list[BrushingSession]:
        if self.state == self.BRUSHING:
            self._end(self._t, self._last_brush)
        elif self.state == self.RINSE:
            self.current.water_running_s = max(self.current.water_running_s - self._rinse_water, 0.0)
            self._end(self._t, self._rinse_start)
        return self.sessions


def run_sessions(times, water, brush, sonic, dt: float, cfg: SessionConfig | None = None):
    det = SessionDetector(cfg)
    for t, w, b, s in zip(times, water, brush, sonic):
        det.update(float(t) + dt / 2, float(w), float(b), float(s), dt)
    return det.finish(), det.events
